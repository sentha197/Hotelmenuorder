using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// UPI payments collected by a gateway (Cashfree): the guest pays from a UPI
/// app or a QR code, and the payment is settled automatically from what the
/// gateway's own API reports, prompted by its webhook, by the app asking for
/// the status, or by the background sweep. Nobody confirms these by hand,
/// and nothing the app says about them counts.
public sealed partial class BillingService
{
    private IUpiGateway GatewayOf(Payment payment) =>
        ProviderOf(payment) as IUpiGateway
        ?? throw ApiException.Conflict("notGatewayPayment", "This payment is not paid by UPI app or QR code.");

    private static UpiCheckoutChannel ParseChannel(string? channel) => (channel ?? "apps").ToLowerInvariant() switch
    {
        "apps" or "app" or "link" => UpiCheckoutChannel.Apps,
        "qr" or "qrcode" => UpiCheckoutChannel.Qr,
        _ => throw ApiException.Validation("channel", "Choose a UPI app or the QR code."),
    };

    /// Guest (own bill) or cashier: the UPI app links or the QR code for a
    /// pending gateway payment. Asking again (another app, or the QR after an
    /// app) pays the same order, so it can never be paid twice.
    public async Task<(Payment Payment, UpiCheckout Checkout)> CheckoutAsync(string paymentId, string? channel,
        CancellationToken ct)
    {
        var parsed = ParseChannel(channel);
        var payment = await db.Payments.AsNoTracking()
                          .Include(p => p.Invoice).ThenInclude(i => i.Order)
                          .FirstOrDefaultAsync(p => p.Id == paymentId, ct)
                      ?? throw ApiException.NotFound("Payment not found.");
        await CheckPayAccessAsync(payment.Invoice, ct);
        if (payment.Status != PaymentStatus.Pending)
        {
            throw ApiException.Conflict("paymentEnded",
                "This payment can no longer be paid. Check its status, or start a new payment.");
        }
        return (payment, await GatewayOf(payment).CheckoutAsync(payment, parsed, ct));
    }

    /// Guest (own bill, before paying) or cashier: cancels a pending payment.
    /// A gateway payment's order is ended at the gateway first; if the guest
    /// had already paid, the payment is recorded as paid instead.
    public async Task<(Payment, Invoice)> CancelPaymentAsync(string paymentId, CancellationToken ct)
    {
        var provider = await db.Payments.Where(p => p.Id == paymentId).Select(p => p.Provider)
                           .FirstOrDefaultAsync(ct)
                       ?? throw ApiException.NotFound("Payment not found.");
        if (provider == UpiRules.Provider) return await CancelUpiAsync(paymentId, ct);

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockPaymentAsync(paymentId, ct);
        await CheckPayAccessAsync(invoice, ct);
        if (payment.Status != PaymentStatus.Pending) return (payment, invoice);
        var outcome = await GatewayOf(payment).CancelAsync(payment, ct);
        if (outcome.Status == PaymentStatus.Pending) return (payment, invoice);
        Apply(payment, invoice, outcome);
        if (outcome.Status == PaymentStatus.Cancelled && !caller.IsGuest)
        {
            var staff = await caller.RequireStaffAsync(ct);
            payment.RecordedByUserId = staff.Id;
            payment.RecordedByName = staff.FullName;
            audit.Record(staff, "payment.cancel",
                $"Cancelled {payment.Provider} payment of {Currencies.Format(payment.AmountPaise, payment.Currency)} " +
                $"on bill {invoice.BillNumber}", invoice.Id);
        }
        RecordGatewayResult(payment, invoice, outcome);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return (payment, invoice);
    }

    /// A gateway reported news about [providerOrderId] (a webhook). Returns
    /// false when no payment has that order. What changes is decided by the
    /// gateway's API, not by the notification.
    public async Task<bool> ResolveGatewayOrderAsync(string providerOrderId, CancellationToken ct)
    {
        var paymentId = await db.Payments.Where(p => p.ProviderOrderId == providerOrderId)
            .Select(p => p.Id).FirstOrDefaultAsync(ct);
        if (paymentId == null) return false;
        await ResolveGatewayPaymentAsync(paymentId, ct);
        return true;
    }

    /// Settles a pending gateway payment from the gateway's own record. Runs
    /// for the gateway (webhook, sweep), not for a person, so it checks no
    /// caller. Repeats are harmless: a settled payment is left alone. Returns
    /// whether the payment was settled now.
    private async Task<bool> ResolveGatewayPaymentAsync(string paymentId, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var (payment, invoice) = await LockPaymentAsync(paymentId, ct);
        if (payment.Status != PaymentStatus.Pending) return false;
        if (providers.Named(payment.Provider) is not { } provider || provider is not IUpiGateway) return false;
        var outcome = await provider.CheckStatusAsync(payment, ct);
        if (outcome.Status == PaymentStatus.Pending) return false;
        Apply(payment, invoice, outcome);
        RecordGatewayResult(payment, invoice, outcome);
        await SaveAsync(ct);
        await tx.CommitAsync(ct);
        await notifier.BillChanged(invoice, invoice.Order.GuestSessionId);
        return true;
    }

    /// Re-checks pending gateway payments whose webhook may have been lost,
    /// and ends orders whose time ran out. Returns how many were settled.
    public async Task<int> SweepGatewayPaymentsAsync(CancellationToken ct)
    {
        var gateway = providers.Live;
        if (gateway is not IUpiGateway || !gateway.IsAvailable) return 0;
        // A webhook normally arrives within seconds; leave fresh ones to it.
        var settledBy = Now.AddSeconds(-20);
        var pending = await db.Payments.AsNoTracking()
            .Where(p => p.Status == PaymentStatus.Pending && p.Provider == gateway.Name &&
                        p.ProviderOrderId != null && p.CreatedAt < settledBy)
            .OrderBy(p => p.CreatedAt)
            .Select(p => p.Id)
            .Take(100)
            .ToListAsync(ct);
        var settled = 0;
        foreach (var id in pending)
        {
            if (await ResolveGatewayPaymentAsync(id, ct)) settled++;
            // Each payment is read fresh under its bill's lock.
            db.ChangeTracker.Clear();
        }
        return settled;
    }

    /// The audit trail of what the gateway decided.
    private void RecordGatewayResult(Payment payment, Invoice invoice, ProviderOutcome outcome)
    {
        var amount = Currencies.Format(payment.AmountPaise, payment.Currency);
        switch (outcome.Status)
        {
            case PaymentStatus.Succeeded:
                audit.Record(null, "payment.gateway.paid",
                    $"{payment.Provider} confirmed the UPI payment of {amount} on bill {invoice.BillNumber} " +
                    $"(transaction {payment.Reference})", invoice.Id);
                break;
            case PaymentStatus.Failed when payment.ProviderPaymentId != null:
                // Money moved, but not as asked (e.g. another amount).
                audit.Record(null, "payment.gateway.mismatch",
                    $"{payment.Provider} payment {payment.ProviderPaymentId} on bill {invoice.BillNumber} was " +
                    $"not counted: {payment.FailureReason}", invoice.Id);
                break;
        }
    }
}
