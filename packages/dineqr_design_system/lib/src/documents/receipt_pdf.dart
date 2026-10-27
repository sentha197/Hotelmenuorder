import 'dart:typed_data';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_theme.dart';

/// Printable bill / receipt for one [Invoice].
abstract final class ReceiptPdf {
  static const pageFormats = {
    'Receipt (80 mm)': PdfPageFormat.roll80,
    'A5': PdfPageFormat.a5,
    'A4': PdfPageFormat.a4,
  };

  static String fileName(Invoice invoice) => 'DineQR-${invoice.billNumber}.pdf';

  static Future<Uint8List> build(
    Invoice invoice, {
    PdfPageFormat format = PdfPageFormat.roll80,
    Uint8List? logoPng,
    DateTime? printedAt,
  }) async {
    final theme = await DineQrPdfTheme.load();
    final narrow = format.width < 100 * PdfPageFormat.mm;
    final doc = pw.Document(
      title: 'Bill ${invoice.billNumber}',
      author: invoice.restaurant.name,
    );
    final content = _content(invoice, theme, narrow, logoPng, printedAt);
    if (format.height == double.infinity) {
      doc.addPage(
        pw.Page(
          pageTheme: theme.pageTheme(format, margin: 14),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
      );
    } else {
      doc.addPage(
        pw.MultiPage(
          pageTheme: theme.pageTheme(format, margin: narrow ? 14 : 36),
          build: (context) => content,
        ),
      );
    }
    return doc.save();
  }

  static List<pw.Widget> _content(
    Invoice invoice,
    DineQrPdfTheme theme,
    bool narrow,
    Uint8List? logoPng,
    DateTime? printedAt,
  ) {
    String money(Money m) => CurrencyFormatter.format(m);
    final r = invoice.restaurant;
    final amounts = invoice.amounts;
    final paidInFull = invoice.status == InvoiceStatus.paid;
    final demoNotice = invoice.demoNotice;

    pw.Widget row(String label, String value, {bool strong = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(label, style: strong ? theme.label : theme.body),
              ),
              pw.Text(
                value,
                style: strong ? theme.label.copyWith(fontSize: 11) : theme.body,
              ),
            ],
          ),
        );

    pw.Widget divider() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Divider(color: DineQrPdfTheme.line, thickness: 0.6),
    );

    return [
      pw.Column(
        children: [
          if (logoPng != null) pw.Image(pw.MemoryImage(logoPng), width: 46),
          pw.SizedBox(height: 4),
          pw.Text(r.name, style: theme.heading, textAlign: pw.TextAlign.center),
          if (r.address.isNotEmpty)
            pw.Text(
              r.address,
              style: theme.small,
              textAlign: pw.TextAlign.center,
            ),
          if (r.phone.isNotEmpty || r.email.isNotEmpty)
            pw.Text(
              [r.phone, r.email].where((s) => s.isNotEmpty).join(' · '),
              style: theme.small,
              textAlign: pw.TextAlign.center,
            ),
          if (r.taxRegistration.isNotEmpty)
            pw.Text(
              'Tax registration: ${r.taxRegistration}',
              style: theme.small,
              textAlign: pw.TextAlign.center,
            ),
          pw.SizedBox(height: 6),
          pw.Text(
            paidInFull ? 'RECEIPT' : 'BILL',
            style: theme.label.copyWith(
              color: DineQrPdfTheme.red,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      divider(),
      row('Bill no.', invoice.billNumber),
      row('Order', AppFormat.orderNumber(invoice.orderId)),
      if (invoice.isTakeaway)
        row('Type', 'Takeaway')
      else
        row('Table', AppFormat.table(invoice.tableNumber)),
      row('Date', AppFormat.dateTime(invoice.createdAt)),
      row('Status', invoice.status.label),
      divider(),
      pw.Row(
        children: [
          pw.Expanded(child: pw.Text('Item', style: theme.label)),
          pw.SizedBox(width: 24, child: pw.Text('Qty', style: theme.label)),
          pw.SizedBox(
            width: narrow ? 52 : 80,
            child: pw.Text(
              'Amount',
              style: theme.label,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 3),
      for (final line in invoice.lines)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(line.name, style: theme.body),
                    pw.Text(
                      [
                        '${money(line.unitPrice)} each',
                        ...line.options,
                      ].join(' · '),
                      style: theme.small,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(
                width: 24,
                child: pw.Text('${line.quantity}', style: theme.body),
              ),
              pw.SizedBox(
                width: narrow ? 52 : 80,
                child: pw.Text(
                  money(line.lineTotal),
                  style: theme.body,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      divider(),
      row('Subtotal', money(amounts.subtotal)),
      if (amounts.hasDiscount)
        row(
          amounts.discountLabel ?? 'Discount',
          '− ${money(amounts.discount)}',
        ),
      if (amounts.hasServiceCharge)
        row(amounts.serviceChargeLabel, money(amounts.serviceCharge)),
      row(amounts.taxLabel, money(amounts.tax)),
      divider(),
      row('Total', money(amounts.total), strong: true),
      row('Paid', money(invoice.amountPaid)),
      if (!invoice.amountRefunded.isZero)
        row('Refunded', '− ${money(invoice.amountRefunded)}'),
      row(
        invoice.isVoid ? 'Balance (void)' : 'Balance due',
        money(invoice.outstanding),
        strong: !invoice.outstanding.isZero,
      ),
      if (invoice.payments.isNotEmpty) ...[
        divider(),
        pw.Text('Payments', style: theme.label),
        pw.SizedBox(height: 2),
        for (final p in invoice.payments)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${p.method.label} · ${p.statusLabel}',
                        style: theme.body,
                      ),
                      pw.Text(
                        [
                          AppFormat.dateTime(p.updatedAt),
                          if (p.reference.isNotEmpty) 'Ref ${p.reference}',
                        ].join(' · '),
                        style: theme.small,
                      ),
                    ],
                  ),
                ),
                pw.Text(money(p.amount), style: theme.body),
              ],
            ),
          ),
      ],
      if (invoice.refunds.isNotEmpty) ...[
        divider(),
        pw.Text('Refunds', style: theme.label),
        for (final refund in invoice.refunds)
          row(
            '${AppFormat.date(refund.createdAt)} · ${refund.status.label}',
            money(refund.amount),
          ),
      ],
      if (invoice.isVoid)
        theme.notice(
          'VOID: the order was cancelled'
          '${invoice.voidReason.isEmpty ? '' : ' (${invoice.voidReason})'}.',
        ),
      if (demoNotice != null) theme.notice('DEMO: $demoNotice'),
      pw.SizedBox(height: 8),
      if (r.footer.isNotEmpty)
        pw.Text(r.footer, style: theme.body, textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 2),
      pw.Text(
        [
          'Powered by DineQR',
          if (printedAt != null) 'Printed ${AppFormat.dateTime(printedAt)}',
        ].join(' · '),
        style: theme.small,
        textAlign: pw.TextAlign.center,
      ),
    ];
  }
}

/// Printable table tents: one QR code per table with the DineQR brand.
abstract final class TableQrPdf {
  static Future<Uint8List> build(
    List<RestaurantTable> tables, {
    required String restaurantName,
    required String Function(int table) payloadFor,
    Uint8List? logoPng,
  }) async {
    final theme = await DineQrPdfTheme.load();
    final doc = pw.Document(title: 'DineQR table QR codes');
    final qr = pw.Barcode.qrCode(
      errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high,
    );

    pw.Widget card(RestaurantTable table) => pw.Container(
      margin: const pw.EdgeInsets.all(8),
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: DineQrPdfTheme.red, width: 1.2),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          theme.wordmark(18),
          pw.Text(restaurantName, style: theme.small),
          pw.SizedBox(height: 10),
          pw.Stack(
            alignment: pw.Alignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: qr,
                data: payloadFor(table.number),
                width: 150,
                height: 150,
                color: DineQrPdfTheme.charcoal,
              ),
              if (logoPng != null)
                pw.Container(
                  width: 34,
                  height: 34,
                  color: PdfColors.white,
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Image(pw.MemoryImage(logoPng)),
                ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(OrderTables.label(table.number), style: theme.title),
          pw.Text('Scan • Order • Enjoy', style: theme.label),
          pw.SizedBox(height: 4),
          pw.Text(
            OrderTables.isTakeaway(table.number)
                ? 'Point your phone camera at the code to see the menu and '
                      'order takeaway to collect at the counter.'
                : 'Point your phone camera at the code to see the menu and '
                      'order from your table.',
            style: theme.small,
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );

    for (var i = 0; i < tables.length; i += 4) {
      final page = tables.skip(i).take(4).toList();
      doc.addPage(
        pw.Page(
          pageTheme: theme.pageTheme(PdfPageFormat.a4, margin: 24),
          build: (context) => pw.GridView(
            crossAxisCount: 2,
            childAspectRatio: 1.05,
            children: [for (final t in page) card(t)],
          ),
        ),
      );
    }
    return doc.save();
  }
}
