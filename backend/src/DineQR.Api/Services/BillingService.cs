using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace DineQR.Api.Services;

/// Bills, counter payments and refunds. DineQR takes no payments online:
/// guests order, then pay at the restaurant's billing counter, where staff
/// record the payment against the bill. Amounts come from the bill's
/// snapshot; the guest app never records or changes a payment.
///
/// Payments recorded before online payment was retired (gateway, UPI to the
/// restaurant, the old demo simulator) stay on their bills as history and
/// still count toward what was paid.
///
/// Every change to a bill's payments runs in a transaction that holds the
/// bill's row lock ([LockAsync]). Requests for one bill therefore run one
/// after another: each sees what the others recorded, a repeated request
/// finds its first result, and no mix of payments can overpay the bill.
public sealed class BillingService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    /// [Payment.Provider] of every payment recorded at the billing counter.
    public const string CounterProvider = "Counter";

    /// [Payment.Provider] of payments made to the restaurant's own UPI ID
    /// before online payment was retired. Kept as history only.
    public const string LegacyUpiDirectProvider = "UPI direct";

    /// [Payment.Provider] of payments the long-retired demo simulator took
    /// (no money moved). Kept as history only.
    public const string LegacySimulatorProvider = "Simulator";

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

    /// Staff listing: bills created in [from, to) plus any still to be
    /// settled at the counter, newest first.
    public async Task<List<Invoice>> ForStaffAsync(DateTime? from, DateTime? to, CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ViewBills, ct);
        var start = from ?? Now.AddDays(-30);
        var end = to ?? DateTime.MaxValue;
        // Payments, refunds and lines are loaded by id afterwards (ListLoading).
        var bills = await db.Invoices.Include(i => i.Order).AsNoTracking()
            .Where(i => (i.CreatedAt >= start && i.CreatedAt < end) || !i.IsSettled)
            .OrderByDescending(i => i.CreatedAt)
            .Take(2000)
            .ToListAsync(ct);
        await ListLoading.LoadBillChildrenAsync(db, bills, ct);
        return bills;
    }

    // ------------------------------------------------------- counter payments

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

    /// Display-only detail of a method (`Credit`, a card network, a bank
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

    /// Same rules as the admin apps: more than zero and never above what is
    /// still due. A bill may be settled in several counter payments.
    private static void ValidateAmount(Invoice invoice, long amount)
    {
        if (invoice.IsVoid) throw ApiException.Conflict("billVoid", "This bill was cancelled.");
        if (amount <= 0) throw ApiException.Validation("amount", "Enter an amount above zero.");
        var payable = invoice.PayableNowPaise;
        if (payable == 0) throw ApiException.Conflict("nothingDue", "Nothing is due on this bill.");
        if (amount > payable) throw ApiException.Validation("amount", "That is more than the amount due.");
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

    /// Staff: a payment taken at the billing counter (cash, card terminal,
    /// or the counter's own UPI scanner). The staff member confirms it, so it
    /// is recorded as successful.
    public async Task<(Payment, Invoice)> RecordCounterPaymentAsync(string invoiceId,
        CounterPaymentRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.CollectPayments, ct);
        var key = ValidKey(request.IdempotencyKey);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invoice = await LockAsync(invoiceId, ct);
        if (await ReplayAsync(key, invoice, ct) is { } replay) return (replay, invoice);

        var method = ParseMethod(request.Method);
        if (!CounterMethods.IsAllowed(method))
        {
            throw ApiException.Validation("method", "The counter takes cash, card or UPI.");
        }
        var detail = ValidDetail(request.MethodDetail);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        ValidateAmount(invoice, request.Amount);
        var reference = (request.Reference ?? "").Trim();
        if (reference.Length > 100) throw ApiException.Validation("reference", "Reference is too long.");

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
            $"Recorded {method} payment of " +
            $"{Currencies.Format(request.Amount, settings.Currency)} on bill {invoice.BillNumber}", invoice.Id);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    // ---------------------------------------------------------------- refunds

    /// Staff: records a refund of part or all of a successful payment. The
    /// restaurant returns the money itself at the counter; this records it.
    /// A payment taken through the retired online gateway is refunded from
    /// that gateway's own dashboard, not from here.
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
        if (payment.Provider is not (CounterProvider or LegacyUpiDirectProvider or LegacySimulatorProvider))
        {
            throw ApiException.Conflict("refundAtProvider",
                $"This payment was taken online through {payment.Provider}. " +
                "Refund it from that provider's dashboard.");
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

        var now = Now;
        var refund = new Refund
        {
            Id = $"RFD{await db.NextValueAsync(AppDbContext.RefundSequence, ct):D5}",
            InvoiceId = invoice.Id,
            PaymentId = payment.Id,
            AmountPaise = request.Amount,
            Reason = reason,
            // Returned by the restaurant itself (cash, or its own card
            // terminal or UPI app); this records it. The retired simulator
            // moved no money, so there was nothing to send back.
            Status = RefundStatus.Processed,
            Reference = "",
            IsSimulated = payment.IsSimulated,
            ProcessedByUserId = staff.Id,
            ProcessedByName = staff.FullName,
            IdempotencyKey = key,
            CreatedAt = now,
        };
        invoice.Refunds.Add(refund);
        invoice.UpdatedAt = now;
        audit.Record(staff, "payment.refund",
            $"Refund of " +
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
                                              { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            throw DuplicateRequest();
        }
    }
}
