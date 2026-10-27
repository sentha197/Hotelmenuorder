using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace DineQR.Api.Tests;

/// UPI payments straight to the restaurant's own account: the settings, the
/// payment lifecycle and, above all, that nothing but a cashier (or a real
/// verifier) can mark one paid.
[Collection(ApiCollection.Name)]
public class UpiPaymentTests(ApiFactory api) : IAsyncLifetime
{
    private const string SettingsUrl = "/api/v1/admin/payments/settings";
    private const string QrUploadUrl = "/api/v1/admin/uploads/upi-qr";

    private static readonly byte[] Png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    // The settings row is shared by every test: start each from a known
    // state and leave UPI off so other tests are unaffected.
    public async Task InitializeAsync()
    {
        api.Verifier.Reset();
        var owner = await api.OwnerAsync();
        (await owner.PutAsJsonAsync(SettingsUrl, Payload())).EnsureSuccessStatusCode();
    }

    public async Task DisposeAsync()
    {
        api.Verifier.Reset();
        var owner = await api.OwnerAsync();
        (await owner.PutAsJsonAsync(SettingsUrl, Payload(enabled: false, qr: ""))).EnsureSuccessStatusCode();
    }

    // ------------------------------------------------------------ helpers

    private static object Payload(
        bool enabled = true,
        string? upiId = "cafe@okhdfcbank",
        string? name = "Test Cafe",
        string? qr = "",
        string? mode = "manual") =>
        new { enabled, upiId, payeeName = name, qrImage = qr, verificationMode = mode };

    private static object Line(string itemId, int quantity) =>
        new { itemId, quantity, options = new { portion = (string?)null, addOns = Array.Empty<string>() } };

    private static async Task<InvoiceDto> BillAsync(HttpClient guest, string dish = "paneer_tikka", int quantity = 1)
    {
        var placed = await guest.PostJsonAsync("/api/v1/orders",
            new { lines = new[] { Line(dish, quantity) }, idempotencyKey = HttpTestExtensions.Key() });
        var order = await placed.ReadAsync<OrderDto>();
        return await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
    }

    private static Task<HttpResponseMessage> StartAsync(HttpClient client, InvoiceDto bill, long? amount = null,
        string? key = null) =>
        client.PostJsonAsync("/api/v1/payments/upi", new
        {
            invoiceId = bill.Id, amount = amount ?? bill.PayableNow, idempotencyKey = key ?? HttpTestExtensions.Key(),
        });

    private static async Task<PaymentResultDto> StartOkAsync(HttpClient client, InvoiceDto bill, long? amount = null) =>
        await (await StartAsync(client, bill, amount)).ReadAsync<PaymentResultDto>();

    private static Task<HttpResponseMessage> ClaimAsync(HttpClient client, string paymentId, string? reference = null) =>
        client.PostJsonAsync($"/api/v1/payments/{paymentId}/upi/claim", new { reference });

    private static Task<HttpResponseMessage> VerifyAsync(HttpClient staff, string paymentId, string? reference) =>
        staff.PostJsonAsync($"/api/v1/admin/payments/{paymentId}/verify", new { reference });

    private static Task<HttpResponseMessage> RejectAsync(HttpClient staff, string paymentId, string? reason = null) =>
        staff.PostJsonAsync($"/api/v1/admin/payments/{paymentId}/reject", new { reason });

    private static Task<HttpResponseMessage> CancelAsync(HttpClient client, string paymentId) =>
        client.PostJsonAsync($"/api/v1/payments/{paymentId}/cancel", new { });

    private static async Task<InvoiceDto> BillOfAsync(HttpClient client, string orderId) =>
        await (await client.GetAsync($"/api/v1/orders/{orderId}/bill")).ReadAsync<InvoiceDto>();

    private static async Task<PaymentDto> RefreshAsync(HttpClient client, string paymentId) =>
        (await (await client.GetAsync($"/api/v1/payments/{paymentId}")).ReadAsync<PaymentResultDto>()).Payment;

    private async Task BackdateAsync(string paymentId, TimeSpan age)
    {
        using var scope = api.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var created = DateTime.UtcNow - age;
        await db.Payments.Where(p => p.Id == paymentId)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.CreatedAt, created));
    }

    private static MultipartFormDataContent Form(byte[] bytes, string name = "qr.png", string type = "image/png")
    {
        var content = new ByteArrayContent(bytes);
        content.Headers.ContentType = new MediaTypeHeaderValue(type);
        return new MultipartFormDataContent { { content, "file", name } };
    }

    private static byte[] Image(byte[] signature, int length = 256)
    {
        var bytes = new byte[length];
        signature.CopyTo(bytes, 0);
        return bytes;
    }

    // ----------------------------------------------------------- settings

    [Fact]
    public async Task Only_the_owner_changes_payment_settings_but_staff_can_read_them()
    {
        var owner = await api.OwnerAsync();
        var saved = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(name: "Spice Route")))
            .ReadAsync<PaymentSettingsDto>();
        Assert.True(saved.Enabled);
        Assert.True(saved.Ready);
        Assert.Equal("cafe@okhdfcbank", saved.UpiId);
        Assert.Equal("Spice Route", saved.PayeeName);
        Assert.Equal("manual", saved.VerificationMode);
        Assert.False(saved.AutomaticVerificationAvailable);

        var cashier = await api.NewStaffAsync("cashier");
        Assert.Equal(HttpStatusCode.Forbidden,
            (await cashier.PutAsJsonAsync(SettingsUrl, Payload(upiId: "thief@okaxis"))).StatusCode);
        var read = await (await cashier.GetAsync(SettingsUrl)).ReadAsync<PaymentSettingsDto>();
        Assert.Equal("cafe@okhdfcbank", read.UpiId);

        // A manager runs the floor but does not own the settings.
        var manager = await api.NewStaffAsync("manager");
        Assert.Equal(HttpStatusCode.Forbidden, (await manager.PutAsJsonAsync(SettingsUrl, Payload())).StatusCode);

        var guest = await api.GuestAsync();
        Assert.Equal(HttpStatusCode.Forbidden, (await guest.GetAsync(SettingsUrl)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await guest.PutAsJsonAsync(SettingsUrl, Payload())).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync(SettingsUrl)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await api.Anonymous().PutAsJsonAsync(SettingsUrl, Payload())).StatusCode);
    }

    [Theory]
    [InlineData("no-at-sign")]
    [InlineData("@okhdfcbank")]
    [InlineData("cafe@")]
    [InlineData("ca fe@okhdfcbank")]
    [InlineData("cafe@b")]
    [InlineData("cafe@bank@x")]
    [InlineData("c@okhdfcbank")]
    [InlineData("cafe@123bank")]
    public async Task A_malformed_UPI_ID_is_refused(string upiId)
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PutAsJsonAsync(SettingsUrl, Payload(upiId: upiId));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("validation", await response.ErrorCodeAsync());
        // Nothing was saved.
        var current = await (await owner.GetAsync(SettingsUrl)).ReadAsync<PaymentSettingsDto>();
        Assert.Equal("cafe@okhdfcbank", current.UpiId);
    }

    [Fact]
    public async Task Switching_UPI_on_needs_a_UPI_ID_and_a_payee_name()
    {
        var owner = await api.OwnerAsync();
        Assert.Equal(HttpStatusCode.BadRequest,
            (await owner.PutAsJsonAsync(SettingsUrl, Payload(upiId: ""))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await owner.PutAsJsonAsync(SettingsUrl, Payload(name: "  "))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await owner.PutAsJsonAsync(SettingsUrl, Payload(name: "<b>Cafe</b>"))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await owner.PutAsJsonAsync(SettingsUrl, Payload(name: new string('x', 61)))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await owner.PutAsJsonAsync(SettingsUrl, Payload(mode: "psychic"))).StatusCode);

        // Switched off, the details may be incomplete.
        var off = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(enabled: false, upiId: "", name: "")))
            .ReadAsync<PaymentSettingsDto>();
        Assert.False(off.Enabled);
        Assert.False(off.Ready);
    }

    [Fact]
    public async Task The_UPI_ID_and_name_are_trimmed_and_the_ID_is_lower_cased()
    {
        var owner = await api.OwnerAsync();
        var saved = await (await owner.PutAsJsonAsync(SettingsUrl,
            Payload(upiId: "  Cafe.Owner@OkHDFCBank ", name: "  Spice Route  "))).ReadAsync<PaymentSettingsDto>();
        Assert.Equal("cafe.owner@okhdfcbank", saved.UpiId);
        Assert.Equal("Spice Route", saved.PayeeName);
    }

    [Fact]
    public async Task Settings_can_be_disabled_and_enabled_again_without_losing_the_details()
    {
        var owner = await api.OwnerAsync();
        var guest = await api.GuestAsync();
        var off = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(enabled: false)))
            .ReadAsync<PaymentSettingsDto>();
        Assert.False(off.Enabled);
        Assert.Equal("cafe@okhdfcbank", off.UpiId);

        // While off, guests learn nothing about the account.
        var hidden = await (await guest.GetAsync("/api/v1/payments/upi")).ReadAsync<UpiConfigDto>();
        Assert.False(hidden.Enabled);
        Assert.Equal("", hidden.UpiId);
        Assert.Equal("", hidden.PayeeName);

        var on = await (await owner.PutAsJsonAsync(SettingsUrl, Payload())).ReadAsync<PaymentSettingsDto>();
        Assert.True(on.Enabled);
        var shown = await (await guest.GetAsync("/api/v1/payments/upi")).ReadAsync<UpiConfigDto>();
        Assert.True(shown.Enabled);
        Assert.Equal("cafe@okhdfcbank", shown.UpiId);
        Assert.Equal("Test Cafe", shown.PayeeName);
        Assert.Equal("manual", shown.VerificationMode);
    }

    [Fact]
    public async Task The_payee_is_only_shown_to_a_guest_session_or_staff()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/v1/payments/upi")).StatusCode);
        var cashier = await api.NewStaffAsync("cashier");
        Assert.Equal(HttpStatusCode.OK, (await cashier.GetAsync("/api/v1/payments/upi")).StatusCode);
    }

    [Fact]
    public async Task Payment_settings_changes_are_recorded_in_the_activity_log()
    {
        var owner = await api.OwnerAsync();
        (await owner.PutAsJsonAsync(SettingsUrl, Payload(upiId: "old@oksbi"))).EnsureSuccessStatusCode();
        (await owner.PutAsJsonAsync(SettingsUrl, Payload(upiId: "new@oksbi"))).EnsureSuccessStatusCode();

        var log = await (await owner.GetAsync("/api/v1/admin/audit?action=settings.payments&limit=20"))
            .ReadAsync<List<AuditDto>>();
        var change = log.First(a => a.Summary.Contains("new@oksbi"));
        Assert.Contains("from old@oksbi to new@oksbi", change.Summary);
        Assert.Equal("Test Owner", change.Name);
    }

    [Fact]
    public async Task Automatic_verification_cannot_be_chosen_without_a_connected_provider()
    {
        var owner = await api.OwnerAsync();
        var refused = await owner.PutAsJsonAsync(SettingsUrl, Payload(mode: "automatic"));
        Assert.Equal(HttpStatusCode.BadRequest, refused.StatusCode);
        var body = await refused.Content.ReadAsStringAsync();
        Assert.Contains("verificationMode", body);
        Assert.Contains("none is set up", body);

        var current = await (await owner.GetAsync(SettingsUrl)).ReadAsync<PaymentSettingsDto>();
        Assert.Equal("manual", current.VerificationMode);
        Assert.False(current.AutomaticVerificationAvailable);
    }

    // ---------------------------------------------------- starting a payment

    [Fact]
    public async Task A_UPI_payment_starts_pending_and_reserves_the_amount()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);

        var started = await StartOkAsync(guest, bill);
        var payment = started.Payment;
        Assert.Equal("pending", payment.Status);
        Assert.Equal("upi", payment.Method);
        Assert.Equal(UpiRules.Provider, payment.Provider);
        Assert.False(payment.Simulated);
        Assert.Equal(bill.Amounts.Total, payment.Amount);
        Assert.Null(payment.Claimed);

        // Starting is not paying: nothing is collected, but the balance is
        // reserved so it cannot be paid twice.
        var invoice = started.Invoice;
        Assert.Equal("pending", invoice.Status);
        Assert.Equal(0, invoice.Paid);
        Assert.Equal(bill.Amounts.Total, invoice.Outstanding);
        Assert.Equal(0, invoice.PayableNow);

        var again = await StartAsync(guest, bill, amount: 100);
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
        Assert.Equal("paymentInProgress", await again.ErrorCodeAsync());

        var cashier = await api.NewStaffAsync("cashier");
        var counter = await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments",
            new { amount = 100, method = "cash", idempotencyKey = HttpTestExtensions.Key() });
        Assert.Equal("paymentInProgress", await counter.ErrorCodeAsync());
    }

    [Fact]
    public async Task Two_simultaneous_starts_hold_the_balance_only_once()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var results = await Task.WhenAll(StartAsync(guest, bill), StartAsync(guest, bill));

        // One wins; the other is told a payment is already in progress (or
        // that the bill changed under it). Never two reservations.
        Assert.All(results, r => Assert.True(
            r.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict, $"{(int)r.StatusCode}"));
        Assert.Contains(results, r => r.StatusCode == HttpStatusCode.OK);
        var after = await BillOfAsync(guest, bill.Order);
        Assert.Single(after.Payments, p => p.Status == "pending");
        Assert.Equal(0, after.PayableNow);
        Assert.Equal(bill.Amounts.Total, after.Outstanding);
    }

    [Fact]
    public async Task Replaying_a_start_request_returns_the_same_payment()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var key = HttpTestExtensions.Key();
        var first = await (await StartAsync(guest, bill, key: key)).ReadAsync<PaymentResultDto>();
        var second = await (await StartAsync(guest, bill, key: key)).ReadAsync<PaymentResultDto>();
        Assert.Equal(first.Payment.Id, second.Payment.Id);
        Assert.Single(second.Invoice.Payments);
    }

    [Fact]
    public async Task The_server_checks_the_amount_against_the_balance()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        Assert.Equal(HttpStatusCode.BadRequest, (await StartAsync(guest, bill, amount: 0)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await StartAsync(guest, bill, amount: -500)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await StartAsync(guest, bill, amount: bill.Amounts.Total + 1)).StatusCode);

        // A part payment leaves the rest to pay.
        var half = bill.Amounts.Total / 2;
        var part = await StartOkAsync(guest, bill, half);
        Assert.Equal(half, part.Payment.Amount);
        Assert.Equal(bill.Amounts.Total - half, part.Invoice.PayableNow);
        Assert.Equal(bill.Amounts.Total, part.Invoice.Outstanding);
    }

    [Fact]
    public async Task A_restaurant_that_wants_the_full_amount_refuses_part_payments()
    {
        var owner = await api.OwnerAsync();
        var settings = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Partial = false }))
            .EnsureSuccessStatusCode();
        try
        {
            var guest = await api.GuestAsync();
            var bill = await BillAsync(guest);
            var part = await StartAsync(guest, bill, amount: bill.Amounts.Total / 2);
            Assert.Equal(HttpStatusCode.BadRequest, part.StatusCode);
            Assert.Equal(HttpStatusCode.OK, (await StartAsync(guest, bill)).StatusCode);
        }
        finally
        {
            (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings)).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task UPI_is_refused_while_it_is_switched_off()
    {
        var owner = await api.OwnerAsync();
        (await owner.PutAsJsonAsync(SettingsUrl, Payload(enabled: false))).EnsureSuccessStatusCode();
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var response = await StartAsync(guest, bill);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("upiUnavailable", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task Other_guests_cannot_start_claim_cancel_or_read_a_UPI_payment()
    {
        var mine = await api.GuestAsync();
        var stranger = await api.GuestAsync();
        var bill = await BillAsync(mine);
        Assert.Equal(HttpStatusCode.NotFound, (await StartAsync(stranger, bill)).StatusCode);

        var payment = (await StartOkAsync(mine, bill)).Payment;
        Assert.Equal(HttpStatusCode.NotFound, (await ClaimAsync(stranger, payment.Id)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await CancelAsync(stranger, payment.Id)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.GetAsync($"/api/v1/payments/{payment.Id}")).StatusCode);
        Assert.Equal("pending", (await RefreshAsync(mine, payment.Id)).Status);
    }

    // ------------------------------------- the app can never mark it paid

    [Fact]
    public async Task The_payment_simulator_cannot_confirm_a_UPI_payment()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;

        // The test server runs the development simulator, which would
        // happily "succeed" an ordinary online payment.
        var confirm = await guest.PostJsonAsync($"/api/v1/payments/{payment.Id}/confirm",
            new { simulatedOutcome = "success" });
        Assert.Equal(HttpStatusCode.Conflict, confirm.StatusCode);
        Assert.Equal("notOnlinePayment", await confirm.ErrorCodeAsync());

        var after = await BillOfAsync(guest, bill.Order);
        Assert.Equal(0, after.Paid);
        Assert.Equal("pending", after.Status);
    }

    [Fact]
    public async Task A_guest_claim_flags_the_payment_but_does_not_pay_the_bill()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;

        var claimed = await (await ClaimAsync(guest, payment.Id, " utr-1234-5678 ")).ReadAsync<PaymentResultDto>();
        Assert.Equal("pending", claimed.Payment.Status);
        Assert.NotNull(claimed.Payment.Claimed);
        Assert.Equal("UTR-1234-5678", claimed.Payment.Ref);
        Assert.Equal(0, claimed.Invoice.Paid);
        Assert.Equal(bill.Amounts.Total, claimed.Invoice.Outstanding);
        Assert.Equal("pending", claimed.Invoice.Status);

        // Claiming again changes nothing; refreshing never settles it either.
        var again = await (await ClaimAsync(guest, payment.Id)).ReadAsync<PaymentResultDto>();
        // The same moment (the database keeps microseconds, the first answer
        // came straight from memory).
        Assert.True(Math.Abs((again.Payment.Claimed!.Value - claimed.Payment.Claimed!.Value).TotalMilliseconds) < 1);
        Assert.Equal("pending", (await RefreshAsync(guest, payment.Id)).Status);
    }

    [Fact]
    public async Task A_claim_with_a_malformed_reference_is_refused()
    {
        var guest = await api.GuestAsync();
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        Assert.Equal(HttpStatusCode.BadRequest, (await ClaimAsync(guest, payment.Id, "12")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await ClaimAsync(guest, payment.Id, "a b c d e f")).StatusCode);
        // Not claimed by the failed attempts.
        Assert.Null((await RefreshAsync(guest, payment.Id)).Claimed);
    }

    // ---------------------------------------------------------- cashier

    [Fact]
    public async Task A_cashier_confirms_a_claimed_payment_with_the_bank_reference()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;
        await ClaimAsync(guest, payment.Id);

        var verified = await (await VerifyAsync(cashier, payment.Id, " 412345678901 ")).ReadAsync<PaymentResultDto>();
        Assert.Equal("succeeded", verified.Payment.Status);
        Assert.Equal("412345678901", verified.Payment.Ref);
        Assert.Equal("Test cashier", verified.Payment.By);
        Assert.False(verified.Payment.Simulated);
        Assert.Equal(bill.Amounts.Total, verified.Invoice.Paid);
        Assert.Equal(0, verified.Invoice.Outstanding);
        Assert.Equal("paid", verified.Invoice.Status);

        // The guest sees the settled bill, with the method as UPI.
        var seen = await BillOfAsync(guest, bill.Order);
        Assert.Equal("paid", seen.Status);
        Assert.Equal("upi", seen.Payments.Single().Method);

        // Confirming again is harmless (a double tap, a retry).
        var replay = await (await VerifyAsync(cashier, payment.Id, "412345678901")).ReadAsync<PaymentResultDto>();
        Assert.Equal("succeeded", replay.Payment.Status);
        Assert.Equal(bill.Amounts.Total, replay.Invoice.Paid);

        var owner = await api.OwnerAsync();
        var log = await (await owner.GetAsync("/api/v1/admin/audit?action=payment.upi.verify&limit=20"))
            .ReadAsync<List<AuditDto>>();
        var entry = log.First(a => a.Summary.Contains("412345678901"));
        Assert.Equal("Test cashier", entry.Name);
        Assert.Contains(bill.Number, entry.Summary);
    }

    [Fact]
    public async Task A_cashier_can_confirm_a_payment_the_guest_never_claimed()
    {
        // The guest paid but closed the app before saying so.
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        var verified = await (await VerifyAsync(cashier, payment.Id, "REF987654321")).ReadAsync<PaymentResultDto>();
        Assert.Equal("succeeded", verified.Payment.Status);
        Assert.Equal("paid", verified.Invoice.Status);
    }

    [Fact]
    public async Task Confirming_needs_a_valid_bank_reference_and_the_right_role()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;

        Assert.Equal(HttpStatusCode.BadRequest, (await VerifyAsync(cashier, payment.Id, null)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await VerifyAsync(cashier, payment.Id, "  ")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await VerifyAsync(cashier, payment.Id, "12345")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await VerifyAsync(cashier, payment.Id, "ref with spaces")).StatusCode);

        // Guests, anonymous callers and roles that cannot take payments.
        Assert.Equal(HttpStatusCode.Forbidden, (await VerifyAsync(guest, payment.Id, "412345678901")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await VerifyAsync(api.Anonymous(), payment.Id, "412345678901")).StatusCode);
        foreach (var role in new[] { "kitchen", "waiter", "accountant" })
        {
            var staff = await api.NewStaffAsync(role);
            Assert.Equal(HttpStatusCode.Forbidden, (await VerifyAsync(staff, payment.Id, "412345678901")).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await RejectAsync(staff, payment.Id)).StatusCode);
        }

        // None of that settled anything.
        Assert.Equal("pending", (await RefreshAsync(guest, payment.Id)).Status);
    }

    [Fact]
    public async Task The_same_bank_reference_cannot_confirm_two_payments()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var first = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        var second = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        var reference = $"DUP{Guid.NewGuid():N}"[..14];

        (await VerifyAsync(cashier, first.Id, reference)).EnsureSuccessStatusCode();
        var duplicate = await VerifyAsync(cashier, second.Id, reference.ToLowerInvariant());
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        Assert.Equal("duplicateReference", await duplicate.ErrorCodeAsync());
        Assert.Equal("pending", (await RefreshAsync(guest, second.Id)).Status);

        var other = await VerifyAsync(cashier, second.Id, reference + "X");
        Assert.Equal(HttpStatusCode.OK, other.StatusCode);
    }

    [Fact]
    public async Task Two_cashiers_confirming_at_once_pay_the_bill_only_once()
    {
        var guest = await api.GuestAsync();
        var one = await api.NewStaffAsync("cashier");
        var two = await api.NewStaffAsync("manager");
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;

        var results = await Task.WhenAll(
            VerifyAsync(one, payment.Id, "RACE00000001"),
            VerifyAsync(two, payment.Id, "RACE00000002"));
        Assert.All(results, r => Assert.True(
            r.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict, $"{(int)r.StatusCode}"));
        Assert.Contains(results, r => r.StatusCode == HttpStatusCode.OK);

        var after = await BillOfAsync(guest, bill.Order);
        Assert.Equal(bill.Amounts.Total, after.Paid);
        Assert.Equal(1, after.Payments.Count(p => p.Status == "succeeded"));
    }

    [Fact]
    public async Task A_cashier_can_reject_a_payment_that_never_arrived()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;
        await ClaimAsync(guest, payment.Id);

        var rejected = await (await RejectAsync(cashier, payment.Id, "Not in the bank statement"))
            .ReadAsync<PaymentResultDto>();
        Assert.Equal("failed", rejected.Payment.Status);
        Assert.Equal("Not in the bank statement", rejected.Payment.Failure);
        Assert.Equal(0, rejected.Invoice.Paid);
        Assert.Equal("failed", rejected.Invoice.Status);
        // The balance is open again and can be paid another way.
        Assert.Equal(bill.Amounts.Total, rejected.Invoice.PayableNow);

        // It is final: no confirming it afterwards, no rejecting it twice.
        var late = await VerifyAsync(cashier, payment.Id, "412345678901");
        Assert.Equal("notPending", await late.ErrorCodeAsync());
        Assert.Equal("notPending", await (await RejectAsync(cashier, payment.Id)).ErrorCodeAsync());

        var retry = await StartAsync(guest, bill);
        Assert.Equal(HttpStatusCode.OK, retry.StatusCode);
    }

    [Fact]
    public async Task Rejecting_without_a_reason_records_a_default()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        var rejected = await (await RejectAsync(cashier, payment.Id)).ReadAsync<PaymentResultDto>();
        Assert.Equal("The payment was not received.", rejected.Payment.Failure);
    }

    // ------------------------------------------------------- cancelling

    [Fact]
    public async Task A_guest_can_cancel_an_unconfirmed_attempt_and_try_again()
    {
        var guest = await api.GuestAsync();
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;

        var cancelled = await (await CancelAsync(guest, payment.Id)).ReadAsync<PaymentResultDto>();
        Assert.Equal("cancelled", cancelled.Payment.Status);
        Assert.Equal("unpaid", cancelled.Invoice.Status);
        Assert.Equal(bill.Amounts.Total, cancelled.Invoice.PayableNow);

        // Cancelling twice is harmless; a fresh attempt can start.
        Assert.Equal("cancelled", (await (await CancelAsync(guest, payment.Id)).ReadAsync<PaymentResultDto>())
            .Payment.Status);
        Assert.Equal(HttpStatusCode.OK, (await StartAsync(guest, bill)).StatusCode);
    }

    [Fact]
    public async Task After_claiming_only_staff_can_cancel()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        await ClaimAsync(guest, payment.Id);

        var refused = await CancelAsync(guest, payment.Id);
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("alreadyClaimed", await refused.ErrorCodeAsync());
        Assert.Equal("pending", (await RefreshAsync(guest, payment.Id)).Status);

        var cancelled = await (await CancelAsync(cashier, payment.Id)).ReadAsync<PaymentResultDto>();
        Assert.Equal("cancelled", cancelled.Payment.Status);
    }

    [Fact]
    public async Task An_abandoned_attempt_expires_and_stops_blocking_the_bill()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;

        // Within the window it blocks the counter.
        var blocked = await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments",
            new { amount = 100, method = "cash", idempotencyKey = HttpTestExtensions.Key() });
        Assert.Equal(HttpStatusCode.Conflict, blocked.StatusCode);

        await BackdateAsync(payment.Id, UpiRules.AttemptWindow + TimeSpan.FromMinutes(5));
        var counter = await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments",
            new { amount = bill.Amounts.Total, method = "cash", idempotencyKey = HttpTestExtensions.Key() });
        var recorded = await counter.ReadAsync<PaymentResultDto>();
        Assert.Equal("paid", recorded.Invoice.Status);
        var expired = recorded.Invoice.Payments.Single(p => p.Id == payment.Id);
        Assert.Equal("cancelled", expired.Status);
        Assert.Equal("The payment was not completed in time.", expired.Failure);
    }

    [Fact]
    public async Task Checking_the_status_of_an_abandoned_attempt_expires_it()
    {
        var guest = await api.GuestAsync();
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        await BackdateAsync(payment.Id, UpiRules.AttemptWindow + TimeSpan.FromMinutes(1));
        Assert.Equal("cancelled", (await RefreshAsync(guest, payment.Id)).Status);
    }

    [Fact]
    public async Task A_claimed_payment_never_expires_it_waits_for_a_cashier()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        await ClaimAsync(guest, payment.Id);
        await BackdateAsync(payment.Id, TimeSpan.FromHours(6));

        Assert.Equal("pending", (await RefreshAsync(guest, payment.Id)).Status);
        var verified = await (await VerifyAsync(cashier, payment.Id, "LATE12345678")).ReadAsync<PaymentResultDto>();
        Assert.Equal("paid", verified.Invoice.Status);
    }

    // ----------------------------------- alongside the other payment methods

    [Fact]
    public async Task UPI_works_for_the_rest_of_a_bill_part_paid_by_cash()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var bill = await BillAsync(guest, quantity: 2);
        var cash = bill.Amounts.Total / 3;

        var afterCash = await (await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments",
            new { amount = cash, method = "cash", idempotencyKey = HttpTestExtensions.Key() }))
            .ReadAsync<PaymentResultDto>();
        Assert.Equal("partiallyPaid", afterCash.Invoice.Status);

        // The UPI payment is for exactly what is left.
        var rest = afterCash.Invoice.PayableNow;
        Assert.Equal(bill.Amounts.Total - cash, rest);
        var started = await StartOkAsync(guest, bill, rest);
        Assert.Equal(rest, started.Payment.Amount);
        Assert.Equal(cash, started.Invoice.Paid);
        Assert.Equal(0, started.Invoice.PayableNow);

        var done = await (await VerifyAsync(cashier, started.Payment.Id, "SPLIT0000001")).ReadAsync<PaymentResultDto>();
        Assert.Equal("paid", done.Invoice.Status);
        Assert.Equal(bill.Amounts.Total, done.Invoice.Paid);
        Assert.Equal(0, done.Invoice.Outstanding);
        Assert.Equal(["cash", "upi"], done.Invoice.Payments.Select(p => p.Method).Order());
    }

    [Fact]
    public async Task Confirmed_UPI_payments_count_in_the_reports_but_pending_ones_do_not()
    {
        var owner = await api.OwnerAsync();
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var today = DateOnly.FromDateTime(DateTime.UtcNow.AddMinutes(330));
        async Task<SalesSummary> Summary() => await (await owner.GetAsync(
            $"/api/v1/admin/reports/summary?from={today:yyyy-MM-dd}&to={today:yyyy-MM-dd}")).ReadAsync<SalesSummary>();

        var before = await Summary();
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;
        await ClaimAsync(guest, payment.Id);
        var pending = await Summary();
        Assert.Equal(before.Collected, pending.Collected);

        (await VerifyAsync(cashier, payment.Id, "REPORT000001")).EnsureSuccessStatusCode();
        var after = await Summary();
        Assert.Equal(before.Collected + bill.Amounts.Total, after.Collected);
        Assert.Equal((before.CollectedByMethod?.GetValueOrDefault("upi") ?? 0) + bill.Amounts.Total,
            after.CollectedByMethod!["upi"]);
    }

    [Fact]
    public async Task A_confirmed_UPI_payment_is_refunded_by_the_restaurant_and_recorded()
    {
        var guest = await api.GuestAsync();
        var cashier = await api.NewStaffAsync("cashier");
        var owner = await api.OwnerAsync();
        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;
        (await VerifyAsync(cashier, payment.Id, "REFUND000001")).EnsureSuccessStatusCode();

        var refund = await owner.PostJsonAsync($"/api/v1/admin/payments/{payment.Id}/refunds",
            new { amount = 1000, reason = "Cold food", idempotencyKey = HttpTestExtensions.Key() });
        Assert.Equal(HttpStatusCode.OK, refund.StatusCode);
        var body = await refund.Content.ReadAsStringAsync();
        Assert.Contains("\"status\":\"processed\"", body);
        Assert.Contains("\"simulated\":false", body);
    }

    // -------------------------------------------- automatic verification

    [Fact]
    public async Task Automatic_verification_confirms_only_what_the_verifier_reports()
    {
        var owner = await api.OwnerAsync();
        var guest = await api.GuestAsync();
        api.Verifier.IsAvailable = true;

        var saved = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(mode: "automatic")))
            .ReadAsync<PaymentSettingsDto>();
        Assert.True(saved.AutomaticVerificationAvailable);
        Assert.Equal("automatic", saved.VerificationMode);
        Assert.Equal("automatic", (await (await guest.GetAsync("/api/v1/payments/upi")).ReadAsync<UpiConfigDto>())
            .VerificationMode);

        var bill = await BillAsync(guest);
        var payment = (await StartOkAsync(guest, bill)).Payment;

        // Claiming, refreshing and waiting do not settle it: only the bank does.
        await ClaimAsync(guest, payment.Id, "CLAIMED000001");
        Assert.Equal("pending", (await RefreshAsync(guest, payment.Id)).Status);

        api.Verifier.Outcomes[payment.Id] = new ProviderOutcome(PaymentStatus.Succeeded, "bank000000001");
        var settled = await RefreshAsync(guest, payment.Id);
        Assert.Equal("succeeded", settled.Status);
        Assert.Equal("BANK000000001", settled.Ref);
        Assert.Equal("Test bank", settled.By);
        Assert.Equal("paid", (await BillOfAsync(guest, bill.Order)).Status);
    }

    [Fact]
    public async Task Automatic_verification_ignores_a_success_without_evidence()
    {
        var owner = await api.OwnerAsync();
        var guest = await api.GuestAsync();
        api.Verifier.IsAvailable = true;
        (await owner.PutAsJsonAsync(SettingsUrl, Payload(mode: "automatic"))).EnsureSuccessStatusCode();

        // A "success" with no bank reference is not a confirmation.
        var noReference = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        api.Verifier.Outcomes[noReference.Id] = new ProviderOutcome(PaymentStatus.Succeeded);
        Assert.Equal("pending", (await RefreshAsync(guest, noReference.Id)).Status);

        // Nor is one that reuses a reference already confirmed elsewhere.
        var cashier = await api.NewStaffAsync("cashier");
        var used = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        (await VerifyAsync(cashier, used.Id, "ONCE00000001")).EnsureSuccessStatusCode();
        var reused = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        api.Verifier.Outcomes[reused.Id] = new ProviderOutcome(PaymentStatus.Succeeded, "once00000001");
        Assert.Equal("pending", (await RefreshAsync(guest, reused.Id)).Status);

        // A failure from the bank does close it.
        var declined = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        api.Verifier.Outcomes[declined.Id] = new ProviderOutcome(PaymentStatus.Failed, "", "Payer bank declined");
        var failed = await RefreshAsync(guest, declined.Id);
        Assert.Equal("failed", failed.Status);
        Assert.Equal("Payer bank declined", failed.Failure);
    }

    [Fact]
    public async Task With_manual_verification_a_connected_verifier_confirms_nothing()
    {
        var guest = await api.GuestAsync();
        api.Verifier.IsAvailable = true;
        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        api.Verifier.Outcomes[payment.Id] = new ProviderOutcome(PaymentStatus.Succeeded, "MANUAL000001");
        Assert.Equal("pending", (await RefreshAsync(guest, payment.Id)).Status);
    }

    [Fact]
    public async Task A_saved_automatic_mode_falls_back_to_manual_when_the_provider_goes_away()
    {
        var owner = await api.OwnerAsync();
        var guest = await api.GuestAsync();
        api.Verifier.IsAvailable = true;
        (await owner.PutAsJsonAsync(SettingsUrl, Payload(mode: "automatic"))).EnsureSuccessStatusCode();
        api.Verifier.IsAvailable = false;

        // Guests are told the truth (manual); the owner sees the choice and
        // that it cannot run.
        Assert.Equal("manual", (await (await guest.GetAsync("/api/v1/payments/upi")).ReadAsync<UpiConfigDto>())
            .VerificationMode);
        var view = await (await owner.GetAsync(SettingsUrl)).ReadAsync<PaymentSettingsDto>();
        Assert.Equal("automatic", view.VerificationMode);
        Assert.False(view.AutomaticVerificationAvailable);

        var payment = (await StartOkAsync(guest, await BillAsync(guest))).Payment;
        api.Verifier.Outcomes[payment.Id] = new ProviderOutcome(PaymentStatus.Succeeded, "GONE00000001");
        Assert.Equal("pending", (await RefreshAsync(guest, payment.Id)).Status);
    }

    // --------------------------------------------------------- QR image

    [Fact]
    public async Task The_merchant_QR_can_be_uploaded_previewed_replaced_and_removed()
    {
        var owner = await api.OwnerAsync();
        var guest = await api.GuestAsync();

        var first = await (await owner.PostAsync(QrUploadUrl, Form(Image(Png)))).ReadAsync<UploadedImageDto>();
        Assert.StartsWith("http", first.Url);
        Assert.Contains("/uploads/upi/", first.Url);
        Assert.EndsWith(".png", first.Url);

        // The picture is reachable without a token (the guest app shows it).
        var path = new Uri(first.Url).AbsolutePath;
        var served = await api.Anonymous().GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, served.StatusCode);
        Assert.Equal("image/png", served.Content.Headers.ContentType?.MediaType);

        // Uploading alone changes nothing; saving attaches it.
        Assert.Equal("", (await (await owner.GetAsync(SettingsUrl)).ReadAsync<PaymentSettingsDto>()).QrImage);
        var saved = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(qr: first.Url)))
            .ReadAsync<PaymentSettingsDto>();
        Assert.Equal(first.Url, saved.QrImage);
        Assert.Equal(first.Url, (await (await guest.GetAsync("/api/v1/payments/upi")).ReadAsync<UpiConfigDto>()).QrImage);

        // Replacing it removes the old file.
        var second = await (await owner.PostAsync(QrUploadUrl, Form(Image(Png)))).ReadAsync<UploadedImageDto>();
        Assert.NotEqual(first.Url, second.Url);
        (await owner.PutAsJsonAsync(SettingsUrl, Payload(qr: second.Url))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.NotFound, (await api.Anonymous().GetAsync(path)).StatusCode);
        var secondPath = new Uri(second.Url).AbsolutePath;
        Assert.Equal(HttpStatusCode.OK, (await api.Anonymous().GetAsync(secondPath)).StatusCode);

        // Saving other details keeps it; clearing the field removes it.
        var kept = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(name: "Renamed Cafe", qr: second.Url)))
            .ReadAsync<PaymentSettingsDto>();
        Assert.Equal(second.Url, kept.QrImage);
        var removed = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(qr: ""))).ReadAsync<PaymentSettingsDto>();
        Assert.Equal("", removed.QrImage);
        Assert.Equal(HttpStatusCode.NotFound, (await api.Anonymous().GetAsync(secondPath)).StatusCode);
    }

    [Fact]
    public async Task Only_images_this_server_stored_can_be_used_as_the_QR()
    {
        var owner = await api.OwnerAsync();
        var dish = await (await owner.PostAsync("/api/v1/admin/uploads/dish-images", Form(Image(Png))))
            .ReadAsync<UploadedImageDto>();

        foreach (var url in new[]
                 {
                     dish.Url, // a dish photo, not a QR
                     "https://evil.example/qr.png",
                     "http://localhost/uploads/upi/0123456789abcdef0123456789abcdef.png", // never uploaded
                     "javascript:alert(1)",
                     "assets/images/samosa.jpg",
                 })
        {
            var response = await owner.PutAsJsonAsync(SettingsUrl, Payload(qr: url));
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Contains("qrImage", await response.Content.ReadAsStringAsync());
        }
        Assert.Equal("", (await (await owner.GetAsync(SettingsUrl)).ReadAsync<PaymentSettingsDto>()).QrImage);
    }

    [Fact]
    public async Task A_QR_address_on_another_host_is_stored_as_this_servers_own()
    {
        var owner = await api.OwnerAsync();
        var uploaded = await (await owner.PostAsync(QrUploadUrl, Form(Image(Png)))).ReadAsync<UploadedImageDto>();
        var foreign = "https://evil.example" + new Uri(uploaded.Url).AbsolutePath;
        var saved = await (await owner.PutAsJsonAsync(SettingsUrl, Payload(qr: foreign)))
            .ReadAsync<PaymentSettingsDto>();
        Assert.Equal(uploaded.Url, saved.QrImage);
        Assert.DoesNotContain("evil.example", saved.QrImage);
    }

    [Theory]
    [InlineData(new byte[] { 0x47, 0x49, 0x46, 0x38 }, "unsupportedImageType")] // GIF
    [InlineData(new byte[] { 0x25, 0x50, 0x44, 0x46 }, "unsupportedImageType")] // PDF
    [InlineData(new byte[] { 0x4D, 0x5A, 0x90, 0x00 }, "unsupportedImageType")] // Windows executable
    public async Task A_file_that_is_not_an_accepted_image_is_not_stored_as_a_QR(byte[] signature, string code)
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(QrUploadUrl, Form(Image(signature), "qr.png"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(code, await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task QR_uploads_follow_the_size_limit_and_the_roles()
    {
        var owner = await api.OwnerAsync();
        var tooBig = await owner.PostAsync(QrUploadUrl, Form(Image(Png, ApiFactory.MaxUploadBytes + 1)));
        Assert.Equal("fileTooLarge", await tooBig.ErrorCodeAsync());
        Assert.Equal("noFile", await (await owner.PostAsync(QrUploadUrl, Form([]))).ErrorCodeAsync());

        Assert.Equal(HttpStatusCode.Unauthorized,
            (await api.Anonymous().PostAsync(QrUploadUrl, Form(Image(Png)))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await (await api.GuestAsync()).PostAsync(QrUploadUrl, Form(Image(Png)))).StatusCode);
        foreach (var role in new[] { "cashier", "manager", "kitchen" })
        {
            var staff = await api.NewStaffAsync(role);
            Assert.Equal(HttpStatusCode.Forbidden, (await staff.PostAsync(QrUploadUrl, Form(Image(Png)))).StatusCode);
        }
    }
}
