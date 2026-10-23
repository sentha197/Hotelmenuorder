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

public sealed record PricedLine(
    MenuItem Item,
    int Quantity,
    string? PortionId,
    SpiceLevel? Spice,
    List<string> AddOnIds,
    long UnitPrice,
    List<string> Options)
{
    public long LineTotal => UnitPrice * Quantity;
}

public static class Pricing
{
    public const int MaxQuantity = 20;
    public const int MaxInstructions = 200;

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

    public static string NormalizeCode(string code) => code.Trim().ToUpperInvariant();

    /// Prices one requested line from the server's own menu. Throws
    /// `itemsUnavailable` for unknown or unorderable dishes and
    /// `invalidOptions` for options the dish does not have.
    public static PricedLine PriceLine(OrderLineRequest request, IReadOnlyDictionary<string, MenuItem> menu)
    {
        if (!menu.TryGetValue(request.ItemId ?? "", out var item) || !item.IsOrderable)
        {
            throw ApiException.Conflict("itemsUnavailable",
                "Some dishes in your cart are no longer available. Please review your cart.");
        }
        if (request.Quantity < 1 || request.Quantity > MaxQuantity)
        {
            throw ApiException.Validation("quantity", $"Quantity must be between 1 and {MaxQuantity}.");
        }
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
        return new PricedLine(item, request.Quantity, portion?.Id, spice, addOnIds, unitPrice, labels);
    }

    private static ApiException InvalidOptions(MenuItem item) =>
        ApiException.Conflict("invalidOptions",
            $"The options chosen for {item.Name} are no longer available. Please choose again.");
}
