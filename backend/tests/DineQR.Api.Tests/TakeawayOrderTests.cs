using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Tests;

[Collection(ApiCollection.Name)]
public class TakeawayOrderTests(ApiFactory api)
{
    /// Saves the settings as an owner would, after [change], and returns the
    /// saved settings.
    private async Task<SettingsDto> SaveSettingsAsync(Func<SettingsDto, SettingsDto> change)
    {
        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        var response = await owner.PutAsJsonAsync("/api/v1/admin/settings", change(current), Json.Options);
        return await response.ReadAsync<SettingsDto>();
    }

    /// Turns takeaway ordering on or off through the settings API.
    private Task<SettingsDto> SetTakeawayAsync(bool enabled) =>
        SaveSettingsAsync(current => current with { Takeaway = enabled });

    private static Task<HttpResponseMessage> ScanAsync(HttpClient client, string payload) =>
        client.PostJsonAsync("/api/v1/guest/sessions", new { qrPayload = payload });

    private async Task<HttpClient> TakeawayGuestAsync()
    {
        var session = await (await ScanAsync(api.Anonymous(), "DINEQR:TAKEAWAY"))
            .ReadAsync<GuestSessionResponse>();
        return api.WithToken(session.GuestToken);
    }

    /// An order body with one dish; [orderType] is left out when null, as
    /// apps from before the type was sent do.
    private static object Order(string? orderType = null, string? key = null, int? tableNumber = null) => new
    {
        lines = new[] { new { itemId = "chicken_65", quantity = 2, options = (object?)null } },
        idempotencyKey = key ?? HttpTestExtensions.Key(),
        orderType,
        tableNumber,
    };

    private static async Task<OrderDto> MoveAsync(HttpClient staff, string id, string target) =>
        await (await staff.PostJsonAsync($"/api/v1/admin/orders/{id}/status", new { target }))
            .ReadAsync<OrderDto>();

    // ---------------------------------------------------------- settings

    [Fact]
    public async Task Takeaway_ordering_is_off_until_an_owner_turns_it_on()
    {
        await SetTakeawayAsync(false);

        var refused = await ScanAsync(api.Anonymous(), "DINEQR:TAKEAWAY");
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("takeawayUnavailable", await refused.ErrorCodeAsync());

        await SetTakeawayAsync(true);
        var accepted = await ScanAsync(api.Anonymous(), "DINEQR:TAKEAWAY");
        Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
    }

    [Fact]
    public async Task The_takeaway_setting_is_saved_and_served_under_both_names()
    {
        await SetTakeawayAsync(true);
        var published = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.True(published.Takeaway);
        // Installed apps from before the rename read the old name.
        Assert.True(published.Parcel);

        await SetTakeawayAsync(false);
        published = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.False(published.Takeaway);
        Assert.False(published.Parcel);
    }

    [Fact]
    public async Task An_admin_app_from_before_the_rename_still_switches_takeaway()
    {
        await SetTakeawayAsync(false);
        var saved = await SaveSettingsAsync(current => current with { Takeaway = null, Parcel = true });
        Assert.True(saved.Takeaway);

        saved = await SaveSettingsAsync(current => current with { Takeaway = null, Parcel = false });
        Assert.False(saved.Takeaway);
    }

    [Fact]
    public async Task A_save_that_names_neither_key_leaves_takeaway_as_it_was()
    {
        await SetTakeawayAsync(true);
        var saved = await SaveSettingsAsync(current => current with
        {
            Takeaway = null, Parcel = null, Footer = "Thank you!",
        });
        Assert.True(saved.Takeaway);
        Assert.Equal("Thank you!", saved.Footer);
    }

    // ------------------------------------------------------------ sessions

    [Fact]
    public async Task A_takeaway_session_carries_no_table()
    {
        await SetTakeawayAsync(true);
        var session = await (await ScanAsync(api.Anonymous(), "DINEQR:TAKEAWAY"))
            .ReadAsync<GuestSessionResponse>();
        Assert.Equal(OrderTables.Takeaway, session.TableNumber);
        Assert.Equal("takeaway", session.OrderType);
        Assert.NotEmpty(session.GuestToken);

        var table = await (await ScanAsync(api.Anonymous(), "DINEQR:TABLE:05")).ReadAsync<GuestSessionResponse>();
        Assert.Equal("dineIn", table.OrderType);
    }

    [Theory]
    [InlineData("dineqr:takeaway")]
    [InlineData("  DINEQR:TAKEAWAY  ")]
    // Codes printed while takeaway was called "parcel" keep working.
    [InlineData("DINEQR:PARCEL")]
    [InlineData("dineqr:parcel")]
    [InlineData("BITEANDDINE:PARCEL")]
    public async Task The_takeaway_code_is_accepted_whatever_its_casing_padding_or_age(string payload)
    {
        await SetTakeawayAsync(true);
        var session = await (await ScanAsync(api.Anonymous(), payload)).ReadAsync<GuestSessionResponse>();
        Assert.Equal(OrderTables.Takeaway, session.TableNumber);
    }

    [Theory]
    [InlineData("DINEQR:TAKEAWAYS")]
    [InlineData("DINEQR:TAKEAWAY:1")]
    [InlineData("DINEQR:TAKE AWAY")]
    [InlineData("TAKEAWAY")]
    [InlineData("DINEQR:PARCELS")]
    [InlineData("BITEANDDINE:TAKEAWAY")]
    public async Task Near_misses_do_not_open_a_takeaway_session(string payload)
    {
        await SetTakeawayAsync(true);
        var response = await ScanAsync(api.Anonymous(), payload);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Table_zero_is_not_a_dine_in_table()
    {
        await SetTakeawayAsync(true);
        var response = await ScanAsync(api.Anonymous(), "DINEQR:TABLE:00");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // -------------------------------------------------------------- orders

    [Fact]
    public async Task A_guest_takeaway_order_goes_through_the_whole_workflow()
    {
        await SetTakeawayAsync(true);
        var guest = await TakeawayGuestAsync();

        var placed = await guest.PostJsonAsync("/api/v1/orders", Order(orderType: "takeaway"));
        Assert.Equal(HttpStatusCode.Created, placed.StatusCode);
        var order = await placed.ReadAsync<OrderDto>();
        Assert.Equal(OrderTables.Takeaway, order.Table);
        Assert.Equal("takeaway", order.Type);
        Assert.Equal("placed", order.Status);
        Assert.Equal("guest", order.Source);
        Assert.True(order.Total > 0);

        // Its bill exists from the start, with the order's own totals.
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        Assert.Equal(OrderTables.Takeaway, bill.Table);
        Assert.Equal("takeaway", bill.Type);
        Assert.Equal(order.Total, bill.Amounts.Total);
        Assert.Equal(order.Subtotal + order.Service + order.Tax - order.Discount, bill.Amounts.Total);
        Assert.Equal("unpaid", bill.Status);
        Assert.Equal(bill.Amounts.Total, bill.Outstanding);

        // It reaches the staff order list like any other order.
        var owner = await api.OwnerAsync();
        var listed = await (await owner.GetAsync("/api/v1/admin/orders")).ReadAsync<List<OrderDto>>();
        var staffCopy = Assert.Single(listed, o => o.Id == order.Id);
        Assert.Equal("takeaway", staffCopy.Type);

        // The kitchen and service workflow is the same as for a table.
        var kitchen = await api.NewStaffAsync("kitchen");
        var waiter = await api.NewStaffAsync("waiter");
        await MoveAsync(kitchen, order.Id, "accepted");
        await MoveAsync(kitchen, order.Id, "preparing");
        await MoveAsync(kitchen, order.Id, "readyToServe");
        Assert.Equal(HttpStatusCode.Forbidden,
            (await kitchen.PostJsonAsync($"/api/v1/admin/orders/{order.Id}/status", new { target = "served" }))
            .StatusCode);
        var collected = await MoveAsync(waiter, order.Id, "served");
        Assert.Equal("served", collected.Status);

        // The guest sees it collected, in their own list too.
        var tracked = await (await guest.GetAsync($"/api/v1/orders/{order.Id}")).ReadAsync<OrderDto>();
        Assert.Equal("served", tracked.Status);
        Assert.Contains(await (await guest.GetAsync("/api/v1/orders")).ReadAsync<List<OrderDto>>(),
            o => o.Id == order.Id);

        // Paid at the counter: the bill settles like any other.
        var cashier = await api.NewStaffAsync("cashier");
        var paid = await (await cashier.PostJsonAsync($"/api/v1/admin/bills/{bill.Id}/payments", new
        {
            amount = bill.Amounts.Total, method = "cash", idempotencyKey = HttpTestExtensions.Key(),
        })).ReadAsync<PaymentResultDto>();
        Assert.Equal("paid", paid.Invoice.Status);
        Assert.Equal(0, paid.Invoice.Outstanding);
    }

    [Fact]
    public async Task The_order_type_must_match_the_session()
    {
        await SetTakeawayAsync(true);
        var takeaway = await TakeawayGuestAsync();
        var wrong = await takeaway.PostJsonAsync("/api/v1/orders", Order(orderType: "dineIn"));
        Assert.Equal(HttpStatusCode.Conflict, wrong.StatusCode);
        Assert.Equal("orderTypeMismatch", await wrong.ErrorCodeAsync());

        var table = await api.GuestAsync(table: 5);
        wrong = await table.PostJsonAsync("/api/v1/orders", Order(orderType: "takeaway"));
        Assert.Equal("orderTypeMismatch", await wrong.ErrorCodeAsync());

        var unknown = await takeaway.PostJsonAsync("/api/v1/orders", Order(orderType: "parcel"));
        Assert.Equal(HttpStatusCode.BadRequest, unknown.StatusCode);

        // Without a type (apps from before it was sent) the session decides.
        var legacy = await (await takeaway.PostJsonAsync("/api/v1/orders", Order())).ReadAsync<OrderDto>();
        Assert.Equal("takeaway", legacy.Type);
    }

    [Fact]
    public async Task Retrying_a_takeaway_order_never_creates_a_second_one()
    {
        await SetTakeawayAsync(true);
        var guest = await TakeawayGuestAsync();
        var key = HttpTestExtensions.Key();

        var first = await guest.PostJsonAsync("/api/v1/orders", Order(orderType: "takeaway", key: key));
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var replay = await guest.PostJsonAsync("/api/v1/orders", Order(orderType: "takeaway", key: key));
        Assert.Equal(HttpStatusCode.OK, replay.StatusCode);
        var original = await first.ReadAsync<OrderDto>();
        Assert.Equal(original.Id, (await replay.ReadAsync<OrderDto>()).Id);

        var mine = await (await guest.GetAsync("/api/v1/orders")).ReadAsync<List<OrderDto>>();
        Assert.Single(mine, o => o.Id == original.Id);
    }

    [Fact]
    public async Task Closing_takeaway_stops_new_orders_on_an_open_session()
    {
        await SetTakeawayAsync(true);
        var guest = await TakeawayGuestAsync();

        // The session token stays valid, but the order must still be refused.
        await SetTakeawayAsync(false);
        var response = await guest.PostJsonAsync("/api/v1/orders", Order(orderType: "takeaway"));
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("takeawayUnavailable", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task Staff_ring_up_takeaway_orders_without_a_table()
    {
        await SetTakeawayAsync(true);
        var cashier = await api.NewStaffAsync("cashier");

        var placed = await cashier.PostJsonAsync("/api/v1/admin/orders", Order(orderType: "takeaway"));
        Assert.Equal(HttpStatusCode.Created, placed.StatusCode);
        var order = await placed.ReadAsync<OrderDto>();
        Assert.Equal(OrderTables.Takeaway, order.Table);
        Assert.Equal("takeaway", order.Type);
        Assert.Equal("staff", order.Source);

        // Apps from before the type was sent use table 0.
        var legacy = await (await cashier.PostJsonAsync("/api/v1/admin/orders", Order(tableNumber: 0)))
            .ReadAsync<OrderDto>();
        Assert.Equal("takeaway", legacy.Type);

        var both = await cashier.PostJsonAsync("/api/v1/admin/orders", Order(orderType: "takeaway", tableNumber: 5));
        Assert.Equal(HttpStatusCode.BadRequest, both.StatusCode);
        var noTable = await cashier.PostJsonAsync("/api/v1/admin/orders", Order(orderType: "dineIn"));
        Assert.Equal("missingTable", await noTable.ErrorCodeAsync());

        await SetTakeawayAsync(false);
        var closed = await cashier.PostJsonAsync("/api/v1/admin/orders", Order(orderType: "takeaway"));
        Assert.Equal("takeawayUnavailable", await closed.ErrorCodeAsync());
    }

    [Fact]
    public async Task Dine_in_orders_still_work_while_takeaway_is_open()
    {
        await SetTakeawayAsync(true);
        var guest = await api.GuestAsync(table: 5);

        var placed = await guest.PostJsonAsync("/api/v1/orders", Order());
        Assert.Equal(HttpStatusCode.Created, placed.StatusCode);
        var order = await placed.ReadAsync<OrderDto>();
        Assert.Equal(5, order.Table);
        Assert.Equal("dineIn", order.Type);

        var typed = await (await guest.PostJsonAsync("/api/v1/orders", Order(orderType: "dineIn")))
            .ReadAsync<OrderDto>();
        Assert.Equal(5, typed.Table);

        var waiter = await api.NewStaffAsync("waiter");
        var staffOrder = await (await waiter.PostJsonAsync("/api/v1/admin/orders", Order(tableNumber: 7)))
            .ReadAsync<OrderDto>();
        Assert.Equal("dineIn", staffOrder.Type);
        Assert.Equal(7, staffOrder.Table);
    }

    [Fact]
    public void Labels_separate_takeaway_from_a_table()
    {
        Assert.Equal("Takeaway", OrderTables.Label(OrderTables.Takeaway));
        Assert.Equal("Table 07", OrderTables.Label(7));
        Assert.Equal(OrderType.Takeaway, OrderTables.TypeOf(OrderTables.Takeaway));
        Assert.Equal(OrderType.DineIn, OrderTables.TypeOf(1));
    }
}
