using System.Globalization;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Services;

/// `Payments:Cashfree`. The client secret stays on the server: the apps never
/// see it, and Cashfree signs its webhooks with it.
public sealed partial class CashfreeOptions
{
    public const string HttpClientName = "cashfree";

    public string ClientId { get; set; } = "";
    public string ClientSecret { get; set; } = "";

    /// `sandbox` (test keys, no real money) or `production`.
    public string Environment { get; set; } = "sandbox";

    public string ApiVersion { get; set; } = "2023-08-01";

    /// The public HTTPS address of `/api/v1/webhooks/payments/cashfree`, sent
    /// with every order so Cashfree reports its payments there. Without it
    /// payments are still confirmed, by the status checks below, only later.
    public string NotifyUrl { get; set; } = "";

    /// Cashfree needs a customer phone on every order. Guests give none, so
    /// the restaurant's own 10-digit number is sent.
    public string CustomerPhone { get; set; } = "";

    /// How long a guest has to pay one order (Cashfree's minimum is 15).
    public int OrderMinutes { get; set; } = 16;

    /// How often pending payments are re-checked with Cashfree, in case a
    /// webhook was lost; 0 turns the background check off.
    public int ReconcileSeconds { get; set; } = 60;

    public bool IsProduction => Environment.Equals("production", StringComparison.OrdinalIgnoreCase);

    public string BaseUrl => IsProduction ? "https://api.cashfree.com/pg" : "https://sandbox.cashfree.com/pg";

    public bool IsConfigured =>
        ClientId.Trim().Length > 0 && ClientSecret.Trim().Length > 0 && PhonePattern().IsMatch(CustomerPhone.Trim());

    [GeneratedRegex(@"^[6-9][0-9]{9}$")]
    private static partial Regex PhonePattern();
}

/// Cashfree refused a request ([Status] 4xx) or could not be reached ([Status] 0).
public sealed class CashfreeException(int status, string code, string message)
    : Exception($"Cashfree {status} {code}: {message}")
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

/// The Cashfree Payment Gateway API (orders, order pay, payments, refunds).
public sealed class CashfreeClient(IHttpClientFactory http, CashfreeOptions options)
{
    private async Task<JsonElement> SendAsync(HttpMethod method, string path, object? body, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(method, options.BaseUrl + path);
        request.Headers.Add("x-client-id", options.ClientId.Trim());
        request.Headers.Add("x-client-secret", options.ClientSecret.Trim());
        request.Headers.Add("x-api-version", options.ApiVersion);
        if (body != null) request.Content = JsonContent.Create(body);
        HttpResponseMessage response;
        try
        {
            response = await http.CreateClient(CashfreeOptions.HttpClientName).SendAsync(request, ct);
        }
        catch (Exception error) when (error is HttpRequestException ||
                                      (error is TaskCanceledException && !ct.IsCancellationRequested))
        {
            throw new CashfreeException(0, "unreachable", error.Message);
        }
        using (response)
        {
            var text = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode)
            {
                var (code, message) = ("", text);
                try
                {
                    using var error = JsonDocument.Parse(text);
                    code = error.RootElement.TryGetProperty("code", out var c) ? c.GetString() ?? "" : "";
                    message = error.RootElement.TryGetProperty("message", out var m) ? m.GetString() ?? "" : text;
                }
                catch (JsonException)
                {
                    // Not JSON (a proxy's error page): keep the text.
                }
                throw new CashfreeException((int)response.StatusCode, code, message);
            }
            using var json = JsonDocument.Parse(text.Length == 0 ? "{}" : text);
            return json.RootElement.Clone();
        }
    }

    public Task<JsonElement> CreateOrderAsync(object order, CancellationToken ct) =>
        SendAsync(HttpMethod.Post, "/orders", order, ct);

    public Task<JsonElement> GetOrderAsync(string orderId, CancellationToken ct) =>
        SendAsync(HttpMethod.Get, $"/orders/{Uri.EscapeDataString(orderId)}", null, ct);

    public Task<JsonElement> GetPaymentsAsync(string orderId, CancellationToken ct) =>
        SendAsync(HttpMethod.Get, $"/orders/{Uri.EscapeDataString(orderId)}/payments", null, ct);

    /// "Order pay": starts a UPI payment on the order and returns the app
    /// links (`link`) or the QR code (`qrcode`).
    public Task<JsonElement> PayAsync(string sessionId, string channel, CancellationToken ct) =>
        SendAsync(HttpMethod.Post, "/orders/sessions", new
        {
            payment_session_id = sessionId,
            payment_method = new { upi = new { channel } },
        }, ct);

    public Task<JsonElement> TerminateOrderAsync(string orderId, CancellationToken ct) =>
        SendAsync(HttpMethod.Patch, $"/orders/{Uri.EscapeDataString(orderId)}",
            new { order_status = "TERMINATED" }, ct);

    public Task<JsonElement> RefundAsync(string orderId, string refundId, decimal amount, string note,
        CancellationToken ct) =>
        SendAsync(HttpMethod.Post, $"/orders/{Uri.EscapeDataString(orderId)}/refunds", new
        {
            refund_amount = amount,
            refund_id = refundId,
            refund_note = note,
        }, ct);
}

/// UPI through Cashfree: the guest pays Cashfree's order (from a UPI app or a
/// QR code) and Cashfree settles the money to the restaurant's bank account.
///
/// A payment counts only when Cashfree's own API says the order's payment
/// succeeded for exactly the amount and currency asked for. A webhook only
/// prompts that check (its body is never trusted on its own), and the app
/// returning from a UPI app, or a guest saying they paid, proves nothing.
public sealed class CashfreePaymentProvider(
    CashfreeClient client,
    CashfreeOptions options,
    TimeProvider clock,
    ILogger<CashfreePaymentProvider> logger) : IPaymentProvider, IUpiGateway
{
    public const string ProviderName = "Cashfree";

    public string Name => ProviderName;
    public bool IsAvailable => options.IsConfigured;
    public bool IsSimulated => false;
    public string? PublicKeyId => null;

    /// UPI only: the app has no card or bank checkout of its own.
    public bool Supports(PaymentMethod method) => method == PaymentMethod.Upi;

    private static ApiException Unreachable() => ApiException.Unavailable("gatewayUnavailable",
        "The payment service did not respond. Please try again in a moment.");

    private static decimal Rupees(long paise) => paise / 100m;

    private static string Token() => Convert.ToHexString(RandomNumberGenerator.GetBytes(3)).ToLowerInvariant();

    private static string OrderIdOf(Payment payment) =>
        payment.ProviderOrderId ?? throw new InvalidOperationException($"Payment {payment.Id} has no order.");

    public async Task<string> CreateOrderAsync(Payment payment, CancellationToken ct)
    {
        if (payment.Method != PaymentMethod.Upi || payment.Currency != "INR")
        {
            throw ApiException.Conflict("methodUnavailable", "Only UPI in rupees can be paid online right now.");
        }
        // Unique in the Cashfree account even when several databases (tests,
        // a restore) reuse payment numbers.
        var orderId = $"{payment.Id}_{Token()}";
        var expires = clock.GetUtcNow().AddMinutes(Math.Max(16, options.OrderMinutes));
        var order = new Dictionary<string, object?>
        {
            ["order_id"] = orderId,
            ["order_amount"] = Rupees(payment.AmountPaise),
            ["order_currency"] = payment.Currency,
            ["customer_details"] = new
            {
                customer_id = payment.GuestSessionId is { } session ? $"guest_{session:N}" : "staff",
                customer_phone = options.CustomerPhone.Trim(),
            },
            ["order_meta"] = options.NotifyUrl.Trim().Length > 0
                ? new Dictionary<string, string> { ["notify_url"] = options.NotifyUrl.Trim(), ["payment_methods"] = "upi" }
                : new Dictionary<string, string> { ["payment_methods"] = "upi" },
            ["order_expiry_time"] = expires.ToString("yyyy-MM-dd'T'HH:mm:ssK", CultureInfo.InvariantCulture),
            ["order_note"] = $"Bill payment {payment.Id}",
            ["order_tags"] = new { invoice = payment.InvoiceId, payment = payment.Id },
        };
        try
        {
            await client.CreateOrderAsync(order, ct);
        }
        catch (CashfreeException error)
        {
            logger.LogError("Cashfree refused order {Order}: {Error}", orderId, error.Message);
            throw error.Status == 0
                ? Unreachable()
                : ApiException.Unavailable("gatewayRefused",
                    "The payment service could not start this payment. Please try again or pay at the counter.");
        }
        payment.ExpiresAt = expires.UtcDateTime;
        // Sandbox payments are Cashfree's test payments: no money moves, and
        // bills and receipts must say so.
        payment.IsSimulated = !options.IsProduction;
        return orderId;
    }

    public async Task<UpiCheckout> CheckoutAsync(Payment payment, UpiCheckoutChannel channel, CancellationToken ct)
    {
        try
        {
            var order = await client.GetOrderAsync(OrderIdOf(payment), ct);
            if (Text(order, "order_status") != "ACTIVE")
            {
                throw ApiException.Conflict("paymentEnded",
                    "This payment can no longer be paid. Check its status, or start a new payment.");
            }
            var pay = await client.PayAsync(Text(order, "payment_session_id"),
                channel == UpiCheckoutChannel.Qr ? "qrcode" : "link", ct);
            var links = new Dictionary<string, string>();
            var qr = "";
            if (pay.TryGetProperty("data", out var data) &&
                data.TryGetProperty("payload", out var payload) && payload.ValueKind == JsonValueKind.Object)
            {
                foreach (var entry in payload.EnumerateObject())
                {
                    if (entry.Value.ValueKind != JsonValueKind.String) continue;
                    var value = entry.Value.GetString()!;
                    if (entry.Name == "qrcode") qr = value;
                    else links[entry.Name] = value;
                }
            }
            if (links.Count == 0 && qr.Length == 0)
            {
                logger.LogError("Cashfree returned no UPI link or QR for {Order}", payment.ProviderOrderId);
                throw ApiException.Unavailable("gatewayRefused",
                    "The payment service could not prepare this payment. Please try again.");
            }
            return new UpiCheckout(links, qr, payment.ExpiresAt);
        }
        catch (CashfreeException error)
        {
            logger.LogError("Cashfree checkout failed for {Order}: {Error}", payment.ProviderOrderId, error.Message);
            throw error.Status == 0
                ? Unreachable()
                : ApiException.Unavailable("gatewayRefused",
                    "The payment service could not prepare this payment. Please try again.");
        }
    }

    /// The app's checkout result is not evidence: only Cashfree's own record
    /// of the order is.
    public Task<ProviderOutcome> VerifyAsync(Payment payment, PaymentConfirmRequest data, CancellationToken ct) =>
        CheckStatusAsync(payment, ct);

    /// What Cashfree says about the payment's order. A final failure is only
    /// reported once the order can no longer be paid (it expired or was
    /// terminated here), so a payment never fails here and succeeds later.
    /// While Cashfree cannot be reached the payment stays pending.
    public async Task<ProviderOutcome> CheckStatusAsync(Payment payment, CancellationToken ct)
    {
        var orderId = OrderIdOf(payment);
        try
        {
            var attempts = (await client.GetPaymentsAsync(orderId, ct)).EnumerateArrayOrEmpty().ToList();
            if (attempts.FirstOrDefault(a => Text(a, "payment_status") == "SUCCESS") is { ValueKind: JsonValueKind.Object } paid)
            {
                return Verified(payment, paid);
            }
            var order = await client.GetOrderAsync(orderId, ct);
            var status = Text(order, "order_status");
            var latest = attempts.LastOrDefault();
            var latestStatus = latest.ValueKind == JsonValueKind.Object ? Text(latest, "payment_status") : "";
            switch (status)
            {
                case "PAID":
                    // The order is paid but its payment is not listed yet.
                    return new ProviderOutcome(PaymentStatus.Pending);
                case "EXPIRED":
                    return new ProviderOutcome(PaymentStatus.Cancelled, "",
                        "The payment was not completed in time. No money was taken.");
                case "TERMINATED" or "TERMINATION_REQUESTED":
                    return Ended(latest, latestStatus);
                case "ACTIVE":
                    var expired = payment.ExpiresAt is { } at && clock.GetUtcNow().UtcDateTime > at.AddMinutes(1);
                    if (latestStatus is "FAILED" or "USER_DROPPED" or "CANCELLED" or "VOID" || expired)
                    {
                        // Over: end the order first, so it cannot be paid
                        // after this payment is recorded as not paid.
                        return await EndAsync(payment, ct);
                    }
                    return new ProviderOutcome(PaymentStatus.Pending);
                default:
                    logger.LogWarning("Cashfree order {Order} has unknown status {Status}", orderId, status);
                    return new ProviderOutcome(PaymentStatus.Pending);
            }
        }
        catch (CashfreeException error)
        {
            logger.LogWarning("Cashfree status check failed for {Order}: {Error}", orderId, error.Message);
            return new ProviderOutcome(PaymentStatus.Pending);
        }
    }

    public async Task<ProviderOutcome> CancelAsync(Payment payment, CancellationToken ct)
    {
        try
        {
            return await EndAsync(payment, ct);
        }
        catch (CashfreeException error)
        {
            logger.LogWarning("Cashfree could not end order {Order}: {Error}", payment.ProviderOrderId, error.Message);
            throw error.Status == 0
                ? Unreachable()
                : ApiException.Conflict("cannotCancel", "This payment could not be cancelled. Check its status.");
        }
    }

    /// Terminates the order, then reports what Cashfree says: the guest may
    /// have paid just before.
    private async Task<ProviderOutcome> EndAsync(Payment payment, CancellationToken ct)
    {
        var orderId = OrderIdOf(payment);
        try
        {
            await client.TerminateOrderAsync(orderId, ct);
        }
        catch (CashfreeException error) when (error.Status is >= 400 and < 500)
        {
            // Already paid, expired or ended: the checks below say which.
            logger.LogInformation("Cashfree did not terminate {Order}: {Error}", orderId, error.Message);
        }
        var attempts = (await client.GetPaymentsAsync(orderId, ct)).EnumerateArrayOrEmpty().ToList();
        if (attempts.FirstOrDefault(a => Text(a, "payment_status") == "SUCCESS") is { ValueKind: JsonValueKind.Object } paid)
        {
            return Verified(payment, paid);
        }
        var order = await client.GetOrderAsync(orderId, ct);
        var latest = attempts.LastOrDefault();
        return Text(order, "order_status") switch
        {
            "PAID" => new ProviderOutcome(PaymentStatus.Pending),
            "EXPIRED" => new ProviderOutcome(PaymentStatus.Cancelled, "",
                "The payment was not completed in time. No money was taken."),
            "TERMINATED" or "TERMINATION_REQUESTED" =>
                Ended(latest, latest.ValueKind == JsonValueKind.Object ? Text(latest, "payment_status") : ""),
            // Still payable: the termination did not happen yet.
            _ => new ProviderOutcome(PaymentStatus.Pending),
        };
    }

    private static ProviderOutcome Ended(JsonElement latest, string latestStatus) =>
        latestStatus == "FAILED"
            ? new ProviderOutcome(PaymentStatus.Failed, "",
                Limit(Text(latest, "payment_message") is { Length: > 0 } message
                    ? $"The payment failed: {message}. No money was taken."
                    : "The payment failed. No money was taken."))
            : new ProviderOutcome(PaymentStatus.Cancelled, "", "The payment was not completed. No money was taken.");

    /// A successful Cashfree payment, accepted only for exactly the amount
    /// and currency this payment asked for.
    private ProviderOutcome Verified(Payment payment, JsonElement paid)
    {
        var amount = paid.TryGetProperty("payment_amount", out var a) && a.ValueKind == JsonValueKind.Number
            ? a.GetDecimal()
            : -1m;
        var currency = Text(paid, "payment_currency") is { Length: > 0 } c ? c : payment.Currency;
        var id = paid.TryGetProperty("cf_payment_id", out var p)
            ? (p.ValueKind == JsonValueKind.Number ? p.GetRawText() : p.GetString() ?? "")
            : "";
        if (amount * 100m != payment.AmountPaise || currency != payment.Currency)
        {
            logger.LogCritical(
                "Cashfree payment {Id} on {Order} is {Amount} {Currency}, not {Expected} {ExpectedCurrency}",
                id, payment.ProviderOrderId, amount, currency, Rupees(payment.AmountPaise), payment.Currency);
            return new ProviderOutcome(PaymentStatus.Failed, id,
                Limit($"Cashfree reported {amount:0.00} {currency}, not the {Rupees(payment.AmountPaise):0.00} " +
                      $"{payment.Currency} asked for. Nothing was counted: staff, check Cashfree payment {id}."),
                id);
        }
        var bankReference = Text(paid, "bank_reference");
        return new ProviderOutcome(PaymentStatus.Succeeded, bankReference.Length > 0 ? bankReference : id, "", id);
    }

    public async Task<ProviderOutcome> RefundAsync(Payment payment, long amount, CancellationToken ct)
    {
        try
        {
            var refund = await client.RefundAsync(OrderIdOf(payment), $"RF_{payment.Id}_{Token()}", Rupees(amount),
                "Refund from the restaurant", ct);
            var reference = Text(refund, "cf_refund_id") is { Length: > 0 } r ? r : Text(refund, "refund_id");
            return Text(refund, "refund_status") switch
            {
                "SUCCESS" => new ProviderOutcome(PaymentStatus.Succeeded, reference),
                "CANCELLED" => new ProviderOutcome(PaymentStatus.Failed, reference, "Cashfree cancelled the refund."),
                _ => new ProviderOutcome(PaymentStatus.Pending, reference),
            };
        }
        catch (CashfreeException error)
        {
            logger.LogError("Cashfree refund failed for {Order}: {Error}", payment.ProviderOrderId, error.Message);
            return new ProviderOutcome(PaymentStatus.Failed, "", Limit($"Cashfree refused the refund: {error.Message}"));
        }
    }

    /// Whether a webhook really comes from Cashfree: the base64 HMAC-SHA256 of
    /// its timestamp followed by the raw body, keyed with the client secret.
    public bool IsAuthentic(string? timestamp, string body, string? signature)
    {
        if (string.IsNullOrEmpty(timestamp) || string.IsNullOrEmpty(signature) || !options.IsConfigured) return false;
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(options.ClientSecret.Trim()));
        var expected = hmac.ComputeHash(Encoding.UTF8.GetBytes(timestamp + body));
        byte[] given;
        try
        {
            given = Convert.FromBase64String(signature);
        }
        catch (FormatException)
        {
            return false;
        }
        return CryptographicOperations.FixedTimeEquals(expected, given);
    }

    private static string Text(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) &&
        value.ValueKind == JsonValueKind.String
            ? value.GetString()!
            : "";

    // Payment.FailureReason is 200 characters at most.
    private static string Limit(string text) => text.Length <= 200 ? text : text[..197] + "...";
}

internal static class JsonElementExtensions
{
    public static IEnumerable<JsonElement> EnumerateArrayOrEmpty(this JsonElement element) =>
        element.ValueKind == JsonValueKind.Array ? element.EnumerateArray() : [];
}
