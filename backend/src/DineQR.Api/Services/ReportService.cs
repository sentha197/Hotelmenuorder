using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

public sealed record DailyFigures(DateOnly Day, int Orders, long Billed, long Collected);

public sealed record ItemFigures(string ItemId, string Name, string Category, int Quantity, long Revenue);

/// Sales figures for restaurant days [From, To] (inclusive), with the
/// definitions in docs/BACKEND_INTEGRATION.md and the apps' SalesReport.
/// Money fields are null for staff without viewFinancials.
public sealed record SalesSummary(
    DateOnly From,
    DateOnly To,
    int UtcOffsetMinutes,
    int OrderCount,
    int CancelledCount,
    int CompletedCount,
    int ActiveCount,
    long? GrossSales,
    long? Discounts,
    long? ServiceCharges,
    long? Taxes,
    long? Billed,
    long? Collected,
    long? Refunds,
    long? NetCollected,
    long? NetSales,
    long? Outstanding,
    long? AverageOrderValue,
    int PaidBills,
    int UnpaidBills,
    int PartiallyPaidBills,
    int PendingBills,
    int FailedPayments,
    Dictionary<string, long>? CollectedByMethod,
    List<DailyFigures> Daily,
    List<ItemFigures> Items);

public sealed class ReportService(AppDbContext db, CurrentCaller caller)
{
    public async Task<SalesSummary> SummaryAsync(DateOnly from, DateOnly to, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ViewReports, ct);
        if (to < from) throw ApiException.Validation("to", "The end date is before the start date.");
        if (to.DayNumber - from.DayNumber > 366) throw ApiException.Validation("to", "Choose at most a year.");
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var offset = TimeSpan.FromMinutes(settings.UtcOffsetMinutes);
        // Restaurant days, half-open [start, end) in UTC.
        DateTime Utc(DateOnly day) => DateTime.SpecifyKind(day.ToDateTime(TimeOnly.MinValue) - offset, DateTimeKind.Utc);
        DateOnly DayOf(DateTime utc) => DateOnly.FromDateTime(utc + offset);
        var start = Utc(from);
        var end = Utc(to.AddDays(1));

        var orders = await db.Orders.AsNoTracking().Include(o => o.Lines)
            .Where(o => o.CreatedAt >= start && o.CreatedAt < end).ToListAsync(ct);
        var bills = await db.Invoices.AsNoTracking().Include(i => i.Payments).Include(i => i.Refunds)
            .Where(i => i.CreatedAt >= start && i.CreatedAt < end).ToListAsync(ct);
        var collectedPayments = await db.Payments.AsNoTracking()
            .Where(p => p.Status == PaymentStatus.Succeeded && p.ConfirmedAt >= start && p.ConfirmedAt < end)
            .ToListAsync(ct);
        var refunds = await db.Refunds.AsNoTracking()
            .Where(r => r.Status == RefundStatus.Processed && r.CreatedAt >= start && r.CreatedAt < end)
            .ToListAsync(ct);
        var failed = await db.Payments.AsNoTracking()
            .CountAsync(p => p.Status == PaymentStatus.Failed && p.CreatedAt >= start && p.CreatedAt < end, ct);

        // Orders exclude cancelled ones; billed and sales come from them.
        var counted = orders.Where(o => o.Status != OrderStatus.Cancelled).ToList();
        var billed = counted.Sum(o => o.TotalPaise);
        var collected = collectedPayments.Sum(p => p.AmountPaise);
        var refunded = refunds.Sum(r => r.AmountPaise);
        var gross = counted.Sum(o => o.SubtotalPaise);
        var discounts = counted.Sum(o => o.DiscountPaise);

        var statuses = bills.Where(b => !b.IsVoid).Select(Contracts.Mapping.StatusOf).ToList();
        var daily = new List<DailyFigures>();
        for (var day = from; day <= to; day = day.AddDays(1))
        {
            daily.Add(new DailyFigures(
                day,
                counted.Count(o => DayOf(o.CreatedAt) == day),
                counted.Where(o => DayOf(o.CreatedAt) == day).Sum(o => o.TotalPaise),
                collectedPayments.Where(p => DayOf(p.ConfirmedAt!.Value) == day).Sum(p => p.AmountPaise)));
        }
        var items = counted.SelectMany(o => o.Lines)
            .GroupBy(l => l.ItemId)
            .Select(g => new ItemFigures(g.Key, g.First().Name, g.First().CategoryName,
                g.Sum(l => l.Quantity), g.Sum(l => l.UnitPricePaise * l.Quantity)))
            .OrderByDescending(i => i.Quantity).ThenByDescending(i => i.Revenue)
            .ToList();

        var money = RolePermissions.Can(staff, Permission.ViewFinancials);
        long? M(long value) => money ? value : null;
        return new SalesSummary(
            from, to, settings.UtcOffsetMinutes,
            counted.Count,
            orders.Count(o => o.Status == OrderStatus.Cancelled),
            orders.Count(o => o.Status == OrderStatus.Served),
            orders.Count(o => o.Status.IsActive()),
            M(gross),
            M(discounts),
            M(counted.Sum(o => o.ServiceChargePaise)),
            M(counted.Sum(o => o.TaxPaise)),
            M(billed),
            M(collected),
            M(refunded),
            M(collected - refunded),
            M(gross - discounts - refunded),
            M(bills.Where(b => !b.IsVoid).Sum(b => b.OutstandingPaise)),
            M(counted.Count == 0 ? 0 : (long)Math.Round(billed / (double)counted.Count, MidpointRounding.AwayFromZero)),
            statuses.Count(s => s == "paid"),
            statuses.Count(s => s is "unpaid" or "failed"),
            statuses.Count(s => s == "partiallyPaid"),
            statuses.Count(s => s == "pending"),
            failed,
            money
                ? collectedPayments.GroupBy(p => EnumNames.ToName(p.Method))
                    .ToDictionary(g => g.Key, g => g.Sum(p => p.AmountPaise))
                : null,
            money ? daily : [.. daily.Select(d => d with { Billed = 0, Collected = 0 })],
            money ? items : [.. items.Select(i => i with { Revenue = 0 })]);
    }
}
