using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;

namespace DineQR.Api.Tests;

/// The GPS ordering area (geofence): guests order only from within the
/// configured radius of the restaurant, measured by the server from the
/// position sent with the order. Independent of the dine-in Wi-Fi
/// restriction; with both on, an order must pass both. Every test switches
/// both off again.
[Collection(ApiCollection.Name)]
public class GeofenceTests(ApiFactory api) : IAsyncLifetime
{
    // The restaurant: a point in Chennai.
    private const double Lat = 13.0827;
    private const double Lon = 80.2707;

    /// Metres per degree of latitude (mean Earth radius 6,371,008.8 m).
    private const double MetresPerDegree = 6_371_008.8 * Math.PI / 180;

    /// The restaurant's own public address and a phone on mobile data.
    private const string Restaurant = "203.0.113.10";
    private const string MobileData = "198.51.100.77";

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync()
    {
        var owner = await api.OwnerAsync();
        (await owner.PutAsJsonAsync("/api/v1/admin/geofence", new GeofenceSettingsDto(false, Lat, Lon, 50), Json.Options))
            .EnsureSuccessStatusCode();
        (await api.From(Restaurant, await TokenAsync(owner))
                .PutAsJsonAsync("/api/v1/admin/network-access", new NetworkAccessSettingsDto(false, "", false, []), Json.Options))
            .EnsureSuccessStatusCode();
    }

    private static async Task<string> TokenAsync(HttpClient client) =>
        client.DefaultRequestHeaders.Authorization!.Parameter!;

    /// A position [metres] north of the restaurant.
    private static object North(double metres, double accuracy = 5, bool? mocked = null, DateTime? at = null) => new
    {
        latitude = Lat + metres / MetresPerDegree,
        longitude = Lon,
        accuracy,
        mocked,
        capturedAt = at ?? DateTime.UtcNow,
    };

    private async Task<GeofenceViewDto> ConfigureAsync(bool enabled, int radius, bool takeaway = false)
    {
        var owner = await api.OwnerAsync();
        return await (await owner.PutAsJsonAsync("/api/v1/admin/geofence",
            new GeofenceSettingsDto(enabled, Lat, Lon, radius, takeaway), Json.Options)).ReadAsync<GeofenceViewDto>();
    }

    private static Task<HttpResponseMessage> OrderAsync(HttpClient guest, object? location) =>
        guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { new { itemId = "samosa", quantity = 1 } },
            idempotencyKey = HttpTestExtensions.Key(),
            location,
        });

    private static async Task AssertRefusedAsync(HttpResponseMessage response, string code)
    {
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(code, await response.ErrorCodeAsync());
    }

    [Fact]
    public void Haversine_distances_match_known_values()
    {
        // One degree of latitude.
        Assert.Equal(111_195, GeofenceRules.Distance(0, 0, 1, 0), 0);
        // Chennai Central to Chennai Egmore (about 2.2 km).
        Assert.InRange(GeofenceRules.Distance(13.0827, 80.2707, 13.0784, 80.2610), 1_150, 1_200);
        Assert.Equal(0, GeofenceRules.Distance(Lat, Lon, Lat, Lon), 6);
        // Across the antimeridian.
        Assert.Equal(GeofenceRules.Distance(0, 179.9, 0, -179.9), GeofenceRules.Distance(0, 0, 0, 0.2), 3);
    }

    [Theory]
    [InlineData(20, 10, true)]   // 1. inside a 20 m radius
    [InlineData(20, 60, false)]  // 2. outside a 20 m radius
    [InlineData(50, 40, true)]   // 3. inside a 50 m radius
    [InlineData(50, 120, false)] // 4. outside a 50 m radius
    [InlineData(30, 30, true)]   // on the edge
    [InlineData(100, 99, true)]
    [InlineData(100, 140, false)]
    public async Task Orders_are_accepted_only_inside_the_radius(int radius, double metres, bool allowed)
    {
        await ConfigureAsync(true, radius);
        var guest = await api.GuestAsync(table: 3);
        var response = await OrderAsync(guest, North(metres));
        if (allowed)
        {
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        }
        else
        {
            await AssertRefusedAsync(response, GeofenceRules.OutsideCode);
            Assert.Contains("You are outside the restaurant's permitted location. Please move closer to the " +
                            "restaurant to place your order.", await response.Content.ReadAsStringAsync());
        }

        // The app's own check agrees with the order.
        var check = await guest.PostJsonAsync("/api/v1/guest/location-check", North(metres));
        if (allowed)
        {
            var result = await check.ReadAsync<GuestLocationCheckDto>();
            Assert.True(result.Required);
            Assert.True(result.Allowed);
            Assert.Equal(radius, result.Radius);
            Assert.Equal(metres, result.Distance!.Value, 0);
        }
        else
        {
            await AssertRefusedAsync(check, GeofenceRules.OutsideCode);
        }
    }

    [Fact]
    public async Task The_device_uncertainty_helps_only_a_little()
    {
        await ConfigureAsync(true, 20);
        var guest = await api.GuestAsync(table: 3);
        // 35 m away with ±15 m: possibly inside.
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest, North(35, accuracy: 15))).StatusCode);
        // 60 m away with ±80 m: the tolerance is capped at 20 m.
        await AssertRefusedAsync(await OrderAsync(guest, North(60, accuracy: 80)), GeofenceRules.OutsideCode);
        // Too vague to tell at all.
        await AssertRefusedAsync(await OrderAsync(guest, North(0, accuracy: 500)), GeofenceRules.InaccurateCode);
    }

    [Fact]
    public async Task Missing_invalid_mocked_or_old_positions_are_refused()
    {
        await ConfigureAsync(true, 50);
        var guest = await api.GuestAsync(table: 3);

        // 5./6. Permission denied or GPS off: the app has no position to send.
        await AssertRefusedAsync(await OrderAsync(guest, null), GeofenceRules.RequiredCode);
        await AssertRefusedAsync(await OrderAsync(guest, new { latitude = Lat }), GeofenceRules.RequiredCode);

        // 10. Direct API calls with invalid coordinates.
        await AssertRefusedAsync(await OrderAsync(guest, new { latitude = 123.0, longitude = Lon, accuracy = 5 }),
            GeofenceRules.InvalidCode);
        await AssertRefusedAsync(await OrderAsync(guest, new { latitude = Lat, longitude = 200.0, accuracy = 5 }),
            GeofenceRules.InvalidCode);
        await AssertRefusedAsync(await OrderAsync(guest, new { latitude = 0.0, longitude = 0.0, accuracy = 5 }),
            GeofenceRules.InvalidCode);
        await AssertRefusedAsync(await OrderAsync(guest, new { latitude = Lat, longitude = Lon }),
            GeofenceRules.InaccurateCode);
        await AssertRefusedAsync(await OrderAsync(guest, new { latitude = Lat, longitude = Lon, accuracy = -1 }),
            GeofenceRules.InaccurateCode);
        // A mock-location app, and a reading from long ago or the future.
        await AssertRefusedAsync(await OrderAsync(guest, North(0, mocked: true)), GeofenceRules.MockedCode);
        await AssertRefusedAsync(await OrderAsync(guest, North(0, at: DateTime.UtcNow.AddMinutes(-10))),
            GeofenceRules.StaleCode);
        await AssertRefusedAsync(await OrderAsync(guest, North(0, at: DateTime.UtcNow.AddMinutes(10))),
            GeofenceRules.StaleCode);
        Assert.Empty(await (await guest.GetAsync("/api/v1/orders")).ReadAsync<List<OrderDto>>());
    }

    [Fact]
    public async Task Leaving_and_coming_back_blocks_and_reopens_ordering()
    {
        // 7. The guest walks out of the area, then comes back.
        await ConfigureAsync(true, 30);
        var guest = await api.GuestAsync(table: 3);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest, North(5))).StatusCode);
        await AssertRefusedAsync(await OrderAsync(guest, North(200)), GeofenceRules.OutsideCode);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest, North(8))).StatusCode);
    }

    [Fact]
    public async Task Switched_off_it_is_not_enforced_and_staff_are_never_affected()
    {
        await ConfigureAsync(false, 20);
        var guest = await api.GuestAsync(table: 3);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest, null)).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest, North(5_000))).StatusCode);
        var check = await (await guest.PostJsonAsync("/api/v1/guest/location-check", new { }))
            .ReadAsync<GuestLocationCheckDto>();
        Assert.False(check.Required);

        await ConfigureAsync(true, 20);
        var waiter = await api.NewStaffAsync("waiter");
        Assert.Equal(HttpStatusCode.Created, (await waiter.PostJsonAsync("/api/v1/admin/orders", new
        {
            lines = new[] { new { itemId = "samosa", quantity = 1 } },
            idempotencyKey = HttpTestExtensions.Key(),
            tableNumber = 3,
        })).StatusCode);
    }

    [Fact]
    public async Task Takeaway_is_covered_only_when_the_owner_says_so()
    {
        var owner = await api.OwnerAsync();
        var settings = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Takeaway = true }, Json.Options))
            .EnsureSuccessStatusCode();
        try
        {
            await ConfigureAsync(true, 20);
            var session = await (await api.Anonymous().PostJsonAsync("/api/v1/guest/sessions",
                new { qrPayload = "DINEQR:TAKEAWAY" })).ReadAsync<GuestSessionResponse>();
            var takeaway = api.WithToken(session.GuestToken);
            await ApiFactory.AcceptLegalAsync(takeaway);
            Assert.Equal(HttpStatusCode.Created, (await OrderAsync(takeaway, null)).StatusCode);

            await ConfigureAsync(true, 20, takeaway: true);
            await AssertRefusedAsync(await OrderAsync(takeaway, North(500)), GeofenceRules.OutsideCode);
            Assert.Equal(HttpStatusCode.Created, (await OrderAsync(takeaway, North(3))).StatusCode);
        }
        finally
        {
            (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings, Json.Options)).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task Changing_table_QR_keeps_the_same_rule()
    {
        // 8. A guest scans another table's code: a new session, same area.
        await ConfigureAsync(true, 20);
        var first = await api.GuestAsync(table: 3);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(first, North(5))).StatusCode);
        var second = await api.GuestAsync(table: 4);
        await AssertRefusedAsync(await OrderAsync(second, North(100)), GeofenceRules.OutsideCode);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(second, North(5))).StatusCode);
    }

    [Fact]
    public void Each_restaurant_is_measured_against_its_own_area()
    {
        // 9. Two restaurants with different areas: the same guest position
        // passes one and fails the other.
        var near = new RestaurantGeofence { SettingsId = 1, Latitude = Lat, Longitude = Lon, RadiusMeters = 50, Enabled = true };
        var far = new RestaurantGeofence
        {
            SettingsId = 2, Latitude = 12.9716, Longitude = 77.5946, RadiusMeters = 100, Enabled = true,
        };
        var position = new GuestLocationDto(Lat + 10 / MetresPerDegree, Lon, 5, false, DateTime.UtcNow);
        Assert.Equal(10, GeofenceRules.Check(near, position, DateTime.UtcNow), 0);
        var refused = Assert.Throws<ApiException>(() => GeofenceRules.Check(far, position, DateTime.UtcNow));
        Assert.Equal(GeofenceRules.OutsideCode, refused.Code);
        Assert.Equal(403, refused.Status);
    }

    [Fact]
    public async Task Gps_and_wifi_must_both_pass()
    {
        // 11. The Wi-Fi restriction keeps working exactly as before, and the
        // GPS area is checked in addition to it.
        var owner = api.From(Restaurant, await TokenAsync(await api.OwnerAsync()));
        (await owner.PutAsJsonAsync("/api/v1/admin/network-access", new NetworkAccessSettingsDto(true, "DineQR Guest",
            false, [new AuthorizedNetworkDto(Restaurant, "Router")]), Json.Options)).EnsureSuccessStatusCode();
        await ConfigureAsync(true, 20);

        var session = await (await api.From(Restaurant).PostJsonAsync("/api/v1/guest/sessions",
            new { qrPayload = "DINEQR:TABLE:07" })).ReadAsync<GuestSessionResponse>();
        var onWifi = api.From(Restaurant, session.GuestToken);
        await ApiFactory.AcceptLegalAsync(onWifi);
        var offWifi = api.From(MobileData, session.GuestToken);

        // Wrong network, right place: the Wi-Fi check refuses it, as before.
        var refused = await OrderAsync(offWifi, North(5));
        Assert.Equal(HttpStatusCode.Forbidden, refused.StatusCode);
        Assert.Equal(NetworkAccessService.BlockedCode, await refused.ErrorCodeAsync());
        // Right network, wrong place: the GPS area refuses it.
        await AssertRefusedAsync(await OrderAsync(onWifi, North(300)), GeofenceRules.OutsideCode);
        // Right network, right place.
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(api.From(Restaurant, session.GuestToken), North(5))).StatusCode);
    }

    [Fact]
    public async Task The_owner_configures_the_area_and_guests_see_only_whether_it_is_on()
    {
        var owner = await api.OwnerAsync();
        var view = await ConfigureAsync(true, 30, takeaway: true);
        Assert.True(view.Configured);
        Assert.Equal(1, view.RestaurantId);
        Assert.False(string.IsNullOrEmpty(view.RestaurantName));
        Assert.Equal(Lat, view.Latitude);
        Assert.Equal(30, view.Radius);
        Assert.NotNull(view.CreatedAt);
        Assert.Equal("Test Owner", view.UpdatedBy);

        var reread = await (await owner.GetAsync("/api/v1/admin/geofence")).ReadAsync<GeofenceViewDto>();
        Assert.Equal(view.Longitude, reread.Longitude);

        // Guests learn that it is on and the radius, never the coordinates.
        var json = await (await api.Anonymous().GetAsync("/api/v1/settings")).Content.ReadAsStringAsync();
        var settings = System.Text.Json.JsonSerializer.Deserialize<SettingsDto>(json, Json.Options)!;
        Assert.Equal(new DineInLocationDto(true, 30, true), settings.Location);
        Assert.DoesNotContain(Lat.ToString(System.Globalization.CultureInfo.InvariantCulture), json);

        // Validation.
        async Task Invalid(GeofenceSettingsDto dto) => Assert.Equal(HttpStatusCode.BadRequest,
            (await owner.PutAsJsonAsync("/api/v1/admin/geofence", dto, Json.Options)).StatusCode);
        await Invalid(new GeofenceSettingsDto(true, Lat, Lon, 5));
        await Invalid(new GeofenceSettingsDto(true, Lat, Lon, 5_000));
        await Invalid(new GeofenceSettingsDto(true, 95, Lon, 50));
        await Invalid(new GeofenceSettingsDto(true, Lat, null, 50));
        await Invalid(new GeofenceSettingsDto(true, 0, 0, 50));

        // Only those who manage settings may change it.
        var waiter = await api.NewStaffAsync("waiter");
        Assert.Equal(HttpStatusCode.Forbidden, (await waiter.PutAsJsonAsync("/api/v1/admin/geofence",
            new GeofenceSettingsDto(false, Lat, Lon, 50), Json.Options)).StatusCode);
        var guest = await api.GuestAsync();
        Assert.Equal(HttpStatusCode.Forbidden, (await guest.GetAsync("/api/v1/admin/geofence")).StatusCode);
    }
}
