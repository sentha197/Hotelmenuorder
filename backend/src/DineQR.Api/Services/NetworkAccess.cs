using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// `Network`: how the API learns a caller's public address, which the
/// dine-in Wi-Fi restriction compares with the restaurant's own.
public sealed class NetworkOptions
{
    /// `RemoteAddress` (default): the connection's address as ASP.NET Core
    /// reports it. Behind a reverse proxy that is the last
    /// `X-Forwarded-For` hop, added by the proxy itself, once
    /// `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true` (the Dockerfile sets it);
    /// a client cannot forge that hop, but a chain of several proxies makes
    /// it a proxy's address. `Header`: the single value of [ClientIpHeader],
    /// for an edge that always overwrites it (e.g. Cloudflare's
    /// `CF-Connecting-IP`). Use it only after checking that a value sent by
    /// the client is replaced (see the README).
    public string ClientIpSource { get; set; } = "RemoteAddress";

    public string ClientIpHeader { get; set; } = "";

    /// Allows private and loopback addresses to be authorised. Only for a
    /// local test, where phones reach the API over the LAN: the deployed
    /// API never sees a guest's private address.
    public bool AllowPrivateNetworks { get; set; }

    /// How long a dynamic-DNS hostname's addresses are reused.
    public int HostCacheSeconds { get; set; } = 60;

    public bool UsesHeader => ClientIpSource.Equals("Header", StringComparison.OrdinalIgnoreCase);

    /// `remote address` or `header CF-Connecting-IP`.
    public string SourceLabel => UsesHeader ? $"header {ClientIpHeader.Trim()}" : "remote address";
}

/// The rules for authorised networks: what an entry may be, and whether an
/// address belongs to one.
public static partial class NetworkRules
{
    public const int MaxNetworks = 20;

    /// The narrowest ranges that still fit a restaurant: an IPv4 block up to
    /// 256 addresses, an IPv6 site prefix.
    public const int MinIpv4Prefix = 24;
    public const int MinIpv6Prefix = 48;

    private static readonly IPNetwork CarrierNat = IPNetwork.Parse("100.64.0.0/10");

    private static readonly IPNetwork[] PrivateRanges =
    [
        IPNetwork.Parse("10.0.0.0/8"), IPNetwork.Parse("172.16.0.0/12"), IPNetwork.Parse("192.168.0.0/16"),
        IPNetwork.Parse("127.0.0.0/8"), IPNetwork.Parse("169.254.0.0/16"),
        IPNetwork.Parse("::1/128"), IPNetwork.Parse("fc00::/7"), IPNetwork.Parse("fe80::/10"),
    ];

    private static readonly IPNetwork[] InvalidRanges =
    [
        IPNetwork.Parse("0.0.0.0/8"), IPNetwork.Parse("224.0.0.0/4"), IPNetwork.Parse("240.0.0.0/4"),
        IPNetwork.Parse("::/128"), IPNetwork.Parse("ff00::/8"),
    ];

    [GeneratedRegex(@"^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")]
    private static partial Regex HostPattern();

    public static IPAddress Normalize(IPAddress address) =>
        address.IsIPv4MappedToIPv6 ? address.MapToIPv4() : address;

    /// An entry as stored: `203.0.113.7/32`, `2001:db8::/48` or a lower-case
    /// hostname. Null when it is none of these.
    public static string? Canonical(string? value)
    {
        var text = (value ?? "").Trim().ToLowerInvariant();
        if (text.Length == 0) return null;
        if (IPAddress.TryParse(text, out var address) && !text.Contains('/'))
        {
            address = Normalize(address);
            return new IPNetwork(address, address.AddressFamily == AddressFamily.InterNetwork ? 32 : 128)
                .ToString();
        }
        var slash = text.IndexOf('/');
        if (slash > 0 && IPAddress.TryParse(text[..slash], out var start) &&
            int.TryParse(text[(slash + 1)..], out var prefix))
        {
            start = Normalize(start);
            var max = start.AddressFamily == AddressFamily.InterNetwork ? 32 : 128;
            // `203.0.113.5/29` means the block that address is in.
            return prefix < 0 || prefix > max ? null : new IPNetwork(Mask(start, prefix), prefix).ToString();
        }
        return HostPattern().IsMatch(text) ? text : null;
    }

    public static bool IsHost(string canonical) => !IPNetwork.TryParse(canonical, out _);

    public static bool IsPrivate(IPAddress address) =>
        PrivateRanges.Any(range => range.Contains(Normalize(address)));

    public static bool IsCarrierNat(IPAddress address) => CarrierNat.Contains(Normalize(address));

    /// Why [canonical] cannot be authorised, or null.
    public static string? Problem(string canonical, NetworkOptions options)
    {
        if (IsHost(canonical)) return null;
        var network = IPNetwork.Parse(canonical);
        var start = network.BaseAddress;
        var v4 = start.AddressFamily == AddressFamily.InterNetwork;
        if (InvalidRanges.Any(range => range.Contains(start)))
        {
            return $"{canonical} is not an address a phone can use on the internet.";
        }
        if (v4 ? network.PrefixLength < MinIpv4Prefix : network.PrefixLength < MinIpv6Prefix)
        {
            return $"{canonical} is too wide: a range can be at most a /{MinIpv4Prefix} for IPv4 or a " +
                   $"/{MinIpv6Prefix} for IPv6, so other people's networks are not included.";
        }
        if (IsCarrierNat(start))
        {
            return $"{canonical} is carrier-grade NAT (100.64.0.0/10): the internet provider shares it " +
                   "between many unrelated customers, so it cannot identify the restaurant. Ask the provider " +
                   "for a public (ideally static) address.";
        }
        if (IsPrivate(start) && !options.AllowPrivateNetworks)
        {
            return $"{canonical} is a private address, which the server never sees for a guest on the " +
                   "internet. Use the restaurant's public address: open this screen on the restaurant Wi-Fi " +
                   "and choose \"Add this network\".";
        }
        return null;
    }

    /// What to authorise for a device seen at [address]: the address itself
    /// (IPv4), or its /64 (IPv6, where phones change address within it).
    public static string SuggestedEntry(IPAddress address)
    {
        address = Normalize(address);
        return address.AddressFamily == AddressFamily.InterNetwork
            ? address.ToString()
            : new IPNetwork(Mask(address, 64), 64).ToString();
    }

    private static IPAddress Mask(IPAddress address, int prefix)
    {
        var bytes = address.GetAddressBytes();
        for (var i = 0; i < bytes.Length; i++)
        {
            var bits = Math.Clamp(prefix - i * 8, 0, 8);
            bytes[i] &= (byte)(0xFF << (8 - bits));
        }
        return new IPAddress(bytes);
    }
}

/// The addresses of dynamic-DNS hostnames, re-resolved every
/// `Network:HostCacheSeconds`. A name that does not resolve matches
/// nothing, and (unless private networks are allowed) neither does a
/// private address a name resolves to.
public sealed class HostAddressCache(NetworkOptions options, TimeProvider clock, ILogger<HostAddressCache> logger)
{
    private readonly ConcurrentDictionary<string, (DateTimeOffset Until, IPAddress[] Addresses)> _cache = new();

    /// For tests: answers instead of DNS.
    public Func<string, IPAddress[]>? Override { get; set; }

    public async Task<IPAddress[]> ResolveAsync(string host, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        if (_cache.TryGetValue(host, out var hit) && hit.Until > now) return hit.Addresses;
        IPAddress[] addresses;
        try
        {
            if (Override is { } fake)
            {
                addresses = fake(host);
            }
            else
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(3));
                addresses = await Dns.GetHostAddressesAsync(host, timeout.Token);
            }
        }
        catch (Exception error) when (error is SocketException ||
                                      (error is OperationCanceledException && !ct.IsCancellationRequested))
        {
            logger.LogWarning("Could not resolve authorised network {Host}: {Error}", host, error.Message);
            addresses = [];
        }
        addresses =
        [
            .. addresses.Select(NetworkRules.Normalize)
                .Where(a => options.AllowPrivateNetworks || (!NetworkRules.IsPrivate(a) && !NetworkRules.IsCarrierNat(a))),
        ];
        _cache[host] = (now.AddSeconds(Math.Max(5, options.HostCacheSeconds)), addresses);
        return addresses;
    }

    public void Clear() => _cache.Clear();
}

/// Runs the restaurant-network check before guest dine-in actions (placing
/// an order, starting a payment, asking for the counter, rating).
public sealed class DineInNetworkFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var access = context.HttpContext.RequestServices.GetRequiredService<NetworkAccessService>();
        await access.RequireGuestAccessAsync(context.HttpContext.RequestAborted);
        return await next(context);
    }
}

/// The dine-in Wi-Fi restriction. When it is on, a guest at a table may
/// start a session, order and start payments only from the restaurant's own
/// internet connection: the request's public address (see
/// [NetworkOptions]) must fall in one of the authorised networks. Nothing
/// the app says about its network (Wi-Fi name, connection type, address)
/// is ever used. Staff, payment confirmations and status checks, and
/// gateway webhooks are never affected, so nothing already paid or ordered
/// changes when a guest leaves the network.
public sealed class NetworkAccessService(
    AppDbContext db,
    CurrentCaller caller,
    IHttpContextAccessor http,
    NetworkOptions options,
    HostAddressCache hosts,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock,
    ILogger<NetworkAccessService> logger)
{
    public const string BlockedCode = "networkNotAllowed";

    public const string BlockedMessage =
        "Please connect to the restaurant's Wi-Fi to access the DineQR menu and place your order.";

    /// How often an allowed session's verification time is refreshed.
    private static readonly TimeSpan VerifiedRefresh = TimeSpan.FromMinutes(1);

    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    public static ApiException Blocked() => new(StatusCodes.Status403Forbidden, BlockedCode, BlockedMessage);

    /// The caller's public address, or null when it cannot be known (which
    /// never passes the check).
    public IPAddress? ClientAddress()
    {
        var context = http.HttpContext;
        if (context == null) return null;
        IPAddress? address;
        if (options.UsesHeader)
        {
            var name = options.ClientIpHeader.Trim();
            var values = name.Length == 0 ? default : context.Request.Headers[name];
            // One value, set by the edge. A list means something upstream
            // passed a client's own value along: not trusted.
            var raw = values.Count == 1 ? values[0]!.Trim() : "";
            address = raw.Contains(',') || !IPAddress.TryParse(raw, out var parsed) ? null : parsed;
        }
        else
        {
            address = context.Connection.RemoteIpAddress;
        }
        return address == null ? null : NetworkRules.Normalize(address);
    }

    /// Whether the restriction covers sessions for [table].
    public static bool AppliesTo(RestaurantSettings settings, int table) =>
        settings.WifiRestrictionEnabled &&
        (!OrderTables.IsTakeaway(table) || settings.WifiRestrictTakeaway);

    private Task<RestaurantSettings> SettingsAsync(CancellationToken ct) =>
        db.Settings.AsNoTracking().Include(s => s.AuthorizedNetworks).SingleAsync(ct);

    /// The authorised entry [address] belongs to, or null.
    public async Task<string?> MatchAsync(IPAddress? address, IEnumerable<AuthorizedNetwork> networks,
        CancellationToken ct)
    {
        if (address == null) return null;
        foreach (var network in networks)
        {
            if (IPNetwork.TryParse(network.Value, out var range))
            {
                if (range.Contains(address)) return network.Value;
            }
            else if ((await hosts.ResolveAsync(network.Value, ct)).Contains(address))
            {
                return network.Value;
            }
        }
        return null;
    }

    /// Scanning a code: when the restriction covers [table], the session is
    /// issued only on the restaurant's network. Returns whether it was
    /// checked.
    public async Task<bool> RequireForNewSessionAsync(int table, CancellationToken ct)
    {
        var settings = await SettingsAsync(ct);
        if (!AppliesTo(settings, table)) return false;
        if (await MatchAsync(ClientAddress(), settings.AuthorizedNetworks, ct) == null)
        {
            logger.LogInformation("Refused a guest session for {Table}: not on the restaurant network",
                OrderTables.Label(table));
            throw Blocked();
        }
        return true;
    }

    /// Records a newly issued (or renewed) guest session.
    public Task RecordSessionAsync(Guid session, int table, DateTime expires, bool verified,
        CancellationToken ct)
    {
        var now = Now;
        DateTime? verifiedAt = verified ? now : null;
        int? tableNumber = OrderTables.IsTakeaway(table) ? null : table;
        return db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO guest_sessions (id, settings_id, table_number, status, created_at, expires_at,
                                        verified_at, status_changed_at)
            VALUES ({session}, {RestaurantSettings.SingletonId},
                    (SELECT number FROM restaurant_tables WHERE number = {tableNumber}),
                    'active', {now}, {expires}, {verifiedAt}, {now})
            ON CONFLICT (id) DO UPDATE SET
                expires_at = EXCLUDED.expires_at,
                verified_at = COALESCE(EXCLUDED.verified_at, guest_sessions.verified_at),
                status = 'active',
                status_changed_at = CASE WHEN guest_sessions.status = 'active'
                    THEN guest_sessions.status_changed_at ELSE EXCLUDED.status_changed_at END
            """, ct);
    }

    /// Before a guest dine-in action (and for the app's own check): passes
    /// staff, sessions the restriction does not cover, and guests on the
    /// restaurant's network. Anyone else gets 403 `networkNotAllowed`, and
    /// the session is recorded as blocked until a request passes again.
    public Task RequireGuestAccessAsync(CancellationToken ct) => CheckGuestAsync(ct);

    /// For `POST /guest/network-access`: whether the check applies to this
    /// session (403 `networkNotAllowed` when it applies and fails).
    public async Task<GuestNetworkAccessDto> VerifyGuestAsync(CancellationToken ct)
    {
        if (!caller.IsGuest) throw ApiException.Forbidden("Only a guest session can be checked.");
        return new GuestNetworkAccessDto(await CheckGuestAsync(ct), true);
    }

    /// Returns whether the check applied; throws when it applied and failed.
    private async Task<bool> CheckGuestAsync(CancellationToken ct)
    {
        if (!caller.IsGuest || caller.GuestSessionId is not { } session || caller.GuestTable is not { } table)
        {
            return false;
        }
        var settings = await SettingsAsync(ct);
        if (!AppliesTo(settings, table)) return false;
        var now = Now;
        int? tableNumber = OrderTables.IsTakeaway(table) ? null : table;
        // A session from before sessions were recorded gets a row too; its
        // real expiry is in its token, so this is only an estimate.
        var expires = now.AddHours(8);
        if (await MatchAsync(ClientAddress(), settings.AuthorizedNetworks, ct) != null)
        {
            var refreshBefore = now - VerifiedRefresh;
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO guest_sessions (id, settings_id, table_number, status, created_at, expires_at,
                                            verified_at, status_changed_at)
                VALUES ({session}, {RestaurantSettings.SingletonId},
                        (SELECT number FROM restaurant_tables WHERE number = {tableNumber}),
                        'active', {now}, {expires}, {now}, {now})
                ON CONFLICT (id) DO UPDATE SET
                    verified_at = EXCLUDED.verified_at,
                    status = 'active',
                    status_changed_at = CASE WHEN guest_sessions.status = 'active'
                        THEN guest_sessions.status_changed_at ELSE EXCLUDED.status_changed_at END
                WHERE guest_sessions.status <> 'active' OR guest_sessions.verified_at IS NULL
                   OR guest_sessions.verified_at < {refreshBefore}
                """, ct);
            return true;
        }
        await db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO guest_sessions (id, settings_id, table_number, status, created_at, expires_at,
                                        verified_at, status_changed_at)
            VALUES ({session}, {RestaurantSettings.SingletonId},
                    (SELECT number FROM restaurant_tables WHERE number = {tableNumber}),
                    'blocked', {now}, {expires}, NULL, {now})
            ON CONFLICT (id) DO UPDATE SET status = 'blocked', status_changed_at = EXCLUDED.status_changed_at
            WHERE guest_sessions.status <> 'blocked'
            """, ct);
        throw Blocked();
    }

    // ------------------------------------------------------------ staff

    /// What the server sees for the caller's own request: the address it
    /// would check, whether it is authorised, and the proxy headers that
    /// came with it, so the owner can confirm the deployment reports real
    /// addresses before switching the restriction on.
    public async Task<NetworkCheckDto> CheckCallerAsync(IEnumerable<AuthorizedNetwork>? networks,
        CancellationToken ct)
    {
        var address = ClientAddress();
        networks ??= (await SettingsAsync(ct)).AuthorizedNetworks;
        var matchedBy = await MatchAsync(address, networks, ct);
        var request = http.HttpContext!.Request;
        string? Header(string name) => request.Headers.TryGetValue(name, out var v) ? v.ToString() : null;
        var headers = new Dictionary<string, string>();
        foreach (var name in new[]
                 {
                     "X-Forwarded-For", "X-Original-For", "X-Real-IP", "CF-Connecting-IP", "True-Client-IP",
                     "Forwarded",
                 })
        {
            if (Header(name) is { } value) headers[name] = value;
        }
        // Edge headers that name a single client address and disagree with
        // the one used mean the deployment hides callers behind its proxies.
        var others = new[] { "CF-Connecting-IP", "True-Client-IP", "X-Real-IP" }
            .Select(Header)
            .Where(v => v != null && IPAddress.TryParse(v.Trim(), out _))
            .Select(v => NetworkRules.Normalize(IPAddress.Parse(v!.Trim())))
            .ToList();
        var consistent = address != null && others.All(o => o.Equals(address));
        return new NetworkCheckDto(
            address?.ToString(),
            options.SourceLabel,
            matchedBy != null,
            matchedBy,
            address != null && NetworkRules.IsPrivate(address),
            address != null && NetworkRules.IsCarrierNat(address),
            consistent,
            headers,
            address == null ? null : NetworkRules.SuggestedEntry(address));
    }

    public async Task<NetworkAccessViewDto> ForStaffAsync(CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ManageSettings, ct);
        var settings = await SettingsAsync(ct);
        var networks = new List<AuthorizedNetworkDto>();
        foreach (var network in settings.AuthorizedNetworks.OrderBy(n => n.Id))
        {
            networks.Add(new AuthorizedNetworkDto(network.Value, network.Label,
                NetworkRules.IsHost(network.Value)
                    ? [.. (await hosts.ResolveAsync(network.Value, ct)).Select(a => a.ToString())]
                    : null));
        }
        return new NetworkAccessViewDto(settings.WifiRestrictionEnabled, settings.WifiSsid,
            settings.WifiRestrictTakeaway, networks, await CheckCallerAsync(settings.AuthorizedNetworks, ct));
    }

    /// Saves the restriction and the full list of authorised networks.
    public async Task<NetworkAccessViewDto> SaveAsync(NetworkAccessSettingsDto dto, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        var ssid = (dto.Ssid ?? "").Trim();
        if (ssid.Length > 32 || ssid.Any(char.IsControl))
        {
            throw ApiException.Validation("ssid", "A Wi-Fi name is at most 32 characters.");
        }
        var entries = new List<(string Value, string Label)>();
        foreach (var network in dto.Networks ?? [])
        {
            var canonical = NetworkRules.Canonical(network.Value)
                            ?? throw ApiException.Validation("networks",
                                $"\"{network.Value}\" is not an IP address, an address range (like " +
                                "203.0.113.0/29) or a hostname (like cafe.ddns.net).");
            if (NetworkRules.Problem(canonical, options) is { } problem)
            {
                throw ApiException.Validation("networks", problem);
            }
            var label = (network.Label ?? "").Trim();
            if (label.Length > 60) throw ApiException.Validation("networks", "A label is at most 60 characters.");
            if (entries.Any(e => e.Value == canonical))
            {
                throw ApiException.Validation("networks", $"{canonical} is listed twice.");
            }
            entries.Add((canonical, label));
        }
        if (entries.Count > NetworkRules.MaxNetworks)
        {
            throw ApiException.Validation("networks", $"List at most {NetworkRules.MaxNetworks} networks.");
        }
        if (dto.Enabled && entries.Count == 0)
        {
            throw ApiException.Validation("networks",
                "Add the restaurant's network before switching the restriction on, or no guest could order.");
        }
        if (dto.Enabled && ClientAddress() == null)
        {
            throw ApiException.Conflict("addressUnknown",
                "This server cannot tell which network requests come from (check Network:ClientIpSource), " +
                "so the restriction would block every guest. It stays off.");
        }

        var settings = await db.Settings.Include(s => s.AuthorizedNetworks).SingleAsync(ct);
        var now = Now;
        settings.AuthorizedNetworks.RemoveAll(n => entries.All(e => e.Value != n.Value));
        foreach (var (value, label) in entries)
        {
            var row = settings.AuthorizedNetworks.FirstOrDefault(n => n.Value == value);
            if (row == null)
            {
                settings.AuthorizedNetworks.Add(new AuthorizedNetwork
                {
                    Value = value, Label = label, CreatedAt = now, CreatedByName = staff.FullName,
                });
            }
            else
            {
                row.Label = label;
            }
        }
        var switched = settings.WifiRestrictionEnabled != dto.Enabled;
        settings.WifiRestrictionEnabled = dto.Enabled;
        settings.WifiSsid = ssid;
        settings.WifiRestrictTakeaway = dto.RestrictTakeaway;
        settings.UpdatedAt = now;
        audit.Record(staff, "settings.wifi",
            switched
                ? $"{(dto.Enabled ? "Switched on" : "Switched off")} the dine-in Wi-Fi restriction " +
                  $"({entries.Count} {(entries.Count == 1 ? "network" : "networks")})"
                : $"Updated the dine-in Wi-Fi restriction ({entries.Count} " +
                  $"{(entries.Count == 1 ? "network" : "networks")})");
        await db.SaveChangesAsync(ct);
        hosts.Clear();
        await notifier.SettingsChanged();
        return await ForStaffAsync(ct);
    }
}
