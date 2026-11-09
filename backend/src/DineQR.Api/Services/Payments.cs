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
/// `bhim`); the QR code is [QrImage], a `data:image/png;base64,` picture, or
/// [QrText], a `upi://pay` link for the app to draw as one. All carry the
/// exact amount and are tied to one gateway order.
public sealed record UpiCheckout(
    IReadOnlyDictionary<string, string> Links,
    string QrImage,
    DateTime? ExpiresAt,
    string QrText = "");

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
    /// The payment gateway: `Cashfree` (with `Payments:Cashfree` set), or
    /// `None` (the default: no online payments through a gateway). `Simulated`,
    /// a value from when a demo simulator existed, also means `None`.
    public string Provider { get; set; } = "None";
}

/// The payment gateway online payments go through. There is no simulator:
/// without a configured gateway, guests pay the restaurant's own UPI ID (if
/// set up) or at the counter.
public sealed class PaymentProviders(IPaymentProvider live)
{
    /// [Payment.Provider] of payments the demo simulator took before it was
    /// removed. No money moved for them; they are kept as history.
    public const string RetiredSimulator = "Simulator";

    public IPaymentProvider Live { get; } = live;

    /// A real gateway is configured.
    public bool LiveAvailable => Live.IsAvailable;

    /// The provider that took a payment, or null when it is not configured
    /// (any more).
    public IPaymentProvider? Named(string name) =>
        name == Live.Name && Live.IsAvailable ? Live : null;
}

/// Used while no gateway is configured: online payments through a gateway
/// are unavailable; UPI to the restaurant and counter payments still work.
public sealed class UnavailablePaymentProvider : IPaymentProvider
{
    public string Name => "None";
    public bool IsAvailable => false;
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

