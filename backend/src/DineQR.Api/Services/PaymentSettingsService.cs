using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// The restaurant's UPI payment settings: the owner changes them, staff read
/// them (a cashier needs the UPI ID to check a payment), and a guest with a
/// bill gets the part they need to pay. Only public payee details are kept:
/// never a PIN, a card or any bank credential.
public sealed class PaymentSettingsService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    ImageStorage storage,
    IUpiPaymentVerifier verifier,
    TimeProvider clock)
{
    /// The mode in effect: automatic only while a verifier is really
    /// connected, so a payment is never auto-confirmed by something absent.
    private UpiVerificationMode Effective(RestaurantSettings settings) =>
        settings.UpiVerificationMode == UpiVerificationMode.Automatic && verifier.IsAvailable
            ? UpiVerificationMode.Automatic
            : UpiVerificationMode.Manual;

    private PaymentSettingsDto ToDto(RestaurantSettings s) => new(
        s.UpiEnabled,
        s.UpiId,
        s.UpiPayeeName,
        s.UpiQrImage,
        // What the owner chose; AutomaticVerificationAvailable says whether
        // it can actually run.
        EnumNames.ToName(s.UpiVerificationMode),
        verifier.IsAvailable,
        UpiRules.IsReady(s));

    /// Any signed-in staff member.
    public async Task<PaymentSettingsDto> ForStaffAsync(CancellationToken ct)
    {
        await caller.RequireStaffAsync(ct);
        return ToDto(await db.Settings.AsNoTracking().SingleAsync(ct));
    }

    /// A guest's table session or a staff member. Nothing is revealed while
    /// UPI is switched off or incomplete.
    public async Task<UpiConfigDto> ConfigAsync(CancellationToken ct)
    {
        if (!caller.IsGuest) await caller.RequireStaffAsync(ct);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        if (!UpiRules.IsOffered(settings))
        {
            return new UpiConfigDto(false, "", "", "", EnumNames.ToName(UpiVerificationMode.Manual));
        }
        return new UpiConfigDto(true, settings.UpiId, settings.UpiPayeeName, settings.UpiQrImage,
            EnumNames.ToName(Effective(settings)));
    }

    /// Owner only. Validates everything and saves the settings together, so
    /// guests never see half of a change.
    public async Task<PaymentSettingsDto> SaveAsync(PaymentSettingsRequest dto, HttpRequest request,
        CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        var id = UpiRules.NormalizeId(dto.UpiId);
        var name = UpiRules.NormalizeName(dto.PayeeName);
        if (id.Length > 0 && UpiRules.IdProblem(id) is { } problem)
        {
            throw ApiException.Validation("upiId", problem);
        }
        if (name.Length > 0 && !UpiRules.IsValidName(name))
        {
            throw ApiException.Validation("payeeName", "The name must be 2 to 60 characters.");
        }
        if (dto.Enabled)
        {
            if (id.Length == 0)
            {
                throw ApiException.Validation("upiId", "Enter the restaurant's UPI ID to switch UPI payments on.");
            }
            if (name.Length == 0)
            {
                throw ApiException.Validation("payeeName", "Enter the name guests will see when they pay.");
            }
        }

        var settings = await db.Settings.SingleAsync(ct);
        var mode = settings.UpiVerificationMode;
        if (!string.IsNullOrWhiteSpace(dto.VerificationMode) &&
            !EnumNames.TryParse(dto.VerificationMode, out mode))
        {
            throw ApiException.Validation("verificationMode", "Choose manual or automatic verification.");
        }
        if (mode == UpiVerificationMode.Automatic && !verifier.IsAvailable)
        {
            throw ApiException.Validation("verificationMode",
                "Automatic verification needs a bank or payment provider connected to this server, and none " +
                "is set up. Choose manual verification so a cashier confirms each payment.");
        }

        var requested = (dto.QrImage ?? "").Trim();
        var qr = requested.Length == 0 || requested == settings.UpiQrImage
            ? requested
            : await storage.CanonicalUpiQrUrlAsync(requested, request, ct)
              ?? throw ApiException.Validation("qrImage",
                  "That QR image is no longer available. Upload it again.");

        var changes = new List<string>();
        if (settings.UpiEnabled != dto.Enabled)
        {
            changes.Add(dto.Enabled ? "switched UPI payments on" : "switched UPI payments off");
        }
        if (settings.UpiId != id)
        {
            changes.Add(id.Length == 0 ? "removed the UPI ID"
                : settings.UpiId.Length == 0 ? $"set the UPI ID to {id}"
                : $"changed the UPI ID from {settings.UpiId} to {id}");
        }
        if (settings.UpiPayeeName != name) changes.Add($"set the payee name to \"{name}\"");
        if (settings.UpiQrImage != qr)
        {
            changes.Add(qr.Length == 0 ? "removed the QR image"
                : settings.UpiQrImage.Length == 0 ? "added a QR image"
                : "replaced the QR image");
        }
        if (settings.UpiVerificationMode != mode)
        {
            changes.Add($"set verification to {EnumNames.ToName(mode)}");
        }

        var previousQr = settings.UpiQrImage;
        settings.UpiEnabled = dto.Enabled;
        settings.UpiId = id;
        settings.UpiPayeeName = name;
        settings.UpiQrImage = qr;
        settings.UpiVerificationMode = mode;
        if (changes.Count > 0)
        {
            settings.UpdatedAt = clock.GetUtcNow().UtcDateTime;
            audit.Record(staff, "settings.payments", "Updated UPI payment settings: " + string.Join(", ", changes),
                "upi");
        }
        await db.SaveChangesAsync(ct);
        // The replaced image is no longer referenced; a leftover would be
        // harmless, so this never fails the save.
        if (previousQr.Length > 0 && previousQr != qr) await storage.TryDeleteUpiQrAsync(previousQr, ct);
        if (changes.Count > 0) await notifier.SettingsChanged();
        return ToDto(settings);
    }

    /// Owner only. Stores the image and returns its URL; it takes effect when
    /// the settings are saved with that URL.
    public async Task<UploadedImageDto> UploadQrAsync(IFormFile? file, HttpRequest request, CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ManageSettings, ct);
        return new UploadedImageDto(await storage.SaveUpiQrAsync(file, request, ct));
    }
}
