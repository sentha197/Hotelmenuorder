import 'dart:typed_data';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_theme.dart';

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
