using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using DineQR.Api.Services;

namespace DineQR.Api.Tests;

/// Cashfree's Payment Gateway API as the server sees it (orders, order pay,
/// payments, terminate, refunds) plus its signed webhooks, kept in memory.
/// Off by default, like production without keys: a test calls [Enable] and
/// must call [Reset] when done. Tests decide what each guest does in their
/// UPI app ([Pay], [Fail], [Drop]).
public sealed class FakeCashfree
{
    public const string Secret = "test-cashfree-secret";

    /// The options the API runs with; empty (unconfigured) until [Enable].
    public CashfreeOptions Options { get; } = new() { ReconcileSeconds = 0 };

    public ConcurrentDictionary<string, FakeOrder> Orders { get; } = new();

    /// Every request, e.g. `POST /orders`.
    public ConcurrentQueue<string> Calls { get; } = new();

    /// When true every request fails as if Cashfree could not be reached.
    public bool Unreachable { get; set; }

    /// The amount (rupees) the UPI links ask for; the order's when null.
    public decimal? LinkAmount { get; set; }

    /// The QR code comes as a `upi://pay` link instead of a picture.
    public bool QrAsLink { get; set; }

    /// Ending an order takes a while: it stays `TERMINATION_REQUESTED`.
    public bool SlowTermination { get; set; }

    private int _nextPayment = 5000;

    public void Enable(string environment = "production")
    {
        Options.ClientId = "TEST_APP_ID";
        Options.ClientSecret = Secret;
        Options.CustomerPhone = "9876543210";
        Options.Environment = environment;
        Options.NotifyUrl = "https://api.test.local/api/v1/webhooks/payments/cashfree";
    }

    public void Reset()
    {
        Options.ClientId = "";
        Options.ClientSecret = "";
        Options.CustomerPhone = "";
        Options.Environment = "sandbox";
        Unreachable = false;
        LinkAmount = null;
        QrAsLink = false;
        SlowTermination = false;
        Orders.Clear();
        Calls.Clear();
    }

    public FakeOrder Order(string orderId) => Orders[orderId];

    /// The guest paid in their UPI app: the latest attempt succeeds for
    /// [amount] rupees (the order's amount unless a test says otherwise).
    public void Pay(string orderId, decimal? amount = null, string bankReference = "412345678901")
    {
        var order = Orders[orderId];
        lock (order)
        {
            var attempt = order.Attempts.LastOrDefault() ?? order.NewAttempt(Interlocked.Increment(ref _nextPayment));
            attempt.Status = "SUCCESS";
            attempt.Amount = amount ?? order.Amount;
            attempt.BankReference = bankReference;
            order.Status = "PAID";
        }
    }

    public void Fail(string orderId, string message = "Insufficient balance")
    {
        var order = Orders[orderId];
        lock (order)
        {
            var attempt = order.Attempts.LastOrDefault() ?? order.NewAttempt(Interlocked.Increment(ref _nextPayment));
            attempt.Status = "FAILED";
            attempt.Message = message;
        }
    }

    public void Drop(string orderId)
    {
        var order = Orders[orderId];
        lock (order)
        {
            var attempt = order.Attempts.LastOrDefault() ?? order.NewAttempt(Interlocked.Increment(ref _nextPayment));
            attempt.Status = "USER_DROPPED";
        }
    }

    /// A webhook body for [orderId] and its headers, signed with [secret].
    public (string Body, string Timestamp, string Signature) Webhook(string orderId,
        string type = "PAYMENT_SUCCESS_WEBHOOK", string secret = Secret)
    {
        var order = Orders.TryGetValue(orderId, out var found) ? found : null;
        var attempt = order?.Attempts.LastOrDefault();
        var body = new JsonObject
        {
            ["data"] = new JsonObject
            {
                ["order"] = new JsonObject
                {
                    ["order_id"] = orderId,
                    ["order_amount"] = order?.Amount ?? 1m,
                    ["order_currency"] = "INR",
                },
                ["payment"] = new JsonObject
                {
                    ["cf_payment_id"] = attempt?.Id ?? 1,
                    // A forged body could say anything here; the server asks the API.
                    ["payment_status"] = type == "PAYMENT_SUCCESS_WEBHOOK" ? "SUCCESS" : "FAILED",
                    ["payment_amount"] = attempt?.Amount ?? order?.Amount ?? 1m,
                    ["payment_group"] = "upi",
                },
            },
            ["event_time"] = DateTime.UtcNow.ToString("O"),
            ["type"] = type,
        }.ToJsonString();
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture);
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var signature = Convert.ToBase64String(hmac.ComputeHash(Encoding.UTF8.GetBytes(timestamp + body)));
        return (body, timestamp, signature);
    }

    internal async Task<HttpResponseMessage> HandleAsync(HttpRequestMessage request)
    {
        var path = request.RequestUri!.AbsolutePath;
        path = path[(path.IndexOf("/pg", StringComparison.Ordinal) + 3)..];
        Calls.Enqueue($"{request.Method} {path}");
        if (Unreachable) throw new HttpRequestException("Connection refused (fake Cashfree)");
        if (request.Headers.GetValues("x-client-id").Single() != Options.ClientId ||
            request.Headers.GetValues("x-client-secret").Single() != Options.ClientSecret ||
            request.Headers.GetValues("x-api-version").Single() != "2023-08-01")
        {
            return Error(HttpStatusCode.Unauthorized, "authentication_failed", "Bad credentials");
        }
        var body = request.Content == null
            ? null
            : JsonNode.Parse(await request.Content.ReadAsStringAsync());
        var parts = path.Trim('/').Split('/');

        if (request.Method == HttpMethod.Post && path == "/orders")
        {
            var id = body!["order_id"]!.GetValue<string>();
            if (Orders.ContainsKey(id)) return Error(HttpStatusCode.Conflict, "order_already_exists", "Order exists");
            var phone = body["customer_details"]!["customer_phone"]!.GetValue<string>();
            if (phone.Length != 10) return Error(HttpStatusCode.BadRequest, "customer_phone_invalid", "Phone");
            var order = new FakeOrder(id, body["order_amount"]!.GetValue<decimal>(),
                body["order_currency"]!.GetValue<string>(), $"session_{Guid.NewGuid():N}",
                body["order_meta"]?["notify_url"]?.GetValue<string>() ?? "");
            Orders[id] = order;
            return Json(order.ToJson());
        }
        if (request.Method == HttpMethod.Post && path == "/orders/sessions")
        {
            var session = body!["payment_session_id"]!.GetValue<string>();
            var order = Orders.Values.FirstOrDefault(o => o.Session == session);
            if (order == null) return Error(HttpStatusCode.BadRequest, "session_invalid", "Unknown session");
            if (order.Status != "ACTIVE") return Error(HttpStatusCode.BadRequest, "order_inactive", "Not active");
            var channel = body["payment_method"]!["upi"]!["channel"]!.GetValue<string>();
            FakeAttempt attempt;
            lock (order) attempt = order.NewAttempt(Interlocked.Increment(ref _nextPayment));
            var asks = (LinkAmount ?? order.Amount).ToString("0.00", CultureInfo.InvariantCulture);
            var query = $"pa=cashfree.test@axis&pn=Test%20Cafe&tr={attempt.Id}&am={asks}&cu=INR";
            var payload = channel == "qrcode"
                ? new JsonObject { ["qrcode"] = QrAsLink ? $"upi://pay?{query}" : "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" }
                : new JsonObject
                {
                    ["default"] = $"upi://pay?{query}",
                    ["gpay"] = $"tez://upi/pay?{query}",
                    ["phonepe"] = $"phonepe://pay?{query}",
                    ["paytm"] = $"paytmmp://pay?{query}",
                    ["bhim"] = $"upi://pay?{query}",
                };
            return Json(new JsonObject
            {
                ["cf_payment_id"] = attempt.Id,
                ["payment_method"] = "upi",
                ["channel"] = channel,
                ["action"] = "custom",
                ["data"] = new JsonObject { ["url"] = null, ["payload"] = payload },
            });
        }
        if (parts is ["orders", var orderId, ..] && !Orders.ContainsKey(orderId))
        {
            return Error(HttpStatusCode.NotFound, "order_not_found", "No such order");
        }
        if (request.Method == HttpMethod.Get && parts is ["orders", var getId])
        {
            return Json(Orders[getId].ToJson());
        }
        if (request.Method == HttpMethod.Get && parts is ["orders", var listId, "payments"])
        {
            var order = Orders[listId];
            lock (order) return Json(new JsonArray(order.Attempts.Select(a => (JsonNode)a.ToJson(order)).ToArray()));
        }
        if (request.Method == HttpMethod.Patch && parts is ["orders", var endId])
        {
            var order = Orders[endId];
            lock (order)
            {
                if (order.Status == "PAID") return Error(HttpStatusCode.BadRequest, "order_already_paid", "Paid");
                if (order.Status != "ACTIVE") return Error(HttpStatusCode.BadRequest, "order_inactive", "Not active");
                order.Status = SlowTermination ? "TERMINATION_REQUESTED" : "TERMINATED";
                return Json(order.ToJson());
            }
        }
        if (request.Method == HttpMethod.Post && parts is ["orders", var refundOrder, "refunds"])
        {
            var order = Orders[refundOrder];
            if (order.Status != "PAID") return Error(HttpStatusCode.BadRequest, "refund_invalid", "Not paid");
            return Json(new JsonObject
            {
                ["cf_refund_id"] = $"CFR{Interlocked.Increment(ref _nextPayment)}",
                ["refund_id"] = body!["refund_id"]!.GetValue<string>(),
                ["refund_amount"] = body["refund_amount"]!.GetValue<decimal>(),
                ["refund_status"] = "SUCCESS",
            });
        }
        return Error(HttpStatusCode.NotFound, "not_found", $"{request.Method} {path}");
    }

    private static HttpResponseMessage Json(JsonNode node) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(node.ToJsonString(), Encoding.UTF8, "application/json"),
    };

    private static HttpResponseMessage Error(HttpStatusCode status, string code, string message) => new(status)
    {
        Content = new StringContent(
            JsonSerializer.Serialize(new { message, code, type = "invalid_request_error" }),
            Encoding.UTF8, "application/json"),
    };
}

public sealed class FakeOrder(string id, decimal amount, string currency, string session, string notifyUrl)
{
    public string Id { get; } = id;
    public decimal Amount { get; } = amount;
    public string Currency { get; } = currency;
    public string Session { get; } = session;
    public string NotifyUrl { get; } = notifyUrl;
    public string Status { get; set; } = "ACTIVE";
    public List<FakeAttempt> Attempts { get; } = [];

    internal FakeAttempt NewAttempt(int id)
    {
        var attempt = new FakeAttempt(id);
        Attempts.Add(attempt);
        return attempt;
    }

    internal JsonObject ToJson() => new()
    {
        ["cf_order_id"] = $"CF{Id}",
        ["order_id"] = Id,
        ["order_amount"] = Amount,
        ["order_currency"] = Currency,
        ["order_status"] = Status,
        ["payment_session_id"] = Session,
    };
}

public sealed class FakeAttempt(int id)
{
    public int Id { get; } = id;
    public string Status { get; set; } = "NOT_ATTEMPTED";
    public decimal? Amount { get; set; }
    public string BankReference { get; set; } = "";
    public string Message { get; set; } = "";

    internal JsonObject ToJson(FakeOrder order) => new()
    {
        ["cf_payment_id"] = Id,
        ["order_id"] = order.Id,
        ["payment_status"] = Status,
        ["payment_amount"] = Amount ?? order.Amount,
        ["payment_currency"] = order.Currency,
        ["payment_message"] = Message,
        ["bank_reference"] = BankReference,
        ["payment_group"] = "upi",
    };
}

/// Hands each request to the shared [FakeCashfree] (the HTTP client factory
/// creates and disposes handlers on its own schedule).
public sealed class FakeCashfreeHandler(FakeCashfree cashfree) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
        cashfree.HandleAsync(request);
}
