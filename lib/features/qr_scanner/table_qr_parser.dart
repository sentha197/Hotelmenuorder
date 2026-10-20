enum TableQrError {
  empty('No QR code content was found.'),
  unrecognized('This is not a DineQR table QR code.'),
  invalidTable('This QR code points to a table that does not exist.');

  const TableQrError(this.message);

  final String message;
}

sealed class TableQrResult {
  const TableQrResult();
}

final class ValidTableQr extends TableQrResult {
  const ValidTableQr(this.tableNumber);

  final int tableNumber;
}

final class InvalidTableQr extends TableQrResult {
  const InvalidTableQr(this.error);

  final TableQrError error;
}

/// Parses table QR payloads of the form `DINEQR:TABLE:05`.
abstract final class TableQrParser {
  static const prefix = 'DINEQR:TABLE:';

  /// Codes printed before the DineQR rename keep working.
  static const legacyPrefixes = ['BITEANDDINE:TABLE:'];

  /// Tables in the demo restaurant are numbered 1 to [maxTable].
  static const maxTable = 30;

  static final RegExp _digits = RegExp(r'^\d{1,3}$');

  static TableQrResult parse(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return const InvalidTableQr(TableQrError.empty);
    final upper = value.toUpperCase();
    final matched = [prefix, ...legacyPrefixes].where(upper.startsWith);
    if (matched.isEmpty) {
      return const InvalidTableQr(TableQrError.unrecognized);
    }
    final tablePart = value.substring(matched.first.length).trim();
    if (!_digits.hasMatch(tablePart)) {
      return const InvalidTableQr(TableQrError.unrecognized);
    }
    final table = int.parse(tablePart);
    if (table < 1 || table > maxTable) {
      return const InvalidTableQr(TableQrError.invalidTable);
    }
    return ValidTableQr(table);
  }

  static String payloadFor(int table) =>
      '$prefix${table.toString().padLeft(2, '0')}';
}
