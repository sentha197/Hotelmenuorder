using System.Text.RegularExpressions;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

public sealed partial class AuthService(
    AppDbContext db,
    TokenService tokens,
    JwtOptions options,
    IPasswordHasher<User> hasher,
    AuditTrail audit,
    NetworkAccessService network,
    TimeProvider clock)
{
    public const int MaxFailedAttempts = 5;
    public static readonly TimeSpan Lockout = TimeSpan.FromMinutes(1);

    // Hash used when the email is unknown, so timing does not reveal which
    // emails exist.
    private static readonly string TimingGuardHash =
        new PasswordHasher<User>().HashPassword(new User(), "timing-guard-password");

    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    public static string NormalizeEmail(string? email) => (email ?? "").Trim().ToLowerInvariant();

    /// Generic errors throughout, so responses never reveal which emails
    /// exist.
    public async Task<AuthResponse> LoginAsync(LoginRequest request, CancellationToken ct)
    {
        var email = NormalizeEmail(request.Email);
        if (email.Length == 0 || string.IsNullOrEmpty(request.Password))
        {
            throw ApiException.BadRequest("invalidInput", "Enter your email and password.");
        }
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email, ct);
        var now = Now;
        if (user?.LockedUntil is { } until && until > now)
        {
            throw new ApiException(StatusCodes.Status429TooManyRequests, "lockedOut",
                "Too many attempts. Try again in a minute.");
        }
        var result = hasher.VerifyHashedPassword(user ?? new User(), user?.PasswordHash ?? TimingGuardHash,
            request.Password);
        if (user == null || result == PasswordVerificationResult.Failed)
        {
            if (user != null)
            {
                user.FailedLoginCount++;
                if (user.FailedLoginCount >= MaxFailedAttempts)
                {
                    user.FailedLoginCount = 0;
                    user.LockedUntil = now + Lockout;
                    audit.Record(null, "auth.locked", $"Sign-in locked after repeated failures for {email}",
                        user.Id.ToString());
                }
                await db.SaveChangesAsync(ct);
                if (user.LockedUntil > now)
                {
                    throw new ApiException(StatusCodes.Status429TooManyRequests, "lockedOut",
                        "Too many attempts. Try again in a minute.");
                }
            }
            throw ApiException.Unauthorized("invalidCredentials", "Incorrect email or password.");
        }
        if (!user.IsActive)
        {
            throw ApiException.Forbidden("This account has been deactivated. Contact the restaurant owner.");
        }
        if (result == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.PasswordHash = hasher.HashPassword(user, request.Password);
        }
        user.FailedLoginCount = 0;
        user.LockedUntil = null;
        user.LastLoginAt = now;
        user.UpdatedAt = now;

        var session = Guid.NewGuid();
        var (refresh, hash) = TokenService.NewRefreshToken();
        var sessionEnds = now.AddHours(options.SessionHours);
        db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            SessionId = session,
            TokenHash = hash,
            CreatedAt = now,
            ExpiresAt = sessionEnds,
            SessionExpiresAt = sessionEnds,
        });
        audit.Record(user, "auth.sign_in", "Signed in", user.Id.ToString());
        await db.SaveChangesAsync(ct);

        var (access, accessExpires) = tokens.StaffAccessToken(user, session);
        return new AuthResponse(access, accessExpires, refresh, sessionEnds, user.ToDto());
    }

    /// Rotates the refresh token. Presenting a token that was already used
    /// ends the whole session (it may have been stolen).
    public async Task<AuthResponse> RefreshAsync(RefreshRequest request, CancellationToken ct)
    {
        var hash = TokenService.Hash(request.RefreshToken ?? "");
        var token = await db.RefreshTokens.Include(t => t.User)
            .FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        var now = Now;
        if (token == null)
        {
            throw ApiException.Unauthorized("sessionEnded", "Your session has ended. Please sign in again.");
        }
        if (token.RevokedAt != null)
        {
            await RevokeSessionAsync(token.SessionId, ct);
            throw ApiException.Unauthorized("sessionEnded", "Your session has ended. Please sign in again.");
        }
        if (token.ExpiresAt <= now || token.SessionExpiresAt <= now)
        {
            throw ApiException.Unauthorized("sessionExpired", "Your session expired. Please sign in again.");
        }
        if (!token.User.IsActive)
        {
            await RevokeSessionAsync(token.SessionId, ct);
            throw ApiException.Unauthorized("inactive", "Your account was deactivated.");
        }
        token.RevokedAt = now;
        var (refresh, newHash) = TokenService.NewRefreshToken();
        db.RefreshTokens.Add(new RefreshToken
        {
            UserId = token.UserId,
            SessionId = token.SessionId,
            TokenHash = newHash,
            CreatedAt = now,
            ExpiresAt = token.SessionExpiresAt,
            SessionExpiresAt = token.SessionExpiresAt,
        });
        await db.SaveChangesAsync(ct);
        var (access, accessExpires) = tokens.StaffAccessToken(token.User, token.SessionId);
        return new AuthResponse(access, accessExpires, refresh, token.SessionExpiresAt, token.User.ToDto());
    }

    /// Ends the session of [refreshToken] (or of the access token's session).
    public async Task LogoutAsync(string? refreshToken, Guid? accessSession, User? actor, CancellationToken ct)
    {
        Guid? session = accessSession;
        if (!string.IsNullOrEmpty(refreshToken))
        {
            var hash = TokenService.Hash(refreshToken);
            session = await db.RefreshTokens.Where(t => t.TokenHash == hash)
                .Select(t => (Guid?)t.SessionId).FirstOrDefaultAsync(ct) ?? session;
        }
        if (session is { } id) await RevokeSessionAsync(id, ct);
        if (actor != null)
        {
            audit.Record(actor, "auth.sign_out", "Signed out", actor.Id.ToString());
            await db.SaveChangesAsync(ct);
        }
    }

    private async Task RevokeSessionAsync(Guid session, CancellationToken ct)
    {
        var now = Now;
        await db.RefreshTokens
            .Where(t => t.SessionId == session && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);
    }

    public async Task ChangeOwnPasswordAsync(User actor, ChangeOwnPasswordRequest request, CancellationToken ct)
    {
        var user = await db.Users.SingleAsync(u => u.Id == actor.Id, ct);
        if (hasher.VerifyHashedPassword(user, user.PasswordHash, request.CurrentPassword ?? "")
            == PasswordVerificationResult.Failed)
        {
            throw ApiException.BadRequest("invalidCredentials", "Your current password is not correct.");
        }
        StaffRules.ValidateNewPassword(request.NewPassword);
        user.PasswordHash = hasher.HashPassword(user, request.NewPassword);
        user.UpdatedAt = Now;
        audit.Record(actor, "staff.password", "Changed their own password", user.Id.ToString());
        await db.SaveChangesAsync(ct);
    }

    // ------------------------------------------------------------ guests

    [GeneratedRegex(@"^(DINEQR|BITEANDDINE):TABLE:\s*(\d{1,3})$", RegexOptions.IgnoreCase)]
    private static partial Regex TableQr();

    /// The single takeaway QR code, which carries no table. Codes printed
    /// while takeaway was called "parcel" (`DINEQR:PARCEL`, and the older
    /// `BITEANDDINE:PARCEL`) keep working.
    [GeneratedRegex(@"^(DINEQR:(TAKEAWAY|PARCEL)|BITEANDDINE:PARCEL)$", RegexOptions.IgnoreCase)]
    private static partial Regex TakeawayQr();

    /// A scanned table QR becomes a guest session token scoped to that table.
    /// It grants no staff permission. Rescanning the same table with a valid
    /// token keeps the session (and so the guest's order history).
    public async Task<GuestSessionResponse> StartGuestSessionAsync(
        GuestSessionRequest request,
        Guid? currentSession,
        int? currentTable,
        CancellationToken ct)
    {
        var payload = (request.QrPayload ?? "").Trim();
        int number;
        if (TakeawayQr().IsMatch(payload))
        {
            var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
            if (!settings.TakeawayOrdersEnabled)
            {
                throw ApiException.Conflict("takeawayUnavailable",
                    "Takeaway orders are not being taken right now. Please ask a staff member.");
            }
            // A takeaway session is not tied to a table.
            number = OrderTables.Takeaway;
        }
        else
        {
            var match = TableQr().Match(payload);
            if (!match.Success)
            {
                throw ApiException.BadRequest("unrecognized", "This is not a DineQR code.");
            }
            number = int.Parse(match.Groups[2].Value);
            var table = await db.Tables.AsNoTracking().FirstOrDefaultAsync(t => t.Number == number, ct);
            if (table == null)
            {
                throw ApiException.NotFound("This QR code points to a table that does not exist.");
            }
            if (!table.IsActive)
            {
                throw ApiException.Conflict("tableInactive",
                    "This table is not taking orders right now. Please ask a staff member.");
            }
        }
        // With the dine-in Wi-Fi restriction on, a table's session is issued
        // only on the restaurant's own network (403 networkNotAllowed).
        var verified = await network.RequireForNewSessionAsync(number, ct);
        var session = currentSession is { } existing && currentTable == number ? existing : Guid.NewGuid();
        var expires = Now.AddHours(options.GuestSessionHours);
        var (token, _) = tokens.GuestToken(session, number, expires);
        await network.RecordSessionAsync(session, number, expires, verified, ct);
        return new GuestSessionResponse(token, number, expires, EnumNames.ToName(OrderTables.TypeOf(number)));
    }
}

public static class StaffRules
{
    public static void ValidateNewPassword(string? password)
    {
        if (password == null || password.Length < 8)
        {
            throw ApiException.Validation("password", "Use at least 8 characters.");
        }
        if (!password.Any(char.IsLetter) || !password.Any(char.IsDigit))
        {
            throw ApiException.Validation("password", "Use letters and numbers.");
        }
    }
}
