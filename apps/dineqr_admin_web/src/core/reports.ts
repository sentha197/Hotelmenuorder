import { paymentMethodLabel, type Invoice, type PaymentMethodType, type RefundRecord } from './billing';
import { csvAmount, sumPaise, type Paise } from './money';
import { lineTotal, Orders, Tables, type RestaurantOrder } from './orders';
import { Bills } from './pricing';
import type { RestaurantSettings } from './settings';
import { AppFormat, DateRanges, formatOffset, RestaurantTime, type DateRange } from './time';

export interface DailySales {
  dayStart: Date;
  orders: number;
  billed: Paise;
  collected: Paise;
}

export interface ItemSales {
  itemId: string;
  name: string;
  category: string;
  quantity: number;
  /** Line totals before discounts and taxes. */
  revenue: Paise;
}

export interface CategorySales {
  name: string;
  quantity: number;
  revenue: Paise;
}

export interface TaxLine {
  /** e.g. `Taxes (5%)`. */
  label: string;
  taxable: Paise;
  tax: Paise;
  bills: number;
}

export interface TableUsage {
  table: number;
  orders: number;
  billed: Paise;
}

/**
 * One report, computed once and shown, charted and exported from the same
 * numbers (SalesReport.build). All in restaurant time, range end exclusive:
 * orders placed in the range excluding cancelled ones; collected = successful
 * payments made in the range; refunds = processed in the range; outstanding =
 * unpaid balance of bills created in the range (void bills excluded).
 */
export interface SalesReport {
  range: DateRange;
  generatedAt: Date;
  includesDemo: boolean;
  demoOrders: number;
  orderCount: number;
  cancelledCount: number;
  completedCount: number;
  activeCount: number;
  grossSales: Paise;
  discounts: Paise;
  serviceCharges: Paise;
  taxes: Paise;
  billed: Paise;
  collected: Paise;
  refunds: Paise;
  outstanding: Paise;
  paidBills: number;
  unpaidBills: number;
  partiallyPaidBills: number;
  daily: DailySales[];
  items: ItemSales[];
  categories: CategorySales[];
  byMethod: Map<PaymentMethodType, Paise>;
  taxLines: TaxLine[];
  tables: TableUsage[];
  refundRecords: RefundRecord[];
  outstandingBills: Invoice[];
  netSales: Paise;
  netCollected: Paise;
  averageOrderValue: Paise;
  isEmpty: boolean;
}

export function buildReport(args: {
  orders: readonly RestaurantOrder[];
  invoices: readonly Invoice[];
  range: DateRange;
  now: Date;
  includeDemo?: boolean;
  categoryOf?: (itemId: string) => string;
}): SalesReport {
  const { range, now, categoryOf } = args;
  const includeDemo = args.includeDemo ?? true;
  const allOrders = args.orders.filter((o) => includeDemo || !o.isDemoSample);
  const allInvoices = args.invoices.filter((i) => includeDemo || !i.isDemoSample);
  const inRange = allOrders.filter((o) => DateRanges.contains(range, o.createdAt));
  const sales = inRange.filter((o) => !Orders.isCancelled(o));

  let gross = 0;
  let discounts = 0;
  let service = 0;
  let taxes = 0;
  let billed = 0;
  const itemMap = new Map<string, ItemSales>();
  const categoryMap = new Map<string, CategorySales>();
  const taxMap = new Map<string, TaxLine>();
  const tableMap = new Map<number, TableUsage>();
  for (const order of sales) {
    const bill = order.bill;
    gross += bill.subtotal;
    discounts += bill.discount;
    service += bill.serviceCharge;
    taxes += bill.tax;
    billed += bill.total;
    const taxKey = Bills.taxLabel(bill);
    const t = taxMap.get(taxKey);
    taxMap.set(taxKey, { label: taxKey, taxable: (t?.taxable ?? 0) + Bills.taxableAmount(bill), tax: (t?.tax ?? 0) + bill.tax, bills: (t?.bills ?? 0) + 1 });
    const tu = tableMap.get(order.tableNumber);
    tableMap.set(order.tableNumber, { table: order.tableNumber, orders: (tu?.orders ?? 0) + 1, billed: (tu?.billed ?? 0) + bill.total });
    for (const line of order.lines) {
      const category = line.categoryName || categoryOf?.(line.itemId) || 'Other';
      const item = itemMap.get(line.itemId);
      itemMap.set(line.itemId, {
        itemId: line.itemId,
        name: line.name,
        category,
        quantity: (item?.quantity ?? 0) + line.quantity,
        revenue: (item?.revenue ?? 0) + lineTotal(line),
      });
      const cat = categoryMap.get(category);
      categoryMap.set(category, { name: category, quantity: (cat?.quantity ?? 0) + line.quantity, revenue: (cat?.revenue ?? 0) + lineTotal(line) });
    }
  }

  // Payments and refunds count by when they happened.
  let collected = 0;
  let refunded = 0;
  const byMethod = new Map<PaymentMethodType, Paise>();
  const refundList: RefundRecord[] = [];
  const dailyCollected = new Map<number, Paise>();
  for (const invoice of allInvoices) {
    for (const payment of invoice.payments) {
      if (!DateRanges.contains(range, payment.updatedAt)) continue;
      if (payment.status === 'succeeded') {
        collected += payment.amount;
        byMethod.set(payment.method, (byMethod.get(payment.method) ?? 0) + payment.amount);
        const day = RestaurantTime.startOfDay(payment.updatedAt).getTime();
        dailyCollected.set(day, (dailyCollected.get(day) ?? 0) + payment.amount);
      }
    }
    for (const refund of invoice.refunds) {
      if (refund.status === 'processed' && DateRanges.contains(range, refund.createdAt)) {
        refunded += refund.amount;
        refundList.push(refund);
      }
    }
  }

  // Bill states for bills created in the range.
  let outstanding = 0;
  let paid = 0;
  let unpaid = 0;
  let partial = 0;
  const open: Invoice[] = [];
  for (const invoice of allInvoices) {
    if (!DateRanges.contains(range, invoice.createdAt) || invoice.isVoid) continue;
    outstanding += invoice.outstanding;
    switch (invoice.status) {
      case 'paid':
      case 'refunded':
      case 'partiallyRefunded':
        paid++;
        break;
      case 'partiallyPaid':
        partial++;
        break;
      case 'pending':
      case 'unpaid':
      case 'failed':
        unpaid++;
        break;
      case 'voided':
        break;
    }
    if (invoice.outstanding !== 0) open.push(invoice);
  }
  open.sort((a, b) => b.outstanding - a.outstanding);

  const daily = DateRanges.dayStarts(range).map((day) => {
    const dayOrders = sales.filter((o) => RestaurantTime.startOfDay(o.createdAt).getTime() === day.getTime());
    return {
      dayStart: day,
      orders: dayOrders.length,
      billed: sumPaise(dayOrders.map((o) => o.bill.total)),
      collected: dailyCollected.get(day.getTime()) ?? 0,
    };
  });

  const items = [...itemMap.values()].sort((a, b) => b.revenue - a.revenue || b.quantity - a.quantity);
  const categories = [...categoryMap.values()].sort((a, b) => b.revenue - a.revenue);
  const tables = [...tableMap.values()].sort((a, b) => b.orders - a.orders);

  return {
    range,
    generatedAt: now,
    includesDemo: includeDemo,
    demoOrders: inRange.filter((o) => o.isDemoSample).length,
    orderCount: sales.length,
    cancelledCount: inRange.filter(Orders.isCancelled).length,
    completedCount: sales.filter((o) => o.status === 'served').length,
    activeCount: sales.filter(Orders.isActive).length,
    grossSales: gross,
    discounts,
    serviceCharges: service,
    taxes,
    billed,
    collected,
    refunds: refunded,
    outstanding,
    paidBills: paid,
    unpaidBills: unpaid,
    partiallyPaidBills: partial,
    daily,
    items,
    categories,
    byMethod,
    taxLines: [...taxMap.values()],
    tables,
    refundRecords: refundList.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()),
    outstandingBills: open,
    netSales: gross - discounts - refunded,
    netCollected: collected - refunded,
    averageOrderValue: sales.length === 0 ? 0 : Math.round(billed / sales.length),
    isEmpty: sales.length === 0 && collected === 0 && refunded === 0,
  };
}

/** Plain-language definitions shown next to reports and exports. */
export const reportDefinitions: readonly (readonly [string, string])[] = [
  ['Orders', 'Placed in the period, not counting cancelled orders.'],
  ['Gross sales', 'Order subtotals before discounts, charges and taxes.'],
  ['Billed', 'Bill totals after discounts, with service charges and taxes.'],
  ['Collected', 'Payments taken at the billing counter in the period.'],
  ['Refunds', 'Refunds processed in the period.'],
  ['Net sales', 'Gross sales − discounts − refunds.'],
  ['Net collected', 'Collected − refunds.'],
  ['Outstanding', 'Unpaid balance of bills created in the period.'],
  ['Average order value', 'Billed ÷ orders.'],
];

function csvEscape(value: unknown): string {
  const text = value == null ? '' : String(value);
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

/** CSV export of a report (ReportCsv.build): plain two-decimal amounts so spreadsheets read them. */
export function reportCsv(report: SalesReport, settings: RestaurantSettings): string {
  const a = csvAmount;
  const rows: unknown[][] = [
    ['DineQR sales report'],
    ['Restaurant', settings.name],
    ['Period', AppFormat.range(report.range)],
    ['Time zone', formatOffset(settings.utcOffsetMinutes)],
    ['Generated', AppFormat.dateTime(report.generatedAt)],
    ['Currency', settings.currencyCode],
    ['Sample data', report.includesDemo && report.demoOrders > 0 ? `Includes ${report.demoOrders} demo sample orders` : 'None'],
    [],
    ['Summary'],
    ['Metric', 'Value'],
    ['Orders', report.orderCount],
    ['Completed orders', report.completedCount],
    ['Cancelled orders', report.cancelledCount],
    ['Gross sales', a(report.grossSales)],
    ['Discounts', a(report.discounts)],
    ['Service charges', a(report.serviceCharges)],
    ['Taxes', a(report.taxes)],
    ['Billed', a(report.billed)],
    ['Collected', a(report.collected)],
    ['Refunds', a(report.refunds)],
    ['Net sales', a(report.netSales)],
    ['Net collected', a(report.netCollected)],
    ['Outstanding', a(report.outstanding)],
    ['Average order value', a(report.averageOrderValue)],
    ['Paid bills', report.paidBills],
    ['Partially paid bills', report.partiallyPaidBills],
    ['Unpaid bills', report.unpaidBills],
    [],
    ['Daily sales'],
    ['Date', 'Orders', 'Billed', 'Collected'],
    ...report.daily.map((d) => [AppFormat.date(d.dayStart), d.orders, a(d.billed), a(d.collected)]),
    [],
    ['Dishes'],
    ['Dish', 'Category', 'Quantity', 'Revenue'],
    ...report.items.map((i) => [i.name, i.category, i.quantity, a(i.revenue)]),
    [],
    ['Categories'],
    ['Category', 'Quantity', 'Revenue'],
    ...report.categories.map((c) => [c.name, c.quantity, a(c.revenue)]),
    [],
    ['Counter collections by method'],
    ['Method', 'Collected'],
    ...[...report.byMethod.entries()].map(([m, v]) => [paymentMethodLabel[m], a(v)]),
    [],
    ['Taxes'],
    ['Tax', 'Bills', 'Taxable amount', 'Tax'],
    ...report.taxLines.map((t) => [t.label, t.bills, a(t.taxable), a(t.tax)]),
    [],
    ['Tables'],
    ['Table', 'Orders', 'Billed'],
    ...report.tables.map((t) => [Tables.shortLabel(t.table), t.orders, a(t.billed)]),
    [],
    ['Refunds'],
    ['Date', 'Refund', 'Bill', 'Amount', 'Reason'],
    ...report.refundRecords.map((r) => [AppFormat.dateTime(r.createdAt), r.id, r.invoiceId, a(r.amount), r.reason]),
    [],
    ['Outstanding bills'],
    ['Bill', 'Order', 'Table', 'Date', 'Total', 'Paid', 'Outstanding'],
    ...report.outstandingBills.map((i) => [i.billNumber, i.orderId, Tables.shortLabel(i.tableNumber), AppFormat.date(i.createdAt), a(i.total), a(i.amountPaid), a(i.outstanding)]),
  ];
  return `${rows.map((row) => row.map(csvEscape).join(',')).join('\r\n')}\r\n`;
}
