using DineQR.Api.Data;
using DineQR.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// Loads the child rows of a staff list (order lines, status history, bill
/// payments and refunds) by the parents' ids: `order_id = ANY(@ids)`, always
/// an index scan. EF's split queries re-ran the list's filter joined to each
/// child table, and Postgres answered that by scanning every order line or
/// payment ever written, so the lists slowed down with every month of
/// history. Results are the same; only the SQL differs.
internal static class ListLoading
{
    /// Fills [orders]' lines and status history (no-tracking entities).
    public static async Task LoadOrderChildrenAsync(AppDbContext db, IReadOnlyCollection<Order> orders,
        CancellationToken ct)
    {
        if (orders.Count == 0) return;
        var ids = orders.Select(o => o.Id).Distinct().ToList();
        var lines = (await db.OrderLines.AsNoTracking().Where(l => ids.Contains(l.OrderId)).ToListAsync(ct))
            .ToLookup(l => l.OrderId);
        var history = (await db.OrderStatusChanges.AsNoTracking().Where(h => ids.Contains(h.OrderId))
                .ToListAsync(ct))
            .ToLookup(h => h.OrderId);
        foreach (var order in orders)
        {
            order.Lines = [.. lines[order.Id].OrderBy(l => l.LineNo)];
            order.History = [.. history[order.Id].OrderBy(h => h.At)];
        }
    }

    /// Fills [invoices]' payments and refunds, and their orders' lines.
    public static async Task LoadBillChildrenAsync(AppDbContext db, IReadOnlyCollection<Invoice> invoices,
        CancellationToken ct)
    {
        if (invoices.Count == 0) return;
        var ids = invoices.Select(i => i.Id).ToList();
        var payments = (await db.Payments.AsNoTracking().Where(p => ids.Contains(p.InvoiceId)).ToListAsync(ct))
            .ToLookup(p => p.InvoiceId);
        var refunds = (await db.Refunds.AsNoTracking().Where(r => ids.Contains(r.InvoiceId)).ToListAsync(ct))
            .ToLookup(r => r.InvoiceId);
        var orderIds = invoices.Select(i => i.OrderId).Distinct().ToList();
        var lines = (await db.OrderLines.AsNoTracking().Where(l => orderIds.Contains(l.OrderId)).ToListAsync(ct))
            .ToLookup(l => l.OrderId);
        foreach (var invoice in invoices)
        {
            invoice.Payments = [.. payments[invoice.Id].OrderBy(p => p.CreatedAt)];
            invoice.Refunds = [.. refunds[invoice.Id].OrderBy(r => r.CreatedAt)];
            invoice.Order.Lines = [.. lines[invoice.OrderId].OrderBy(l => l.LineNo)];
        }
    }
}
