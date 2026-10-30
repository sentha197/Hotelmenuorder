using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.IdentityModel.Tokens;

namespace DineQR.Api.Tests;

/// The dine-in Wi-Fi restriction: a guest at a table may order and start
/// paying only from the restaurant's internet connection, recognised by
/// the public address the server sees. Requests here say which address
/// they come from (ApiFactory.From); documentation addresses stand in for
/// real ones. Every test switches the restriction off again.
[Collection(ApiCollection.Name)]
public class WifiRestrictionTests(ApiFactory api) : IAsyncLifetime
{
    /// The restaurant's own public address (its Wi-Fi's way out).
    private const string Restaurant = "203.0.113.10";

    /// A phone on mobile data.
    private const string MobileData = "198.51.100.77";

    /// A phone on some other Wi-Fi (a café next door).
    private const string OtherWifi = "192.0.2.44";

    private HttpClient? _owner;

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync()
    {
        await SaveAsync(new NetworkAccessSettingsDto(false, "", false, []));
        api.Services.GetRequiredService<HostAddressCache>().Override = null;
    }

    private async Task<HttpClient> OwnerAsync() => _owner ??= api.From(Restaurant,
        (await (await api.Anonymous().PostAsJsonAsync("/api/v1/auth/login",
            new { email = ApiFactory.OwnerEmail, password = ApiFactory.OwnerPassword }))
            .ReadAsync<AuthResponse>()).AccessToken);

    private async Task<NetworkAccessViewDto> SaveAsync(NetworkAccessSettingsDto dto) =>
        await (await (await OwnerAsync()).PutAsJsonAsync("/api/v1/admin/network-access", dto, Json.Options))
            .ReadAsync<NetworkAccessViewDto>();

    private Task<NetworkAccessViewDto> RestrictAsync(bool takeaway = false, params string[] networks) =>
        SaveAsync(new NetworkAccessSettingsDto(true, "DineQR Guest", takeaway,
            [.. (networks.Length == 0 ? [Restaurant] : networks).Select(n => new AuthorizedNetworkDto(n, "Router"))]));

    private static Task<HttpResponseMessage> ScanAsync(HttpClient client, string payload = "DINEQR:TABLE:07") =>
        client.PostJsonAsync("/api/v1/guest/sessions", new { qrPayload = payload });

    /// A guest session started on [address]: its token.
    private async Task<string> SessionAsync(string address, string payload = "DINEQR:TABLE:07") =>
        (await (await ScanAsync(api.From(address), payload)).ReadAsync<GuestSessionResponse>()).GuestToken;

    private static Task<HttpResponseMessage> OrderAsync(HttpClient guest) =>
        guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { new { itemId = "samosa", quantity = 1 } },
            idempotencyKey = HttpTestExtensions.Key(),
        });

    private static async Task AssertBlockedAsync(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(NetworkAccessService.BlockedCode, await response.ErrorCodeAsync());
        Assert.Contains("connect to the restaurant's Wi-Fi", await response.Content.ReadAsStringAsync());
    }

    private async Task<GuestSession?> SessionRowAsync(string token)
    {
        var id = Guid.Parse(new JwtSecurityTokenHandler().ReadJwtToken(token).Claims
            .First(c => c.Type == ClaimNames.Session).Value);
        await using var scope = api.Services.CreateAsyncScope();
        return await scope.ServiceProvider.GetRequiredService<AppDbContext>().GuestSessions.AsNoTracking()
            .FirstOrDefaultAsync(g => g.Id == id);
    }

    // ------------------------------------------------------------ the flow

    [Fact]
    public async Task On_the_restaurant_wifi_a_guest_scans_orders_and_pays()
    {
        await RestrictAsync();
        var token = await SessionAsync(Restaurant);
        var guest = api.From(Restaurant, token);

        var checkResult = await (await guest.PostJsonAsync("/api/v1/guest/network-access", new { }))
            .ReadAsync<GuestNetworkAccessDto>();
        Assert.True(checkResult.Required);
        Assert.True(checkResult.Allowed);

        var order = await (await OrderAsync(guest)).ReadAsync<OrderDto>();
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        var intent = await guest.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount = bill.Amounts.Total, method = "upi",
            idempotencyKey = HttpTestExtensions.Key(),
        });
        Assert.True(intent.IsSuccessStatusCode, await intent.Content.ReadAsStringAsync());

        var row = await SessionRowAsync(token);
        Assert.Equal(GuestSessionStatus.Active, row!.Status);
        Assert.Equal(7, row.TableNumber);
        Assert.NotNull(row.VerifiedAt);
    }

    [Theory]
    [InlineData(MobileData)]
    [InlineData(OtherWifi)]
    [InlineData("2001:db8:ffff::5")]
    public async Task On_mobile_data_or_another_wifi_no_session_starts(string address)
    {
        await RestrictAsync();

        await AssertBlockedAsync(await ScanAsync(api.From(address)));
    }

    [Fact]
    public async Task Leaving_the_wifi_blocks_the_session_and_coming_back_restores_it()
    {
        await RestrictAsync();
        var token = await SessionAsync(Restaurant);

        // The guest switches to mobile data while browsing the menu: the
        // menu itself is public, ordering is not.
        var away = api.From(MobileData, token);
        Assert.True((await away.GetAsync("/api/v1/menu")).IsSuccessStatusCode);
        await AssertBlockedAsync(await OrderAsync(away));
        await AssertBlockedAsync(await away.PostJsonAsync("/api/v1/guest/network-access", new { }));
        var blocked = await SessionRowAsync(token);
        Assert.Equal(GuestSessionStatus.Blocked, blocked!.Status);

        // Back on the restaurant Wi-Fi, a check restores it.
        var back = api.From(Restaurant, token);
        var verified = await (await back.PostJsonAsync("/api/v1/guest/network-access", new { }))
            .ReadAsync<GuestNetworkAccessDto>();
        Assert.True(verified.Allowed);
        Assert.Equal(GuestSessionStatus.Active, (await SessionRowAsync(token))!.Status);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(back)).StatusCode);
    }

    [Fact]
    public async Task Calling_the_api_directly_or_naming_the_restaurant_address_does_not_get_through()
    {
        await RestrictAsync();
        var token = await SessionAsync(Restaurant);
        var away = api.From(MobileData, token);

        // Headers a client can set prove nothing: the address comes from the
        // connection (or a trusted edge), never from what the app claims.
        foreach (var (name, value) in new[]
                 {
                     ("X-Forwarded-For", Restaurant), ("X-Real-IP", Restaurant), ("CF-Connecting-IP", Restaurant),
                     ("X-Wifi-Ssid", "DineQR Guest"), ("X-Is-Connected", "true"),
                 })
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/orders")
            {
                Content = JsonContent.Create(new
                {
                    lines = new[] { new { itemId = "samosa", quantity = 1 } },
                    idempotencyKey = HttpTestExtensions.Key(),
                }, options: Json.Options),
            };
            request.Headers.Add(name, value);
            await AssertBlockedAsync(await away.SendAsync(request));
        }

        // Starting a payment or asking for the counter is refused as well;
        // reading one's own bills is not (it changes nothing).
        Assert.True((await away.GetAsync("/api/v1/bills")).IsSuccessStatusCode);
        var order = await (await OrderAsync(api.From(Restaurant, token))).ReadAsync<OrderDto>();
        var bill = await (await away.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        await AssertBlockedAsync(await away.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount = bill.Amounts.Total, method = "upi",
            idempotencyKey = HttpTestExtensions.Key(),
        }));
        await AssertBlockedAsync(await away.PostJsonAsync($"/api/v1/bills/{bill.Id}/counter-request",
            new { kind = "cash" }));

        // A session cannot even be started by naming the restaurant address.
        using var scan = new HttpRequestMessage(HttpMethod.Post, "/api/v1/guest/sessions")
        {
            Content = JsonContent.Create(new { qrPayload = "DINEQR:TABLE:07" }, options: Json.Options),
        };
        scan.Headers.Add("X-Forwarded-For", Restaurant);
        await AssertBlockedAsync(await api.From(MobileData).SendAsync(scan));
    }

    [Fact]
    public async Task With_the_restriction_off_everything_works_from_anywhere()
    {
        await SaveAsync(new NetworkAccessSettingsDto(false, "DineQR Guest", false,
            [new AuthorizedNetworkDto(Restaurant, null)]));
        var token = await SessionAsync(MobileData);
        var guest = api.From(OtherWifi, token);

        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest)).StatusCode);
        var verified = await (await guest.PostJsonAsync("/api/v1/guest/network-access", new { }))
            .ReadAsync<GuestNetworkAccessDto>();
        Assert.False(verified.Required);
    }

    [Fact]
    public async Task Takeaway_is_left_alone_unless_the_restaurant_includes_it()
    {
        var owner = await OwnerAsync();
        var settings = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Takeaway = true, Offers = null },
            Json.Options)).EnsureSuccessStatusCode();
        try
        {
            await RestrictAsync();
            var takeaway = await SessionAsync(MobileData, "DINEQR:TAKEAWAY");
            Assert.Equal(HttpStatusCode.Created, (await OrderAsync(api.From(MobileData, takeaway))).StatusCode);

            await RestrictAsync(takeaway: true);
            await AssertBlockedAsync(await ScanAsync(api.From(MobileData), "DINEQR:TAKEAWAY"));
            await AssertBlockedAsync(await OrderAsync(api.From(MobileData, takeaway)));
        }
        finally
        {
            (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Offers = null }, Json.Options))
                .EnsureSuccessStatusCode();
        }
    }

    // ---------------------------------------------- what keeps working

    [Fact]
    public async Task Accepted_orders_and_payments_already_started_carry_on_off_the_wifi()
    {
        await RestrictAsync();
        var token = await SessionAsync(Restaurant);
        var onWifi = api.From(Restaurant, token);
        var order = await (await OrderAsync(onWifi)).ReadAsync<OrderDto>();
        var bill = await (await onWifi.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        var intent = await (await onWifi.PostJsonAsync("/api/v1/payments/intents", new
        {
            invoiceId = bill.Id, amount = bill.Amounts.Total, method = "upi",
            idempotencyKey = HttpTestExtensions.Key(),
        })).ReadAsync<PaymentIntentResponse>();

        // The guest walks out of Wi-Fi range.
        var away = api.From(MobileData, token);
        await AssertBlockedAsync(await OrderAsync(away));

        // The kitchen goes on; staff are never restricted.
        var owner = await OwnerAsync();
        foreach (var target in new[] { "accepted", "preparing" })
        {
            (await owner.PostJsonAsync($"/api/v1/admin/orders/{order.Id}/status", new { target }))
                .EnsureSuccessStatusCode();
        }
        // The guest can still follow the order and finish the payment
        // already under way; nothing is cancelled or changed by leaving.
        var tracked = await (await away.GetAsync($"/api/v1/orders/{order.Id}")).ReadAsync<OrderDto>();
        Assert.Equal("preparing", tracked.Status);
        var paid = await (await away.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/confirm",
            new { simulatedOutcome = "success" })).ReadAsync<PaymentResultDto>();
        Assert.Equal("succeeded", paid.Payment.Status);
        Assert.Equal("paid", paid.Invoice.Status);
    }

    [Fact]
    public async Task Gateway_webhooks_settle_payments_whatever_network_the_guest_is_on()
    {
        var owner = await OwnerAsync();
        api.Cashfree.Enable();
        var settings = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { PaymentMode = "live", Offers = null },
            Json.Options)).EnsureSuccessStatusCode();
        try
        {
            await RestrictAsync();
            var token = await SessionAsync(Restaurant);
            var onWifi = api.From(Restaurant, token);
            var order = await (await OrderAsync(onWifi)).ReadAsync<OrderDto>();
            var bill = await (await onWifi.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
            var intent = await (await onWifi.PostJsonAsync("/api/v1/payments/intents", new
            {
                invoiceId = bill.Id, amount = bill.Amounts.Total, method = "upi",
                idempotencyKey = HttpTestExtensions.Key(),
            })).ReadAsync<PaymentIntentResponse>();
            var gatewayOrder = api.Cashfree.Orders.Keys.Single(k => k.StartsWith(intent.Payment.Id + "_"));

            // The guest pays in their UPI app over mobile data; Cashfree's
            // webhook (which carries no guest token) settles the bill.
            api.Cashfree.Pay(gatewayOrder, bankReference: "512345678901");
            var (body, timestamp, signature) = api.Cashfree.Webhook(gatewayOrder, "PAYMENT_SUCCESS_WEBHOOK");
            using var webhook = new HttpRequestMessage(HttpMethod.Post, "/api/v1/webhooks/payments/cashfree")
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            };
            webhook.Headers.Add("x-webhook-timestamp", timestamp);
            webhook.Headers.Add("x-webhook-signature", signature);
            Assert.Equal(HttpStatusCode.OK, (await api.From("198.51.100.200").SendAsync(webhook)).StatusCode);

            var away = api.From(MobileData, token);
            var status = await (await away.GetAsync($"/api/v1/payments/{intent.Payment.Id}"))
                .ReadAsync<PaymentResultDto>();
            Assert.Equal("succeeded", status.Payment.Status);
            Assert.Equal("paid", status.Invoice.Status);
        }
        finally
        {
            (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Offers = null }, Json.Options))
                .EnsureSuccessStatusCode();
            api.Cashfree.Reset();
        }
    }

    // ------------------------------------------------------- isolation

    [Fact]
    public async Task Another_restaurants_session_cannot_be_used_and_the_config_stays_private()
    {
        await RestrictAsync();

        // A token another DineQR deployment issued (its own signing key)
        // for the same table and session shape is not accepted here.
        var foreign = new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            issuer: "dineqr-api",
            audience: "dineqr-apps",
            claims:
            [
                new Claim(ClaimNames.TokenType, ClaimNames.Guest),
                new Claim(ClaimNames.Session, Guid.NewGuid().ToString()),
                new Claim(ClaimNames.Table, "7"),
            ],
            expires: DateTime.UtcNow.AddHours(1),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(Encoding.UTF8.GetBytes("another-restaurant-signing-key-0123456789-abcdef")),
                SecurityAlgorithms.HmacSha256)));
        var stranger = api.From(Restaurant, foreign);
        Assert.Equal(HttpStatusCode.Unauthorized, (await OrderAsync(stranger)).StatusCode);

        // Guests learn only that the restriction is on and the Wi-Fi's name.
        var published = await (await api.Anonymous().GetAsync("/api/v1/settings")).Content.ReadAsStringAsync();
        Assert.Contains("DineQR Guest", published);
        Assert.DoesNotContain(Restaurant, published);
        var cashier = await api.NewStaffAsync("cashier");
        Assert.Equal(HttpStatusCode.Forbidden, (await cashier.GetAsync("/api/v1/admin/network-access")).StatusCode);
    }

    // ------------------------------------------------ setting it up

    [Fact]
    public async Task Only_usable_networks_can_be_authorised()
    {
        var owner = await OwnerAsync();
        async Task<string> Refused(params string[] networks)
        {
            var response = await owner.PutAsJsonAsync("/api/v1/admin/network-access",
                new NetworkAccessSettingsDto(false, "", false,
                    [.. networks.Select(n => new AuthorizedNetworkDto(n, null))]), Json.Options);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            return await response.Content.ReadAsStringAsync();
        }

        Assert.Contains("private", await Refused("192.168.1.0/24"));
        Assert.Contains("private", await Refused("10.0.0.1"));
        Assert.Contains("carrier-grade NAT", await Refused("100.64.12.34"));
        Assert.Contains("too wide", await Refused("203.0.0.0/16"));
        Assert.Contains("too wide", await Refused("2001:db8::/32"));
        Assert.Contains("not an IP address", await Refused("not a network!"));
        Assert.Contains("listed twice", await Refused("203.0.113.10", "203.0.113.10/32"));

        // Switching on needs a network.
        var empty = await owner.PutAsJsonAsync("/api/v1/admin/network-access",
            new NetworkAccessSettingsDto(true, "", false, []), Json.Options);
        Assert.Equal(HttpStatusCode.BadRequest, empty.StatusCode);

        // Saved in canonical form; a range typed with host bits means its block.
        var saved = await SaveAsync(new NetworkAccessSettingsDto(false, "Cafe", false,
        [
            new AuthorizedNetworkDto("203.0.113.10", "Fibre"),
            new AuthorizedNetworkDto("198.51.100.13/29", "Backup line"),
            new AuthorizedNetworkDto("2001:db8:12:34::/64", null),
        ]));
        Assert.Equal(["203.0.113.10/32", "198.51.100.8/29", "2001:db8:12:34::/64"],
            saved.Networks.Select(n => n.Value));
    }

    [Fact]
    public async Task The_owner_sees_what_the_server_sees_for_their_own_device()
    {
        var view = await RestrictAsync();
        Assert.Equal(Restaurant, view.You.Address);
        Assert.True(view.You.Matches);
        Assert.Equal("203.0.113.10/32", view.You.MatchedBy);
        Assert.Equal(Restaurant, view.You.SuggestedEntry);
        Assert.True(view.You.Consistent);

        // From an IPv6 phone, the suggestion is its /64.
        var owner = api.From("2001:db8:12:34:aaaa:bbbb:cccc:dddd", (await OwnerAsync()).DefaultRequestHeaders
            .Authorization!.Parameter);
        var seen = await (await owner.GetAsync("/api/v1/admin/network-access")).ReadAsync<NetworkAccessViewDto>();
        Assert.False(seen.You.Matches);
        Assert.Equal("2001:db8:12:34::/64", seen.You.SuggestedEntry);

        // A proxy header naming another client is flagged.
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/admin/network-access");
        request.Headers.Add("CF-Connecting-IP", MobileData);
        var flagged = await (await owner.SendAsync(request)).ReadAsync<NetworkAccessViewDto>();
        Assert.False(flagged.You.Consistent);
        Assert.Equal(MobileData, flagged.You.Headers["CF-Connecting-IP"]);
    }

    [Fact]
    public async Task An_ipv6_prefix_and_a_dynamic_dns_name_are_honoured()
    {
        var cache = api.Services.GetRequiredService<HostAddressCache>();
        var current = IPAddress.Parse("203.0.113.50");
        cache.Override = host => host == "cafe.example.net" ? [current] : [];
        await RestrictAsync(false, "cafe.example.net", "2001:db8:12:34::/64");

        Assert.True((await ScanAsync(api.From("203.0.113.50"))).IsSuccessStatusCode);
        Assert.True((await ScanAsync(api.From("2001:db8:12:34:1:2:3:4"))).IsSuccessStatusCode);
        await AssertBlockedAsync(await ScanAsync(api.From("2001:db8:12:35::1")));

        // The provider hands the restaurant a new address: once the name
        // points at it (and the cache expires), the old one stops working.
        current = IPAddress.Parse("203.0.113.51");
        cache.Clear();
        await AssertBlockedAsync(await ScanAsync(api.From("203.0.113.50")));
        Assert.True((await ScanAsync(api.From("203.0.113.51"))).IsSuccessStatusCode);
    }

    // ---------------------------------------------------- unit checks

    [Fact]
    public async Task Behind_the_deployed_proxy_a_forged_forwarded_address_never_wins()
    {
        // What ASPNETCORE_FORWARDEDHEADERS_ENABLED=true (the Dockerfile) sets
        // up: X-Forwarded-For from any proxy, and only its last hop, which
        // the proxy itself appends.
        var options = new ForwardedHeadersOptions
        {
            ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
        };
        options.KnownIPNetworks.Clear();
        options.KnownProxies.Clear();
        IPAddress? seen = null;
        var middleware = new ForwardedHeadersMiddleware(context =>
        {
            seen = context.Connection.RemoteIpAddress;
            return Task.CompletedTask;
        }, NullLoggerFactory.Instance, Microsoft.Extensions.Options.Options.Create(options));

        // A phone on mobile data claims the restaurant's address; the
        // platform's proxy appends the address it really came from.
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = IPAddress.Parse("10.1.2.3");
        context.Request.Headers["X-Forwarded-For"] = $"{Restaurant}, {MobileData}";
        await middleware.Invoke(context);

        Assert.Equal(IPAddress.Parse(MobileData), seen);
    }

    [Fact]
    public void The_address_comes_from_the_configured_source_only()
    {
        static IPAddress? Seen(NetworkOptions options, Action<HttpContext> setup)
        {
            var context = new DefaultHttpContext();
            setup(context);
            var service = new NetworkAccessService(null!, null!, new HttpContextAccessor { HttpContext = context },
                options, null!, null!, null!, TimeProvider.System, NullLogger<NetworkAccessService>.Instance);
            return service.ClientAddress();
        }

        var remote = new NetworkOptions();
        Assert.Equal(IPAddress.Parse("203.0.113.9"), Seen(remote, c =>
        {
            c.Connection.RemoteIpAddress = IPAddress.Parse("::ffff:203.0.113.9");
            c.Request.Headers["CF-Connecting-IP"] = Restaurant;
        }));

        var header = new NetworkOptions { ClientIpSource = "Header", ClientIpHeader = "CF-Connecting-IP" };
        Assert.Equal(IPAddress.Parse(Restaurant), Seen(header, c => c.Request.Headers["CF-Connecting-IP"] = Restaurant));
        // Missing, several values, or a list: nothing is trusted.
        Assert.Null(Seen(header, _ => { }));
        Assert.Null(Seen(header, c => c.Request.Headers["CF-Connecting-IP"] = $"{MobileData}, {Restaurant}"));
        Assert.Null(Seen(header, c => c.Request.Headers.Append("CF-Connecting-IP", new[] { MobileData, Restaurant })));
        Assert.Null(Seen(new NetworkOptions { ClientIpSource = "Header" }, c =>
            c.Request.Headers["CF-Connecting-IP"] = Restaurant));
    }
}
