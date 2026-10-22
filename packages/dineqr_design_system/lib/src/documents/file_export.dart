import 'dart:convert';
import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Saving, sharing and printing generated files.
abstract final class FileExport {
  /// Opens the share sheet (or downloads, on the web) for a PDF.
  static Future<void> sharePdf(Uint8List bytes, String fileName) =>
      Printing.sharePdf(bytes: bytes, filename: fileName);

  /// Opens the system print dialog. Returns whether the job was handed to
  /// a printer (not a guarantee that paper came out).
  static Future<bool> printPdf(Uint8List bytes, String jobName) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: jobName);

  /// Shares a CSV file (downloads it on the web). Written as UTF-8 with a
  /// byte order mark so spreadsheet apps read ₹ and names correctly.
  static Future<void> shareCsv(String csv, String fileName) async {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/csv', name: fileName)],
        fileNameOverrides: [fileName],
        subject: fileName,
      ),
    );
  }
}
