using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace DineQR.Api.Infrastructure;

public sealed class JwtOptions
{
    public string Issuer { get; set; } = "dineqr-api";
    public string Audience { get; set; } = "dineqr-apps";

    /// At least 32 bytes. Set through user secrets or an environment
    /// variable (`Jwt__SigningKey`), never in source control.
    public string SigningKey { get; set; } = "";
    public int AccessTokenMinutes { get; set; } = 15;

    /// Absolute length of a staff sign-in session.
    public int SessionHours { get; set; } = 8;

    /// How long a guest's table session lasts after scanning.
    public int GuestSessionHours { get; set; } = 4;

    public SymmetricSecurityKey Key()
    {
        if (Encoding.UTF8.GetByteCount(SigningKey) < 32)
        {
            throw new InvalidOperationException(
                "Jwt:SigningKey must be set to at least 32 bytes (user secrets or Jwt__SigningKey).");
        }
        return new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SigningKey));
    }
}

public static class ClaimNames
{
    public const string TokenType = "kind";
    public const string Session = "sid";
    public const string Table = "table";
    public const string Role = "role";
    public const string Staff = "staff";
    public const string Guest = "guest";
}

public sealed class TokenService(JwtOptions options, TimeProvider clock)
{
    public (string Token, DateTime ExpiresAt) StaffAccessToken(User user, Guid sessionId)
    {
        var expires = clock.GetUtcNow().UtcDateTime.AddMinutes(options.AccessTokenMinutes);
        return (Write(expires,
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(ClaimNames.TokenType, ClaimNames.Staff),
            new Claim(ClaimNames.Session, sessionId.ToString()),
            new Claim(ClaimNames.Role, EnumNames.ToName(user.Role))), expires);
    }

    public (string Token, DateTime ExpiresAt) GuestToken(Guid sessionId, int table, DateTime expires) =>
        (Write(expires,
            new Claim(JwtRegisteredClaimNames.Sub, sessionId.ToString()),
            new Claim(ClaimNames.TokenType, ClaimNames.Guest),
            new Claim(ClaimNames.Session, sessionId.ToString()),
            new Claim(ClaimNames.Table, table.ToString())), expires);

    /// A random refresh token and the hash that is stored.
    public static (string Token, string Hash) NewRefreshToken()
    {
        var token = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(48));
        return (token, Hash(token));
    }

    public static string Hash(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    private string Write(DateTime expires, params Claim[] claims)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        return new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = options.Issuer,
            Audience = options.Audience,
            Subject = new ClaimsIdentity(claims),
            NotBefore = now.AddSeconds(-5),
            Expires = expires,
            IssuedAt = now,
            SigningCredentials = new SigningCredentials(options.Key(), SecurityAlgorithms.HmacSha256),
        });
    }

    public TokenValidationParameters ValidationParameters() => new()
    {
        ValidateIssuer = true,
        ValidIssuer = options.Issuer,
        ValidateAudience = true,
        ValidAudience = options.Audience,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = options.Key(),
        ValidateLifetime = true,
        ClockSkew = TimeSpan.FromSeconds(30),
        NameClaimType = JwtRegisteredClaimNames.Sub,
        RoleClaimType = ClaimNames.Role,
    };
}

/// Who is calling: a staff member (loaded fresh from the database, so a
/// role change or deactivation applies at once) or a guest table session.
public sealed class CurrentCaller(IHttpContextAccessor http, AppDbContext db)
{
    private User? _staff;
    private bool _loaded;

    private ClaimsPrincipal? Principal => http.HttpContext?.User;

    public bool IsStaff => Principal?.FindFirstValue(ClaimNames.TokenType) == ClaimNames.Staff;

    public bool IsGuest => Principal?.FindFirstValue(ClaimNames.TokenType) == ClaimNames.Guest;

    public Guid? GuestSessionId =>
        IsGuest && Guid.TryParse(Principal!.FindFirstValue(ClaimNames.Session), out var id) ? id : null;

    public int? GuestTable =>
        IsGuest && int.TryParse(Principal!.FindFirstValue(ClaimNames.Table), out var table) ? table : null;

    public Guid? StaffSessionId =>
        IsStaff && Guid.TryParse(Principal!.FindFirstValue(ClaimNames.Session), out var id) ? id : null;

    /// The signed-in staff member if the account is still active.
    public async Task<User?> StaffAsync(CancellationToken ct = default)
    {
        if (_loaded) return _staff;
        _loaded = true;
        if (!IsStaff ||
            !long.TryParse(Principal!.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id))
        {
            return null;
        }
        _staff = await db.Users.AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == id && u.IsActive, ct);
        return _staff;
    }

    public async Task<User> RequireStaffAsync(CancellationToken ct = default) =>
        await StaffAsync(ct) ?? throw ApiException.Unauthorized(
            "sessionEnded", "Your session has ended. Please sign in again.");

    /// Throws 403 unless the active staff member has [permission].
    public async Task<User> RequireAsync(Permission permission, CancellationToken ct = default)
    {
        var staff = await RequireStaffAsync(ct);
        if (!RolePermissions.Can(staff, permission))
        {
            throw ApiException.Forbidden(
                $"Your role cannot {PermissionLabels.Of(permission)}.");
        }
        return staff;
    }

    public async Task<bool> CanAsync(Permission permission, CancellationToken ct = default)
    {
        var staff = await StaffAsync(ct);
        return staff != null && RolePermissions.Can(staff, permission);
    }
}

public static class PermissionLabels
{
    public static string Of(Permission permission) => permission switch
    {
        Permission.ViewFinancials => "view financial figures",
        Permission.CreateOrders => "create orders",
        Permission.ManageKitchen => "update the kitchen workflow",
        Permission.ServeOrders => "mark orders served",
        Permission.CancelOrders => "cancel orders",
        Permission.ManageMenu => "edit dishes",
        Permission.ManageCategories => "edit categories",
        Permission.ManageTables => "edit tables",
        Permission.CollectPayments => "record payments",
        Permission.ViewPayments => "view payment history",
        Permission.ReconcilePayments => "reconcile payments",
        Permission.IssueRefunds => "issue refunds",
        Permission.ExportReports => "export reports",
        Permission.ManageInventory => "manage inventory",
        Permission.ManageStaff => "manage staff",
        Permission.ManageSettings => "change settings",
        Permission.ViewAuditLog => "view the activity log",
        _ => "do that",
    };
}

/// Policies: `staff` (any active staff member), `guest` (a table session)
/// and `perm:<name>` for each permission.
public static class Policies
{
    public const string Staff = "staff";
    public const string Guest = "guest";

    public static string For(Permission permission) => $"perm:{EnumNames.ToName(permission)}";

    public static void Register(AuthorizationOptions options)
    {
        options.AddPolicy(Staff, p => p.AddRequirements(new StaffRequirement(null)));
        options.AddPolicy(Guest, p => p.RequireClaim(ClaimNames.TokenType, ClaimNames.Guest));
        foreach (var permission in Enum.GetValues<Permission>())
        {
            options.AddPolicy(For(permission), p => p.AddRequirements(new StaffRequirement(permission)));
        }
    }
}

public sealed record StaffRequirement(Permission? Permission) : IAuthorizationRequirement;

public sealed class StaffRequirementHandler : AuthorizationHandler<StaffRequirement>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        StaffRequirement requirement)
    {
        if (context.Resource is not HttpContext http) return;
        var caller = http.RequestServices.GetRequiredService<CurrentCaller>();
        var staff = await caller.StaffAsync(http.RequestAborted);
        if (staff == null) return;
        if (requirement.Permission is { } permission && !RolePermissions.Can(staff, permission))
        {
            return;
        }
        context.Succeed(requirement);
    }
}
