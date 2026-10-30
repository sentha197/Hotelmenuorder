using System.Text.RegularExpressions;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// The Offers section: special offers, combos and coupons (same rules as the
/// app's OffersController). Guests read them with the menu and settings;
/// what an order pays is decided in [Pricing] when it is placed.
public sealed partial class PromotionService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    public const int MaxUsageLimit = 1_000_000;
    public const int MaxComboParts = 10;
    public const int MaxPartQuantity = 10;
    public const int MaxSpecialItems = 100;

    [GeneratedRegex(@"^[a-z0-9][a-z0-9_]{0,39}$")]
    private static partial Regex IdPattern();

    [GeneratedRegex(@"^[A-Z0-9]{3,16}$")]
    private static partial Regex CodePattern();

    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    private static string Money(long paise) => Currencies.Format(paise, Currencies.Default);

    // ------------------------------------------------- special offers, combos

    /// Creates or replaces a special offer or combo. Its usage count is kept.
    public async Task<Promotion> SavePromotionAsync(string id, PromotionDto dto, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageOffers, ct);
        if (!IdPattern().IsMatch(id) || dto.Id != id)
        {
            throw ApiException.Validation("id", "Offer ids use lower-case letters, digits and underscores.");
        }
        if (!EnumNames.TryParse<PromotionKind>(dto.Kind, out var kind))
        {
            throw ApiException.Validation("kind", "Choose a special offer or a combo.");
        }
        var promotion = await db.Promotions.Include(p => p.Items).FirstOrDefaultAsync(p => p.Id == id, ct);
        if (promotion != null && promotion.Kind != kind)
        {
            throw ApiException.Validation("kind", "A special offer cannot become a combo, or the other way round.");
        }
        // A combo line is stored under the combo's id, next to dish ids.
        if (promotion == null && await db.MenuItems.AnyAsync(i => i.Id == id, ct))
        {
            throw ApiException.Validation("id", "That id is already used by a dish.");
        }
        var title = (dto.Title ?? "").Trim();
        if (title.Length is < 2 or > 60) throw ApiException.Validation("title", "Give it a title of 2 to 60 characters.");
        var description = (dto.Description ?? "").Trim();
        if (description.Length > 300)
        {
            throw ApiException.Validation("description", "The description can be at most 300 characters.");
        }
        var image = (dto.Image ?? "").Trim();
        if (image.Length > 0 && !MenuService.IsValidImage(image))
        {
            throw ApiException.Validation("image", "Upload a picture or use an https:// image URL.");
        }
        CheckDates(dto.StartsOn, dto.EndsOn);
        CheckLimit(dto.Limit);

        var parts = dto.Items ?? [];
        if (parts.Select(p => p.ItemId).Distinct().Count() != parts.Count)
        {
            throw ApiException.Validation("items", "Each dish can be listed once.");
        }
        var ids = parts.Select(p => p.ItemId).ToList();
        var dishes = await db.MenuItems.AsNoTracking().Include(i => i.Portions)
            .Where(i => ids.Contains(i.Id) && !i.IsArchived)
            .ToDictionaryAsync(i => i.Id, ct);
        if (dishes.Count != ids.Count)
        {
            throw ApiException.Validation("items", "Some of the chosen dishes are no longer on the menu.");
        }

        var type = DiscountType.Percent;
        var value = 0;
        long? comboPrice = null;
        if (kind == PromotionKind.Special)
        {
            if (parts.Count is < 1 or > MaxSpecialItems)
            {
                throw ApiException.Validation("items", $"Choose 1 to {MaxSpecialItems} dishes for the offer.");
            }
            if (!EnumNames.TryParse(dto.DiscountType, out type))
            {
                throw ApiException.Validation("discountType", "The discount is a percentage or a flat amount.");
            }
            value = dto.Value ?? 0;
            if (type == DiscountType.Percent ? value is < 100 or > 10_000 : value is < 100 or > 10_000_000)
            {
                throw ApiException.Validation("value", type == DiscountType.Percent
                    ? "A percentage discount is 1% to 100%."
                    : "A flat discount is ₹1 to ₹1,00,000.");
            }
            parts = [.. parts.Select(p => p with { Quantity = 1 })];
        }
        else
        {
            if (parts.Count is < 1 or > MaxComboParts || parts.Sum(p => p.Quantity) < 2)
            {
                throw ApiException.Validation("items",
                    $"A combo holds at least two dishes, from 1 to {MaxComboParts} different ones.");
            }
            if (parts.Any(p => p.Quantity is < 1 or > MaxPartQuantity))
            {
                throw ApiException.Validation("items", $"Each dish can be in a combo 1 to {MaxPartQuantity} times.");
            }
            comboPrice = dto.ComboPrice ?? 0;
            if (comboPrice is < 100 or > 10_000_000)
            {
                throw ApiException.Validation("comboPrice", "The combo price must be between ₹1 and ₹1,00,000.");
            }
            var original = parts.Sum(p => Pricing.DefaultUnitPrice(dishes[p.ItemId]) * p.Quantity);
            if (comboPrice >= original)
            {
                throw ApiException.Validation("comboPrice",
                    $"A combo must cost less than its dishes do separately ({Money(original)}).");
            }
        }

        var now = Now;
        var created = promotion == null;
        if (promotion == null)
        {
            promotion = new Promotion
            {
                Id = id,
                Kind = kind,
                CreatedAt = now,
                SortOrder = dto.Sort ?? (await db.Promotions.MaxAsync(p => (int?)p.SortOrder, ct) ?? -1) + 1,
            };
            db.Promotions.Add(promotion);
        }
        else if (dto.Sort is { } sort)
        {
            promotion.SortOrder = sort;
        }
        promotion.Title = title;
        promotion.Description = description;
        promotion.Image = image;
        promotion.StartsOn = dto.StartsOn;
        promotion.EndsOn = dto.EndsOn;
        promotion.IsActive = dto.Active;
        promotion.UsageLimit = dto.Limit;
        promotion.DiscountType = type;
        promotion.DiscountValue = value;
        promotion.ComboPricePaise = comboPrice;
        promotion.UpdatedAt = now;
        // In place: a dish kept in the list keeps its row (same key).
        promotion.Items.RemoveAll(i => parts.All(p => p.ItemId != i.ItemId));
        foreach (var (part, index) in parts.Select((p, i) => (p, i)))
        {
            var row = promotion.Items.FirstOrDefault(i => i.ItemId == part.ItemId);
            if (row == null)
            {
                row = new PromotionItem { PromotionId = id, ItemId = part.ItemId };
                promotion.Items.Add(row);
            }
            row.Quantity = part.Quantity;
            row.SortOrder = index;
        }
        var what = kind == PromotionKind.Combo ? "combo" : "special offer";
        audit.Record(staff, created ? "promotion.create" : "promotion.update",
            $"{(created ? "Created" : "Updated")} {what} \"{title}\"", id);
        await db.SaveChangesAsync(ct);
        await notifier.MenuChanged();
        return promotion;
    }

    public async Task<Promotion> SetPromotionActiveAsync(string id, ActiveRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageOffers, ct);
        var promotion = await db.Promotions.Include(p => p.Items).FirstOrDefaultAsync(p => p.Id == id, ct)
                        ?? throw ApiException.NotFound("Offer not found.");
        if (promotion.IsActive == request.Active) return promotion;
        promotion.IsActive = request.Active;
        promotion.UpdatedAt = Now;
        audit.Record(staff, "promotion.toggle",
            $"{(request.Active ? "Activated" : "Paused")} \"{promotion.Title}\"", id);
        await db.SaveChangesAsync(ct);
        await notifier.MenuChanged();
        return promotion;
    }

    /// Orders that used it keep their own copy of what it gave them.
    public async Task DeletePromotionAsync(string id, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageOffers, ct);
        var promotion = await db.Promotions.FirstOrDefaultAsync(p => p.Id == id, ct)
                        ?? throw ApiException.NotFound("Offer not found.");
        db.Promotions.Remove(promotion);
        audit.Record(staff, "promotion.delete", $"Deleted \"{promotion.Title}\"", id);
        await db.SaveChangesAsync(ct);
        await notifier.MenuChanged();
    }

    // ---------------------------------------------------------------- coupons

    /// Creates or updates the coupon [code]; [dto] may rename it. Its usage
    /// count is kept.
    public async Task<DiscountOffer> SaveCouponAsync(string code, OfferDto dto, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageOffers, ct);
        var newCode = Pricing.NormalizeCode(dto.Code ?? "");
        if (!CodePattern().IsMatch(newCode))
        {
            throw ApiException.Validation("code", "Offer codes are 3 to 16 capital letters or digits.");
        }
        var title = (dto.Title ?? "").Trim();
        if (title.Length is < 1 or > 40) throw ApiException.Validation("title", "Give the offer a title (up to 40 characters).");
        if (!EnumNames.TryParse<DiscountType>(dto.Type, out var type))
        {
            throw ApiException.Validation("type", "Offer type must be percent or flat.");
        }
        if (type == DiscountType.Percent ? dto.Value is < 100 or > 9000 : dto.Value is < 100 or > 10_000_000)
        {
            throw ApiException.Validation("value", type == DiscountType.Percent
                ? "A percentage discount is 1% to 90%."
                : "A flat discount is ₹1 to ₹1,00,000.");
        }
        if ((dto.Min ?? 0) < 0 || dto.Max is < 0) throw ApiException.Validation("min", "Amounts cannot be negative.");
        CheckDates(dto.StartsOn, dto.EndsOn);
        CheckLimit(dto.Limit);

        var original = Pricing.NormalizeCode(code);
        var offer = await db.Offers.FirstOrDefaultAsync(o => o.Code == original, ct);
        if (newCode != original && await db.Offers.AnyAsync(o => o.Code == newCode, ct))
        {
            throw ApiException.Validation("code", $"There is already an offer {newCode}.");
        }
        var created = offer == null;
        if (offer != null && newCode != offer.Code)
        {
            // The code is the key: a rename replaces the row, keeping its count.
            db.Offers.Remove(offer);
            offer = new DiscountOffer { Code = newCode, UsedCount = offer.UsedCount, SortOrder = offer.SortOrder };
            db.Offers.Add(offer);
        }
        else if (offer == null)
        {
            offer = new DiscountOffer
            {
                Code = newCode,
                SortOrder = (await db.Offers.MaxAsync(o => (int?)o.SortOrder, ct) ?? -1) + 1,
            };
            db.Offers.Add(offer);
        }
        offer.Title = title;
        offer.Type = type;
        offer.Value = dto.Value;
        offer.MinSubtotalPaise = dto.Min ?? 0;
        offer.MaxDiscountPaise = dto.Max;
        offer.IsActive = dto.Active;
        offer.StartsOn = dto.StartsOn;
        offer.EndsOn = dto.EndsOn;
        offer.UsageLimit = dto.Limit;
        audit.Record(staff, created ? "offer.create" : "offer.update",
            $"{(created ? "Created" : "Updated")} offer {newCode}", newCode);
        await db.SaveChangesAsync(ct);
        await notifier.SettingsChanged();
        return offer;
    }

    public async Task<DiscountOffer> SetCouponActiveAsync(string code, ActiveRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageOffers, ct);
        var normalized = Pricing.NormalizeCode(code);
        var offer = await db.Offers.FirstOrDefaultAsync(o => o.Code == normalized, ct)
                    ?? throw ApiException.NotFound("Offer not found.");
        if (offer.IsActive == request.Active) return offer;
        offer.IsActive = request.Active;
        audit.Record(staff, "offer.toggle", $"{(request.Active ? "Activated" : "Paused")} offer {offer.Code}",
            offer.Code);
        await db.SaveChangesAsync(ct);
        await notifier.SettingsChanged();
        return offer;
    }

    public async Task DeleteCouponAsync(string code, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageOffers, ct);
        var normalized = Pricing.NormalizeCode(code);
        var offer = await db.Offers.FirstOrDefaultAsync(o => o.Code == normalized, ct)
                    ?? throw ApiException.NotFound("Offer not found.");
        db.Offers.Remove(offer);
        audit.Record(staff, "offer.delete", $"Deleted offer {offer.Code}", offer.Code);
        await db.SaveChangesAsync(ct);
        await notifier.SettingsChanged();
    }

    // ----------------------------------------------------------------- shared

    private static void CheckDates(DateOnly? startsOn, DateOnly? endsOn)
    {
        if (startsOn is { } start && endsOn is { } end && end < start)
        {
            throw ApiException.Validation("endsOn", "The last day cannot be before the first day.");
        }
    }

    private static void CheckLimit(int? limit)
    {
        if (limit is < 1 or > MaxUsageLimit)
        {
            throw ApiException.Validation("limit", "A usage limit is 1 to 10,00,000 orders, or none.");
        }
    }
}
