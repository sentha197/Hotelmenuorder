import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../models/restaurant_settings.dart';
import 'pdf_theme.dart';
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

/// PDF version of a [SalesReport].
abstract final class ReportPdf {
  static Future<Uint8List> build(
    SalesReport report,
    RestaurantSettings settings, {
    Uint8List? logoPng,
  }) async {
    final theme = await DineQrPdfTheme.load();
    final doc = pw.Document(
      title: 'DineQR report ${AppFormat.range(report.range)}',
      author: settings.name,
    );
    String money(Money m) => CurrencyFormatter.format(m);

    pw.Widget table(
      List<String> headers,
      List<List<String>> rows,
    ) => pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: theme.label.copyWith(color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: DineQrPdfTheme.red),
      cellStyle: theme.body,
      cellAlignments: {
        for (var i = 1; i < headers.length; i++) i: pw.Alignment.centerRight,
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: DineQrPdfTheme.line, width: 0.5),
      ),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );

    pw.Widget section(String title, pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: theme.heading),
          pw.SizedBox(height: 6),
          child,
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: theme.pageTheme(PdfPageFormat.a4),
        header: (context) => theme.header(
          title: 'Sales report',
          subtitle:
              '${settings.name} · ${AppFormat.range(report.range)} '
              '(${settings.utcOffsetLabel})',
          logoPng: logoPng,
        ),
        footer: (context) => theme.footer(
          'Generated ${AppFormat.dateTime(report.generatedAt)} · '
          'Page ${context.pageNumber} of ${context.pagesCount}',
        ),
        build: (context) => [
          if (report.includesDemo && report.demoOrders > 0)
            theme.notice(
              'Includes ${report.demoOrders} demo sample orders. '
              'Sample data is for demonstration only.',
            ),
          section(
            'Summary',
            table(
              ['Metric', 'Value'],
              [
                ['Orders', '${report.orderCount}'],
                ['Completed orders', '${report.completedCount}'],
                ['Cancelled orders', '${report.cancelledCount}'],
                ['Gross sales', money(report.grossSales)],
                ['Discounts', money(report.discounts)],
                ['Service charges', money(report.serviceCharges)],
                ['Taxes', money(report.taxes)],
                ['Billed', money(report.billed)],
                ['Collected', money(report.collected)],
                ['Refunds', money(report.refunds)],
                ['Net sales', money(report.netSales)],
                ['Net collected', money(report.netCollected)],
                ['Outstanding', money(report.outstanding)],
                ['Average order value', money(report.averageOrderValue)],
              ],
            ),
          ),
          section(
            'Daily sales',
            table(
              ['Date', 'Orders', 'Billed', 'Collected'],
              [
                for (final d in report.daily)
                  [
                    AppFormat.date(d.dayStart),
                    '${d.orders}',
                    money(d.billed),
                    money(d.collected),
                  ],
              ],
            ),
          ),
          if (report.items.isNotEmpty)
            section(
              'Best-selling dishes',
              table(
                ['Dish', 'Category', 'Qty', 'Revenue'],
                [
                  for (final i in report.items.take(15))
                    [i.name, i.category, '${i.quantity}', money(i.revenue)],
                ],
              ),
            ),
          if (report.categories.isNotEmpty)
            section(
              'Categories',
              table(
                ['Category', 'Qty', 'Revenue'],
                [
                  for (final c in report.categories)
                    [c.name, '${c.quantity}', money(c.revenue)],
                ],
              ),
            ),
          if (report.byMethod.isNotEmpty)
            section(
              'Payment collection',
              table(
                ['Method', 'Collected'],
                [
                  for (final e in report.byMethod.entries)
                    [e.key.label, money(e.value)],
                ],
              ),
            ),
          if (report.taxLines.isNotEmpty)
            section(
              'Taxes (as recorded on bills)',
              table(
                ['Tax', 'Bills', 'Taxable', 'Tax'],
                [
                  for (final t in report.taxLines)
                    [t.label, '${t.bills}', money(t.taxable), money(t.tax)],
                ],
              ),
            ),
          if (report.outstandingBills.isNotEmpty)
            section(
              'Outstanding bills',
              table(
                ['Bill', 'Table', 'Total', 'Paid', 'Due'],
                [
                  for (final i in report.outstandingBills)
                    [
                      i.billNumber,
                      AppFormat.table(i.tableNumber),
                      money(i.total),
                      money(i.amountPaid),
                      money(i.outstanding),
                    ],
                ],
              ),
            ),
          if (report.refundRecords.isNotEmpty)
            section(
              'Refunds',
              table(
                ['Date', 'Refund', 'Amount', 'Reason'],
                [
                  for (final r in report.refundRecords)
                    [
                      AppFormat.date(r.createdAt),
                      r.id,
                      money(r.amount),
                      r.reason,
                    ],
                ],
              ),
            ),
          section(
            'Definitions',
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final (term, meaning) in SalesReport.definitions)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(text: '$term: ', style: theme.label),
                          pw.TextSpan(text: meaning, style: theme.body),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
