using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// The rules of the GPS ordering area: distances, what a valid position is,
/// and when a guest is inside.
public static class GeofenceRules
{
    public const int MinRadius = 10;
    public const int MaxRadius = 1000;

    /// The radii offered in the admin app (anything from [MinRadius] to
    /// [MaxRadius] can be saved as a custom radius).
    public static readonly int[] PresetRadii = [20, 30, 50, 100];

    /// A position less precise than this cannot tell inside from outside.
    public const double MaxAccuracy = 100;

    /// At most this much of the device's own uncertainty is given to the
    /// guest: a guest at the edge with a fair reading is not refused, while
    /// a vague reading can never stretch the area much.
    public const double MaxTolerance = 20;

    /// A position older than this is not where the guest is now.
    public static readonly TimeSpan MaxAge = TimeSpan.FromMinutes(2);

    /// Clock difference allowed for a position "from the future".
    public static readonly TimeSpan MaxClockSkew = TimeSpan.FromMinutes(1);

    public const string OutsideCode = "outsideRestaurantArea";
    public const string RequiredCode = "locationRequired";
    public const string InvalidCode = "locationInvalid";
    public const string InaccurateCode = "locationInaccurate";
    public const string StaleCode = "locationStale";
    public const string MockedCode = "mockLocation";

    public const string OutsideMessage =
        "You are outside the restaurant's permitted location. Please move closer to the restaurant to place " +
        "your order.";

    private const double EarthRadius = 6_371_008.8; // metres (mean radius)

    /// The great-circle distance in metres between two points (Haversine).
    public static double Distance(double lat1, double lon1, double lat2, double lon2)
    {
        static double Rad(double degrees) => degrees * Math.PI / 180;
        var dLat = Rad(lat2 - lat1);
        var dLon = Rad(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(Rad(lat1)) * Math.Cos(Rad(lat2)) * Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        return 2 * EarthRadius * Math.Asin(Math.Min(1, Math.Sqrt(a)));
    }

    public static bool IsValidPoint(double? latitude, double? longitude) =>
        latitude is { } lat && longitude is { } lon &&
        double.IsFinite(lat) && double.IsFinite(lon) &&
        lat is >= -90 and <= 90 && lon is >= -180 and <= 180 &&
        // 0,0 is what a broken reading reports, not a restaurant.
        !(lat == 0 && lon == 0);

    /// The distance from the area's centre, after checking that [location]
    /// is a usable, recent, real reading. Throws 403 with the reason.
    public static double Check(RestaurantGeofence area, GuestLocationDto? location, DateTime now)
    {
        if (location?.Latitude == null || location.Longitude == null)
        {
            throw Refuse(RequiredCode,
                "This restaurant takes orders only from guests at the restaurant. Turn on location and allow " +
                "DineQR to use it, then try again.");
        }
        if (!IsValidPoint(location.Latitude, location.Longitude))
        {
            throw Refuse(InvalidCode, "Your location could not be read. Please try again.");
        }
        if (location.Mocked == true)
        {
            throw Refuse(MockedCode,
                "Your phone reports a simulated location. Turn off mock location apps to order.");
        }
        if (location.Accuracy is not { } accuracy || !double.IsFinite(accuracy) || accuracy < 0 ||
            accuracy > MaxAccuracy)
        {
            throw Refuse(InaccurateCode,
                "Your location is not precise enough. Turn on precise location (GPS) and try again, " +
                "ideally near a window or outdoors.");
        }
        if (location.CapturedAt is { } at)
        {
            var captured = at.Kind == DateTimeKind.Unspecified ? DateTime.SpecifyKind(at, DateTimeKind.Utc) : at.ToUniversalTime();
            if (captured < now - MaxAge || captured > now + MaxClockSkew)
            {
                throw Refuse(StaleCode, "Your location is out of date. Please try again.");
            }
        }
        var distance = Distance(area.Latitude, area.Longitude, location.Latitude.Value, location.Longitude.Value);
        if (distance - Math.Min(accuracy, MaxTolerance) > area.RadiusMeters)
        {
            throw Refuse(OutsideCode, OutsideMessage);
        }
        return distance;
    }

    private static ApiException Refuse(string code, string message) =>
        new(StatusCodes.Status403Forbidden, code, message);
}

/// The GPS ordering area (geofence). When it is on, a guest may place an
/// order only with a recent, precise position within the configured radius
/// of the restaurant. The server measures the distance itself: what the app
/// decides is never trusted. Positions are checked and discarded, never
/// stored.
///
/// It is independent of the dine-in Wi-Fi restriction ([NetworkAccessService],
/// which it does not touch): an order must pass both when both are on.
/// Staff are never affected, nor are payments for orders already placed.
public sealed class GeofenceService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    /// The area of the restaurant [settingsId], or null when none was saved.
    private Task<RestaurantGeofence?> AreaAsync(int settingsId, CancellationToken ct) =>
        db.Geofences.AsNoTracking().FirstOrDefaultAsync(g => g.SettingsId == settingsId, ct);

    private static bool Covers(RestaurantGeofence? area, int table) =>
        area is { Enabled: true } && (!OrderTables.IsTakeaway(table) || area.ApplyToTakeaway);

    /// What guests are told (with the public settings).
    public async Task<DineInLocationDto> PublicAsync(CancellationToken ct)
    {
        var area = await AreaAsync(RestaurantSettings.SingletonId, ct);
        return area == null
            ? new DineInLocationDto(false, 0, false)
            : new DineInLocationDto(area.Enabled, area.RadiusMeters, area.ApplyToTakeaway);
    }

    /// The restaurant a guest session belongs to: the one whose QR code was
    /// scanned (recorded when the session started).
    private async Task<(int SettingsId, int Table)> GuestRestaurantAsync(CancellationToken ct)
    {
        if (!caller.IsGuest || caller.GuestSessionId is not { } session || caller.GuestTable is not { } table)
        {
            throw ApiException.Forbidden("Only a guest session can be checked.");
        }
        var settingsId = await db.GuestSessions.AsNoTracking().Where(s => s.Id == session)
            .Select(s => (int?)s.SettingsId).FirstOrDefaultAsync(ct);
        // A session token always has its row (written when it was issued).
        return (settingsId ?? throw ApiException.Unauthorized("sessionExpired",
            "Your ordering session has ended. Scan the QR code again to continue."), table);
    }

    /// Before a guest order (OrderService): throws 403 unless the area is off
    /// for this session or [location] is inside it.
    public async Task RequireGuestLocationAsync(GuestLocationDto? location, CancellationToken ct)
    {
        var (settingsId, table) = await GuestRestaurantAsync(ct);
        var area = await AreaAsync(settingsId, ct);
        if (!Covers(area, table)) return;
        GeofenceRules.Check(area!, location, Now);
    }

    /// `POST /guest/location-check`: the app's own check (on opening, on
    /// resume and before checkout). The order itself is checked again.
    public async Task<GuestLocationCheckDto> CheckGuestAsync(GuestLocationDto? location, CancellationToken ct)
    {
        var (settingsId, table) = await GuestRestaurantAsync(ct);
        var area = await AreaAsync(settingsId, ct);
        if (!Covers(area, table)) return new GuestLocationCheckDto(false, true, area?.RadiusMeters ?? 0, null);
        var distance = GeofenceRules.Check(area!, location, Now);
        return new GuestLocationCheckDto(true, true, area!.RadiusMeters, Math.Round(distance, 1));
    }

    // ------------------------------------------------------------ staff

    public async Task<GeofenceViewDto> ForStaffAsync(CancellationToken ct)
    {
        await caller.RequireStaffAsync(ct);
        return await ViewAsync(ct);
    }

    private async Task<GeofenceViewDto> ViewAsync(CancellationToken ct)
    {
        var name = await db.Settings.AsNoTracking().Where(s => s.Id == RestaurantSettings.SingletonId)
            .Select(s => s.Name).FirstOrDefaultAsync(ct) ?? "";
        var area = await AreaAsync(RestaurantSettings.SingletonId, ct);
        return area == null
            ? new GeofenceViewDto(RestaurantSettings.SingletonId, name, false, false, null, null, 50, false,
                null, null, "")
            : new GeofenceViewDto(area.SettingsId, name, true, area.Enabled, area.Latitude, area.Longitude,
                area.RadiusMeters, area.ApplyToTakeaway, area.CreatedAt, area.UpdatedAt, area.UpdatedByName);
    }

    /// Saves the area (owner and those who manage settings). A location is
    /// required to switch it on.
    public async Task<GeofenceViewDto> SaveAsync(GeofenceSettingsDto dto, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        if (dto.Radius is < GeofenceRules.MinRadius or > GeofenceRules.MaxRadius)
        {
            throw ApiException.Validation("radius",
                $"Choose a radius from {GeofenceRules.MinRadius} to {GeofenceRules.MaxRadius} metres.");
        }
        var hasPoint = dto.Latitude != null || dto.Longitude != null;
        if (hasPoint && !GeofenceRules.IsValidPoint(dto.Latitude, dto.Longitude))
        {
            throw ApiException.Validation("location",
                "Enter a latitude from -90 to 90 and a longitude from -180 to 180 (pick the restaurant on the map).");
        }
        var area = await db.Geofences.FirstOrDefaultAsync(g => g.SettingsId == RestaurantSettings.SingletonId, ct);
        if (!hasPoint && area == null)
        {
            if (dto.Enabled)
            {
                throw ApiException.Validation("location",
                    "Set the restaurant's location before switching the GPS restriction on.");
            }
            throw ApiException.Validation("location", "Set the restaurant's location.");
        }
        var now = Now;
        if (area == null)
        {
            area = new RestaurantGeofence { SettingsId = RestaurantSettings.SingletonId, CreatedAt = now };
            db.Geofences.Add(area);
        }
        if (hasPoint)
        {
            area.Latitude = Math.Round(dto.Latitude!.Value, 7);
            area.Longitude = Math.Round(dto.Longitude!.Value, 7);
        }
        area.RadiusMeters = dto.Radius;
        var switched = area.Enabled != dto.Enabled;
        area.Enabled = dto.Enabled;
        area.ApplyToTakeaway = dto.Takeaway;
        area.UpdatedAt = now;
        area.UpdatedByName = staff.FullName;
        audit.Record(staff, "settings.geofence",
            (switched ? (dto.Enabled ? "Switched the GPS ordering restriction on" : "Switched the GPS ordering restriction off") : "Updated the GPS ordering area") +
            $" ({dto.Radius} m{(dto.Takeaway ? ", takeaway included" : "")})");
        await db.SaveChangesAsync(ct);
        await notifier.SettingsChanged();
        return await ViewAsync(ct);
    }
}
