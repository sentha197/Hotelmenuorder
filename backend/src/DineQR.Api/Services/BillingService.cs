using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace DineQR.Api.Services;

/// Bills, payments and refunds. Amounts come from the bill's snapshot and
/// payment status only from verified provider results or staff-recorded
/// counter payments; the app never sets them.
public sealed partial class BillingService(
    AppDbContext db,
    CurrentCaller caller,
    IPaymentProvider provider,
    IUpiPaymentVerifier upiVerifier,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    public const string CounterProvider = "Counter";

    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    private IQueryable<Invoice> Full => db.Invoices
        .Include(i => i.Order).ThenInclude(o => o.Lines)
        .Include(i => i.Payments)
        .Include(i => i.Refunds)
        .AsSplitQuery();

    public async Task<Invoice> GetAsync(string id, CancellationToken ct)
    {
        var invoice = await Full.AsNoTracking().FirstOrDefaultAsync(i => i.Id == id, ct)
                      ?? throw ApiException.NotFound("Bill not found.");
        await CheckReadAccessAsync(invoice, ct);
        return invoice;
    }

    public async Task<Invoice> ForOrderAsync(string orderId, CancellationToken ct)
    {
        var invoice = await Full.AsNoTracking().FirstOrDefaultAsync(i => i.OrderId == orderId, ct)
                      ?? throw ApiException.NotFound("Bill not found.");
        await CheckReadAccessAsync(invoice, ct);
        return invoice;
    }

    private async Task CheckReadAccessAsync(Invoice invoice, CancellationToken ct)
    {
        if (caller.IsGuest)
        {
            if (invoice.Order.GuestSessionId != caller.GuestSessionId)
            {
                throw ApiException.NotFound("Bill not found.");
            }
            return;
        }
        await caller.RequireAsync(Permission.ViewBills, ct);
    }

    public Task<List<Invoice>> ForGuestAsync(CancellationToken ct)
    {
        var session = caller.GuestSessionId;
        return Full.AsNoTracking()
            .Where(i => i.Order.GuestSessionId == session)
            .OrderByDescending(i => i.CreatedAt)
            .ToListAsync(ct);
    }

    /// Staff listing: bills created in [from, to) plus any with a balance or
    /// a pending payment, newest first.
    public async Task<List<Invoice>> ForStaffAsync(DateTime? from, DateTime? to, CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ViewBills, ct);
        var start = from ?? Now.AddDays(-30);
        var end = to ?? DateTime.MaxValue;
        return await Full.AsNoTracking()
            .Where(i => (i.CreatedAt >= start && i.CreatedAt < end) ||
                        !i.IsSettled ||
                        i.Payments.Any(p => p.Status == PaymentStatus.Pending))
            .OrderByDescending(i => i.CreatedAt)
            .Take(2000)
            .ToListAsync(ct);
    }

    // ------------------------------------------------------------ payments

    private static PaymentMethod ParseMethod(string? method) =>
        EnumNames.TryParse<PaymentMethod>(method, out var parsed)
            ? parsed
            : throw ApiException.Validation("method", "Unknown payment method.");

    private static string ValidKey(string? key)
    {
        var value = (key ?? "").Trim();
        return value.Length is >= 8 and <= 64
            ? value
            : throw ApiException.Validation("idempotencyKey", "An idempotency key of 8 to 64 characters is required.");
    }

    /// Same rules as the app: more than zero, never above what is payable
    /// now, and only part of the balance if the restaurant allows it.
    private static void ValidateAmount(Invoice invoice, long amount, bool allowPartial)
    {
        if (invoice.IsVoid) throw ApiException.Conflict("billVoid", "This bill was cancelled.");
        if (amount <= 0) throw ApiException.Validation("amount", "Enter an amount above zero.");
        var payable = invoice.PayableNowPaise;
        if (payable == 0)
        {
            throw ApiException.Conflict(invoice.PendingPaise > 0 ? "paymentInProgress" : "nothingDue",
                invoice.PendingPaise > 0
                    ? "A payment for this bill is in progress."
                    : "Nothing is due on this bill.");
        }
        if (amount > payable) throw ApiException.Validation("amount", "That is more than the amount due.");
        if (!allowPartial && amount != payable)
        {
            throw ApiException.Validation("amount", "This restaurant takes the full amount in one payment.");
        }
    }

    private async Task<Invoice> LoadForUpdateAsync(string invoiceId, CancellationToken ct) =>
        await Full.FirstOrDefaultAsync(i => i.Id == invoiceId, ct)
        ?? throw ApiException.NotFound("Bill not found.");

    private async Task<string> NextPaymentIdAsync(CancellationToken ct) =>
        $"PAY{await db.NextValueAsync(AppDbContext.PaymentSequence, ct):D6}";

    /// Guest (own bill) or cashier: starts an online payment. The attempt is
    /// recorded as pending before the provider is involved.
    public async Task<(Payment Payment, string ProviderOrderId)> CreateIntentAsync(
        PaymentIntentRequest request,
        CancellationToken ct)
    {
        var key = ValidKey(request.IdempotencyKey);
        var existing = await db.Payments.AsNoTracking().Include(p => p.Invoice).ThenInclude(i => i.Order)
            .FirstOrDefaultAsync(p => p.IdempotencyKey == key, ct);
        if (existing != null)
        {
            await CheckReadAccessAsync(existing.Invoice, ct);
            return (existing, existing.ProviderOrderId ?? "");
        }

        var method = ParseMethod(request.Method);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        if (method == PaymentMethod.Cash || !settings.OnlineMethods.Contains(EnumNames.ToName(method)))
        {
            throw ApiException.Conflict("methodUnavailable", $"{method} is not available right now.");
        }
        if (!provider.IsAvailable)
        {
            throw ApiException.Unavailable("paymentsUnavailable",
                "Online payment is not available right now. Please pay at the counter.");
        }
        var invoice = await LoadForUpdateAsync(request.InvoiceId, ct);
        await CheckReadAccessAsync(invoice, ct);
        ExpireStaleUpiAttempts(invoice);
        ValidateAmount(invoice, request.Amount, settings.AllowPartialPayments);

        var now = Now;
        var payment = new Payment
        {
            Id = await NextPaymentIdAsync(ct),
            InvoiceId = invoice.Id,
            OrderId = invoice.OrderId,
            AmountPaise = request.Amount,
            Method = method,
            Status = PaymentStatus.Pending,
            Provider = provider.Name,
            IdempotencyKey = key,
            IsSimulated = provider.IsSimulated,
            GuestSessionId = caller.GuestSessionId,
            CreatedAt = now,
            UpdatedAt = now,
        };
        payment.ProviderOrderId = await provider.CreateOrderAsync(payment, ct);
        invoice.Payments.Add(payment);
        invoice.UpdatedAt = now;
        await SaveAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, payment.ProviderOrderId);
    }

    /// The app sends the provider's checkout result; the server verifies it
    /// with the provider before the payment counts.
    public async Task<(Payment, Invoice)> ConfirmAsync(string paymentId, PaymentConfirmRequest request,
        CancellationToken ct)
    {
        var (payment, invoice) = await LoadPaymentAsync(paymentId, ct);
        await CheckReadAccessAsync(invoice, ct);
        if (payment.Status != PaymentStatus.Pending) return (payment, invoice);
        if (UpiRules.IsDirect(payment))
        {
            // Money paid to the restaurant's own UPI ID is confirmed by staff
            // (or a connected verifier), never by the app that sent it, and
            // never by the development simulator.
            throw ApiException.Conflict("notOnlinePayment",
                "This payment is confirmed by the restaurant, not by the app.");
        }
        var outcome = await provider.VerifyAsync(payment, request, ct);
        Apply(payment, invoice, outcome);
        await SaveAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// Current status; a pending payment is re-checked with the provider.
    public async Task<(Payment, Invoice)> RefreshPaymentAsync(string paymentId, CancellationToken ct)
    {
        var (payment, invoice) = await LoadPaymentAsync(paymentId, ct);
        await CheckReadAccessAsync(invoice, ct);
        if (payment.Status == PaymentStatus.Pending && UpiRules.IsDirect(payment))
        {
            if (await ResolveUpiAsync(payment, invoice, ct))
            {
                await SaveAsync(ct);
                await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
            }
            return (payment, invoice);
        }
        if (payment.Status == PaymentStatus.Pending && payment.Provider == provider.Name)
        {
            var outcome = await provider.CheckStatusAsync(payment, ct);
            if (outcome.Status != PaymentStatus.Pending)
            {
                Apply(payment, invoice, outcome);
                await SaveAsync(ct);
                await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
            }
        }
        return (payment, invoice);
    }

    /// Staff: re-checks every pending payment on a bill with the provider.
    public async Task<(int Resolved, Invoice Invoice)> ReconcileAsync(string invoiceId, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ReconcilePayments, ct);
        var invoice = await LoadForUpdateAsync(invoiceId, ct);
        var resolved = 0;
        foreach (var payment in invoice.Payments.Where(p => p.Status == PaymentStatus.Pending).ToList())
        {
            if (UpiRules.IsDirect(payment))
            {
                if (await TryVerifyAutomaticallyAsync(payment, invoice, ct)) resolved++;
                continue;
            }
            if (payment.Provider != provider.Name) continue;
            var outcome = await provider.CheckStatusAsync(payment, ct);
            if (outcome.Status == PaymentStatus.Pending) continue;
            Apply(payment, invoice, outcome);
            resolved++;
        }
        resolved += ExpireStaleUpiAttempts(invoice);
        if (resolved > 0)
        {
            audit.Record(staff, "payment.reconcile",
                $"Reconciled {resolved} pending payment(s) on bill {invoice.BillNumber}", invoice.Id);
            await SaveAsync(ct);
            await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        }
        return (resolved, invoice);
    }

    private void Apply(Payment payment, Invoice invoice, ProviderOutcome outcome)
    {
        var now = Now;
        payment.Status = outcome.Status;
        payment.Reference = outcome.Reference;
        payment.FailureReason = outcome.FailureReason;
        payment.UpdatedAt = now;
        payment.ConfirmedAt = outcome.Status == PaymentStatus.Pending ? null : now;
        invoice.UpdatedAt = now;
        invoice.UpdateSettled();
    }

    private async Task<(Payment, Invoice)> LoadPaymentAsync(string paymentId, CancellationToken ct)
    {
        var invoiceId = await db.Payments.Where(p => p.Id == paymentId).Select(p => p.InvoiceId)
                            .FirstOrDefaultAsync(ct)
                        ?? throw ApiException.NotFound("Payment not found.");
        var invoice = await LoadForUpdateAsync(invoiceId, ct);
        return (invoice.Payments.Single(p => p.Id == paymentId), invoice);
    }

    /// Staff: a payment taken at the counter (cash, card terminal, UPI QR).
    /// The staff member confirms it, so it is recorded as successful.
    public async Task<(Payment, Invoice)> RecordCounterPaymentAsync(string invoiceId,
        CounterPaymentRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.CollectPayments, ct);
        var key = ValidKey(request.IdempotencyKey);
        var replay = await db.Payments.AsNoTracking().Where(p => p.IdempotencyKey == key)
            .Select(p => p.Id).FirstOrDefaultAsync(ct);
        if (replay != null) return await LoadPaymentAsync(replay, ct);

        var method = ParseMethod(request.Method);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var invoice = await LoadForUpdateAsync(invoiceId, ct);
        ExpireStaleUpiAttempts(invoice);
        ValidateAmount(invoice, request.Amount, settings.AllowPartialPayments);
        var reference = (request.Reference ?? "").Trim();
        if (reference.Length > 100) throw ApiException.Validation("reference", "Reference is too long.");

        var now = Now;
        var payment = new Payment
        {
            Id = await NextPaymentIdAsync(ct),
            InvoiceId = invoice.Id,
            OrderId = invoice.OrderId,
            AmountPaise = request.Amount,
            Method = method,
            Status = PaymentStatus.Succeeded,
            Provider = CounterProvider,
            Reference = reference,
            IdempotencyKey = key,
            RecordedByUserId = staff.Id,
            RecordedByName = staff.FullName,
            CreatedAt = now,
            UpdatedAt = now,
            ConfirmedAt = now,
        };
        invoice.Payments.Add(payment);
        invoice.UpdatedAt = now;
        invoice.UpdateSettled();
        audit.Record(staff, "payment.counter",
            $"Recorded {method} payment of {Rupees(request.Amount)} on bill {invoice.BillNumber}", invoice.Id);
        await SaveAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// Staff: refunds part or all of a successful payment. Counter payments
    /// are refunded at the counter; online ones through the provider.
    public async Task<(Refund, Invoice)> RefundAsync(string paymentId, RefundRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.IssueRefunds, ct);
        var key = ValidKey(request.IdempotencyKey);
        var replay = await db.Refunds.AsNoTracking().FirstOrDefaultAsync(r => r.IdempotencyKey == key, ct);
        if (replay != null) return (replay, await LoadForUpdateAsync(replay.InvoiceId, ct));

        var (payment, invoice) = await LoadPaymentAsync(paymentId, ct);
        if (payment.Status != PaymentStatus.Succeeded)
        {
            throw ApiException.Conflict("notRefundable", "Only successful payments can be refunded.");
        }
        var already = invoice.Refunds
            .Where(r => r.PaymentId == payment.Id && r.Status != RefundStatus.Failed)
            .Sum(r => r.AmountPaise);
        var refundable = payment.AmountPaise - already;
        if (request.Amount <= 0 || request.Amount > refundable)
        {
            throw ApiException.Validation("amount",
                $"You can refund between {Rupees(1)} and {Rupees(Math.Max(0, refundable))}.");
        }
        var reason = (request.Reason ?? "").Trim();
        if (reason.Length is < 3 or > 120)
        {
            throw ApiException.Validation("reason", "Give a reason of 3 to 120 characters.");
        }

        RefundStatus status;
        var reference = "";
        var simulated = payment.IsSimulated;
        if (payment.Provider is CounterProvider or UpiRules.Provider)
        {
            // Counter and direct UPI payments are returned by the
            // restaurant itself (cash, or from its own UPI app); this
            // records it.
            status = RefundStatus.Processed;
        }
        else
        {
            if (payment.Provider != provider.Name)
            {
                throw ApiException.Unavailable("providerUnavailable",
                    "The provider that took this payment is not configured.");
            }
            var outcome = await provider.RefundAsync(payment, request.Amount, ct);
            status = outcome.Status switch
            {
                PaymentStatus.Succeeded => RefundStatus.Processed,
                PaymentStatus.Pending => RefundStatus.Pending,
                _ => RefundStatus.Failed,
            };
            reference = outcome.Reference;
        }
        var now = Now;
        var refund = new Refund
        {
            Id = $"RFD{await db.NextValueAsync(AppDbContext.RefundSequence, ct):D5}",
            InvoiceId = invoice.Id,
            PaymentId = payment.Id,
            AmountPaise = request.Amount,
            Reason = reason,
            Status = status,
            Reference = reference,
            IsSimulated = simulated,
            ProcessedByUserId = staff.Id,
            ProcessedByName = staff.FullName,
            IdempotencyKey = key,
            CreatedAt = now,
        };
        invoice.Refunds.Add(refund);
        invoice.UpdatedAt = now;
        audit.Record(staff, "payment.refund",
            $"Refund of {Rupees(request.Amount)} on bill {invoice.BillNumber} ({reason})", invoice.Id);
        await SaveAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (refund, invoice);
    }

    private async Task SaveAsync(CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException error) when (error.InnerException is PostgresException
                                              { SqlState: PostgresErrorCodes.UniqueViolation } violation)
        {
            if (violation.ConstraintName == UpiReferenceIndex)
            {
                throw ApiException.Conflict("duplicateReference",
                    "That UPI transaction ID is already recorded on another payment.");
            }
            throw ApiException.Conflict("duplicateRequest",
                "This payment request was already received. Refresh the bill.");
        }
    }

    public static string Rupees(long paise) =>
        paise % 100 == 0 ? $"₹{paise / 100:N0}" : $"₹{paise / 100m:N2}";
}
