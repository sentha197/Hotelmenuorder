using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// UPI payments straight to the restaurant's own account (no payment
/// gateway).
///
/// The guest pays in their own UPI app and the server never sees that money
/// move. So a payment starts `pending`, the guest can only *claim* to have
/// paid, and it becomes `succeeded` only when a cashier (or a connected
/// verifier) confirms the money arrived and records the bank's transaction
/// reference. A frontend redirect, a UPI app's return value or a screenshot
/// never settles a bill, and the demo payment simulator cannot confirm these
/// payments either.
public sealed partial class BillingService
{
    private const string UpiReferenceIndex = "ix_payments_upi_reference";

    /// Guest (their own bill) or a cashier who may collect payments.
    private async Task CheckPayAccessAsync(Invoice invoice, CancellationToken ct)
    {
        if (caller.IsGuest)
        {
            if (invoice.Order.GuestSessionId != caller.GuestSessionId)
            {
                throw ApiException.NotFound("Bill not found.");
            }
            return;
        }
        await caller.RequireAsync(Permission.CollectPayments, ct);
    }

    private static Payment RequireUpi(Payment payment) =>
        UpiRules.IsDirect(payment)
            ? payment
            : throw ApiException.Conflict("notUpiPayment", "This is not a UPI payment to the restaurant.");

    /// Loads a UPI payment and its bill, taking the bill's row lock. Call
    /// inside a transaction.
    private async Task<(Payment, Invoice)> LockUpiPaymentAsync(string paymentId, CancellationToken ct)
    {
        var (payment, invoice) = await LockPaymentAsync(paymentId, ct);
        return (RequireUpi(payment), invoice);
    }

    /// Ends [payment] as [status] without moving any money.
    private void Finish(Payment payment, Invoice invoice, PaymentStatus status, string failureReason)
    {
        var now = Now;
        payment.Status = status;
        payment.FailureReason = failureReason;
        payment.UpdatedAt = now;
        payment.ConfirmedAt = now;
        invoice.UpdatedAt = now;
        invoice.UpdateSettled();
    }

    /// Drops UPI attempts the guest started but never said they had made, so
    /// an abandoned one cannot block the bill. A claimed payment is never
    /// dropped: it waits for a cashier. Returns how many were dropped.
    private int ExpireStaleUpiAttempts(Invoice invoice)
    {
        var cutoff = Now - UpiRules.AttemptWindow;
        var stale = invoice.Payments
            .Where(p => UpiRules.IsDirect(p) && p.Status == PaymentStatus.Pending &&
                        p.ClaimedAt == null && p.CreatedAt < cutoff)
            .ToList();
        foreach (var payment in stale)
        {
            Finish(payment, invoice, PaymentStatus.Cancelled, "The payment was not completed in time.");
        }
        return stale.Count;
    }

    /// Starts a UPI payment to the restaurant. The attempt is recorded as
    /// pending before the guest leaves for their UPI app, so the amount is
    /// reserved against the bill and a second attempt cannot double it.
    public async Task<(Payment, Invoice)> StartUpiAsync(UpiStartRequest request, CancellationToken ct)
    {
        var key = ValidKey(request.IdempotencyKey);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invoice = await LockAsync(request.InvoiceId, ct);
        await CheckPayAccessAsync(invoice, ct);
        if (await ReplayAsync(key, invoice, ct) is { } existing) return (RequireUpi(existing), invoice);

        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        if (!UpiRules.IsOffered(settings))
        {
            throw ApiException.Conflict("upiUnavailable",
                "UPI payment is not available right now. Please pay at the counter.");
        }
        ExpireStaleUpiAttempts(invoice);
        ValidateAmount(invoice, request.Amount, settings.AllowPartialPayments);

        var now = Now;
        var payment = new Payment
        {
            Id = await NextPaymentIdAsync(ct),
            InvoiceId = invoice.Id,
            OrderId = invoice.OrderId,
            AmountPaise = request.Amount,
            Currency = settings.Currency,
            Method = PaymentMethod.Upi,
            Status = PaymentStatus.Pending,
            Provider = UpiRules.Provider,
            IdempotencyKey = key,
            IsSimulated = false,
            GuestSessionId = caller.GuestSessionId,
            CreatedAt = now,
            UpdatedAt = now,
        };
        invoice.Payments.Add(payment);
        invoice.UpdatedAt = now;
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// The guest says they have paid. This only flags the payment for the
    /// cashier (optionally with the UPI transaction ID the guest read from
    /// their app); it does not change what the bill shows as paid.
    public async Task<(Payment, Invoice)> ClaimUpiAsync(string paymentId, UpiClaimRequest request,
        CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockUpiPaymentAsync(paymentId, ct);
        await CheckPayAccessAsync(invoice, ct);
        if (payment.Status != PaymentStatus.Pending) return (payment, invoice);

        var reference = UpiRules.NormalizeReference(request.Reference);
        if (reference.Length > 0 && !UpiRules.IsValidReference(reference))
        {
            throw ApiException.Validation("reference",
                "The UPI transaction ID is 6 to 40 letters or digits. Leave it empty if you do not have it.");
        }
        var now = Now;
        payment.ClaimedAt ??= now;
        // Unverified: shown to the cashier as what the guest reported.
        if (reference.Length > 0) payment.Reference = reference;
        payment.UpdatedAt = now;
        invoice.UpdatedAt = now;
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// Cancels a UPI payment that is still pending. A guest can only cancel
    /// one they have not claimed to have paid; after that, staff decide.
    public async Task<(Payment, Invoice)> CancelUpiAsync(string paymentId, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockUpiPaymentAsync(paymentId, ct);
        await CheckPayAccessAsync(invoice, ct);
        if (payment.Status != PaymentStatus.Pending) return (payment, invoice);
        if (caller.IsGuest && payment.ClaimedAt != null)
        {
            throw ApiException.Conflict("alreadyClaimed",
                "You have told us this was paid, so only the restaurant staff can cancel it. Please ask them.");
        }

        Finish(payment, invoice, PaymentStatus.Cancelled,
            caller.IsGuest ? "Cancelled before the payment was completed." : "Cancelled by staff.");
        if (!caller.IsGuest)
        {
            var staff = await caller.RequireStaffAsync(ct);
            payment.RecordedByUserId = staff.Id;
            payment.RecordedByName = staff.FullName;
            audit.Record(staff, "payment.upi.cancel",
                $"Cancelled UPI payment of {Currencies.Format(payment.AmountPaise, payment.Currency)} " +
                $"on bill {invoice.BillNumber}", invoice.Id);
        }
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// A cashier confirms the money reached the restaurant's account and
    /// records the bank's UPI transaction ID. The only way (besides a
    /// connected verifier) a direct UPI payment becomes `succeeded`.
    public async Task<(Payment, Invoice)> VerifyUpiAsync(string paymentId, UpiVerifyRequest request,
        CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.CollectPayments, ct);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockUpiPaymentAsync(paymentId, ct);
        if (payment.Status == PaymentStatus.Succeeded) return (payment, invoice);
        if (payment.Status != PaymentStatus.Pending)
        {
            throw ApiException.Conflict("notPending",
                $"This payment is already {EnumNames.ToName(payment.Status)}. If the money did arrive, " +
                "record it as a new payment on the bill.");
        }

        var reference = UpiRules.NormalizeReference(request.Reference);
        if (reference.Length == 0)
        {
            throw ApiException.Validation("reference",
                "Enter the UPI transaction ID shown in your bank or UPI app.");
        }
        if (!UpiRules.IsValidReference(reference))
        {
            throw ApiException.Validation("reference",
                "The UPI transaction ID is 6 to 40 letters or digits.");
        }
        var duplicate = await db.Payments.AsNoTracking().AnyAsync(
            p => p.Id != payment.Id && p.Provider == UpiRules.Provider &&
                 p.Status == PaymentStatus.Succeeded && p.Reference == reference, ct);
        if (duplicate)
        {
            throw ApiException.Conflict("duplicateReference",
                "That UPI transaction ID is already recorded on another payment.");
        }

        Finish(payment, invoice, PaymentStatus.Succeeded, "");
        payment.Reference = reference;
        payment.RecordedByUserId = staff.Id;
        payment.RecordedByName = staff.FullName;
        audit.Record(staff, "payment.upi.verify",
            $"Confirmed UPI payment of {Currencies.Format(payment.AmountPaise, payment.Currency)} " +
            $"on bill {invoice.BillNumber} (transaction {reference})", invoice.Id);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// A cashier did not receive the money: the payment fails and the
    /// balance is open again.
    public async Task<(Payment, Invoice)> RejectUpiAsync(string paymentId, UpiRejectRequest request,
        CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.CollectPayments, ct);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockUpiPaymentAsync(paymentId, ct);
        if (payment.Status != PaymentStatus.Pending)
        {
            throw ApiException.Conflict("notPending",
                $"This payment is already {EnumNames.ToName(payment.Status)}.");
        }
        var reason = (request.Reason ?? "").Trim();
        if (reason.Length == 0) reason = "The payment was not received.";
        if (reason.Length is < 3 or > 120)
        {
            throw ApiException.Validation("reason", "Give a reason of 3 to 120 characters.");
        }

        Finish(payment, invoice, PaymentStatus.Failed, reason);
        payment.RecordedByUserId = staff.Id;
        payment.RecordedByName = staff.FullName;
        audit.Record(staff, "payment.upi.reject",
            $"Rejected UPI payment of {Currencies.Format(payment.AmountPaise, payment.Currency)} " +
            $"on bill {invoice.BillNumber} ({reason})", invoice.Id);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// Asks the connected verifier about a pending payment, but only when
    /// the restaurant chose automatic verification and one really exists.
    /// A success without a valid bank reference is ignored: no evidence, no
    /// payment. Returns whether the payment changed.
    private async Task<bool> TryVerifyAutomaticallyAsync(Payment payment, Invoice invoice, CancellationToken ct)
    {
        if (!upiVerifier.IsAvailable) return false;
        var mode = await db.Settings.AsNoTracking().Select(s => s.UpiVerificationMode).SingleAsync(ct);
        if (mode != UpiVerificationMode.Automatic) return false;

        var outcome = await upiVerifier.CheckAsync(payment, ct);
        switch (outcome.Status)
        {
            case PaymentStatus.Succeeded:
                var reference = UpiRules.NormalizeReference(outcome.Reference);
                if (!UpiRules.IsValidReference(reference)) return false;
                var duplicate = await db.Payments.AsNoTracking().AnyAsync(
                    p => p.Id != payment.Id && p.Provider == UpiRules.Provider &&
                         p.Status == PaymentStatus.Succeeded && p.Reference == reference, ct);
                if (duplicate) return false;
                Finish(payment, invoice, PaymentStatus.Succeeded, "");
                payment.Reference = reference;
                payment.RecordedByName = upiVerifier.Name;
                return true;
            case PaymentStatus.Failed or PaymentStatus.Cancelled:
                Finish(payment, invoice, outcome.Status,
                    string.IsNullOrWhiteSpace(outcome.FailureReason)
                        ? "The payment was not received."
                        : outcome.FailureReason);
                payment.RecordedByName = upiVerifier.Name;
                return true;
            default:
                return false;
        }
    }

    /// Automatic verification (if on), then dropping abandoned attempts.
    private async Task<bool> ResolveUpiAsync(Payment payment, Invoice invoice, CancellationToken ct)
    {
        var changed = await TryVerifyAutomaticallyAsync(payment, invoice, ct);
        if (payment.Status == PaymentStatus.Pending) changed |= ExpireStaleUpiAttempts(invoice) > 0;
        return changed;
    }
}
