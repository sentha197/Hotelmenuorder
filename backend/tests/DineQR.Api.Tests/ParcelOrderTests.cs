using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Tests;

[Collection(ApiCollection.Name)]
public class ParcelOrderTests(ApiFactory api)
{
    /// Turns parcel ordering on or off through the settings API, as an owner
    /// would, and returns the saved settings.
    private async Task<SettingsDto> SetParcelAsync(bool enabled)
    {
        var owner = await api.OwnerAsync();
        var current = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        var response = await owner.PutAsJsonAsync(
            "/api/v1/admin/settings", current with { Parcel = enabled }, Json.Options);
        return await response.ReadAsync<SettingsDto>();
    }

    private static Task<HttpResponseMessage> ScanAsync(HttpClient client, string payload) =>
        client.PostJsonAsync("/api/v1/guest/sessions", new { qrPayload = payload });

    [Fact]
    public async Task Parcel_ordering_is_off_until_an_owner_turns_it_on()
    {
        await SetParcelAsync(false);

        var refused = await ScanAsync(api.Anonymous(), "DINEQR:PARCEL");
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("parcelUnavailable", await refused.ErrorCodeAsync());

        await SetParcelAsync(true);
        var accepted = await ScanAsync(api.Anonymous(), "DINEQR:PARCEL");
        Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
    }

    [Fact]
    public async Task The_parcel_setting_is_persisted_and_served_to_guests()
    {
        await SetParcelAsync(true);
        var published = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.True(published.Parcel);

        await SetParcelAsync(false);
        published = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.False(published.Parcel);
    }

    [Fact]
    public async Task A_parcel_session_carries_no_table()
    {
        await SetParcelAsync(true);
        var session = await (await ScanAsync(api.Anonymous(), "DINEQR:PARCEL"))
            .ReadAsync<GuestSessionResponse>();
        Assert.Equal(OrderTables.Parcel, session.TableNumber);
        Assert.NotEmpty(session.GuestToken);
    }

    [Theory]
    [InlineData("dineqr:parcel")]
    [InlineData("  DINEQR:PARCEL  ")]
    [InlineData("BITEANDDINE:PARCEL")]
    public async Task The_parcel_code_is_accepted_whatever_its_casing_or_padding(string payload)
    {
        await SetParcelAsync(true);
        var response = await ScanAsync(api.Anonymous(), payload);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Theory]
    [InlineData("DINEQR:PARCELS")]
    [InlineData("DINEQR:PARCEL:1")]
    [InlineData("PARCEL")]
    public async Task Near_misses_do_not_open_a_parcel_session(string payload)
    {
        await SetParcelAsync(true);
        var response = await ScanAsync(api.Anonymous(), payload);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Table_zero_is_not_a_dine_in_table()
    {
        await SetParcelAsync(true);
        var response = await ScanAsync(api.Anonymous(), "DINEQR:TABLE:00");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task A_guest_can_place_and_track_a_parcel_order()
    {
        await SetParcelAsync(true);
        var session = await (await ScanAsync(api.Anonymous(), "DINEQR:PARCEL"))
            .ReadAsync<GuestSessionResponse>();
        var guest = api.WithToken(session.GuestToken);

        var placed = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { new { itemId = "chicken_65", quantity = 2, options = (object?)null } },
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal(HttpStatusCode.Created, placed.StatusCode);
        var order = await placed.ReadAsync<OrderDto>();
        Assert.Equal(OrderTables.Parcel, order.Table);

        // It reaches the staff order list like any other order.
        var owner = await api.OwnerAsync();
        var fetched = await (await owner.GetAsync($"/api/v1/admin/orders/{order.Id}")).ReadAsync<OrderDto>();
        Assert.Equal(OrderTables.Parcel, fetched.Table);
    }

    [Fact]
    public async Task Closing_parcel_orders_stops_new_ones_on_an_open_session()
    {
        await SetParcelAsync(true);
        var session = await (await ScanAsync(api.Anonymous(), "DINEQR:PARCEL"))
            .ReadAsync<GuestSessionResponse>();
        var guest = api.WithToken(session.GuestToken);

        // The session token stays valid, but the order must still be refused.
        await SetParcelAsync(false);
        var response = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { new { itemId = "chicken_65", quantity = 1, options = (object?)null } },
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("parcelUnavailable", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task Dine_in_orders_still_work_while_parcel_is_open()
    {
        await SetParcelAsync(true);
        var guest = await api.GuestAsync(table: 5);
        var placed = await guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { new { itemId = "chicken_65", quantity = 1, options = (object?)null } },
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.Equal(HttpStatusCode.Created, placed.StatusCode);
        Assert.Equal(5, (await placed.ReadAsync<OrderDto>()).Table);
    }

    [Fact]
    public void Labels_separate_parcel_from_a_table()
    {
        Assert.Equal("Parcel", OrderTables.Label(OrderTables.Parcel));
        Assert.Equal("Table 07", OrderTables.Label(7));
        Assert.Equal(OrderType.Parcel, OrderTables.TypeOf(OrderTables.Parcel));
        Assert.Equal(OrderType.DineIn, OrderTables.TypeOf(1));
    }
}
