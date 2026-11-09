using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Services;

namespace DineQR.Api.Tests;

[Collection(ApiCollection.Name)]
public class ApiFlowTests(ApiFactory api)
{
    private static object Line(string itemId, int quantity, string? portion = null, params string[] addOns) =>
        new { itemId, quantity, options = new { portion, addOns } };

    private static async Task<OrderDto> PlaceAsync(HttpClient guest, object[] lines, string? offer = null,
        long? expectedTotal = null)
    {
        var response = await guest.PostJsonAsync("/api/v1/orders",
            new { lines, offerCode = offer, idempotencyKey = HttpTestExtensions.Key(), expectedTotal });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return await response.ReadAsync<OrderDto>();
    }

    // ------------------------------------------------------------ public

    [Fact]
    public async Task Health_reports_only_the_status()
    {
        var body = await api.Anonymous().GetStringAsync("/health");
        Assert.Equal("{\"status\":\"Healthy\"}", body);
    }

    [Fact]
    public async Task The_seeded_catalogue_is_served_from_the_database()
    {
        var menu = await (await api.Anonymous().GetAsync("/api/v1/menu")).ReadAsync<MenuDto>();
        Assert.Equal(4, menu.Categories.Count);
        Assert.Equal(21, menu.Items.Count);
        var chicken = menu.Items.Single(i => i.Id == "chicken_65");
        Assert.Equal(18_000, chicken.Price);
        Assert.Equal(["half", "full"], chicken.Portions!.Select(p => p.Id));

        var settings = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.Equal(500, settings.TaxRate);
        Assert.Equal(330, settings.UtcOffset);
        Assert.Contains(settings.Offers!, o => o.Code == "WELCOME10");
    }

    [Theory]
    [InlineData("HELLO", HttpStatusCode.BadRequest)]
    [InlineData("DINEQR:TABLE:99", HttpStatusCode.NotFound)]
    public async Task Only_real_table_codes_start_a_guest_session(string payload, HttpStatusCode expected)
    {
        var response = await api.Anonymous().PostJsonAsync("/api/v1/guest/sessions", new { qrPayload = payload });
        Assert.Equal(expected, response.StatusCode);
    }

    [Fact]
    public async Task A_table_link_is_checked_against_the_public_table_list()
    {
        var anonymous = api.Anonymous();
        var tables = await (await anonymous.GetAsync("/api/v1/tables")).ReadAsync<List<PublicTableDto>>();
        Assert.NotEmpty(tables);
        Assert.All(tables, t => Assert.True(t.Seats > 0));

        var table = await (await anonymous.GetAsync($"/api/v1/tables/{tables[0].Number}")).ReadAsync<PublicTableDto>();
        Assert.Equal(tables[0], table);
        Assert.Equal(HttpStatusCode.NotFound, (await anonymous.GetAsync("/api/v1/tables/999")).StatusCode);
    }

    [Fact]
    public async Task A_guest_token_grants_no_staff_access()
    {
        var guest = await api.GuestAsync();
        Assert.Equal(HttpStatusCode.Forbidden, (await guest.GetAsync("/api/v1/admin/orders")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await api.Anonymous().GetAsync("/api/v1/orders")).StatusCode);
    }

    // ------------------------------------------------------------ orders

    [Fact]
    public async Task Orders_are_priced_by_the_server()
    {
        var guest = await api.GuestAsync(table: 5);
        // Chicken 65, full portion (+₹140) with mint mayo (+₹30), twice.
        var order = await PlaceAsync(guest, [Line("chicken_65", 2, "full", "mint_mayo")], offer: "welcome10");

        Assert.Equal(5, order.Table);
        Assert.Equal("placed", order.Status);
        Assert.Equal(35_000, order.Lines.Single().UnitPrice);
        Assert.Equal(["Spice: Medium", "Full", "Mint Mayo Dip"], order.Lines.Single().Options);
        Assert.Equal(70_000, order.Subtotal);
        Assert.Equal(7_000, order.Discount); // 10%, under the ₹100 cap
        Assert.Equal("Offer WELCOME10", order.DiscountLabel);
        Assert.Equal(3_150, order.Tax); // 5% of ₹630
        Assert.Equal(66_150, order.Total);
        Assert.NotNull(order.InvoiceId);

        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        Assert.Equal(66_150, bill.Amounts.Total);
        Assert.Equal("unpaid", bill.Status);
        Assert.StartsWith("DQ-", bill.Number);
    }

    [Fact]
    public async Task Replaying_an_order_returns_the_original()
    {
        var guest = await api.GuestAsync();
        var body = new { lines = new[] { Line("samosa", 1) }, idempotencyKey = HttpTestExtensions.Key() };
        var first = await guest.PostJsonAsync("/api/v1/orders", body);
        var second = await guest.PostJsonAsync("/api/v1/orders", body);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal((await first.ReadAsync<OrderDto>()).Id, (await second.ReadAsync<OrderDto>()).Id);
    }

    [Fact]
    public async Task A_changed_price_or_bad_options_are_refused()
    {
        var guest = await api.GuestAsync();
        var stale = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { Line("samosa", 1) }, idempotencyKey = HttpTestExtensions.Key(), expectedTotal = 1,
        });
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal("priceChanged", await stale.ErrorCodeAsync());

        var options = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { Line("chicken_65", 1, "giant") }, idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal("invalidOptions", await options.ErrorCodeAsync());

        var unknown = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { Line("not_a_dish", 1) }, idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal("itemsUnavailable", await unknown.ErrorCodeAsync());

        var empty = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = Array.Empty<object>(), idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal("emptyCart", await empty.ErrorCodeAsync());
    }

    [Fact]
    public async Task The_home_banner_flag_is_saved_and_reaches_guests()
    {
        var owner = await api.OwnerAsync();
        var guestMenu = async () =>
            await (await api.Anonymous().GetAsync("/api/v1/menu")).ReadAsync<MenuDto>();

        // The seeded banner dishes come through, others are not featured.
        var before = await guestMenu();
        Assert.True(before.Items.Single(i => i.Id == "chicken_65").Featured);
        Assert.False(before.Items.Single(i => i.Id == "samosa").Featured);

        // Switch it on for another dish and off for one that was on.
        var menu = await (await owner.GetAsync("/api/v1/admin/menu")).ReadAsync<MenuDto>();
        var samosa = menu.Items.Single(i => i.Id == "samosa");
        var chicken = menu.Items.Single(i => i.Id == "chicken_65");
        (await owner.PutAsJsonAsync("/api/v1/admin/menu/items/samosa", samosa with { Featured = true },
            DineQR.Api.Infrastructure.Json.Options)).EnsureSuccessStatusCode();
        (await owner.PutAsJsonAsync("/api/v1/admin/menu/items/chicken_65", chicken with { Featured = false },
            DineQR.Api.Infrastructure.Json.Options)).EnsureSuccessStatusCode();

        var after = await guestMenu();
        Assert.True(after.Items.Single(i => i.Id == "samosa").Featured);
        Assert.False(after.Items.Single(i => i.Id == "chicken_65").Featured);

        // Put the seeded state back for the other tests.
        (await owner.PutAsJsonAsync("/api/v1/admin/menu/items/samosa", samosa,
            DineQR.Api.Infrastructure.Json.Options)).EnsureSuccessStatusCode();
        (await owner.PutAsJsonAsync("/api/v1/admin/menu/items/chicken_65", chicken,
            DineQR.Api.Infrastructure.Json.Options)).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Sold_out_dishes_and_inactive_tables_cannot_be_ordered()
    {
        var owner = await api.OwnerAsync();
        (await owner.PatchAsJsonAsync("/api/v1/admin/menu/items/rasmalai", new { available = false }))
            .EnsureSuccessStatusCode();
        var guest = await api.GuestAsync(table: 9);
        var soldOut = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { Line("rasmalai", 1) }, idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal("itemsUnavailable", await soldOut.ErrorCodeAsync());
        (await owner.PatchAsJsonAsync("/api/v1/admin/menu/items/rasmalai", new { available = true }))
            .EnsureSuccessStatusCode();

        var tables = await (await owner.GetAsync("/api/v1/admin/tables")).ReadAsync<List<TableDto>>();
        var updated = tables.Select(t => t.Number == 9 ? t with { Active = false } : t).ToList();
        (await owner.PutAsJsonAsync("/api/v1/admin/tables", updated)).EnsureSuccessStatusCode();
        var closed = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { Line("samosa", 1) }, idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal("tableUnavailable", await closed.ErrorCodeAsync());
        var rescan = await api.Anonymous().PostJsonAsync("/api/v1/guest/sessions", new { qrPayload = "DINEQR:TABLE:09" });
        Assert.Equal(HttpStatusCode.Conflict, rescan.StatusCode);
        (await owner.PutAsJsonAsync("/api/v1/admin/tables", tables)).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Guests_only_see_their_own_orders()
    {
        var mine = await api.GuestAsync(table: 3);
        var other = await api.GuestAsync(table: 3);
        var order = await PlaceAsync(mine, [Line("samosa", 1)]);
        Assert.Equal(HttpStatusCode.NotFound, (await other.GetAsync($"/api/v1/orders/{order.Id}")).StatusCode);
        var list = await (await mine.GetAsync("/api/v1/orders")).ReadAsync<List<OrderDto>>();
        Assert.Contains(list, o => o.Id == order.Id);
        Assert.DoesNotContain(await (await other.GetAsync("/api/v1/orders")).ReadAsync<List<OrderDto>>(),
            o => o.Id == order.Id);
    }

    [Fact]
    public async Task Status_changes_follow_the_workflow_and_role_permissions()
    {
        var guest = await api.GuestAsync();
        var order = await PlaceAsync(guest, [Line("masala_dosa", 1)]);
        var kitchen = await api.NewStaffAsync("kitchen");
        var waiter = await api.NewStaffAsync("waiter");

        async Task<HttpResponseMessage> Move(HttpClient staff, string target, string? reason = null) =>
            await staff.PostJsonAsync($"/api/v1/admin/orders/{order.Id}/status", new { target, reason });

        Assert.Equal("invalidTransition", await (await Move(kitchen, "readyToServe")).ErrorCodeAsync());
        Assert.Equal(HttpStatusCode.OK, (await Move(kitchen, "accepted")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Move(kitchen, "preparing")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Move(kitchen, "readyToServe")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Move(kitchen, "served")).StatusCode);
        var served = await (await Move(waiter, "served")).ReadAsync<OrderDto>();
        Assert.Equal("served", served.Status);
        Assert.Equal(["placed", "accepted", "preparing", "readyToServe", "served"],
            served.StatusTimes.OrderBy(t => t.Value).Select(t => t.Key));

        // The guest sees it and may rate it once.
        var tracked = await (await guest.GetAsync($"/api/v1/orders/{order.Id}")).ReadAsync<OrderDto>();
        Assert.Equal("served", tracked.Status);
        Assert.Equal(HttpStatusCode.OK,
            (await guest.PostJsonAsync($"/api/v1/orders/{order.Id}/feedback", new { rating = 5, comment = "Great" }))
            .StatusCode);
        Assert.Equal("alreadyRated", await (await guest.PostJsonAsync($"/api/v1/orders/{order.Id}/feedback",
            new { rating = 4 })).ErrorCodeAsync());
        // Kitchen staff cannot take payments.
        Assert.Equal(HttpStatusCode.Forbidden, (await kitchen.PostJsonAsync(
            $"/api/v1/admin/bills/{tracked.InvoiceId}/payments",
            new { amount = 100, method = "cash", idempotencyKey = HttpTestExtensions.Key() })).StatusCode);
    }

    [Fact]
    public async Task Cancelling_needs_a_reason_and_voids_the_bill()
    {
        var guest = await api.GuestAsync();
        var order = await PlaceAsync(guest, [Line("samosa", 2)]);
        var owner = await api.OwnerAsync();
        var noReason = await owner.PostJsonAsync($"/api/v1/admin/orders/{order.Id}/status", new { target = "cancelled" });
        Assert.Equal(HttpStatusCode.BadRequest, noReason.StatusCode);
        (await owner.PostJsonAsync($"/api/v1/admin/orders/{order.Id}/status",
            new { target = "cancelled", reason = "Kitchen closed" })).EnsureSuccessStatusCode();
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        Assert.True(bill.Void);
        Assert.Equal("voided", bill.Status);
        Assert.Equal(0, bill.Outstanding);
    }

    // ---------------------------------------------------------- payments

    [Fact]
    public async Task Online_payments_count_only_after_server_verification()
    {
        var guest = await api.GuestAsync();
        var order = await PlaceAsync(guest, [Line("paneer_tikka", 1)]);
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();

        async Task<PaymentIntentResponse> Intent(long amount) => await (await guest.PostJsonAsync(
            "/api/v1/payments/intents",
            new { invoiceId = bill.Id, amount, method = "upi", idempotencyKey = HttpTestExtensions.Key() }))
            .ReadAsync<PaymentIntentResponse>();

        var overpay = await guest.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount = bill.Amounts.Total + 1, method = "upi",
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal(HttpStatusCode.BadRequest, overpay.StatusCode);

        // A declined attempt changes nothing.
        var declined = await Intent(bill.Amounts.Total);
        Assert.True(declined.Simulated);
        Assert.Equal("pending", declined.Payment.Status);
        var failed = await (await guest.PostJsonAsync($"/api/v1/payments/{declined.Payment.Id}/confirm",
            new { simulatedOutcome = "failure" })).ReadAsync<PaymentResultDto>();
        Assert.Equal("failed", failed.Payment.Status);
        Assert.Equal(0, failed.Invoice.Paid);
        Assert.Equal("failed", failed.Invoice.Status);

        var intent = await Intent(bill.Amounts.Total);
        // A second attempt cannot start while one is in progress.
        var parallel = await guest.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount = 100, method = "card", idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal("paymentInProgress", await parallel.ErrorCodeAsync());
        var paid = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/confirm",
            new { simulatedOutcome = "success" })).ReadAsync<PaymentResultDto>();
        Assert.Equal("succeeded", paid.Payment.Status);
        Assert.True(paid.Payment.Simulated);
        Assert.Equal("paid", paid.Invoice.Status);
        Assert.Equal(0, paid.Invoice.Outstanding);

        // Another guest cannot touch this bill.
        var stranger = await api.GuestAsync();
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.GetAsync($"/api/v1/bills/{bill.Id}")).StatusCode);
    }

    [Fact]
    public async Task Counter_payments_and_refunds_follow_the_roles()
    {
        var guest = await api.GuestAsync();
        var order = await PlaceAsync(guest, [Line("butter_chicken", 1)]);
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        var cashier = await api.NewStaffAsync("cashier");
        var key = HttpTestExtensions.Key();
        var half = bill.Amounts.Total / 2;

        var first = await (await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments",
            new { amount = half, method = "cash", idempotencyKey = key })).ReadAsync<PaymentResultDto>();
        Assert.Equal("partiallyPaid", first.Invoice.Status);
        // Replaying the same request records nothing new.
        var replay = await (await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments",
            new { amount = half, method = "cash", idempotencyKey = key })).ReadAsync<PaymentResultDto>();
        Assert.Equal(first.Payment.Id, replay.Payment.Id);
        Assert.Single(replay.Invoice.Payments);

        var rest = await (await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments", new
        {
            amount = bill.Amounts.Total - half, method = "card", reference = "TERM-42",
            idempotencyKey = HttpTestExtensions.Key(),
        })).ReadAsync<PaymentResultDto>();
        Assert.Equal("paid", rest.Invoice.Status);

        // Cashiers cannot refund; owners can, up to what was paid.
        var refundBody = new { amount = 1000, reason = "Cold food", idempotencyKey = HttpTestExtensions.Key() };
        Assert.Equal(HttpStatusCode.Forbidden,
            (await cashier.PostJsonAsync($"/api/v1/admin/payments/{rest.Payment.Id}/refunds", refundBody)).StatusCode);
        var owner = await api.OwnerAsync();
        var tooMuch = await owner.PostJsonAsync($"/api/v1/admin/payments/{rest.Payment.Id}/refunds",
            new { amount = rest.Payment.Amount + 1, reason = "Too much", idempotencyKey = HttpTestExtensions.Key() });
        Assert.Equal(HttpStatusCode.BadRequest, tooMuch.StatusCode);
        var refunded = await owner.PostJsonAsync($"/api/v1/admin/payments/{rest.Payment.Id}/refunds", refundBody);
        Assert.Equal(HttpStatusCode.OK, refunded.StatusCode);
        var after = await (await owner.GetAsync($"/api/v1/admin/bills/{bill.Id}")).ReadAsync<InvoiceDto>();
        Assert.Equal("partiallyRefunded", after.Status);
        Assert.Equal(0, after.Outstanding); // refunds never re-open a balance
    }

    // ----------------------------------------------------------- reports

    [Fact]
    public async Task Reports_count_only_successful_payments_as_collected()
    {
        var owner = await api.OwnerAsync();
        var today = DateOnly.FromDateTime(DateTime.UtcNow.AddMinutes(330));
        async Task<SalesSummary> Summary() => await (await owner.GetAsync(
            $"/api/v1/admin/reports/summary?from={today:yyyy-MM-dd}&to={today:yyyy-MM-dd}")).ReadAsync<SalesSummary>();

        var before = await Summary();
        var guest = await api.GuestAsync();
        var order = await PlaceAsync(guest, [Line("lassi", 3)]);
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        var declined = await (await guest.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount = bill.Amounts.Total, method = "card", idempotencyKey = HttpTestExtensions.Key(),
        })).ReadAsync<PaymentIntentResponse>();
        await guest.PostJsonAsync($"/api/v1/payments/{declined.Payment.Id}/confirm", new { simulatedOutcome = "failure" });

        var middle = await Summary();
        Assert.Equal(before.OrderCount + 1, middle.OrderCount);
        Assert.Equal(before.Billed + bill.Amounts.Total, middle.Billed);
        Assert.Equal(before.Collected, middle.Collected);
        Assert.Equal(before.FailedPayments + 1, middle.FailedPayments);

        var cashier = await api.NewStaffAsync("cashier");
        await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments",
            new { amount = bill.Amounts.Total, method = "cash", idempotencyKey = HttpTestExtensions.Key() });
        var after = await Summary();
        Assert.Equal(middle.Collected + bill.Amounts.Total, after.Collected);
        Assert.True(after.CollectedByMethod!["cash"] >= bill.Amounts.Total);

        // Without viewFinancials, money fields are withheld.
        var manager = await api.NewStaffAsync("manager");
        var limited = await (await manager.GetAsync(
            $"/api/v1/admin/reports/summary?from={today:yyyy-MM-dd}&to={today:yyyy-MM-dd}")).ReadAsync<SalesSummary>();
        Assert.Null(limited.Collected);
        Assert.Equal(after.OrderCount, limited.OrderCount);
    }

    // -------------------------------------------------------------- auth

    [Fact]
    public async Task Sign_in_refresh_rotation_and_reuse_detection()
    {
        var anonymous = api.Anonymous();
        var wrong = await anonymous.PostJsonAsync("/api/v1/auth/login",
            new { email = ApiFactory.OwnerEmail, password = "wrong-password-1" });
        Assert.Equal(HttpStatusCode.Unauthorized, wrong.StatusCode);
        Assert.Equal("invalidCredentials", await wrong.ErrorCodeAsync());
        var unknown = await anonymous.PostJsonAsync("/api/v1/auth/login",
            new { email = "nobody@test.local", password = "wrong-password-1" });
        Assert.Equal("invalidCredentials", await unknown.ErrorCodeAsync());

        var login = await (await anonymous.PostJsonAsync("/api/v1/auth/login",
            new { email = ApiFactory.OwnerEmail.ToUpperInvariant(), password = ApiFactory.OwnerPassword }))
            .ReadAsync<AuthResponse>();
        Assert.Equal("owner", login.Staff.Role);
        Assert.Contains("manageStaff", login.Staff.Permissions);

        var me = await (await api.WithToken(login.AccessToken).GetAsync("/api/v1/auth/me")).ReadAsync<StaffDto>();
        Assert.Equal(ApiFactory.OwnerEmail, me.Email);

        var rotated = await (await anonymous.PostJsonAsync("/api/v1/auth/refresh",
            new { refreshToken = login.RefreshToken })).ReadAsync<AuthResponse>();
        Assert.NotEqual(login.RefreshToken, rotated.RefreshToken);
        // Reusing the old token ends the session, including the new token.
        var reused = await anonymous.PostJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, reused.StatusCode);
        var afterReuse = await anonymous.PostJsonAsync("/api/v1/auth/refresh", new { refreshToken = rotated.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, afterReuse.StatusCode);
    }

    [Fact]
    public async Task Repeated_failures_lock_the_account_for_a_minute()
    {
        var owner = await api.OwnerAsync();
        var email = $"lock-{Guid.NewGuid():N}@test.local";
        (await owner.PostJsonAsync("/api/v1/admin/staff",
            new { name = "Lock Test", email, role = "cashier", password = "CashierPass1" })).EnsureSuccessStatusCode();
        var anonymous = api.Anonymous();
        HttpResponseMessage last = null!;
        for (var i = 0; i < AuthService.MaxFailedAttempts; i++)
        {
            last = await anonymous.PostJsonAsync("/api/v1/auth/login", new { email, password = "wrong-pass-123" });
        }
        Assert.Equal("lockedOut", await last.ErrorCodeAsync());
        var right = await anonymous.PostJsonAsync("/api/v1/auth/login", new { email, password = "CashierPass1" });
        Assert.Equal(HttpStatusCode.TooManyRequests, right.StatusCode);
    }

    [Fact]
    public async Task Deactivated_staff_lose_access_immediately()
    {
        var owner = await api.OwnerAsync();
        var email = $"gone-{Guid.NewGuid():N}@test.local";
        var created = await (await owner.PostJsonAsync("/api/v1/admin/staff",
            new { name = "Leaving Soon", email, role = "manager", password = "ManagerPass1" })).ReadAsync<StaffDto>();
        var manager = await api.StaffAsync(email, "ManagerPass1");
        Assert.Equal(HttpStatusCode.OK, (await manager.GetAsync("/api/v1/admin/orders")).StatusCode);

        (await owner.PatchAsJsonAsync($"/api/v1/admin/staff/{created.Id}", new { active = false }))
            .EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Forbidden, (await manager.GetAsync("/api/v1/admin/orders")).StatusCode);

        // The last active owner cannot be removed.
        var ownerId = (await (await owner.GetAsync("/api/v1/auth/me")).ReadAsync<StaffDto>()).Id;
        var self = await owner.PatchAsJsonAsync($"/api/v1/admin/staff/{ownerId}", new { active = false });
        Assert.Equal(HttpStatusCode.BadRequest, self.StatusCode);
    }

    [Fact]
    public async Task Table_saves_keep_server_assignments_unless_changed()
    {
        var owner = await api.OwnerAsync();
        var waiterEmail = $"server-{Guid.NewGuid():N}@test.local";
        var waiter = await (await owner.PostJsonAsync("/api/v1/admin/staff",
            new { name = "Table Server", email = waiterEmail, role = "waiter", password = "WaiterPass1" }))
            .ReadAsync<StaffDto>();
        var tables = await (await owner.GetAsync("/api/v1/admin/tables")).ReadAsync<List<TableDto>>();

        // Assign table 12, then save the list the way the app does (no
        // `server` field): the assignment stays.
        var assigned = tables.Select(t => t.Number == 12 ? t with { Server = waiter.Id } : t).ToList();
        (await owner.PutAsJsonAsync("/api/v1/admin/tables", assigned)).EnsureSuccessStatusCode();
        var appStyle = tables.Select(t => new { number = t.Number, seats = t.Seats, area = t.Area, active = t.Active });
        var saved = await (await owner.PutAsJsonAsync("/api/v1/admin/tables", appStyle)).ReadAsync<List<TableDto>>();
        Assert.Equal(waiter.Id, saved.Single(t => t.Number == 12).Server);

        // An empty value clears it.
        var cleared = saved.Select(t => t.Number == 12 ? t with { Server = "" } : t).ToList();
        saved = await (await owner.PutAsJsonAsync("/api/v1/admin/tables", cleared)).ReadAsync<List<TableDto>>();
        Assert.Null(saved.Single(t => t.Number == 12).Server);
    }

    // ---------------------------------------------------------- inventory

    [Fact]
    public async Task Running_out_of_stock_marks_linked_dishes_sold_out()
    {
        var owner = await api.OwnerAsync();
        var item = await (await owner.PostJsonAsync("/api/v1/admin/inventory", new
        {
            name = "Paneer", unit = "kg", reorder = 1, dishes = new[] { "paneer_butter_masala" }, initialQuantity = 2,
        })).ReadAsync<InventoryItemDto>();

        var tooMuch = await owner.PostJsonAsync($"/api/v1/admin/inventory/{item.Id}/adjustments",
            new { change = -5, reason = "Used" });
        Assert.Equal("insufficientStock", await tooMuch.ErrorCodeAsync());

        (await owner.PostJsonAsync($"/api/v1/admin/inventory/{item.Id}/adjustments",
            new { change = -2, reason = "Used in service" })).EnsureSuccessStatusCode();
        var menu = await (await api.Anonymous().GetAsync("/api/v1/menu")).ReadAsync<MenuDto>();
        Assert.False(menu.Items.Single(i => i.Id == "paneer_butter_masala").Available);

        (await owner.PostJsonAsync($"/api/v1/admin/inventory/{item.Id}/adjustments",
            new { change = 3, reason = "Delivery" })).EnsureSuccessStatusCode();
        menu = await (await api.Anonymous().GetAsync("/api/v1/menu")).ReadAsync<MenuDto>();
        Assert.True(menu.Items.Single(i => i.Id == "paneer_butter_masala").Available);
    }
}
