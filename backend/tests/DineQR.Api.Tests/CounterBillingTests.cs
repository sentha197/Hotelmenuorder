using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;
using Microsoft.Extensions.DependencyInjection;

namespace DineQR.Api.Tests;

/// Billing at the counter, now the only way a bill is paid: staff record
/// cash, card or UPI taken at the counter, in one payment or several. Also the
/// guarantees around it (no overpayment, no double counting under repeats or
/// concurrency, no card numbers stored) and that payments recorded before
/// online payment was retired still read, count and refund as before.
[Collection(ApiCollection.Name)]
public class CounterBillingTests(ApiFactory api)
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

    private static Task<HttpResponseMessage> PutSettingsAsync(HttpClient owner, SettingsDto settings) =>
        owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Offers = null }, Json.Options);

    private static Task<HttpResponseMessage> CounterPaymentAsync(HttpClient cashier, InvoiceDto bill, long amount,
        string method = "cash", string? key = null) =>
        cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments", new
        {
            amount, method, idempotencyKey = key ?? HttpTestExtensions.Key(),
        });

    /// Writes a payment as the retired online flows left it.
    private async Task<string> AddLegacyPaymentAsync(InvoiceDto bill, string provider, PaymentMethod method,
        PaymentStatus status)
    {
        var id = $"PAYOLD{Random.Shared.Next(100000, 999999)}";
        using var scope = api.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var now = DateTime.UtcNow;
        db.Payments.Add(new Payment
        {
            Id = id, InvoiceId = bill.Id, OrderId = bill.Order, AmountPaise = bill.Amounts.Total,
            Currency = "INR", Method = method, Status = status, Provider = provider,
            Reference = status == PaymentStatus.Succeeded ? $"5{Random.Shared.Next(10000000, 99999999)}" : "",
            IdempotencyKey = HttpTestExtensions.Key(), CreatedAt = now, UpdatedAt = now,
            ConfirmedAt = status == PaymentStatus.Succeeded ? now : null,
        });
        var invoice = await db.Invoices.FindAsync(bill.Id);
        invoice!.IsSettled = status == PaymentStatus.Succeeded;
        await db.SaveChangesAsync();
        return id;
    }

    [Fact]
    public async Task Card_or_account_numbers_are_never_accepted()
    {
        var guest = await api.GuestAsync(table: 9);
        var bill = await BillAsync(guest, ("masala_dosa", 1));
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

    [Fact]
    public async Task A_split_bill_settles_once_without_double_counting()
    {
        var guest = await api.GuestAsync(table: 12);
        var bill = await BillAsync(guest, ("chicken_65", 2), ("butter_naan", 2));
        var total = bill.Amounts.Total;
        var byCard = total / 2;
        var inCash = total - byCard;
        var cashier = await api.NewStaffAsync("cashier");

        // Part 1: card, on the counter's terminal.
        var first = await (await CounterPaymentAsync(cashier, bill, byCard, "card")).ReadAsync<PaymentResultDto>();
        Assert.Equal("partiallyPaid", first.Invoice.Status);
        Assert.Equal(byCard, first.Invoice.Paid);
        // Recorded by staff: real money, never a test payment.
        Assert.False(first.Payment.Simulated);
        Assert.Equal("live", first.Payment.Mode);

        // A part larger than what is left is refused.
        Assert.Equal(HttpStatusCode.BadRequest, (await CounterPaymentAsync(cashier, bill, inCash + 1)).StatusCode);

        // Part 2: cash, repeated taps included.
        var key = HttpTestExtensions.Key();
        var recorded = await (await CounterPaymentAsync(cashier, bill, inCash, key: key))
            .ReadAsync<PaymentResultDto>();
        var replay = await (await CounterPaymentAsync(cashier, bill, inCash, key: key))
            .ReadAsync<PaymentResultDto>();

        Assert.Equal(recorded.Payment.Id, replay.Payment.Id);
        Assert.Equal("paid", replay.Invoice.Status);
        Assert.Equal(total, replay.Invoice.Paid);
        Assert.Equal(0, replay.Invoice.Outstanding);
        Assert.Equal(2, replay.Invoice.Payments.Count);
        Assert.Equal(HttpStatusCode.Conflict, (await CounterPaymentAsync(cashier, bill, 100)).StatusCode);
    }

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

    // ------------------------------------------------------------ history

    [Fact]
    public async Task Payments_from_before_online_payment_was_retired_still_count_and_refund()
    {
        var guest = await api.GuestAsync(table: 16);
        var bill = await BillAsync(guest, ("masala_dosa", 2));
        var paymentId = await AddLegacyPaymentAsync(bill, BillingService.LegacyUpiDirectProvider,
            PaymentMethod.Upi, PaymentStatus.Succeeded);

        var owner = await api.OwnerAsync();
        var read = await (await owner.GetAsync($"/api/v1/admin/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal("paid", read.Status);
        var payment = Assert.Single(read.Payments);
        Assert.Equal(paymentId, payment.Id);
        Assert.Equal("UPI direct", payment.Provider);
        Assert.Equal("upi", payment.Method);

        // The restaurant returned that money from its own UPI app: recorded.
        var refunded = await owner.PostJsonAsync($"/api/v1/admin/payments/{paymentId}/refunds",
            new { amount = 100, reason = "Overcharged", idempotencyKey = HttpTestExtensions.Key() });
        Assert.Equal(HttpStatusCode.OK, refunded.StatusCode);
        var after = await (await owner.GetAsync($"/api/v1/admin/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal("partiallyRefunded", after.Status);
        Assert.Equal("processed", Assert.Single(after.Refunds).Status);
    }

    [Fact]
    public async Task A_gateway_payment_is_kept_but_refunded_at_the_gateway()
    {
        var guest = await api.GuestAsync(table: 17);
        var bill = await BillAsync(guest, ("butter_chicken", 1));
        var paymentId = await AddLegacyPaymentAsync(bill, "Cashfree", PaymentMethod.Upi, PaymentStatus.Succeeded);

        var owner = await api.OwnerAsync();
        var refused = await owner.PostJsonAsync($"/api/v1/admin/payments/{paymentId}/refunds",
            new { amount = 100, reason = "Overcharged", idempotencyKey = HttpTestExtensions.Key() });
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("refundAtProvider", await refused.ErrorCodeAsync());
        var read = await (await owner.GetAsync($"/api/v1/admin/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal("paid", read.Status);
        Assert.Empty(read.Refunds);
    }
}
