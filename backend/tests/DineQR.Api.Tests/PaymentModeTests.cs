using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Tests;

/// Demo and live payment modes, every guest payment option (online through
/// the demo simulator, cash or any method at the counter, and splits of
/// them), and the guarantees around them: no overpayment, no double
/// counting under repeats or concurrency, failed attempts never count, and
/// guests reach only their own bills.
[Collection(ApiCollection.Name)]
public class PaymentModeTests(ApiFactory api)
{
    private static async Task<InvoiceDto> BillAsync(HttpClient guest, params (string Item, int Quantity)[] lines)
    {
        var response = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = lines.Select(l => new { itemId = l.Item, quantity = l.Quantity }).ToArray(),
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var order = await response.ReadAsync<OrderDto>();
        return await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
    }

    private static Task<HttpResponseMessage> IntentAsync(HttpClient client, InvoiceDto bill, long amount,
        string method, string? detail = null, string? key = null) =>
        client.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount, method, methodDetail = detail,
            idempotencyKey = key ?? HttpTestExtensions.Key(),
        });

    private static async Task<PaymentResultDto> PayAsync(HttpClient client, InvoiceDto bill, long amount,
        string method, string outcome = "success", string? detail = null)
    {
        var intent = await (await IntentAsync(client, bill, amount, method, detail))
            .ReadAsync<PaymentIntentResponse>();
        return await (await client.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/confirm",
            new { simulatedOutcome = outcome })).ReadAsync<PaymentResultDto>();
    }

    private static Task<HttpResponseMessage> PutSettingsAsync(HttpClient owner, SettingsDto settings) =>
        owner.PutAsJsonAsync("/api/v1/admin/settings", settings, Json.Options);

    // ------------------------------------------------------------ modes

    [Fact]
    public async Task Restaurants_start_in_demo_mode_and_live_mode_needs_a_gateway()
    {
        var settings = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.Equal("demo", settings.PaymentMode);
        Assert.Equal("INR", settings.Currency);

        using var config = JsonDocument.Parse(await api.Anonymous().GetStringAsync("/api/v1/payments/config"));
        var root = config.RootElement;
        Assert.Equal("demo", root.GetProperty("mode").GetString());
        // Apps from before payment modes read these three.
        Assert.True(root.GetProperty("available").GetBoolean());
        Assert.True(root.GetProperty("simulated").GetBoolean());
        Assert.Equal("Simulator", root.GetProperty("provider").GetString());
        Assert.False(root.GetProperty("liveAvailable").GetBoolean());

        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        var live = await PutSettingsAsync(owner, current with { PaymentMode = "live" });
        Assert.Equal(HttpStatusCode.Conflict, live.StatusCode);
        Assert.Equal("liveUnavailable", await live.ErrorCodeAsync());
        var unknown = await PutSettingsAsync(owner, current with { PaymentMode = "free" });
        Assert.Equal(HttpStatusCode.BadRequest, unknown.StatusCode);

        // A save without the field (an older app) keeps the mode.
        var kept = await (await PutSettingsAsync(owner, current with { PaymentMode = null }))
            .ReadAsync<SettingsDto>();
        Assert.Equal("demo", kept.PaymentMode);
    }

    [Fact]
    public async Task A_demo_payment_is_labelled_and_records_detail_and_currency()
    {
        var guest = await api.GuestAsync(table: 7);
        var bill = await BillAsync(guest, ("masala_dosa", 1));

        var intent = await (await IntentAsync(guest, bill, bill.PayableNow, "upi", "Scan & Pay"))
            .ReadAsync<PaymentIntentResponse>();
        Assert.True(intent.Simulated);
        Assert.Equal("demo", intent.Mode);
        Assert.Equal("INR", intent.Currency);
        var paid = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/confirm",
            new { simulatedOutcome = "success" })).ReadAsync<PaymentResultDto>();

        Assert.Equal("succeeded", paid.Payment.Status);
        Assert.StartsWith("DEMO-", paid.Payment.Ref);
        Assert.Equal("demo", paid.Payment.Mode);
        Assert.Equal("INR", paid.Payment.Currency);
        Assert.Equal("Scan & Pay", paid.Payment.Detail);
        Assert.Equal("paid", paid.Invoice.Status);
        Assert.Equal(0, paid.Invoice.Outstanding);
    }

    [Fact]
    public async Task Card_or_account_numbers_are_never_accepted()
    {
        var guest = await api.GuestAsync(table: 8);
        var bill = await BillAsync(guest, ("masala_dosa", 1));

        var response = await IntentAsync(guest, bill, bill.PayableNow, "card", "4111 1111 1111 1111");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var after = await (await guest.GetAsync($"/api/v1/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Empty(after.Payments);
    }

    [Fact]
    public async Task Failed_and_cancelled_payments_never_count()
    {
        var guest = await api.GuestAsync(table: 9);
        var bill = await BillAsync(guest, ("paneer_tikka", 1));

        var failed = await PayAsync(guest, bill, bill.PayableNow, "netBanking", "failure", "HDFC Bank");
        Assert.Equal("failed", failed.Payment.Status);
        Assert.Equal(0, failed.Invoice.Paid);
        Assert.Equal("failed", failed.Invoice.Status);

        var cancelled = await PayAsync(guest, bill, bill.PayableNow, "wallet", "cancel", "PhonePe");
        Assert.Equal("cancelled", cancelled.Payment.Status);
        Assert.Equal(0, cancelled.Invoice.Paid);
        Assert.Equal(bill.Amounts.Total, cancelled.Invoice.Outstanding);

        // A final result cannot be confirmed again.
        var again = await (await guest.PostJsonAsync($"/api/v1/payments/{failed.Payment.Id}/confirm",
            new { simulatedOutcome = "success" })).ReadAsync<PaymentResultDto>();
        Assert.Equal("failed", again.Payment.Status);
        Assert.Equal(0, again.Invoice.Paid);
    }

    // ------------------------------------------------- counter and split

    [Fact]
    public async Task A_counter_request_moves_no_money_and_only_its_guest_can_make_it()
    {
        var guest = await api.GuestAsync(table: 10);
        var bill = await BillAsync(guest, ("butter_chicken", 1));
        var url = $"/api/v1/bills/{bill.Id}/counter-request";

        var requested = await (await guest.PostJsonAsync(url, new { kind = "counter" })).ReadAsync<InvoiceDto>();
        Assert.Equal("counter", requested.CounterRequest!.Kind);
        Assert.Equal(bill.Amounts.Total, requested.CounterRequest.Amount);
        Assert.Equal("unpaid", requested.Status);
        Assert.Equal(0, requested.Paid);
        Assert.Empty(requested.Payments);

        // Staff see it on the bill.
        var cashier = await api.NewStaffAsync("cashier");
        var seen = await (await cashier.GetAsync($"/api/v1/admin/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal("counter", seen.CounterRequest!.Kind);

        // Other guests and staff tokens cannot make or remove it.
        var stranger = await api.GuestAsync(table: 11);
        Assert.Equal(HttpStatusCode.NotFound,
            (await stranger.PostJsonAsync(url, new { kind = "cash" })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.DeleteAsync(url)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await cashier.PostJsonAsync(url, new { kind = "cash" })).StatusCode);

        Assert.Equal(HttpStatusCode.BadRequest, (await guest.PostJsonAsync(url, new { kind = "cheque" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await guest.PostJsonAsync(url, new { kind = "cash", amount = bill.Amounts.Total + 1 })).StatusCode);

        var withdrawn = await (await guest.DeleteAsync(url)).ReadAsync<InvoiceDto>();
        Assert.Null(withdrawn.CounterRequest);
    }

    [Fact]
    public async Task A_split_bill_settles_once_without_double_counting()
    {
        var guest = await api.GuestAsync(table: 12);
        var bill = await BillAsync(guest, ("chicken_65", 2), ("butter_naan", 2));
        var total = bill.Amounts.Total;
        var online = total / 2;
        var atCounter = total - online;

        // Part 1: card, online (demo).
        var first = await PayAsync(guest, bill, online, "card", detail: "Credit");
        Assert.Equal("partiallyPaid", first.Invoice.Status);
        Assert.Equal(online, first.Invoice.Paid);

        // A part larger than what is left is refused.
        var tooMuch = await IntentAsync(guest, bill, atCounter + 1, "upi");
        Assert.Equal(HttpStatusCode.BadRequest, tooMuch.StatusCode);

        // Part 2: cash at the counter. The guest's request moves no money...
        var request = await (await guest.PostJsonAsync($"/api/v1/bills/{bill.Id}/counter-request",
            new { kind = "cash" })).ReadAsync<InvoiceDto>();
        Assert.Equal(atCounter, request.CounterRequest!.Amount);
        Assert.Equal(online, request.Paid);

        // ...until the cashier records it, repeated taps included.
        var cashier = await api.NewStaffAsync("cashier");
        var key = HttpTestExtensions.Key();
        var body = new { amount = atCounter, method = "cash", idempotencyKey = key };
        var recorded = await (await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments", body))
            .ReadAsync<PaymentResultDto>();
        var replay = await (await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments", body))
            .ReadAsync<PaymentResultDto>();

        Assert.Equal(recorded.Payment.Id, replay.Payment.Id);
        Assert.Equal("paid", replay.Invoice.Status);
        Assert.Equal(total, replay.Invoice.Paid);
        Assert.Equal(0, replay.Invoice.Outstanding);
        Assert.Equal(2, replay.Invoice.Payments.Count);
        Assert.Null(replay.Invoice.CounterRequest);
        // Recorded in demo mode, so labelled as a demo payment too.
        Assert.True(recorded.Payment.Simulated);
        Assert.Equal("demo", recorded.Payment.Mode);

        var nothingLeft = await (await guest.GetAsync($"/api/v1/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal(total, nothingLeft.Paid);
    }

    // ------------------------------------------------------- concurrency

    [Fact]
    public async Task Concurrent_payments_on_one_bill_never_overpay_it()
    {
        var guest = await api.GuestAsync(table: 14);
        var bill = await BillAsync(guest, ("paneer_tikka", 2));

        // Five full-amount attempts at once: one starts, the rest are refused.
        var attempts = await Task.WhenAll(Enumerable.Range(0, 5)
            .Select(_ => IntentAsync(guest, bill, bill.PayableNow, "upi")));
        Assert.Single(attempts, r => r.StatusCode == HttpStatusCode.OK);
        foreach (var refused in attempts.Where(r => r.StatusCode != HttpStatusCode.OK))
        {
            Assert.Equal("paymentInProgress", await refused.ErrorCodeAsync());
        }

        // The same request sent five times at once is one payment.
        var other = await BillAsync(guest, ("masala_dosa", 1));
        var key = HttpTestExtensions.Key();
        var replays = await Task.WhenAll(Enumerable.Range(0, 5)
            .Select(_ => IntentAsync(guest, other, other.PayableNow, "card", key: key)));
        var ids = new HashSet<string>();
        foreach (var response in replays) ids.Add((await response.ReadAsync<PaymentIntentResponse>()).Payment.Id);
        Assert.Single(ids);

        // Five cashiers' taps for the full amount at once: one is recorded.
        var third = await BillAsync(guest, ("butter_chicken", 1));
        var cashier = await api.NewStaffAsync("cashier");
        var taps = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ =>
            cashier.PostJsonAsync($"/api/v1/admin/bills/{third.Id}/payments", new
            {
                amount = third.PayableNow, method = "cash", idempotencyKey = HttpTestExtensions.Key(),
            })));
        Assert.Single(taps, r => r.StatusCode == HttpStatusCode.OK);
        var settled = await (await guest.GetAsync($"/api/v1/bills/{third.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal(third.Amounts.Total, settled.Paid);
        Assert.Single(settled.Payments);
    }

    // ---------------------------------------------------------- currency

    [Fact]
    public async Task The_currency_is_fixed_once_bills_exist()
    {
        var guest = await api.GuestAsync(table: 15);
        await BillAsync(guest, ("masala_dosa", 1));
        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();

        var unsupported = await PutSettingsAsync(owner, current with { Currency = "XYZ" });
        Assert.Equal(HttpStatusCode.BadRequest, unsupported.StatusCode);
        var locked = await PutSettingsAsync(owner, current with { Currency = "USD" });
        Assert.Equal(HttpStatusCode.Conflict, locked.StatusCode);
        Assert.Equal("currencyLocked", await locked.ErrorCodeAsync());

        var kept = await (await PutSettingsAsync(owner, current with { Currency = null })).ReadAsync<SettingsDto>();
        Assert.Equal("INR", kept.Currency);
    }
}
