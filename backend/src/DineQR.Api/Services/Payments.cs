using System.Security.Cryptography;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Services;

/// What a provider reports for a payment or refund after verifying it.
/// [ProviderPaymentId] is the provider's own id for the payment that
/// succeeded, where it has one.
public sealed record ProviderOutcome(
    PaymentStatus Status,
    string Reference = "",
    string FailureReason = "",
    string? ProviderPaymentId = null);

/// A payment provider integration (for example Razorpay). The server, not
/// the app, decides whether a payment succeeded: [VerifyAsync] must check
/// the provider's signature and fetch the payment from the provider.
public interface IPaymentProvider
{
    string Name { get; }

    /// False when no provider is configured: online payment is refused.
    bool IsAvailable { get; }

    /// True for the demo simulator (no money moves).
    bool IsSimulated { get; }

    /// Public key id the app may use to open the provider checkout.
    string? PublicKeyId { get; }

    /// Whether guests can pay with [method] through this provider.
    bool Supports(PaymentMethod method) => method != PaymentMethod.Cash;

    Task<string> CreateOrderAsync(Payment payment, CancellationToken ct);

    Task<ProviderOutcome> VerifyAsync(Payment payment, PaymentConfirmRequest data, CancellationToken ct);

    Task<ProviderOutcome> CheckStatusAsync(Payment payment, CancellationToken ct);

    Task<ProviderOutcome> RefundAsync(Payment payment, long amount, CancellationToken ct);
}

/// How a guest pays a gateway UPI payment: in a UPI app on this phone, or by
/// scanning a QR code.
public enum UpiCheckoutChannel { Apps, Qr }

/// What the guest pays a gateway UPI payment with. [Links] are `upi://` (or
/// app-specific) links keyed by app (`default`, `gpay`, `phonepe`, `paytm`,
/// `bhim`); [QrImage] is a `data:image/png;base64,` picture. Both carry the
/// exact amount and are tied to one gateway order.
public sealed record UpiCheckout(IReadOnlyDictionary<string, string> Links, string QrImage, DateTime? ExpiresAt);

/// A gateway that collects UPI payments itself and reports them (webhook and
/// status API), so a payment is confirmed without anyone checking a bank
/// statement.
public interface IUpiGateway
{
    /// UPI app links or a QR code for a pending payment's order.
    Task<UpiCheckout> CheckoutAsync(Payment payment, UpiCheckoutChannel channel, CancellationToken ct);

    /// Ends a pending payment's order so it can no longer be paid. Returns
    /// what the gateway then reports: `Cancelled`, or `Succeeded` when the
    /// guest had already paid.
    Task<ProviderOutcome> CancelAsync(Payment payment, CancellationToken ct);
}

/// Confirms UPI payments made straight to the restaurant's own account
/// without a cashier, through a bank or payment-provider integration (a
/// statement or notification API the restaurant has been onboarded to).
///
/// None ships with the app, so [IsAvailable] stays false until one is
/// registered, and "automatic verification" cannot be selected. Until then
/// only a cashier confirms that money arrived: a guest's claim, the UPI
/// app's return value or a screenshot never counts as payment.
public interface IUpiPaymentVerifier
{
    /// Shown in the audit trail as who confirmed a payment.
    string Name { get; }

    /// True only when a real integration is configured.
    bool IsAvailable { get; }

    /// What the bank or provider says about [payment]. Return `Pending`
    /// while unknown. A `Succeeded` outcome must carry the bank's
    /// transaction reference; without one it is ignored.
    Task<ProviderOutcome> CheckAsync(Payment payment, CancellationToken ct);
}

/// The default: no integration, so only cashiers confirm UPI payments.
public sealed class UnavailableUpiPaymentVerifier : IUpiPaymentVerifier
{
    public string Name => "None";
    public bool IsAvailable => false;

    public Task<ProviderOutcome> CheckAsync(Payment payment, CancellationToken ct) =>
        Task.FromResult(new ProviderOutcome(PaymentStatus.Pending));
}

public sealed class PaymentOptions
{
    /// The live gateway: `Cashfree` (with `Payments:Cashfree` set), or `None`
    /// (the default: live mode cannot be chosen). `Simulated`, an old
    /// development value, means `None`: the simulator serves demo mode
    /// wherever it runs.
    public string Provider { get; set; } = "None";
}

/// The providers a payment can go through: the built-in demo simulator and
/// the live gateway. The restaurant's [PaymentMode] picks the one that takes
/// new online payments; earlier payments stay with the one that took them.
public sealed class PaymentProviders(IPaymentProvider live)
{
    public IPaymentProvider Demo { get; } = new SimulatedPaymentProvider();

    public IPaymentProvider Live { get; } = live;

    /// Live mode needs a real gateway: the simulator never counts as one.
    public bool LiveAvailable => Live.IsAvailable && !Live.IsSimulated;

    public IPaymentProvider For(PaymentMode mode) => mode == PaymentMode.Live ? Live : Demo;

    /// The provider that took a payment, or null when it is not configured
    /// (any more).
    public IPaymentProvider? Named(string name) =>
        name == Demo.Name ? Demo : name == Live.Name && Live.IsAvailable ? Live : null;
}

/// The live gateway until one is integrated: live online payments are
/// unavailable; demo mode and counter payments still work.
public sealed class UnavailablePaymentProvider : IPaymentProvider
{
    public string Name => "None";
    public bool IsAvailable => false;
    public bool IsSimulated => false;
    public string? PublicKeyId => null;

    private static ApiException Unavailable() => ApiException.Unavailable("paymentsUnavailable",
        "Online payment is not available right now. Please pay at the counter.");

    public Task<string> CreateOrderAsync(Payment payment, CancellationToken ct) => throw Unavailable();

    public Task<ProviderOutcome> VerifyAsync(Payment payment, PaymentConfirmRequest data, CancellationToken ct) =>
        throw Unavailable();

    public Task<ProviderOutcome> CheckStatusAsync(Payment payment, CancellationToken ct) =>
        Task.FromResult(new ProviderOutcome(PaymentStatus.Pending));

    public Task<ProviderOutcome> RefundAsync(Payment payment, long amount, CancellationToken ct) =>
        throw Unavailable();
}

/// The demo-mode provider. Every payment it handles is flagged
/// `isSimulated` (a demo payment), and bills and receipts say that no money
/// moved. It never contacts a bank; the outcome is chosen in the app
/// (success, failure or cancel).
public sealed class SimulatedPaymentProvider : IPaymentProvider
{
    // Stored on every payment it took, so it keeps its original name.
    public string Name => "Simulator";
    public bool IsAvailable => true;
    public bool IsSimulated => true;
    public string? PublicKeyId => null;

    public Task<string> CreateOrderAsync(Payment payment, CancellationToken ct) =>
        Task.FromResult($"demo_order_{Token()}");

    public Task<ProviderOutcome> VerifyAsync(Payment payment, PaymentConfirmRequest data, CancellationToken ct) =>
        Task.FromResult((data.SimulatedOutcome ?? "success").ToLowerInvariant() switch
        {
            "failure" or "failed" => new ProviderOutcome(PaymentStatus.Failed, "",
                "Declined in the demo simulator (no money moved)."),
            "cancel" or "cancelled" => new ProviderOutcome(PaymentStatus.Cancelled, "",
                "Cancelled in the demo simulator (no money moved)."),
            _ => new ProviderOutcome(PaymentStatus.Succeeded, $"DEMO-{Token()}"),
        });

    /// An attempt that never came back is treated as not completed.
    public Task<ProviderOutcome> CheckStatusAsync(Payment payment, CancellationToken ct) =>
        Task.FromResult(new ProviderOutcome(PaymentStatus.Failed, "", "The demo payment was not completed."));

    public Task<ProviderOutcome> RefundAsync(Payment payment, long amount, CancellationToken ct) =>
        Task.FromResult(new ProviderOutcome(PaymentStatus.Succeeded, $"DEMO-RFD-{Token()}"));

    private static string Token() => Convert.ToHexString(RandomNumberGenerator.GetBytes(6));
}
