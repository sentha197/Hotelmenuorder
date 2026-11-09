using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;
using Microsoft.Extensions.DependencyInjection;

namespace DineQR.Api.Tests;

/// The restaurant's payment options: no demo mode and no payment simulator,
/// each online option (UPI, QR code, card, net banking, wallet) switched on
/// and off by itself, and the counter options that are always there (cash
/// or any method at the counter, and splits of them). Also the guarantees
/// around them: no overpayment, no double counting under repeats or
/// concurrency, and guests reach only their own bills.
[Collection(ApiCollection.Name)]
public class PaymentOptionsTests(ApiFactory api)
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
        string method, string? detail = null) =>
        client.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount, method, methodDetail = detail,
            idempotencyKey = HttpTestExtensions.Key(),
        });

    /// Saves like the current admin app, which sends no `paymentMode`.
    private static Task<HttpResponseMessage> PutSettingsAsync(HttpClient owner, SettingsDto settings) =>
        owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Offers = null, PaymentMode = null },
            Json.Options);

    /// Saves like an admin app from when a demo mode existed: it always sent
    /// `paymentMode`.
    private static Task<HttpResponseMessage> PutAsOlderAppAsync(HttpClient owner, SettingsDto settings,
        string mode) =>
        owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Offers = null, PaymentMode = mode },
            Json.Options);

    private static Task<HttpResponseMessage> CounterPaymentAsync(HttpClient cashier, InvoiceDto bill, long amount,
        string method = "cash", string? key = null) =>
        cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments", new
        {
            amount, method, idempotencyKey = key ?? HttpTestExtensions.Key(),
        });

    // ------------------------------------------------------ no demo mode

    [Fact]
    public async Task There_is_no_demo_mode_and_no_simulator()
    {
        // Installed apps from when a demo mode existed still read these.
        var settings = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.Equal("live", settings.PaymentMode);
        Assert.Equal("INR", settings.Currency);

        using var config = JsonDocument.Parse(await api.Anonymous().GetStringAsync("/api/v1/payments/config"));
        var root = config.RootElement;
        Assert.Equal("live", root.GetProperty("mode").GetString());
        Assert.False(root.GetProperty("simulated").GetBoolean());
        // The test server's gateway (Cashfree) has no keys: nothing online.
        Assert.False(root.GetProperty("available").GetBoolean());
        Assert.False(root.GetProperty("liveAvailable").GetBoolean());
        Assert.Empty(root.GetProperty("methods").EnumerateArray());

        // Asking for demo mode (an older admin app) changes nothing.
        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        var saved = await (await PutAsOlderAppAsync(owner, current, "demo"))
            .ReadAsync<SettingsDto>();
        Assert.Equal("live", saved.PaymentMode);

        // An online payment needs the gateway; nothing simulates one.
        var guest = await api.GuestAsync(table: 7);
        var bill = await BillAsync(guest, ("masala_dosa", 1));
        var card = await IntentAsync(guest, bill, bill.PayableNow, "card", "Credit");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, card.StatusCode);
        Assert.Equal("paymentsUnavailable", await card.ErrorCodeAsync());
        var after = await (await guest.GetAsync($"/api/v1/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Empty(after.Payments);
    }

    [Fact]
    public async Task A_payment_the_old_simulator_left_pending_no_longer_holds_its_bill()
    {
        var guest = await api.GuestAsync(table: 8);
        var bill = await BillAsync(guest, ("masala_dosa", 1));
        // As the removed simulator would have left it: started, never ended.
        var paymentId = $"PAYSIM{Random.Shared.Next(100000, 999999)}";
        using (var scope = api.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var now = DateTime.UtcNow;
            db.Payments.Add(new Payment
            {
                Id = paymentId, InvoiceId = bill.Id, OrderId = bill.Order, AmountPaise = bill.PayableNow,
                Currency = "INR", Method = PaymentMethod.Card, Status = PaymentStatus.Pending,
                Provider = PaymentProviders.RetiredSimulator, IdempotencyKey = HttpTestExtensions.Key(),
                IsSimulated = true, CreatedAt = now, UpdatedAt = now,
            });
            await db.SaveChangesAsync();
        }
        var held = await (await guest.GetAsync($"/api/v1/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal(0, held.PayableNow);

        var closed = await (await guest.GetAsync($"/api/v1/payments/{paymentId}")).ReadAsync<PaymentResultDto>();
        Assert.Equal("failed", closed.Payment.Status);
        Assert.Equal(0, closed.Invoice.Paid);
        Assert.Equal(bill.Amounts.Total, closed.Invoice.PayableNow);
    }

    // ---------------------------------------------------- online options

    [Fact]
    public async Task Each_online_option_is_saved_on_its_own()
    {
        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        try
        {
            // QR code without UPI from an app, and the other way round.
            var qrOnly = await (await PutSettingsAsync(owner, current with { Methods = ["qr", "wallet"] }))
                .ReadAsync<SettingsDto>();
            Assert.Equal(["qr", "wallet"], qrOnly.Methods);
            var reread = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
            Assert.Equal(["qr", "wallet"], reread.Methods);
            var guestView = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
            Assert.Equal(["qr", "wallet"], guestView.Methods);

            var upiOnly = await (await PutSettingsAsync(owner, current with { Methods = ["upi"] }))
                .ReadAsync<SettingsDto>();
            Assert.Equal(["upi"], upiOnly.Methods);

            // Names are normalised and repeats dropped.
            var tidy = await (await PutSettingsAsync(owner, current with { Methods = ["QR", "netbanking", "qr"] }))
                .ReadAsync<SettingsDto>();
            Assert.Equal(["qr", "netBanking"], tidy.Methods);

            var none = await (await PutSettingsAsync(owner, current with { Methods = [] })).ReadAsync<SettingsDto>();
            Assert.Empty(none.Methods);

            foreach (var unknown in new[] { "cash", "bitcoin", "" })
            {
                var refused = await PutSettingsAsync(owner, current with { Methods = [unknown] });
                Assert.Equal(HttpStatusCode.BadRequest, refused.StatusCode);
            }
        }
        finally
        {
            (await PutSettingsAsync(owner, current)).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task An_older_admin_apps_single_UPI_box_keeps_QR_on()
    {
        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        try
        {
            // Older apps send `paymentMode`; their one "UPI and QR Payment"
            // box is saved as "upi" and meant both.
            var old = await (await PutAsOlderAppAsync(owner,
                current with { Methods = ["upi", "card"] }, "live")).ReadAsync<SettingsDto>();
            Assert.Equal(["upi", "qr", "card"], old.Methods);
            var oldOff = await (await PutAsOlderAppAsync(owner,
                current with { Methods = ["card"] }, "demo")).ReadAsync<SettingsDto>();
            Assert.Equal(["card"], oldOff.Methods);

            // Current apps save exactly what was ticked.
            var upiOnly = await (await PutSettingsAsync(owner,
                current with { Methods = ["upi", "card"] })).ReadAsync<SettingsDto>();
            Assert.Equal(["upi", "card"], upiOnly.Methods);
        }
        finally
        {
            (await PutSettingsAsync(owner, current)).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task Card_or_account_numbers_are_never_accepted()
    {
        var guest = await api.GuestAsync(table: 9);
        var bill = await BillAsync(guest, ("masala_dosa", 1));

        var response = await IntentAsync(guest, bill, bill.PayableNow, "card", "4111 1111 1111 1111");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var cashier = await api.NewStaffAsync("cashier");
        var counter = await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments", new
        {
            amount = bill.PayableNow, method = "card", methodDetail = "4111111111111111",
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal(HttpStatusCode.BadRequest, counter.StatusCode);
        var after = await (await guest.GetAsync($"/api/v1/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Empty(after.Payments);
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
        var byCard = total / 2;
        var atCounter = total - byCard;
        var cashier = await api.NewStaffAsync("cashier");

        // Part 1: card, on the counter's terminal.
        var first = await (await CounterPaymentAsync(cashier, bill, byCard, "card")).ReadAsync<PaymentResultDto>();
        Assert.Equal("partiallyPaid", first.Invoice.Status);
        Assert.Equal(byCard, first.Invoice.Paid);
        // Recorded by staff: real money, never a test payment.
        Assert.False(first.Payment.Simulated);
        Assert.Equal("live", first.Payment.Mode);

        // A part larger than what is left is refused.
        Assert.Equal(HttpStatusCode.BadRequest, (await CounterPaymentAsync(cashier, bill, atCounter + 1)).StatusCode);

        // Part 2: cash at the counter. The guest's request moves no money...
        var request = await (await guest.PostJsonAsync($"/api/v1/bills/{bill.Id}/counter-request",
            new { kind = "cash" })).ReadAsync<InvoiceDto>();
        Assert.Equal(atCounter, request.CounterRequest!.Amount);
        Assert.Equal(byCard, request.Paid);

        // ...until the cashier records it, repeated taps included.
        var key = HttpTestExtensions.Key();
        var recorded = await (await CounterPaymentAsync(cashier, bill, atCounter, key: key))
            .ReadAsync<PaymentResultDto>();
        var replay = await (await CounterPaymentAsync(cashier, bill, atCounter, key: key))
            .ReadAsync<PaymentResultDto>();

        Assert.Equal(recorded.Payment.Id, replay.Payment.Id);
        Assert.Equal("paid", replay.Invoice.Status);
        Assert.Equal(total, replay.Invoice.Paid);
        Assert.Equal(0, replay.Invoice.Outstanding);
        Assert.Equal(2, replay.Invoice.Payments.Count);
        Assert.Null(replay.Invoice.CounterRequest);
        Assert.False(recorded.Payment.Simulated);
    }

    // ------------------------------------------------------- concurrency

    [Fact]
    public async Task Concurrent_payments_on_one_bill_never_overpay_it()
    {
        var guest = await api.GuestAsync(table: 14);
        var cashier = await api.NewStaffAsync("cashier");

        // The same request sent five times at once is one payment.
        var bill = await BillAsync(guest, ("masala_dosa", 1));
        var key = HttpTestExtensions.Key();
        var replays = await Task.WhenAll(Enumerable.Range(0, 5)
            .Select(_ => CounterPaymentAsync(cashier, bill, bill.PayableNow, "card", key)));
        var ids = new HashSet<string>();
        foreach (var response in replays) ids.Add((await response.ReadAsync<PaymentResultDto>()).Payment.Id);
        Assert.Single(ids);

        // Five cashiers' taps for the full amount at once: one is recorded.
        var other = await BillAsync(guest, ("butter_chicken", 1));
        var taps = await Task.WhenAll(Enumerable.Range(0, 5)
            .Select(_ => CounterPaymentAsync(cashier, other, other.PayableNow)));
        Assert.Single(taps, r => r.StatusCode == HttpStatusCode.OK);
        var settled = await (await guest.GetAsync($"/api/v1/bills/{other.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal(other.Amounts.Total, settled.Paid);
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
