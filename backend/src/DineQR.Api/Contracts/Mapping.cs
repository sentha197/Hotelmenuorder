using DineQR.Api.Data;
using DineQR.Api.Domain;

namespace DineQR.Api.Contracts;

public static class Mapping
{
    private static string N<T>(T value) where T : struct, Enum => EnumNames.ToName(value);

    public static CategoryDto ToDto(this MenuCategory c) =>
        new(c.Id, c.Label, c.CoverImage, c.SortOrder, c.IsActive);

    public static MenuItemDto ToDto(this MenuItem i) => new()
    {
        Id = i.Id,
        Name = i.Name,
        Category = i.CategoryId,
        Description = i.Description,
        Short = i.ShortDescription,
        Price = i.PricePaise,
        Image = i.Image,
        Gallery = i.Gallery.Count == 0 ? null : i.Gallery,
        Veg = i.IsVeg,
        Rating = i.Rating,
        Reviews = i.ReviewCount,
        Popular = i.IsPopular,
        Special = i.IsChefSpecial,
        Featured = i.IsFeatured,
        Spicy = i.HasSpiceLevel,
        DefaultSpice = N(i.DefaultSpice),
        Portions = i.Portions.Count == 0
            ? null
            : [.. i.Portions.OrderBy(p => p.SortOrder).Select(p => new PortionDto(
                p.Id, p.Label, p.ExtraPricePaise == 0 ? null : p.ExtraPricePaise, p.Detail))],
        AddOns = i.AddOns.Count == 0
            ? null
            : [.. i.AddOns.OrderBy(a => a.SortOrder).Select(a => new AddOnDto(a.Id, a.Name, a.PricePaise))],
        Prep = i.PrepMinutes,
        Available = i.IsAvailable,
        Archived = i.IsArchived,
    };

    /// [staff]: include the usage limit and count.
    public static OfferDto ToDto(this DiscountOffer o, bool staff = false) => new(
        o.Code, o.Title, N(o.Type), o.Value,
        o.MinSubtotalPaise == 0 ? null : o.MinSubtotalPaise, o.MaxDiscountPaise, o.IsActive,
        o.StartsOn, o.EndsOn,
        staff ? o.UsageLimit : null,
        staff ? o.UsedCount : null);

    public static SettingsDto ToDto(this RestaurantSettings s, IEnumerable<DiscountOffer> offers,
        bool staff = false) => new(
        s.Name, s.Phone, s.Email, s.Address, s.TaxRegistration, s.TaxName,
        s.TaxRateBasisPoints, s.ServiceChargeBasisPoints, s.UtcOffsetMinutes,
        s.AllowPartialPayments, [.. s.OnlineMethods], s.ReceiptFooter, s.ShowSoldOutDishes,
        s.AutoUnavailableWhenOutOfStock, s.PrepBufferMinutes,
        [.. offers.OrderBy(o => o.SortOrder).ThenBy(o => o.Code).Select(o => o.ToDto(staff))],
        Currency: s.Currency,
        Takeaway: s.TakeawayOrdersEnabled,
        Parcel: s.TakeawayOrdersEnabled,
        PaymentMode: N(s.PaymentMode),
        Wifi: new DineInWifiDto(s.WifiRestrictionEnabled, s.WifiSsid, s.WifiRestrictTakeaway));

    public static TableDto ToDto(this RestaurantTable t) =>
        new(t.Number, t.Seats, t.Area, t.IsActive, t.AssignedStaffId?.ToString());

    public static StaffDto ToDto(this User u) => new(
        u.Id.ToString(), u.FullName, u.Email, N(u.Role), u.IsActive, u.CreatedAt, u.LastLoginAt,
        [.. RolePermissions.For(u).Select(p => N(p))],
        u.Role != StaffRole.Owner && u.CustomPermissions != null,
        u.Role == StaffRole.Custom ? u.RoleTitle : null);

    public static OrderLineDto ToDto(this OrderLine l) => new(
        l.ItemId, l.Name, l.Image, l.IsVeg, l.UnitPricePaise, l.Quantity, l.Options,
        l.CategoryId, l.CategoryName,
        l.ComboId,
        l.ComboId == null ? null : [.. l.ComboItems.Select(p => new ComboPartDto(p.ItemId, p.Name, p.Quantity))],
        l.DiscountPaise == 0 ? null : l.DiscountPaise,
        l.DiscountPaise == 0 ? null : l.DiscountLabel,
        l.DiscountPaise == 0 ? null : l.PromotionId);

    /// Null (not sent) when there is no itemised discount.
    private static List<DiscountLineDto>? ToDto(List<DiscountLine> discounts) =>
        discounts.Count == 0 ? null : [.. discounts.Select(d => new DiscountLineDto(d.Kind, d.Label, d.Amount, d.Ref))];

    public static PromotionItemDto ToDto(this PromotionItem i) => new(i.ItemId, i.Quantity);

    /// [staff]: include the usage limit and count.
    public static PromotionDto ToDto(this Promotion p, bool staff) => new(
        p.Id, N(p.Kind), p.Title, p.Description, p.Image, p.StartsOn, p.EndsOn, p.IsActive,
        [.. p.Items.OrderBy(i => i.SortOrder).Select(i => i.ToDto())],
        p.Kind == PromotionKind.Special ? N(p.DiscountType) : null,
        p.Kind == PromotionKind.Special ? p.DiscountValue : null,
        p.Kind == PromotionKind.Combo ? p.ComboPricePaise : null,
        staff ? p.UsageLimit : null,
        staff ? p.UsedCount : null,
        p.SortOrder);

    public static OrderDto ToDto(this Order o) => new(
        o.Id,
        o.TableNumber,
        N(OrderTables.TypeOf(o.TableNumber)),
        o.CreatedAt,
        [.. o.Lines.OrderBy(l => l.LineNo).Select(l => l.ToDto())],
        o.SubtotalPaise,
        o.DiscountPaise,
        o.DiscountLabel,
        o.ServiceChargePaise,
        o.ServiceChargeBasisPoints,
        o.TaxPaise,
        o.TotalPaise,
        o.TaxRateBasisPoints,
        o.TaxName,
        o.SpecialInstructions,
        N(o.Status),
        // Latest time each status was reached.
        o.History
            .GroupBy(h => h.Status)
            .ToDictionary(g => N(g.Key), g => g.Max(h => h.At)),
        o.EstimatedReadyAt,
        o.FeedbackRating is { } rating
            ? new FeedbackDto(rating, o.FeedbackComment ?? "", o.FeedbackAt ?? o.CreatedAt)
            : null,
        N(o.Source),
        o.CancelReason,
        o.Invoice?.Id,
        ToDto(o.Discounts));

    public static PaymentDto ToDto(this Payment p) => new(
        p.Id, p.InvoiceId, p.OrderId, p.AmountPaise, N(p.Method), N(p.Status), p.Provider,
        p.CreatedAt, p.UpdatedAt, p.IdempotencyKey, p.Reference, p.FailureReason, p.IsSimulated,
        p.RecordedByName, p.Currency, N(p.IsSimulated ? PaymentMode.Demo : PaymentMode.Live), p.MethodDetail,
        p.ClaimedAt);

    public static RefundDto ToDto(this Refund r) => new(
        r.Id, r.InvoiceId, r.PaymentId, r.AmountPaise, r.Reason, N(r.Status), r.CreatedAt,
        r.ProcessedByName, r.Reference, r.IsSimulated);

    public static InvoiceDto ToDto(this Invoice i) => new(
        i.Id,
        i.BillNumber,
        i.OrderId,
        i.TableNumber,
        N(OrderTables.TypeOf(i.TableNumber)),
        i.CreatedAt,
        [.. i.Order.Lines.OrderBy(l => l.LineNo).Select(l => l.ToDto())],
        new AmountsDto(i.SubtotalPaise, i.DiscountPaise, i.DiscountLabel, i.ServiceChargePaise,
            i.ServiceChargeBasisPoints, i.TaxPaise, i.TotalPaise, i.TaxRateBasisPoints, i.TaxName,
            // The bill copies its order's pricing, so the order's breakdown is its own.
            ToDto(i.Order.Discounts)),
        new RestaurantSnapshotDto(i.RestaurantName, i.RestaurantPhone, i.RestaurantEmail,
            i.RestaurantAddress, i.RestaurantTaxRegistration, i.ReceiptFooter),
        [.. i.Payments.OrderBy(p => p.CreatedAt).Select(p => p.ToDto())],
        [.. i.Refunds.OrderBy(r => r.CreatedAt).Select(r => r.ToDto())],
        i.IsVoid,
        i.VoidReason,
        StatusOf(i),
        i.AmountPaidPaise,
        i.OutstandingPaise,
        i.PayableNowPaise,
        // Shown only while there is something to collect at the counter.
        i.CounterRequest is { } kind && i.PayableNowPaise > 0
            ? new CounterRequestDto(N(kind),
                Math.Min(i.CounterRequestAmountPaise ?? i.PayableNowPaise, i.PayableNowPaise),
                i.CounterRequestedAt ?? i.UpdatedAt)
            : null);

    /// Same rules as the app's Invoice.status: only payment and refund
    /// records decide it.
    public static string StatusOf(Invoice i)
    {
        var paid = i.AmountPaidPaise;
        var refunded = i.AmountRefundedPaise;
        if (i.IsVoid && paid == 0) return "voided";
        if (paid > 0 && refunded >= paid) return "refunded";
        if (refunded > 0) return "partiallyRefunded";
        if (i.Payments.Any(p => p.Status == PaymentStatus.Pending)) return "pending";
        if (i.OutstandingPaise == 0) return "paid";
        if (paid > 0) return "partiallyPaid";
        var last = i.Payments.OrderByDescending(p => p.CreatedAt).FirstOrDefault();
        return last?.Status == PaymentStatus.Failed ? "failed" : "unpaid";
    }

    public static AuditDto ToDto(this AuditLog a) => new(
        a.Id.ToString(), a.At, a.ActorId?.ToString() ?? "system", a.ActorName, a.ActorRole,
        a.Action, a.Summary, a.TargetId);

    public static InventoryItemDto ToDto(this InventoryItem i) => new(
        i.Id, i.Name, i.Unit, i.Quantity, i.ReorderLevel, i.UpdatedAt, i.Supplier, i.LinkedDishIds);

    public static StockMovementDto ToDto(this StockMovement m) => new(
        m.Id.ToString(), m.ItemId, m.Change, m.Balance, m.Reason, m.At, m.ByName);
}
