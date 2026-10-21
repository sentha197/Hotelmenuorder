import '../../core/utils/currency.dart';
import '../../core/utils/restaurant_time.dart';
import '../models/billing.dart';
import '../models/order_status.dart';
import '../models/restaurant_order.dart';

/// Sales figures for one day of a report.
class DailySales {
  const DailySales({
    required this.dayStart,
    required this.orders,
    required this.billed,
    required this.collected,
  });

  final DateTime dayStart;
  final int orders;
  final Money billed;
  final Money collected;
}

class ItemSales {
  const ItemSales({
    required this.itemId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.revenue,
  });

  final String itemId;
  final String name;
  final String category;
  final int quantity;

  /// Line totals before discounts and taxes.
  final Money revenue;
}

class CategorySales {
  const CategorySales({
    required this.name,
    required this.quantity,
    required this.revenue,
  });

  final String name;
  final int quantity;
  final Money revenue;
}

class TaxLine {
  const TaxLine({
    required this.label,
    required this.taxable,
    required this.tax,
    required this.bills,
  });

  /// e.g. `Taxes (5%)`.
  final String label;
  final Money taxable;
  final Money tax;
  final int bills;
}

class TableUsage {
  const TableUsage({
    required this.table,
    required this.orders,
    required this.billed,
  });

  final int table;
  final int orders;
  final Money billed;
}

/// One report, computed once and shown, charted and exported from the same
/// numbers.
///
/// Definitions (all in restaurant time, range end exclusive):
/// * Orders: placed in the range, excluding cancelled orders.
/// * Gross sales: sum of order subtotals (before discounts, service charges
///   and taxes).
/// * Billed: sum of bill totals (after discounts, including service charges
///   and taxes).
/// * Collected: successful payments made in the range. Pending, failed and
///   cancelled payments never count.
/// * Refunds: refunds processed in the range.
/// * Net sales = gross sales − discounts − refunds.
/// * Net collected = collected − refunds.
/// * Outstanding: unpaid balance of bills created in the range (void bills
///   excluded).
/// * Average order value = billed ÷ orders.
class SalesReport {
  const SalesReport({
    required this.range,
    required this.generatedAt,
    required this.includesDemo,
    required this.demoOrders,
    required this.orderCount,
    required this.cancelledCount,
    required this.completedCount,
    required this.activeCount,
    required this.grossSales,
    required this.discounts,
    required this.serviceCharges,
    required this.taxes,
    required this.billed,
    required this.collected,
    required this.refunds,
    required this.outstanding,
    required this.paidBills,
    required this.unpaidBills,
    required this.partiallyPaidBills,
    required this.pendingBills,
    required this.failedPayments,
    required this.daily,
    required this.items,
    required this.categories,
    required this.byMethod,
    required this.taxLines,
    required this.tables,
    required this.refundRecords,
    required this.outstandingBills,
  });

  factory SalesReport.build({
    required Iterable<RestaurantOrder> orders,
    required Iterable<Invoice> invoices,
    required DateRange range,
    required DateTime now,
    bool includeDemo = true,
    String Function(String itemId)? categoryOf,
  }) {
    final allOrders = [
      for (final o in orders)
        if (includeDemo || !o.isDemoSample) o,
    ];
    final allInvoices = [
      for (final i in invoices)
        if (includeDemo || !i.isDemoSample) i,
    ];
    final inRange = allOrders.where((o) => range.contains(o.createdAt));
    final sales = inRange.where((o) => !o.isCancelled).toList();

    var gross = Money.zero;
    var discounts = Money.zero;
    var service = Money.zero;
    var taxes = Money.zero;
    var billed = Money.zero;
    final itemMap = <String, ItemSales>{};
    final categoryMap = <String, CategorySales>{};
    final taxMap = <String, TaxLine>{};
    final tableMap = <int, TableUsage>{};
    for (final order in sales) {
      final bill = order.bill;
      gross += bill.subtotal;
      discounts += bill.discount;
      service += bill.serviceCharge;
      taxes += bill.tax;
      billed += bill.total;
      final taxKey = bill.taxLabel;
      final previousTax = taxMap[taxKey];
      taxMap[taxKey] = TaxLine(
        label: taxKey,
        taxable: (previousTax?.taxable ?? Money.zero) + bill.taxableAmount,
        tax: (previousTax?.tax ?? Money.zero) + bill.tax,
        bills: (previousTax?.bills ?? 0) + 1,
      );
      final previousTable = tableMap[order.tableNumber];
      tableMap[order.tableNumber] = TableUsage(
        table: order.tableNumber,
        orders: (previousTable?.orders ?? 0) + 1,
        billed: (previousTable?.billed ?? Money.zero) + bill.total,
      );
      for (final line in order.lines) {
        final category = line.categoryName.isNotEmpty
            ? line.categoryName
            : (categoryOf?.call(line.itemId) ?? 'Other');
        final item = itemMap[line.itemId];
        itemMap[line.itemId] = ItemSales(
          itemId: line.itemId,
          name: line.name,
          category: category,
          quantity: (item?.quantity ?? 0) + line.quantity,
          revenue: (item?.revenue ?? Money.zero) + line.lineTotal,
        );
        final cat = categoryMap[category];
        categoryMap[category] = CategorySales(
          name: category,
          quantity: (cat?.quantity ?? 0) + line.quantity,
          revenue: (cat?.revenue ?? Money.zero) + line.lineTotal,
        );
      }
    }

    // Payments and refunds count by when they happened.
    var collected = Money.zero;
    var refunded = Money.zero;
    var failed = 0;
    final byMethod = <PaymentMethodType, Money>{};
    final refundList = <RefundRecord>[];
    final dailyCollected = <DateTime, Money>{};
    for (final invoice in allInvoices) {
      for (final payment in invoice.payments) {
        if (!range.contains(payment.updatedAt)) continue;
        if (payment.status == PaymentStatus.succeeded) {
          collected += payment.amount;
          byMethod[payment.method] =
              (byMethod[payment.method] ?? Money.zero) + payment.amount;
          final day = RestaurantTime.startOfDay(payment.updatedAt);
          dailyCollected[day] =
              (dailyCollected[day] ?? Money.zero) + payment.amount;
        } else if (payment.status == PaymentStatus.failed) {
          failed++;
        }
      }
      for (final refund in invoice.refunds) {
        if (refund.status == RefundStatus.processed &&
            range.contains(refund.createdAt)) {
          refunded += refund.amount;
          refundList.add(refund);
        }
      }
    }

    // Bill states for bills created in the range.
    var outstanding = Money.zero;
    var paid = 0;
    var unpaid = 0;
    var partial = 0;
    var pending = 0;
    final open = <Invoice>[];
    for (final invoice in allInvoices) {
      if (!range.contains(invoice.createdAt) || invoice.isVoid) continue;
      outstanding += invoice.outstanding;
      switch (invoice.status) {
        case InvoiceStatus.paid ||
            InvoiceStatus.refunded ||
            InvoiceStatus.partiallyRefunded:
          paid++;
        case InvoiceStatus.partiallyPaid:
          partial++;
        case InvoiceStatus.pending:
          pending++;
        case InvoiceStatus.unpaid || InvoiceStatus.failed:
          unpaid++;
        case InvoiceStatus.voided:
          break;
      }
      if (!invoice.outstanding.isZero) open.add(invoice);
    }
    open.sort((a, b) => b.outstanding.compareTo(a.outstanding));

    final daily = [
      for (final day in range.dayStarts)
        () {
          final dayOrders = sales.where(
            (o) => RestaurantTime.startOfDay(o.createdAt) == day,
          );
          return DailySales(
            dayStart: day,
            orders: dayOrders.length,
            billed: Money.sum(dayOrders.map((o) => o.bill.total)),
            collected: dailyCollected[day] ?? Money.zero,
          );
        }(),
    ];

    final items = itemMap.values.toList()
      ..sort((a, b) {
        final byRevenue = b.revenue.compareTo(a.revenue);
        return byRevenue != 0 ? byRevenue : b.quantity.compareTo(a.quantity);
      });
    final categories = categoryMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final tables = tableMap.values.toList()
      ..sort((a, b) => b.orders.compareTo(a.orders));

    return SalesReport(
      range: range,
      generatedAt: now,
      includesDemo: includeDemo,
      demoOrders: inRange.where((o) => o.isDemoSample).length,
      orderCount: sales.length,
      cancelledCount: inRange.where((o) => o.isCancelled).length,
      completedCount: sales.where((o) => o.status == OrderStatus.served).length,
      activeCount: sales.where((o) => o.isActive).length,
      grossSales: gross,
      discounts: discounts,
      serviceCharges: service,
      taxes: taxes,
      billed: billed,
      collected: collected,
      refunds: refunded,
      outstanding: outstanding,
      paidBills: paid,
      unpaidBills: unpaid,
      partiallyPaidBills: partial,
      pendingBills: pending,
      failedPayments: failed,
      daily: daily,
      items: items,
      categories: categories,
      byMethod: byMethod,
      taxLines: taxMap.values.toList(),
      tables: tables,
      refundRecords: refundList
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      outstandingBills: open,
    );
  }

  final DateRange range;
  final DateTime generatedAt;
  final bool includesDemo;

  /// Sample orders inside the range (shown as a notice).
  final int demoOrders;
  final int orderCount;
  final int cancelledCount;
  final int completedCount;
  final int activeCount;
  final Money grossSales;
  final Money discounts;
  final Money serviceCharges;
  final Money taxes;
  final Money billed;
  final Money collected;
  final Money refunds;
  final Money outstanding;
  final int paidBills;
  final int unpaidBills;
  final int partiallyPaidBills;
  final int pendingBills;
  final int failedPayments;
  final List<DailySales> daily;
  final List<ItemSales> items;
  final List<CategorySales> categories;
  final Map<PaymentMethodType, Money> byMethod;
  final List<TaxLine> taxLines;
  final List<TableUsage> tables;
  final List<RefundRecord> refundRecords;
  final List<Invoice> outstandingBills;

  Money get netSales => grossSales - discounts - refunds;

  Money get netCollected => collected - refunds;

  Money get averageOrderValue =>
      orderCount == 0 ? Money.zero : Money((billed.paise / orderCount).round());

  bool get isEmpty => orderCount == 0 && collected.isZero && refunds.isZero;

  /// Plain-language definitions shown next to reports and exports.
  static const definitions = [
    ('Orders', 'Placed in the period, not counting cancelled orders.'),
    ('Gross sales', 'Order subtotals before discounts, charges and taxes.'),
    ('Billed', 'Bill totals after discounts, with service charges and taxes.'),
    ('Collected', 'Successful payments made in the period.'),
    ('Refunds', 'Refunds processed in the period.'),
    ('Net sales', 'Gross sales − discounts − refunds.'),
    ('Net collected', 'Collected − refunds.'),
    ('Outstanding', 'Unpaid balance of bills created in the period.'),
    ('Average order value', 'Billed ÷ orders.'),
  ];
}
