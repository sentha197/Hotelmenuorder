import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Brand fonts and styles for generated PDFs (receipts, reports, QR sheets).
/// Poppins is embedded so the ₹ sign and the brand type render everywhere.
class DineQrPdfTheme {
  DineQrPdfTheme._(this.regular, this.medium, this.semiBold, this.bold);

  static const red = PdfColor.fromInt(0xFFB5121B);
  static const deepRed = PdfColor.fromInt(0xFF8E0F17);
  static const orange = PdfColor.fromInt(0xFFFF6A00);
  static const charcoal = PdfColor.fromInt(0xFF202020);
  static const grey = PdfColor.fromInt(0xFF737373);
  static const line = PdfColor.fromInt(0xFFE6DCD9);
  static const pale = PdfColor.fromInt(0xFFFFF5F2);
  static const green = PdfColor.fromInt(0xFF248A45);

  static DineQrPdfTheme? _cached;

  static Future<DineQrPdfTheme> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    Future<pw.Font> font(String weight) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    return _cached = DineQrPdfTheme._(
      await font('Regular'),
      await font('Medium'),
      await font('SemiBold'),
      await font('Bold'),
    );
  }

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semiBold;
  final pw.Font bold;

  pw.TextStyle get body =>
      pw.TextStyle(font: regular, fontSize: 9, color: charcoal);

  pw.TextStyle get small =>
      pw.TextStyle(font: regular, fontSize: 7.5, color: grey);

  pw.TextStyle get label =>
      pw.TextStyle(font: semiBold, fontSize: 9, color: charcoal);

  pw.TextStyle get heading =>
      pw.TextStyle(font: bold, fontSize: 12, color: charcoal);

  pw.TextStyle get title => pw.TextStyle(font: bold, fontSize: 18, color: red);

  pw.PageTheme pageTheme(PdfPageFormat format, {double margin = 32}) =>
      pw.PageTheme(
        pageFormat: format.copyWith(
          marginLeft: margin,
          marginRight: margin,
          marginTop: margin,
          marginBottom: margin,
        ),
        theme: pw.ThemeData.withFont(
          base: regular,
          bold: bold,
          italic: regular,
          boldItalic: bold,
        ),
      );

  /// Brand header: logo, "DineQR" with orange "QR", title and subtitle.
  pw.Widget header({
    required String title,
    String subtitle = '',
    Uint8List? logoPng,
  }) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    margin: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: red, width: 1.5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoPng != null) ...[
          pw.Image(pw.MemoryImage(logoPng), width: 42),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              wordmark(16),
              pw.Text(title, style: heading),
              if (subtitle.isNotEmpty) pw.Text(subtitle, style: small),
            ],
          ),
        ),
      ],
    ),
  );

  pw.Widget wordmark(double size) => pw.RichText(
    text: pw.TextSpan(
      children: [
        pw.TextSpan(
          text: 'Dine',
          style: pw.TextStyle(font: bold, fontSize: size, color: charcoal),
        ),
        pw.TextSpan(
          text: 'QR',
          style: pw.TextStyle(font: bold, fontSize: size, color: orange),
        ),
      ],
    ),
  );

  pw.Widget footer(String text) => pw.Container(
    alignment: pw.Alignment.centerRight,
    padding: const pw.EdgeInsets.only(top: 8),
    child: pw.Text(text, style: small),
  );

  pw.Widget notice(String text) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 6),
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      color: pale,
      border: pw.Border.all(color: orange, width: 0.6),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(text, style: label.copyWith(color: deepRed)),
  );
}
