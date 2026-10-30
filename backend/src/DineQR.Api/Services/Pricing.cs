using System.Globalization;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Services;

/// The amounts of one bill (paise), with the formula the apps use:
/// discount (never above the subtotal), then service charge on the
/// discounted amount, then tax on that, each rounded half-up to the paisa.
public sealed record Breakdown(
    long Subtotal,
    long Discount,
    string? DiscountLabel,
    long Service,
    int ServiceRate,
    long Tax,
    int TaxRate,
    string TaxName,
    long Total);

/// One priced order line. A dish line names the dish; a combo line has
/// [ComboId] set and [ItemId] is the combo's id. [UnitPrice] is always the
/// full price (a combo's dishes bought separately); the saving is
/// [Discount], for the whole line.
public sealed record PricedLine(
    string ItemId,
    string Name,
    string Image,
    bool IsVeg,
    string CategoryId,
    string CategoryName,
    int PrepMinutes,
    int Quantity,
    string? PortionId,
    SpiceLevel? Spice,
    List<string> AddOnIds,
    long UnitPrice,
    List<string> Options)
{
    public string? ComboId { get; init; }
    public List<ComboPart> ComboItems { get; init; } = [];
    public long Discount { get; init; }
    public string? PromotionId { get; init; }
    public string? DiscountLabel { get; init; }

    public long LineTotal => UnitPrice * Quantity;
}

/// An order priced with its offers: the lines (with their savings), the
/// bill, what the discount is made of, and the coupon if it took effect.
public sealed record Quote(
    List<PricedLine> Lines,
    Breakdown Bill,
    List<DiscountLine> Discounts,
    DiscountOffer? Coupon);

/// When coupons and promotions can be used (same rules as the app's
/// OfferRules): switched on, within their dates (restaurant days, both
/// ends included) and with uses left.
public static class OfferRules
{
    public const string ComboCategoryId = "combos";
    public const string ComboCategoryName = "Combos";

    /// Today in the restaurant's time zone.
    public static DateOnly Today(RestaurantSettings settings, DateTime utcNow) =>
        DateOnly.FromDateTime(utcNow.AddMinutes(settings.UtcOffsetMinutes));

    public static bool InDates(DateOnly? startsOn, DateOnly? endsOn, DateOnly today) =>
        (startsOn == null || startsOn <= today) && (endsOn == null || today <= endsOn);

    public static bool HasUsesLeft(int? limit, int used) => limit == null || used < limit;

    public static bool IsLive(DiscountOffer offer, DateOnly today) =>
        offer.IsActive && InDates(offer.StartsOn, offer.EndsOn, today) &&
        HasUsesLeft(offer.UsageLimit, offer.UsedCount);

    public static bool IsLive(Promotion promotion, DateOnly today) =>
        promotion.IsActive && InDates(promotion.StartsOn, promotion.EndsOn, today) &&
        HasUsesLeft(promotion.UsageLimit, promotion.UsedCount);

    /// Why a guest cannot use [offer] today, or null when they can.
    public static string? Problem(DiscountOffer offer, DateOnly today)
    {
        if (!offer.IsActive) return "That offer is not available any more. Remove it and try again.";
        if (offer.StartsOn is { } start && today < start)
        {
            return $"Offer {offer.Code} starts on {Day(start)}. Remove it and try again.";
        }
        if (offer.EndsOn is { } end && today > end)
        {
            return $"Offer {offer.Code} ended on {Day(end)}. Remove it and try again.";
        }
        if (!HasUsesLeft(offer.UsageLimit, offer.UsedCount))
        {
            return $"Offer {offer.Code} has been fully used. Remove it and try again.";
        }
        return null;
    }

    /// `1 Nov 2026`
    public static string Day(DateOnly day) => day.ToString("d MMM yyyy", CultureInfo.InvariantCulture);
}

public static class Pricing
{
    public const int MaxQuantity = 20;
    public const int MaxInstructions = 200;

    /// The order's single discount label when it has several savings.
    public const string CombinedLabel = "Offers & savings";

    /// [paise] × [basisPoints] / 10000, rounded half-up (away from zero).
    public static long ApplyRate(long paise, int basisPoints)
    {
        var scaled = paise * basisPoints;
        return scaled >= 0 ? (scaled + 5000) / 10000 : -((-scaled + 5000) / 10000);
    }

    public static Breakdown Compute(
        long subtotal,
        RestaurantSettings settings,
        long discount = 0,
        string? discountLabel = null)
    {
        var applied = discount <= 0 ? 0 : Math.Min(discount, subtotal);
        var afterDiscount = subtotal - applied;
        var service = ApplyRate(afterDiscount, settings.ServiceChargeBasisPoints);
        var taxable = afterDiscount + service;
        var tax = ApplyRate(taxable, settings.TaxRateBasisPoints);
        return new Breakdown(
            subtotal,
            applied,
            applied == 0 ? null : discountLabel,
            service,
            settings.ServiceChargeBasisPoints,
            tax,
            settings.TaxRateBasisPoints,
            settings.TaxName,
            taxable + tax);
    }

    /// The discount an offer gives on [subtotal]: zero when inactive or
    /// below the minimum, capped, and never above the subtotal.
    public static long DiscountFor(DiscountOffer offer, long subtotal)
    {
        if (!offer.IsActive || subtotal < offer.MinSubtotalPaise) return 0;
        var amount = offer.Type == DiscountType.Percent ? ApplyRate(subtotal, offer.Value) : offer.Value;
        if (offer.MaxDiscountPaise is { } cap && amount > cap) amount = cap;
        return Math.Min(amount, subtotal);
    }

    /// What a special offer takes off one unit costing [unitPrice]: never
    /// more than the unit itself.
    public static long UnitDiscount(Promotion special, long unitPrice)
    {
        var amount = special.DiscountType == DiscountType.Percent
            ? ApplyRate(unitPrice, special.DiscountValue)
            : special.DiscountValue;
        return Math.Clamp(amount, 0, unitPrice);
    }

    /// What one of [item] costs as a combo includes it: its default portion,
    /// no add-ons.
    public static long DefaultUnitPrice(MenuItem item) =>
        item.PricePaise + (item.Portions.OrderBy(p => p.SortOrder).FirstOrDefault()?.ExtraPricePaise ?? 0);

    /// What a combo's dishes cost separately (one combo), or null when one
    /// of them is missing from [menu].
    public static long? ComboOriginalPrice(Promotion combo, IReadOnlyDictionary<string, MenuItem> menu)
    {
        long total = 0;
        foreach (var part in combo.Items)
        {
            if (!menu.TryGetValue(part.ItemId, out var item)) return null;
            total += DefaultUnitPrice(item) * part.Quantity;
        }
        return total;
    }

    /// "2 × Butter Naan", or just the name for one.
    public static string PartLabel(int quantity, string name) => quantity > 1 ? $"{quantity} × {name}" : name;

    public static string NormalizeCode(string code) => code.Trim().ToUpperInvariant();

    /// Prices one requested line: a dish from the server's own menu, or a
    /// combo. Throws `itemsUnavailable` for unknown or unorderable dishes,
    /// `invalidOptions` for options the dish does not have, and
    /// `offerUnavailable` for a combo that cannot be ordered today.
    public static PricedLine PriceLine(
        OrderLineRequest request,
        IReadOnlyDictionary<string, MenuItem> menu,
        IReadOnlyDictionary<string, Promotion>? combos = null,
        DateOnly? today = null)
    {
        if (!string.IsNullOrEmpty(request.ComboId))
        {
            return PriceCombo(request, menu, combos ?? new Dictionary<string, Promotion>(),
                today ?? DateOnly.MinValue);
        }
        if (!menu.TryGetValue(request.ItemId ?? "", out var item) || !item.IsOrderable)
        {
            throw ApiException.Conflict("itemsUnavailable",
                "Some dishes in your cart are no longer available. Please review your cart.");
        }
        CheckQuantity(request.Quantity);
        var options = request.Options;

        SpiceLevel? spice = null;
        if (item.HasSpiceLevel)
        {
            spice = item.DefaultSpice;
            if (!string.IsNullOrEmpty(options?.Spice))
            {
                if (!EnumNames.TryParse<SpiceLevel>(options.Spice, out var chosen)) throw InvalidOptions(item);
                spice = chosen;
            }
        }

        var portions = item.Portions.OrderBy(p => p.SortOrder).ToList();
        MenuItemPortion? portion = null;
        if (portions.Count > 0)
        {
            portion = string.IsNullOrEmpty(options?.Portion)
                ? portions[0]
                : portions.FirstOrDefault(p => p.Id == options.Portion) ?? throw InvalidOptions(item);
        }

        var addOnIds = (options?.AddOns ?? []).Distinct().Order(StringComparer.Ordinal).ToList();
        var addOns = new List<MenuItemAddOn>();
        foreach (var id in addOnIds)
        {
            addOns.Add(item.AddOns.FirstOrDefault(a => a.Id == id) ?? throw InvalidOptions(item));
        }

        var unitPrice = item.PricePaise + (portion?.ExtraPricePaise ?? 0) + addOns.Sum(a => a.PricePaise);
        // Same labels as the app's DishCustomization.describe.
        var labels = new List<string>();
        if (spice is { } level) labels.Add($"Spice: {level}");
        if (portion != null && portions.Count > 1) labels.Add(portion.Label);
        labels.AddRange(addOns.Select(a => a.Name));
        return new PricedLine(item.Id, item.Name, item.Image, item.IsVeg, item.CategoryId, item.Category.Label,
            item.PrepMinutes, request.Quantity, portion?.Id, spice, addOnIds, unitPrice, labels);
    }

    /// A combo line: its dishes at their default options, priced at what
    /// they cost separately, with the combo's saving as the line discount
    /// (none if the dishes have since become cheaper than the combo).
    private static PricedLine PriceCombo(
        OrderLineRequest request,
        IReadOnlyDictionary<string, MenuItem> menu,
        IReadOnlyDictionary<string, Promotion> combos,
        DateOnly today)
    {
        if (!combos.TryGetValue(request.ComboId!, out var combo) || combo.Kind != PromotionKind.Combo ||
            !OfferRules.IsLive(combo, today) || combo.ComboPricePaise is not { } comboPrice)
        {
            throw ApiException.Conflict("offerUnavailable",
                "A combo in your cart is not available any more. Please review your cart.");
        }
        CheckQuantity(request.Quantity);
        var parts = new List<ComboPart>();
        var dishes = new List<MenuItem>();
        foreach (var part in combo.Items.OrderBy(p => p.SortOrder))
        {
            if (!menu.TryGetValue(part.ItemId, out var item) || !item.IsOrderable)
            {
                throw ApiException.Conflict("itemsUnavailable",
                    $"A dish in the {combo.Title} combo is no longer available. Please review your cart.");
            }
            parts.Add(new ComboPart(item.Id, item.Name, part.Quantity));
            dishes.Add(item);
        }
        var original = ComboOriginalPrice(combo, menu)!.Value;
        var saving = Math.Max(0, original - comboPrice);
        var image = combo.Image.Length > 0 ? combo.Image : dishes[0].Image;
        return new PricedLine(combo.Id, combo.Title, image, dishes.All(d => d.IsVeg),
            OfferRules.ComboCategoryId, OfferRules.ComboCategoryName, dishes.Max(d => d.PrepMinutes),
            request.Quantity, null, null, [], original,
            [.. parts.Select(p => PartLabel(p.Quantity, p.Name))])
        {
            ComboId = combo.Id,
            ComboItems = parts,
            Discount = saving * request.Quantity,
            PromotionId = saving > 0 ? combo.Id : null,
            DiscountLabel = saving > 0 ? combo.Title : null,
        };
    }

    /// Applies the offers to priced lines, in this order:
    /// 1. each dish line gets the best live special offer covering its dish
    ///    (one per line; combo lines already carry their own saving);
    /// 2. the coupon applies to what is left, and its minimum spend is
    ///    checked against that;
    /// 3. service charge and tax follow as in [Compute].
    /// [specials] must be live and sorted (sort order, then id): the first
    /// of equally good offers wins. The coupon must be usable today.
    public static Quote Apply(
        IReadOnlyList<PricedLine> lines,
        IReadOnlyList<Promotion> specials,
        RestaurantSettings settings,
        DiscountOffer? coupon)
    {
        var priced = new List<PricedLine>(lines.Count);
        foreach (var line in lines)
        {
            if (line.ComboId != null)
            {
                priced.Add(line);
                continue;
            }
            Promotion? best = null;
            long bestUnit = 0;
            foreach (var special in specials)
            {
                if (special.Kind != PromotionKind.Special || special.Items.All(i => i.ItemId != line.ItemId)) continue;
                var unit = UnitDiscount(special, line.UnitPrice);
                if (unit > bestUnit)
                {
                    best = special;
                    bestUnit = unit;
                }
            }
            priced.Add(best == null
                ? line
                : line with
                {
                    Discount = bestUnit * line.Quantity,
                    PromotionId = best.Id,
                    DiscountLabel = best.Title,
                });
        }

        var discounts = new List<DiscountLine>();
        foreach (var line in priced.Where(l => l.PromotionId != null && l.Discount > 0))
        {
            var index = discounts.FindIndex(d => d.Ref == line.PromotionId);
            if (index >= 0)
            {
                discounts[index] = discounts[index] with { Amount = discounts[index].Amount + line.Discount };
            }
            else
            {
                discounts.Add(new DiscountLine(
                    EnumNames.ToName(line.ComboId != null ? PromotionKind.Combo : PromotionKind.Special),
                    line.DiscountLabel!, line.Discount, line.PromotionId));
            }
        }

        var subtotal = priced.Sum(l => l.LineTotal);
        var itemSavings = priced.Sum(l => l.Discount);
        var couponAmount = coupon == null ? 0 : DiscountFor(coupon, subtotal - itemSavings);
        if (couponAmount > 0) discounts.Add(new DiscountLine("coupon", $"Offer {coupon!.Code}", couponAmount, coupon.Code));

        var label = discounts.Count switch
        {
            0 => null,
            1 => discounts[0].Label,
            _ => CombinedLabel,
        };
        var bill = Compute(subtotal, settings, itemSavings + couponAmount, label);
        return new Quote(priced, bill, discounts, couponAmount > 0 ? coupon : null);
    }

    private static void CheckQuantity(int quantity)
    {
        if (quantity is < 1 or > MaxQuantity)
        {
            throw ApiException.Validation("quantity", $"Quantity must be between 1 and {MaxQuantity}.");
        }
    }

    private static ApiException InvalidOptions(MenuItem item) =>
        ApiException.Conflict("invalidOptions",
            $"The options chosen for {item.Name} are no longer available. Please choose again.");
}
