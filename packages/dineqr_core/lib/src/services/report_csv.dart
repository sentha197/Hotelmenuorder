import '../models/restaurant_settings.dart';
import '../utils/currency.dart';
import '../utils/formatters.dart';
import 'report_service.dart';

/// CSV export of a [SalesReport]. Amounts are plain numbers with two
/// decimals (no currency symbol or grouping) so spreadsheets read them.
abstract final class ReportCsv {
  static String amount(Money money) {
    final negative = money.paise < 0;
    final abs = money.paise.abs();
    final text = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
    return negative ? '-$text' : text;
  }

  static String escape(Object? value) {
    final text = '${value ?? ''}';
    if (text.contains(RegExp(r'[",\n\r]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  static String build(SalesReport report, RestaurantSettings settings) {
    final rows = <List<Object?>>[
      ['DineQR sales report'],
      ['Restaurant', settings.name],
      ['Period', AppFormat.range(report.range)],
      ['Time zone', settings.utcOffsetLabel],
      ['Generated', AppFormat.dateTime(report.generatedAt)],
      ['Currency', settings.currencyCode],
      [
        'Sample data',
        report.includesDemo && report.demoOrders > 0
            ? 'Includes ${report.demoOrders} demo sample orders'
            : 'None',
      ],
      [],
      ['Summary'],
      ['Metric', 'Value'],
      ['Orders', report.orderCount],
      ['Completed orders', report.completedCount],
      ['Cancelled orders', report.cancelledCount],
      ['Gross sales', amount(report.grossSales)],
      ['Discounts', amount(report.discounts)],
      ['Service charges', amount(report.serviceCharges)],
      ['Taxes', amount(report.taxes)],
      ['Billed', amount(report.billed)],
      ['Collected', amount(report.collected)],
      ['Refunds', amount(report.refunds)],
      ['Net sales', amount(report.netSales)],
      ['Net collected', amount(report.netCollected)],
      ['Outstanding', amount(report.outstanding)],
      ['Average order value', amount(report.averageOrderValue)],
      ['Paid bills', report.paidBills],
      ['Partially paid bills', report.partiallyPaidBills],
      ['Unpaid bills', report.unpaidBills],
      ['Failed payment attempts', report.failedPayments],
      [],
      ['Daily sales'],
      ['Date', 'Orders', 'Billed', 'Collected'],
      for (final day in report.daily)
        [
          AppFormat.date(day.dayStart),
          day.orders,
          amount(day.billed),
          amount(day.collected),
        ],
      [],
      ['Dishes'],
      ['Dish', 'Category', 'Quantity', 'Revenue'],
      for (final item in report.items)
        [item.name, item.category, item.quantity, amount(item.revenue)],
      [],
      ['Categories'],
      ['Category', 'Quantity', 'Revenue'],
      for (final c in report.categories)
        [c.name, c.quantity, amount(c.revenue)],
      [],
      ['Payment methods'],
      ['Method', 'Collected'],
      for (final entry in report.byMethod.entries)
        [entry.key.label, amount(entry.value)],
      [],
      ['Taxes'],
      ['Tax', 'Bills', 'Taxable amount', 'Tax'],
      for (final t in report.taxLines)
        [t.label, t.bills, amount(t.taxable), amount(t.tax)],
      [],
      ['Tables'],
      ['Table', 'Orders', 'Billed'],
      for (final t in report.tables)
        [AppFormat.table(t.table), t.orders, amount(t.billed)],
      [],
      ['Refunds'],
      ['Date', 'Refund', 'Bill', 'Amount', 'Reason'],
      for (final r in report.refundRecords)
        [
          AppFormat.dateTime(r.createdAt),
          r.id,
          r.invoiceId,
          amount(r.amount),
          r.reason,
        ],
      [],
      ['Outstanding bills'],
      ['Bill', 'Order', 'Table', 'Date', 'Total', 'Paid', 'Outstanding'],
      for (final i in report.outstandingBills)
        [
          i.billNumber,
          i.orderId,
          AppFormat.table(i.tableNumber),
          AppFormat.date(i.createdAt),
          amount(i.total),
          amount(i.amountPaid),
          amount(i.outstanding),
        ],
    ];
    return '${rows.map((row) => row.map(escape).join(',')).join('\r\n')}\r\n';
  }
}
