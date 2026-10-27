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
///
/// Every change to a bill's payments runs in a transaction that holds the
/// bill's row lock ([LockAsync]). Requests for one bill therefore run one
/// after another: each sees what the others recorded, a repeated request
/// finds its first result, and no mix of payments can overpay the bill.
public sealed partial class BillingService(
    AppDbContext db,
    CurrentCaller caller,
    PaymentProviders providers,
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

    /// Display-only detail of a method (`Scan & Pay`, `Credit`, a bank
    /// name). Refused if it could hold a card or account number.
    private static string ValidDetail(string? detail)
    {
        var value = (detail ?? "").Trim();
        if (value.Length > 40) throw ApiException.Validation("methodDetail", "Method detail is too long.");
        if (value.Count(char.IsDigit) > 4)
        {
            throw ApiException.Validation("methodDetail",
                "Method detail must not contain card or account numbers.");
        }
        return value;
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

    /// Loads a bill for a change, first taking its row lock. Call inside a
    /// transaction: the lock lasts until it commits or rolls back.
    private async Task<Invoice> LockAsync(string invoiceId, CancellationToken ct)
    {
        await db.Database.ExecuteSqlAsync($"select 1 from invoices where id = {invoiceId} for update", ct);
        return await LoadForUpdateAsync(invoiceId, ct);
    }

    private async Task<(Payment, Invoice)> LockPaymentAsync(string paymentId, CancellationToken ct)
    {
        var invoiceId = await db.Payments.Where(p => p.Id == paymentId).Select(p => p.InvoiceId)
                            .FirstOrDefaultAsync(ct)
                        ?? throw ApiException.NotFound("Payment not found.");
        var invoice = await LockAsync(invoiceId, ct);
        return (invoice.Payments.Single(p => p.Id == paymentId), invoice);
    }

    /// The payment already recorded on [invoice] under [key], if any. A key
    /// used on another bill is refused rather than charged again.
    private async Task<Payment?> ReplayAsync(string key, Invoice invoice, CancellationToken ct)
    {
        var existing = invoice.Payments.FirstOrDefault(p => p.IdempotencyKey == key);
        if (existing != null) return existing;
        if (await db.Payments.AnyAsync(p => p.IdempotencyKey == key, ct)) throw DuplicateRequest();
        return null;
    }

    private static ApiException DuplicateRequest() => ApiException.Conflict("duplicateRequest",
        "This payment request was already received. Refresh the bill.");

    private async Task<string> NextPaymentIdAsync(CancellationToken ct) =>
        $"PAY{await db.NextValueAsync(AppDbContext.PaymentSequence, ct):D6}";

    /// Guest (own bill) or cashier: starts an online payment through the
    /// provider of the restaurant's payment mode (the simulator in demo
    /// mode). The attempt is recorded as pending before the provider is
    /// involved.
    public async Task<(Payment Payment, string ProviderOrderId)> CreateIntentAsync(
        PaymentIntentRequest request,
        CancellationToken ct)
    {
        var key = ValidKey(request.IdempotencyKey);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invoice = await LockAsync(request.InvoiceId, ct);
        await CheckReadAccessAsync(invoice, ct);
        if (await ReplayAsync(key, invoice, ct) is { } existing) return (existing, existing.ProviderOrderId ?? "");
        ExpireStaleUpiAttempts(invoice);

        var method = ParseMethod(request.Method);
        var detail = ValidDetail(request.MethodDetail);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        if (method == PaymentMethod.Cash || !settings.OnlineMethods.Contains(EnumNames.ToName(method)))
        {
            throw ApiException.Conflict("methodUnavailable", $"{method} is not available right now.");
        }
        if (method == PaymentMethod.Upi && settings.Currency != "INR")
        {
            throw ApiException.Conflict("methodUnavailable", "UPI takes payments in Indian rupees only.");
        }
        var provider = providers.For(settings.PaymentMode);
        if (!provider.IsAvailable)
        {
            throw ApiException.Unavailable("paymentsUnavailable",
                "Online payment is not available right now. Please pay at the counter.");
        }
        ValidateAmount(invoice, request.Amount, settings.AllowPartialPayments);

        var now = Now;
        var payment = new Payment
        {
            Id = await NextPaymentIdAsync(ct),
            InvoiceId = invoice.Id,
            OrderId = invoice.OrderId,
            AmountPaise = request.Amount,
            Currency = settings.Currency,
            Method = method,
            MethodDetail = detail,
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
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, payment.ProviderOrderId);
    }

    /// The app sends the provider's checkout result; the server verifies it
    /// with the provider that took the payment before it counts.
    public async Task<(Payment, Invoice)> ConfirmAsync(string paymentId, PaymentConfirmRequest request,
        CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockPaymentAsync(paymentId, ct);
        await CheckReadAccessAsync(invoice, ct);
        if (payment.Status != PaymentStatus.Pending) return (payment, invoice);
        if (UpiRules.IsDirect(payment))
        {
            // Money paid to the restaurant's own UPI ID is confirmed by staff
            // (or a connected verifier), never by the app that sent it, and
            // never by the demo simulator.
            throw ApiException.Conflict("notOnlinePayment",
                "This payment is confirmed by the restaurant, not by the app.");
        }
        var provider = ProviderOf(payment);
        var mode = await db.Settings.Select(s => s.PaymentMode).SingleAsync(ct);
        var outcome = provider.IsSimulated && mode != PaymentMode.Demo
            // Started in demo mode, finished after the switch to live.
            ? new ProviderOutcome(PaymentStatus.Failed, "",
                "Demo payments ended when the restaurant switched to live payments. No money moved.")
            : await provider.VerifyAsync(payment, request, ct);
        Apply(payment, invoice, outcome);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    private IPaymentProvider ProviderOf(Payment payment) =>
        providers.Named(payment.Provider)
        ?? throw ApiException.Unavailable("providerUnavailable",
            "The provider that took this payment is not configured.");

    /// Current status; a pending payment is re-checked with the provider.
    public async Task<(Payment, Invoice)> RefreshPaymentAsync(string paymentId, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockPaymentAsync(paymentId, ct);
        await CheckReadAccessAsync(invoice, ct);
        if (payment.Status == PaymentStatus.Pending && UpiRules.IsDirect(payment))
        {
            if (await ResolveUpiAsync(payment, invoice, ct))
            {
                await SaveAsync(ct);
                await tx.CommitAsync(ct);
                await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
            }
            return (payment, invoice);
        }
        if (payment.Status == PaymentStatus.Pending && providers.Named(payment.Provider) is { } provider)
        {
            var outcome = await provider.CheckStatusAsync(payment, ct);
            if (outcome.Status != PaymentStatus.Pending)
            {
                Apply(payment, invoice, outcome);
                await SaveAsync(ct);
                await tx.CommitAsync(ct);
                await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
            }
        }
        return (payment, invoice);
    }

    /// Staff: re-checks every pending payment on a bill with its provider.
    public async Task<(int Resolved, Invoice Invoice)> ReconcileAsync(string invoiceId, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ReconcilePayments, ct);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invoice = await LockAsync(invoiceId, ct);
        var resolved = 0;
        foreach (var payment in invoice.Payments.Where(p => p.Status == PaymentStatus.Pending).ToList())
        {
            if (UpiRules.IsDirect(payment))
            {
                if (await TryVerifyAutomaticallyAsync(payment, invoice, ct)) resolved++;
                continue;
            }
            if (providers.Named(payment.Provider) is not { } provider) continue;
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
            await tx.CommitAsync(ct);
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

    /// Staff: a payment taken at the counter (cash, card terminal, UPI QR).
    /// The staff member confirms it, so it is recorded as successful; in
    /// demo mode it is recorded as a demo payment. It answers the guest's
    /// counter request, if there was one.
    public async Task<(Payment, Invoice)> RecordCounterPaymentAsync(string invoiceId,
        CounterPaymentRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.CollectPayments, ct);
        var key = ValidKey(request.IdempotencyKey);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invoice = await LockAsync(invoiceId, ct);
        if (await ReplayAsync(key, invoice, ct) is { } replay) return (replay, invoice);
        ExpireStaleUpiAttempts(invoice);

        var method = ParseMethod(request.Method);
        var detail = ValidDetail(request.MethodDetail);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        ValidateAmount(invoice, request.Amount, settings.AllowPartialPayments);
        var reference = (request.Reference ?? "").Trim();
        if (reference.Length > 100) throw ApiException.Validation("reference", "Reference is too long.");

        var demo = settings.PaymentMode == PaymentMode.Demo;
        var now = Now;
        var payment = new Payment
        {
            Id = await NextPaymentIdAsync(ct),
            InvoiceId = invoice.Id,
            OrderId = invoice.OrderId,
            AmountPaise = request.Amount,
            Currency = settings.Currency,
            Method = method,
            MethodDetail = detail,
            Status = PaymentStatus.Succeeded,
            Provider = CounterProvider,
            Reference = reference,
            IdempotencyKey = key,
            IsSimulated = demo,
            RecordedByUserId = staff.Id,
            RecordedByName = staff.FullName,
            CreatedAt = now,
            UpdatedAt = now,
            ConfirmedAt = now,
        };
        invoice.Payments.Add(payment);
        invoice.ClearCounterRequest();
        invoice.UpdatedAt = now;
        invoice.UpdateSettled();
        audit.Record(staff, "payment.counter",
            $"Recorded {(demo ? "demo " : "")}{method} payment of " +
            $"{Currencies.Format(request.Amount, settings.Currency)} on bill {invoice.BillNumber}", invoice.Id);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    // ------------------------------------------------------ counter requests

    /// Guest: says they will pay [CounterRequestBody.Amount] (by default all
    /// that is payable now) at the counter, in cash or by any method there.
    /// Nothing is paid: the bill keeps its status until staff record the
    /// payment, and staff see the request on the bill. Asking again replaces
    /// the request.
    public async Task<Invoice> RequestCounterPaymentAsync(string invoiceId, CounterRequestBody request,
        CancellationToken ct)
    {
        if (!EnumNames.TryParse<CounterRequestKind>(request.Kind, out var kind))
        {
            throw ApiException.Validation("kind", "Choose cash or paying at the counter.");
        }
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invoice = await LockAsync(invoiceId, ct);
        await CheckReadAccessAsync(invoice, ct);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var amount = request.Amount ?? invoice.PayableNowPaise;
        ValidateAmount(invoice, amount, settings.AllowPartialPayments);
        var now = Now;
        invoice.CounterRequest = kind;
        invoice.CounterRequestAmountPaise = amount;
        invoice.CounterRequestedAt = now;
        invoice.UpdatedAt = now;
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return invoice;
    }

    /// Guest: withdraws their counter request (e.g. to pay online instead).
    public async Task<Invoice> CancelCounterRequestAsync(string invoiceId, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invoice = await LockAsync(invoiceId, ct);
        await CheckReadAccessAsync(invoice, ct);
        if (invoice.CounterRequest == null) return invoice;
        invoice.ClearCounterRequest();
        invoice.UpdatedAt = Now;
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return invoice;
    }

    // ---------------------------------------------------------------- refunds

    /// Staff: refunds part or all of a successful payment. Counter payments
    /// are refunded at the counter; online ones through their provider.
    public async Task<(Refund, Invoice)> RefundAsync(string paymentId, RefundRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.IssueRefunds, ct);
        var key = ValidKey(request.IdempotencyKey);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockPaymentAsync(paymentId, ct);
        if (invoice.Refunds.FirstOrDefault(r => r.IdempotencyKey == key) is { } replay) return (replay, invoice);
        if (await db.Refunds.AnyAsync(r => r.IdempotencyKey == key, ct)) throw DuplicateRequest();

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
                $"You can refund between {Currencies.Format(1, payment.Currency)} and " +
                $"{Currencies.Format(Math.Max(0, refundable), payment.Currency)}.");
        }
        var reason = (request.Reason ?? "").Trim();
        if (reason.Length is < 3 or > 120)
        {
            throw ApiException.Validation("reason", "Give a reason of 3 to 120 characters.");
        }

        RefundStatus status;
        var reference = "";
        if (payment.Provider is CounterProvider or UpiRules.Provider)
        {
            // Counter and direct UPI payments are returned by the
            // restaurant itself (cash, or from its own UPI app); this
            // records it.
            status = RefundStatus.Processed;
        }
        else
        {
            var outcome = await ProviderOf(payment).RefundAsync(payment, request.Amount, ct);
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
            IsSimulated = payment.IsSimulated,
            ProcessedByUserId = staff.Id,
            ProcessedByName = staff.FullName,
            IdempotencyKey = key,
            CreatedAt = now,
        };
        invoice.Refunds.Add(refund);
        invoice.UpdatedAt = now;
        audit.Record(staff, "payment.refund",
            $"{(payment.IsSimulated ? "Demo refund" : "Refund")} of " +
            $"{Currencies.Format(request.Amount, payment.Currency)} on bill {invoice.BillNumber} ({reason})",
            invoice.Id);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
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
            throw DuplicateRequest();
        }
    }
}
