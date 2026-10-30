using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace DineQR.Api.Services;

public sealed class OrderService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    private IQueryable<Order> Full => db.Orders
        .Include(o => o.Lines)
        .Include(o => o.History)
        .Include(o => o.Invoice);

    /// Places an order priced entirely from the server's menu, settings and
    /// offers. Guests order for the table (or takeaway) of their session;
    /// staff (with createOrders) choose the table or takeaway. Replays of
    /// the same idempotency key return the original order.
    public async Task<(Order Order, bool Created)> PlaceAsync(PlaceOrderRequest request, CancellationToken ct)
    {
        var requestedType = ParseOrderType(request.OrderType);
        int table;
        Guid? guestSession = null;
        User? staff = null;
        if (caller.IsGuest)
        {
            table = caller.GuestTable!.Value;
            guestSession = caller.GuestSessionId;
            // What the guest confirmed must be what their session is, so a
            // takeaway order never lands on a table (or the other way round).
            if (requestedType is { } type && type != OrderTables.TypeOf(table))
            {
                throw ApiException.Conflict("orderTypeMismatch",
                    "This order does not match the code you scanned. Please scan the QR code again.");
            }
        }
        else
        {
            staff = await caller.RequireAsync(Permission.CreateOrders, ct);
            table = StaffTable(request, requestedType);
        }

        var key = (request.IdempotencyKey ?? "").Trim();
        if (key.Length is < 8 or > 64)
        {
            throw ApiException.Validation("idempotencyKey", "An idempotency key of 8 to 64 characters is required.");
        }
        if (await FindReplayAsync(key, guestSession, staff, ct) is { } replay) return (replay, false);

        if (request.Lines is not { Count: > 0 })
        {
            throw ApiException.BadRequest("emptyCart", "Your cart is empty. Add a dish to place an order.");
        }
        if (request.Lines.Count > 50)
        {
            throw ApiException.Validation("lines", "An order can have at most 50 lines.");
        }
        var instructions = (request.Instructions ?? "").Trim();
        if (instructions.Length > Pricing.MaxInstructions)
        {
            throw ApiException.Validation("instructions",
                $"Instructions can be at most {Pricing.MaxInstructions} characters.");
        }

        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        if (OrderTables.IsTakeaway(table))
        {
            // A takeaway order has no table to check; the restaurant only has
            // to still be taking them.
            if (!settings.TakeawayOrdersEnabled)
            {
                throw ApiException.Conflict("takeawayUnavailable",
                    "Takeaway orders are not being taken right now. Please ask a staff member.");
            }
        }
        else
        {
            var tableRow = await db.Tables.AsNoTracking().FirstOrDefaultAsync(t => t.Number == table, ct);
            if (tableRow is not { IsActive: true })
            {
                throw ApiException.Conflict("tableUnavailable",
                    "This table is not taking orders right now. Please ask a staff member.");
            }
        }

        var now = Now;
        var today = OfferRules.Today(settings, now);
        var comboIds = request.Lines.Select(l => l.ComboId).OfType<string>().Distinct().ToList();
        var combos = comboIds.Count == 0
            ? new Dictionary<string, Promotion>()
            : await db.Promotions.AsNoTracking().Include(p => p.Items)
                .Where(p => comboIds.Contains(p.Id))
                .ToDictionaryAsync(p => p.Id, ct);
        var ids = request.Lines.Where(l => string.IsNullOrEmpty(l.ComboId)).Select(l => l.ItemId ?? "")
            .Concat(combos.Values.SelectMany(c => c.Items).Select(i => i.ItemId))
            .Distinct().ToList();
        var menu = await db.MenuItems.AsNoTracking()
            .Include(i => i.Category).Include(i => i.Portions).Include(i => i.AddOns)
            .Where(i => ids.Contains(i.Id))
            .ToDictionaryAsync(i => i.Id, ct);
        var priced = request.Lines.Select(l => Pricing.PriceLine(l, menu, combos, today)).ToList();

        // Special offers apply by themselves; the guest never asks for them.
        var specials = (await db.Promotions.AsNoTracking().Include(p => p.Items)
                .Where(p => p.Kind == PromotionKind.Special && p.IsActive)
                .ToListAsync(ct))
            .Where(p => OfferRules.IsLive(p, today))
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Id, StringComparer.Ordinal)
            .ToList();

        DiscountOffer? coupon = null;
        if (!string.IsNullOrWhiteSpace(request.OfferCode))
        {
            var offerCode = Pricing.NormalizeCode(request.OfferCode);
            coupon = await db.Offers.AsNoTracking().FirstOrDefaultAsync(o => o.Code == offerCode, ct)
                     ?? throw ApiException.Conflict("offerUnavailable",
                         "That offer is not available any more. Remove it and try again.");
            if (OfferRules.Problem(coupon, today) is { } problem)
            {
                throw ApiException.Conflict("offerUnavailable", problem);
            }
        }
        var quote = Pricing.Apply(priced, specials, settings, coupon);
        var bill = quote.Bill;
        if (request.ExpectedTotal is { } expected && expected != bill.Total)
        {
            throw ApiException.Conflict("priceChanged",
                "Prices changed since you opened the menu. Please review your cart.");
        }

        var prep = quote.Lines.Max(l => l.PrepMinutes) + settings.PrepBufferMinutes;
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        await ClaimOffersAsync(quote, ct);
        var order = new Order
        {
            Id = $"OD{await db.NextValueAsync(AppDbContext.OrderSequence, ct)}",
            TableNumber = table,
            CreatedAt = now,
            Status = OrderStatus.Placed,
            Source = staff == null ? OrderSource.Guest : OrderSource.Staff,
            SpecialInstructions = instructions,
            EstimatedReadyAt = now.AddMinutes(prep),
            SubtotalPaise = bill.Subtotal,
            DiscountPaise = bill.Discount,
            DiscountLabel = bill.DiscountLabel,
            ServiceChargePaise = bill.Service,
            ServiceChargeBasisPoints = bill.ServiceRate,
            TaxPaise = bill.Tax,
            TaxRateBasisPoints = bill.TaxRate,
            TaxName = bill.TaxName,
            TotalPaise = bill.Total,
            OfferCode = quote.Coupon?.Code,
            Discounts = quote.Discounts,
            IdempotencyKey = key,
            GuestSessionId = guestSession,
            CreatedByUserId = staff?.Id,
            Lines = [.. quote.Lines.Select((l, index) => new OrderLine
            {
                LineNo = index + 1,
                ItemId = l.ItemId,
                Name = l.Name,
                Image = l.Image,
                IsVeg = l.IsVeg,
                UnitPricePaise = l.UnitPrice,
                Quantity = l.Quantity,
                Options = l.Options,
                CategoryId = l.CategoryId,
                CategoryName = l.CategoryName,
                PortionId = l.PortionId,
                Spice = l.Spice,
                AddOnIds = l.AddOnIds,
                ComboId = l.ComboId,
                ComboItems = l.ComboItems,
                DiscountPaise = l.Discount,
                PromotionId = l.Discount > 0 ? l.PromotionId : null,
                DiscountLabel = l.Discount > 0 ? l.DiscountLabel : null,
            })],
            History =
            [
                new OrderStatusChange
                {
                    Status = OrderStatus.Placed,
                    At = now,
                    ChangedByUserId = staff?.Id,
                    ChangedByName = staff?.FullName ?? "Guest",
                },
            ],
        };
        // Every order has its bill from the start, so guests can pay at any
        // point; it copies the order's pricing snapshot.
        order.Invoice = await NewInvoiceAsync(order, settings, now, ct);
        db.Orders.Add(order);
        if (staff != null)
        {
            audit.Record(staff, "order.create",
                $"Created order {order.Id} for {OrderTables.Label(table).ToLowerInvariant()}", order.Id);
        }
        try
        {
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
        }
        catch (DbUpdateException error) when (error.InnerException is PostgresException
                                              { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            // A concurrent replay with the same key won the race.
            await transaction.RollbackAsync(ct);
            db.ChangeTracker.Clear();
            if (await FindReplayAsync(key, guestSession, staff, ct) is { } winner) return (winner, false);
            throw;
        }
        await notifier.OrderChanged(order, "created");
        await notifier.BillChanged(order.Invoice, guestSession);
        await NotifyIfUsedUpAsync(quote.Discounts, ct);
        return (order, true);
    }

    /// Takes one use of every promotion and the coupon the order saves with.
    /// Each guarded update locks its row until the order commits, so
    /// concurrent orders take turns and a limited offer is never used more
    /// often than allowed. Call inside the order's transaction: an order that
    /// fails gives its uses back.
    private async Task ClaimOffersAsync(Quote quote, CancellationToken ct)
    {
        foreach (var discount in quote.Discounts)
        {
            var id = discount.Ref!;
            var claimed = discount.Kind == "coupon"
                ? await db.Offers
                    .Where(o => o.Code == id && o.IsActive && (o.UsageLimit == null || o.UsedCount < o.UsageLimit))
                    .ExecuteUpdateAsync(s => s.SetProperty(o => o.UsedCount, o => o.UsedCount + 1), ct)
                : await db.Promotions
                    .Where(p => p.Id == id && p.IsActive && (p.UsageLimit == null || p.UsedCount < p.UsageLimit))
                    .ExecuteUpdateAsync(s => s.SetProperty(p => p.UsedCount, p => p.UsedCount + 1), ct);
            if (claimed == 0)
            {
                throw ApiException.Conflict("offerUnavailable",
                    $"{discount.Label} has just run out or ended. Please review your cart.");
            }
        }
    }

    /// Gives back the uses a cancelled order took (orders from before
    /// itemised discounts took none).
    private async Task ReleaseOffersAsync(Order order, CancellationToken ct)
    {
        foreach (var discount in order.Discounts)
        {
            var id = discount.Ref;
            if (id == null) continue;
            if (discount.Kind == "coupon")
            {
                await db.Offers.Where(o => o.Code == id && o.UsedCount > 0)
                    .ExecuteUpdateAsync(s => s.SetProperty(o => o.UsedCount, o => o.UsedCount - 1), ct);
            }
            else
            {
                await db.Promotions.Where(p => p.Id == id && p.UsedCount > 0)
                    .ExecuteUpdateAsync(s => s.SetProperty(p => p.UsedCount, p => p.UsedCount - 1), ct);
            }
        }
    }

    /// An offer this order used up disappears from every guest's menu now,
    /// rather than at their next checkout.
    private async Task NotifyIfUsedUpAsync(List<DiscountLine> discounts, CancellationToken ct)
    {
        var promotions = discounts.Where(d => d.Kind != "coupon").Select(d => d.Ref).ToList();
        var coupons = discounts.Where(d => d.Kind == "coupon").Select(d => d.Ref).ToList();
        if (promotions.Count > 0 && await db.Promotions.AnyAsync(
                p => promotions.Contains(p.Id) && p.UsageLimit != null && p.UsedCount >= p.UsageLimit, ct))
        {
            await notifier.MenuChanged();
        }
        if (coupons.Count > 0 && await db.Offers.AnyAsync(
                o => coupons.Contains(o.Code) && o.UsageLimit != null && o.UsedCount >= o.UsageLimit, ct))
        {
            await notifier.SettingsChanged();
        }
    }

    /// `dineIn` or `takeaway`; null when the app did not say.
    private static OrderType? ParseOrderType(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return EnumNames.TryParse<OrderType>(value.Trim(), out var type)
            ? type
            : throw ApiException.Validation("orderType", "The order type must be dineIn or takeaway.");
    }

    /// The table of a staff order: none for takeaway (given as the type, or
    /// as table 0 by apps from before the type was sent), otherwise the one
    /// chosen.
    private static int StaffTable(PlaceOrderRequest request, OrderType? type)
    {
        if (type == OrderType.Takeaway)
        {
            return request.TableNumber is null or OrderTables.Takeaway
                ? OrderTables.Takeaway
                : throw ApiException.Validation("tableNumber", "A takeaway order has no table.");
        }
        var table = request.TableNumber ?? throw ApiException.BadRequest("missingTable", "Choose a table first.");
        if (type == OrderType.DineIn && OrderTables.IsTakeaway(table))
        {
            throw ApiException.BadRequest("missingTable", "Choose a table first.");
        }
        return table;
    }

    private async Task<Order?> FindReplayAsync(string key, Guid? guestSession, User? staff, CancellationToken ct)
    {
        var existing = await Full.AsNoTracking().FirstOrDefaultAsync(o => o.IdempotencyKey == key, ct);
        if (existing == null) return null;
        var sameCaller = guestSession != null
            ? existing.GuestSessionId == guestSession
            : existing.CreatedByUserId == staff?.Id;
        return sameCaller
            ? existing
            : throw ApiException.Conflict("duplicateKey", "This request was already used for another order.");
    }

    private async Task<Invoice> NewInvoiceAsync(Order order, RestaurantSettings settings, DateTime now,
        CancellationToken ct)
    {
        var number = await db.NextValueAsync(AppDbContext.InvoiceSequence, ct);
        var localYear = now.AddMinutes(settings.UtcOffsetMinutes).Year;
        return new Invoice
        {
            Id = $"INV{number:D5}",
            BillNumber = $"DQ-{localYear}-{number:D5}",
            OrderId = order.Id,
            TableNumber = order.TableNumber,
            CreatedAt = now,
            UpdatedAt = now,
            SubtotalPaise = order.SubtotalPaise,
            DiscountPaise = order.DiscountPaise,
            DiscountLabel = order.DiscountLabel,
            ServiceChargePaise = order.ServiceChargePaise,
            ServiceChargeBasisPoints = order.ServiceChargeBasisPoints,
            TaxPaise = order.TaxPaise,
            TaxRateBasisPoints = order.TaxRateBasisPoints,
            TaxName = order.TaxName,
            TotalPaise = order.TotalPaise,
            RestaurantName = settings.Name,
            RestaurantPhone = settings.Phone,
            RestaurantEmail = settings.Email,
            RestaurantAddress = settings.Address,
            RestaurantTaxRegistration = settings.TaxRegistration,
            ReceiptFooter = settings.ReceiptFooter,
            IsSettled = order.TotalPaise == 0,
        };
    }

    /// One order: a guest may read only orders of their own session.
    public async Task<Order> GetAsync(string id, CancellationToken ct)
    {
        var order = await Full.AsNoTracking().FirstOrDefaultAsync(o => o.Id == id, ct)
                    ?? throw ApiException.NotFound("Order not found.");
        if (caller.IsGuest)
        {
            if (order.GuestSessionId != caller.GuestSessionId) throw ApiException.NotFound("Order not found.");
        }
        else
        {
            await caller.RequireAsync(Permission.ViewOrders, ct);
        }
        return order;
    }

    /// The guest session's own orders, newest first.
    public Task<List<Order>> ForGuestAsync(CancellationToken ct)
    {
        var session = caller.GuestSessionId;
        return Full.AsNoTracking().AsSplitQuery()
            .Where(o => o.GuestSessionId == session)
            .OrderByDescending(o => o.CreatedAt)
            .ToListAsync(ct);
    }

    /// Staff listing: orders created in [from, to), plus every order still in
    /// progress, newest first.
    public async Task<List<Order>> ForStaffAsync(DateTime? from, DateTime? to, string? status,
        CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ViewOrders, ct);
        var start = from ?? Now.AddDays(-30);
        var end = to ?? DateTime.MaxValue;
        var query = Full.AsNoTracking().AsSplitQuery()
            .Where(o => (o.CreatedAt >= start && o.CreatedAt < end) ||
                        (o.Status != OrderStatus.Served && o.Status != OrderStatus.Cancelled));
        if (!string.IsNullOrEmpty(status))
        {
            if (!EnumNames.TryParse<OrderStatus>(status, out var wanted))
            {
                throw ApiException.Validation("status", "Unknown order status.");
            }
            query = query.Where(o => o.Status == wanted);
        }
        return await query.OrderByDescending(o => o.CreatedAt).Take(2000).ToListAsync(ct);
    }

    /// Staff: moves an order to its next stage, or cancels it with a reason.
    /// The permission depends on the target (kitchen, serving, cancelling).
    public async Task<Order> ChangeStatusAsync(string id, StatusChangeRequest request, CancellationToken ct)
    {
        if (!EnumNames.TryParse<OrderStatus>(request.Target, out var target))
        {
            throw ApiException.Validation("target", "Unknown order status.");
        }
        var staff = await caller.RequireAsync(OrderStatusRules.PermissionFor(target), ct);
        var order = await Full.FirstOrDefaultAsync(o => o.Id == id, ct)
                    ?? throw ApiException.NotFound("Order not found.");
        if (!order.Status.CanTransitionTo(target))
        {
            throw ApiException.Conflict("invalidTransition",
                $"Order {order.Id} cannot go from {EnumNames.ToName(order.Status)} to {EnumNames.ToName(target)}.");
        }
        var reason = (request.Reason ?? "").Trim();
        if (target == OrderStatus.Cancelled && reason.Length is < 3 or > 120)
        {
            throw ApiException.Validation("reason", "Give a reason of 3 to 120 characters.");
        }
        var now = Now;
        // A cancellation gives back the offer uses in the same transaction.
        await using var transaction = target == OrderStatus.Cancelled
            ? await db.Database.BeginTransactionAsync(ct)
            : null;
        order.Status = target;
        order.History.Add(new OrderStatusChange
        {
            Status = target,
            At = now,
            ChangedByUserId = staff.Id,
            ChangedByName = staff.FullName,
            Reason = reason,
        });
        if (target == OrderStatus.Cancelled)
        {
            order.CancelReason = reason;
            if (order.Invoice is { IsVoid: false } invoice)
            {
                // Any payment already taken stays recorded; the bill shows a
                // refund due.
                invoice.IsVoid = true;
                invoice.VoidReason = reason;
                invoice.VoidedAt = now;
                invoice.UpdatedAt = now;
                invoice.UpdateSettled();
            }
            audit.Record(staff, "order.cancel", $"Cancelled order {order.Id}: {reason}", order.Id);
        }
        else
        {
            audit.Record(staff, "order.status",
                $"Order {order.Id} → {EnumNames.ToName(target)}", order.Id);
        }
        await db.SaveChangesAsync(ct);
        if (transaction != null)
        {
            await ReleaseOffersAsync(order, ct);
            await transaction.CommitAsync(ct);
        }
        await notifier.OrderChanged(order, "status");
        if (target == OrderStatus.Cancelled && order.Invoice != null)
        {
            await notifier.BillChanged(order.Invoice, order.GuestSessionId);
        }
        return order;
    }

    /// Guest: rates their own served order once.
    public async Task<Order> SubmitFeedbackAsync(string id, FeedbackRequest request, CancellationToken ct)
    {
        var order = await Full.FirstOrDefaultAsync(o => o.Id == id, ct);
        if (order == null || order.GuestSessionId != caller.GuestSessionId)
        {
            throw ApiException.NotFound("Order not found.");
        }
        if (order.Status != OrderStatus.Served)
        {
            throw ApiException.Conflict("notServed", "Orders can be rated once they are served.");
        }
        if (order.FeedbackRating != null)
        {
            throw ApiException.Conflict("alreadyRated", "This order was already rated.");
        }
        if (request.Rating is < 1 or > 5)
        {
            throw ApiException.Validation("rating", "Ratings go from 1 to 5 stars.");
        }
        var comment = (request.Comment ?? "").Trim();
        if (comment.Length > 300)
        {
            throw ApiException.Validation("comment", "Feedback can be at most 300 characters.");
        }
        order.FeedbackRating = request.Rating;
        order.FeedbackComment = comment;
        order.FeedbackAt = Now;
        await db.SaveChangesAsync(ct);
        await notifier.OrderChanged(order, "feedback");
        return order;
    }
}
