using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace DineQR.Api.Tests;

/// UPI through Cashfree in live mode: UPI app links and QR codes for full
/// and part payments, settled automatically, and only from Cashfree's own
/// API (signed webhooks prompt the check; a lost webhook is caught by the
/// status checks). Duplicate notifications, failures, cancellations,
/// expired orders, wrong amounts and an unreachable Cashfree never mark a
/// bill paid by mistake.
[Collection(ApiCollection.Name)]
public class CashfreeTests(ApiFactory api) : IAsyncLifetime
{
    private FakeCashfree Cashfree => api.Cashfree;

    public async Task InitializeAsync()
    {
        Cashfree.Enable();
        await SetModeAsync("live");
    }

    public async Task DisposeAsync()
    {
        await SetModeAsync("demo");
        Cashfree.Reset();
    }

    private async Task SetModeAsync(string mode)
    {
        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        var saved = await owner.PutAsJsonAsync("/api/v1/admin/settings",
            current with { PaymentMode = mode }, Json.Options);
        await saved.ReadAsync<SettingsDto>();
    }

    private static async Task<InvoiceDto> BillAsync(HttpClient guest)
    {
        var response = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { new { itemId = "chicken_65", quantity = 2 } },
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var order = await response.ReadAsync<OrderDto>();
        return await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
    }

    private static Task<HttpResponseMessage> IntentAsync(HttpClient client, InvoiceDto bill, long amount,
        string method = "upi", string? key = null) =>
        client.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount, method, methodDetail = "Google Pay",
            idempotencyKey = key ?? HttpTestExtensions.Key(),
        });

    private static async Task<PaymentIntentResponse> StartAsync(HttpClient client, InvoiceDto bill, long amount) =>
        await (await IntentAsync(client, bill, amount)).ReadAsync<PaymentIntentResponse>();

    private string OrderOf(PaymentDto payment) => Cashfree.Orders.Keys.Single(k => k.StartsWith(payment.Id + "_"));

    private async Task<HttpResponseMessage> WebhookAsync(string orderId, string type = "PAYMENT_SUCCESS_WEBHOOK",
        string? signature = null, string? body = null)
    {
        var (signedBody, timestamp, signed) = Cashfree.Webhook(orderId, type);
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/webhooks/payments/cashfree")
        {
            Content = new StringContent(body ?? signedBody, Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("x-webhook-timestamp", timestamp);
        if (signature != "") request.Headers.Add("x-webhook-signature", signature ?? signed);
        return await api.Anonymous().SendAsync(request);
    }

    private static async Task<PaymentResultDto> RefreshAsync(HttpClient client, string paymentId) =>
        await (await client.GetAsync($"/api/v1/payments/{paymentId}")).ReadAsync<PaymentResultDto>();

    private async Task<T> InScopeAsync<T>(Func<IServiceProvider, Task<T>> action)
    {
        await using var scope = api.Services.CreateAsyncScope();
        return await action(scope.ServiceProvider);
    }

    // ------------------------------------------------------------ setup

    [Fact]
    public async Task Live_mode_takes_upi_through_cashfree_and_nothing_else_online()
    {
        using var config = JsonDocument.Parse(await api.Anonymous().GetStringAsync("/api/v1/payments/config"));
        var root = config.RootElement;
        Assert.Equal("live", root.GetProperty("mode").GetString());
        Assert.Equal("Cashfree", root.GetProperty("provider").GetString());
        Assert.False(root.GetProperty("simulated").GetBoolean());
        Assert.True(root.GetProperty("liveAvailable").GetBoolean());
        Assert.Equal(["upi"], root.GetProperty("methods").EnumerateArray().Select(m => m.GetString()!).ToArray());
        Assert.Equal(["upi"], root.GetProperty("liveMethods").EnumerateArray().Select(m => m.GetString()!).ToArray());

        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var card = await IntentAsync(guest, bill, bill.PayableNow, "card");
        Assert.Equal(HttpStatusCode.Conflict, card.StatusCode);
        Assert.Equal("methodUnavailable", await card.ErrorCodeAsync());
        Assert.Empty(Cashfree.Orders);
    }

    // ---------------------------------------------------------- paying

    [Fact]
    public async Task A_upi_app_payment_counts_only_once_cashfree_confirms_it()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        Assert.Equal("pending", intent.Payment.Status);
        Assert.Equal("Cashfree", intent.Payment.Provider);
        Assert.False(intent.Payment.Simulated);
        Assert.Equal("live", intent.Payment.Mode);
        Assert.NotNull(intent.Invoice);
        Assert.Equal(0, intent.Invoice!.PayableNow);

        // The exact amount, in rupees, on the gateway order.
        var orderId = OrderOf(intent.Payment);
        var order = Cashfree.Order(orderId);
        Assert.Equal(bill.PayableNow / 100m, order.Amount);
        Assert.Equal("INR", order.Currency);
        Assert.EndsWith("/api/v1/webhooks/payments/cashfree", order.NotifyUrl);

        var checkout = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout",
            new { channel = "apps" })).ReadAsync<UpiCheckoutDto>();
        Assert.StartsWith("tez://upi/pay?", checkout.Links["gpay"]);
        Assert.StartsWith("phonepe://", checkout.Links["phonepe"]);
        Assert.StartsWith("paytmmp://", checkout.Links["paytm"]);
        Assert.Contains($"am={bill.PayableNow / 100m:0.00}", checkout.Links["default"]);
        Assert.NotNull(checkout.ExpiresAt);

        // Coming back from the UPI app, or the app "confirming", proves nothing.
        Assert.Equal("pending", (await RefreshAsync(guest, intent.Payment.Id)).Payment.Status);
        var confirmed = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/confirm",
            new { simulatedOutcome = "success", providerPaymentId = "forged", signature = "forged" }))
            .ReadAsync<PaymentResultDto>();
        Assert.Equal("pending", confirmed.Payment.Status);
        Assert.Equal("pending", confirmed.Invoice.Status);
        Assert.Equal(0, confirmed.Invoice.Paid);

        // The guest pays; Cashfree's webhook arrives.
        Cashfree.Pay(orderId, bankReference: "412345678901");
        Assert.Equal(HttpStatusCode.OK, (await WebhookAsync(orderId)).StatusCode);

        var paid = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("succeeded", paid.Payment.Status);
        Assert.Equal("412345678901", paid.Payment.Ref);
        Assert.Equal("paid", paid.Invoice.Status);
        Assert.Equal(0, paid.Invoice.Outstanding);

        // Cashfree repeats itself: nothing changes, nothing is counted twice.
        var before = paid.Payment.UpdatedAt;
        var repeats = await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => WebhookAsync(orderId)));
        Assert.All(repeats, r => Assert.Equal(HttpStatusCode.OK, r.StatusCode));
        var after = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal(before, after.Payment.UpdatedAt);
        Assert.Equal(bill.Amounts.Total, after.Invoice.Paid);
        var audits = await InScopeAsync(s => s.GetRequiredService<AppDbContext>().AuditLogs
            .CountAsync(a => a.Action == "payment.gateway.paid" && a.TargetId == bill.Id));
        Assert.Equal(1, audits);
    }

    [Fact]
    public async Task A_qr_payment_for_part_of_the_bill_leaves_it_partially_paid_even_without_a_webhook()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var part = bill.PayableNow / 2;
        var intent = await StartAsync(guest, bill, part);
        var checkout = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout",
            new { channel = "qr" })).ReadAsync<UpiCheckoutDto>();
        Assert.StartsWith("data:image/png;base64,", checkout.QrImage);
        Assert.Equal(part / 100m, Cashfree.Order(OrderOf(intent.Payment)).Amount);

        // Paid, but the webhook never arrives: the app's status check settles it.
        Cashfree.Pay(OrderOf(intent.Payment));
        var paid = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("succeeded", paid.Payment.Status);
        Assert.Equal("partiallyPaid", paid.Invoice.Status);
        Assert.Equal(part, paid.Invoice.Paid);
        Assert.Equal(bill.Amounts.Total - part, paid.Invoice.Outstanding);

        // The rest, by another UPI payment.
        var rest = await StartAsync(guest, paid.Invoice, paid.Invoice.PayableNow);
        await guest.PostJsonAsync($"/api/v1/payments/{rest.Payment.Id}/checkout", new { channel = "apps" });
        Cashfree.Pay(OrderOf(rest.Payment), bankReference: "412345678902");
        await WebhookAsync(OrderOf(rest.Payment));
        var done = await RefreshAsync(guest, rest.Payment.Id);
        Assert.Equal("paid", done.Invoice.Status);
        Assert.Equal(bill.Amounts.Total, done.Invoice.Paid);
    }

    [Fact]
    public async Task Retrying_a_payment_request_reuses_the_same_payment_and_order()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var key = HttpTestExtensions.Key();
        var first = await (await IntentAsync(guest, bill, bill.PayableNow, key: key)).ReadAsync<PaymentIntentResponse>();
        var again = await (await IntentAsync(guest, bill, bill.PayableNow, key: key)).ReadAsync<PaymentIntentResponse>();
        Assert.Equal(first.Payment.Id, again.Payment.Id);
        Assert.Single(Cashfree.Orders);

        // Another app after the first: the same order, so one payment at most.
        await guest.PostJsonAsync($"/api/v1/payments/{first.Payment.Id}/checkout", new { channel = "apps" });
        await guest.PostJsonAsync($"/api/v1/payments/{first.Payment.Id}/checkout", new { channel = "qr" });
        Assert.Single(Cashfree.Orders);
        Assert.Equal(2, Cashfree.Order(OrderOf(first.Payment)).Attempts.Count);
    }

    // ------------------------------------------------- not paid, or wrong

    [Fact]
    public async Task A_failed_payment_ends_the_order_and_never_counts()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        var orderId = OrderOf(intent.Payment);
        await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout", new { channel = "apps" });

        Cashfree.Fail(orderId, "Insufficient balance");
        Assert.Equal(HttpStatusCode.OK, (await WebhookAsync(orderId, "PAYMENT_FAILED_WEBHOOK")).StatusCode);
        var failed = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("failed", failed.Payment.Status);
        Assert.Contains("Insufficient balance", failed.Payment.Failure);
        Assert.Equal("failed", failed.Invoice.Status);
        Assert.Equal(0, failed.Invoice.Paid);
        Assert.Equal(bill.Amounts.Total, failed.Invoice.PayableNow);
        // The order cannot be paid any more, so it can never succeed later.
        Assert.Equal("TERMINATED", Cashfree.Order(orderId).Status);
        var late = await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout", new { channel = "qr" });
        Assert.Equal("paymentEnded", await late.ErrorCodeAsync());
    }

    [Fact]
    public async Task Cancelling_ends_the_order_but_money_paid_first_still_counts()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var first = await StartAsync(guest, bill, bill.PayableNow);
        var cancelled = await (await guest.PostAsync($"/api/v1/payments/{first.Payment.Id}/cancel", null))
            .ReadAsync<PaymentResultDto>();
        Assert.Equal("cancelled", cancelled.Payment.Status);
        Assert.Equal("TERMINATED", Cashfree.Order(OrderOf(first.Payment)).Status);
        Assert.Equal(bill.Amounts.Total, cancelled.Invoice.PayableNow);

        // The guest paid just before cancelling: that money is recorded.
        var second = await StartAsync(guest, cancelled.Invoice, bill.PayableNow);
        await guest.PostJsonAsync($"/api/v1/payments/{second.Payment.Id}/checkout", new { channel = "apps" });
        Cashfree.Pay(OrderOf(second.Payment));
        var paid = await (await guest.PostAsync($"/api/v1/payments/{second.Payment.Id}/cancel", null))
            .ReadAsync<PaymentResultDto>();
        Assert.Equal("succeeded", paid.Payment.Status);
        Assert.Equal("paid", paid.Invoice.Status);

        // Another guest cannot touch this bill's payments.
        var stranger = await api.GuestAsync(table: 6);
        var foreign = await stranger.PostAsync($"/api/v1/payments/{second.Payment.Id}/cancel", null);
        Assert.Equal(HttpStatusCode.NotFound, foreign.StatusCode);
    }

    [Fact]
    public async Task An_amount_other_than_the_one_asked_for_is_never_counted()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        var orderId = OrderOf(intent.Payment);
        Cashfree.Pay(orderId, amount: 1m);
        await WebhookAsync(orderId);

        var result = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("failed", result.Payment.Status);
        Assert.Contains("Nothing was counted", result.Payment.Failure);
        Assert.Equal("failed", result.Invoice.Status);
        Assert.Equal(0, result.Invoice.Paid);
        var flagged = await InScopeAsync(s => s.GetRequiredService<AppDbContext>().AuditLogs
            .AnyAsync(a => a.Action == "payment.gateway.mismatch" && a.TargetId == bill.Id));
        Assert.True(flagged);
    }

    [Fact]
    public async Task Links_and_qr_codes_must_ask_for_exactly_the_payments_amount()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var part = bill.PayableNow / 2;
        var intent = await StartAsync(guest, bill, part);

        // Every link Cashfree gives is checked before the guest sees it.
        var checkout = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout",
            new { channel = "apps" })).ReadAsync<UpiCheckoutDto>();
        Assert.All(checkout.Links.Values, link =>
        {
            Assert.Contains($"am={part / 100m:0.00}&", link);
            Assert.EndsWith("cu=INR", link);
        });

        // A QR code that comes as a link is passed on for the app to draw.
        Cashfree.QrAsLink = true;
        var qr = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout",
            new { channel = "qr" })).ReadAsync<UpiCheckoutDto>();
        Assert.Equal("", qr.QrImage);
        Assert.StartsWith("upi://pay?pa=", qr.QrText);
        Assert.Contains($"am={part / 100m:0.00}&", qr.QrText);

        // Links for another amount never reach the guest.
        Cashfree.LinkAmount = bill.PayableNow / 100m;
        foreach (var channel in new[] { "apps", "qr" })
        {
            var wrong = await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout", new { channel });
            Assert.Equal(HttpStatusCode.ServiceUnavailable, wrong.StatusCode);
            Assert.Equal("gatewayRefused", await wrong.ErrorCodeAsync());
        }
        Assert.Equal("pending", (await RefreshAsync(guest, intent.Payment.Id)).Payment.Status);
    }

    [Fact]
    public async Task A_payment_stays_pending_until_cashfree_has_really_ended_its_order()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        var orderId = OrderOf(intent.Payment);

        // Cashfree accepted the request to end the order but has not ended
        // it: a payment under way could still succeed.
        Cashfree.SlowTermination = true;
        var cancelling = await (await guest.PostAsync($"/api/v1/payments/{intent.Payment.Id}/cancel", null))
            .ReadAsync<PaymentResultDto>();
        Assert.Equal("pending", cancelling.Payment.Status);
        Assert.Equal("TERMINATION_REQUESTED", Cashfree.Order(orderId).Status);
        Assert.Equal("pending", (await RefreshAsync(guest, intent.Payment.Id)).Payment.Status);

        Cashfree.Order(orderId).Status = "TERMINATED";
        var ended = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("cancelled", ended.Payment.Status);
        Assert.Equal(bill.Amounts.Total, ended.Invoice.PayableNow);
    }

    [Fact]
    public async Task Money_reported_after_a_payment_ended_is_flagged_for_staff_not_counted()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        var orderId = OrderOf(intent.Payment);
        var cancelled = await (await guest.PostAsync($"/api/v1/payments/{intent.Payment.Id}/cancel", null))
            .ReadAsync<PaymentResultDto>();
        Assert.Equal("cancelled", cancelled.Payment.Status);

        // Should never happen (the order was ended first), but if Cashfree
        // reports money afterwards, staff hear of it once.
        Cashfree.Pay(orderId, bankReference: "412345678909");
        for (var i = 0; i < 3; i++) Assert.Equal(HttpStatusCode.OK, (await WebhookAsync(orderId)).StatusCode);

        var after = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("cancelled", after.Payment.Status);
        Assert.Equal(0, after.Invoice.Paid);
        Assert.Equal(bill.Amounts.Total, after.Invoice.PayableNow);
        var alerts = await InScopeAsync(s => s.GetRequiredService<AppDbContext>().AuditLogs
            .Where(a => a.Action == "payment.gateway.late" && a.TargetId == bill.Id)
            .Select(a => a.Summary).ToListAsync());
        var alert = Assert.Single(alerts);
        Assert.Contains("Not counted", alert);
    }

    [Fact]
    public async Task Webhooks_need_cashfrees_signature_and_their_body_is_never_trusted()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        var orderId = OrderOf(intent.Payment);

        Assert.Equal(HttpStatusCode.Unauthorized, (await WebhookAsync(orderId, signature: "")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await WebhookAsync(orderId, signature: "bm90IHRoZSBzaWc=")).StatusCode);
        var (body, _, _) = Cashfree.Webhook(orderId);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await WebhookAsync(orderId, body: body.Replace("SUCCESS", "SUCCESS "))).StatusCode);

        // Genuine and claiming success, but Cashfree's API says nothing was paid.
        Assert.Equal(HttpStatusCode.OK, (await WebhookAsync(orderId)).StatusCode);
        var still = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("pending", still.Payment.Status);
        Assert.Equal("pending", still.Invoice.Status);
        Assert.Equal(0, still.Invoice.Paid);

        // An order this server never made is acknowledged and ignored.
        Cashfree.Orders["PAY999999_zzzzzz"] = new FakeOrder("PAY999999_zzzzzz", 10m, "INR", "s", "");
        Assert.Equal(HttpStatusCode.OK, (await WebhookAsync("PAY999999_zzzzzz")).StatusCode);
    }

    // ------------------------------------------------ lost and late news

    [Fact]
    public async Task The_sweep_settles_lost_webhooks_and_ends_orders_whose_time_ran_out()
    {
        var guest = await api.GuestAsync();
        var paidBill = await BillAsync(guest);
        var paid = await StartAsync(guest, paidBill, paidBill.PayableNow);
        Cashfree.Pay(OrderOf(paid.Payment));

        var otherGuest = await api.GuestAsync(table: 7);
        var abandonedBill = await BillAsync(otherGuest);
        var abandoned = await StartAsync(otherGuest, abandonedBill, abandonedBill.PayableNow);
        await otherGuest.PostJsonAsync($"/api/v1/payments/{abandoned.Payment.Id}/checkout", new { channel = "qr" });

        // A minute later (webhooks lost), and the second order's time is up.
        await InScopeAsync(async s =>
        {
            var db = s.GetRequiredService<AppDbContext>();
            await db.Database.ExecuteSqlInterpolatedAsync(
                $"update payments set created_at = created_at - interval '1 minute' where id in ({paid.Payment.Id}, {abandoned.Payment.Id})");
            await db.Database.ExecuteSqlInterpolatedAsync(
                $"update payments set expires_at = now() - interval '5 minutes' where id = {abandoned.Payment.Id}");
            return 0;
        });
        var settled = await InScopeAsync(s => s.GetRequiredService<BillingService>()
            .SweepGatewayPaymentsAsync(CancellationToken.None));
        Assert.Equal(2, settled);

        var paidNow = await RefreshAsync(guest, paid.Payment.Id);
        Assert.Equal("succeeded", paidNow.Payment.Status);
        Assert.Equal("paid", paidNow.Invoice.Status);
        var ended = await RefreshAsync(otherGuest, abandoned.Payment.Id);
        Assert.Equal("cancelled", ended.Payment.Status);
        Assert.Equal("TERMINATED", Cashfree.Order(OrderOf(abandoned.Payment)).Status);
        Assert.Equal(abandonedBill.Amounts.Total, ended.Invoice.PayableNow);
    }

    [Fact]
    public async Task An_unreachable_cashfree_starts_nothing_and_keeps_payments_pending()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);

        Cashfree.Unreachable = true;
        var status = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("pending", status.Payment.Status);
        var checkout = await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/checkout", new { channel = "apps" });
        Assert.Equal(HttpStatusCode.ServiceUnavailable, checkout.StatusCode);
        Assert.Equal("gatewayUnavailable", await checkout.ErrorCodeAsync());

        var otherGuest = await api.GuestAsync(table: 8);
        var otherBill = await BillAsync(otherGuest);
        var key = HttpTestExtensions.Key();
        var refused = await IntentAsync(otherGuest, otherBill, otherBill.PayableNow, key: key);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, refused.StatusCode);
        var untouched = await (await otherGuest.GetAsync($"/api/v1/bills/{otherBill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal(otherBill.Amounts.Total, untouched.PayableNow);

        // Back again: the same request goes through once.
        Cashfree.Unreachable = false;
        var retried = await (await IntentAsync(otherGuest, otherBill, otherBill.PayableNow, key: key))
            .ReadAsync<PaymentIntentResponse>();
        Assert.Equal("pending", retried.Payment.Status);
    }

    // ------------------------------------------------- sandbox, refunds

    [Fact]
    public async Task Sandbox_payments_are_labelled_as_demo_payments()
    {
        Cashfree.Enable("sandbox");
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        Assert.True(intent.Payment.Simulated);
        Assert.Equal("demo", intent.Payment.Mode);
        Cashfree.Pay(OrderOf(intent.Payment));
        await WebhookAsync(OrderOf(intent.Payment));
        var paid = await RefreshAsync(guest, intent.Payment.Id);
        Assert.Equal("succeeded", paid.Payment.Status);
        Assert.True(paid.Payment.Simulated);
    }

    [Fact]
    public async Task A_cashfree_payment_is_refunded_through_cashfree()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var intent = await StartAsync(guest, bill, bill.PayableNow);
        Cashfree.Pay(OrderOf(intent.Payment));
        await WebhookAsync(OrderOf(intent.Payment));

        var owner = await api.OwnerAsync();
        var refund = await owner.PostJsonAsync($"/api/v1/admin/payments/{intent.Payment.Id}/refunds", new
        {
            amount = 1000, reason = "Dish was cold", idempotencyKey = HttpTestExtensions.Key(),
        });
        var result = await refund.ReadAsync<JsonElement>();
        Assert.Equal("processed", result.GetProperty("refund").GetProperty("status").GetString());
        Assert.Contains($"POST /orders/{OrderOf(intent.Payment)}/refunds", Cashfree.Calls);
    }
}
