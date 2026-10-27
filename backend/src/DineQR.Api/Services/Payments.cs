using System.Security.Cryptography;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Services;

/// What a provider reports for a payment or refund after verifying it.
public sealed record ProviderOutcome(PaymentStatus Status, string Reference = "", string FailureReason = "");

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

    Task<string> CreateOrderAsync(Payment payment, CancellationToken ct);

    Task<ProviderOutcome> VerifyAsync(Payment payment, PaymentConfirmRequest data, CancellationToken ct);

    Task<ProviderOutcome> CheckStatusAsync(Payment payment, CancellationToken ct);

    Task<ProviderOutcome> RefundAsync(Payment payment, long amount, CancellationToken ct);
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
    /// The live gateway. `None` (the default) is the only value until a real
    /// gateway is integrated. `Simulated`, its old development value, means
    /// the same: the simulator now serves demo mode wherever it runs.
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
