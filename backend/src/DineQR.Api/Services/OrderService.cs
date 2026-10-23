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
    /// offers. Guests order for the table of their session; staff (with
    /// createOrders) choose the table. Replays of the same idempotency key
    /// return the original order.
    public async Task<(Order Order, bool Created)> PlaceAsync(PlaceOrderRequest request, CancellationToken ct)
    {
        int table;
        Guid? guestSession = null;
        User? staff = null;
        if (caller.IsGuest)
        {
            table = caller.GuestTable!.Value;
            guestSession = caller.GuestSessionId;
        }
        else
        {
            staff = await caller.RequireAsync(Permission.CreateOrders, ct);
            table = request.TableNumber ?? throw ApiException.BadRequest("missingTable", "Choose a table first.");
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
        if (OrderTables.IsParcel(table))
        {
            // A parcel order has no table to check; the restaurant only has
            // to still be taking them.
            if (!settings.ParcelOrdersEnabled)
            {
                throw ApiException.Conflict("parcelUnavailable",
                    "Parcel orders are not being taken right now. Please ask a staff member.");
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

        var ids = request.Lines.Select(l => l.ItemId).Distinct().ToList();
        var menu = await db.MenuItems.AsNoTracking()
            .Include(i => i.Category).Include(i => i.Portions).Include(i => i.AddOns)
            .Where(i => ids.Contains(i.Id))
            .ToDictionaryAsync(i => i.Id, ct);
        var priced = request.Lines.Select(l => Pricing.PriceLine(l, menu)).ToList();
        var subtotal = priced.Sum(l => l.LineTotal);

        long discount = 0;
        string? label = null;
        string? offerCode = null;
        if (!string.IsNullOrWhiteSpace(request.OfferCode))
        {
            offerCode = Pricing.NormalizeCode(request.OfferCode);
            var offer = await db.Offers.AsNoTracking().FirstOrDefaultAsync(o => o.Code == offerCode, ct);
            if (offer is not { IsActive: true })
            {
                throw ApiException.Conflict("offerUnavailable",
                    "That offer is not available any more. Remove it and try again.");
            }
            discount = Pricing.DiscountFor(offer, subtotal);
            label = $"Offer {offer.Code}";
        }
        var bill = Pricing.Compute(subtotal, settings, discount, label);
        if (request.ExpectedTotal is { } expected && expected != bill.Total)
        {
            throw ApiException.Conflict("priceChanged",
                "Prices changed since you opened the menu. Please review your cart.");
        }

        var now = Now;
        var prep = priced.Max(l => l.Item.PrepMinutes) + settings.PrepBufferMinutes;
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
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
            OfferCode = bill.Discount > 0 ? offerCode : null,
            IdempotencyKey = key,
            GuestSessionId = guestSession,
            CreatedByUserId = staff?.Id,
            Lines = [.. priced.Select((l, index) => new OrderLine
            {
                LineNo = index + 1,
                ItemId = l.Item.Id,
                Name = l.Item.Name,
                Image = l.Item.Image,
                IsVeg = l.Item.IsVeg,
                UnitPricePaise = l.UnitPrice,
                Quantity = l.Quantity,
                Options = l.Options,
                CategoryId = l.Item.CategoryId,
                CategoryName = l.Item.Category.Label,
                PortionId = l.PortionId,
                Spice = l.Spice,
                AddOnIds = l.AddOnIds,
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
        return (order, true);
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
