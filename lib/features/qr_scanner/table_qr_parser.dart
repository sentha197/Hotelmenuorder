enum TableQrError {
  empty('No QR code content was found.'),
  unrecognized('This is not a DineQR table QR code.'),
  invalidTable('This QR code points to a table that does not exist.'),
  tableInactive(
    'This table is not taking orders right now. Please ask a staff member.',
  );

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
///
/// A table QR only identifies where an order is placed. It never grants
/// access to anything else (staff sign-in is separate), and in production
/// the backend must check the table again when an order is submitted.
abstract final class TableQrParser {
  static const prefix = 'DINEQR:TABLE:';

  /// Codes printed before the DineQR rename keep working.
  static const legacyPrefixes = ['BITEANDDINE:TABLE:'];

  /// Without restaurant configuration, tables are numbered 1 to [maxTable].
  static const maxTable = 30;

  static final RegExp _digits = RegExp(r'^\d{1,3}$');

  /// [tableExists] and [tableActive] check the number against the
  /// restaurant's configured tables when they are known.
  static TableQrResult parse(
    String? raw, {
    bool Function(int table)? tableExists,
    bool Function(int table)? tableActive,
  }) {
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
    final exists = tableExists == null
        ? table >= 1 && table <= maxTable
        : table >= 1 && tableExists(table);
    if (!exists) return const InvalidTableQr(TableQrError.invalidTable);
    if (tableActive != null && !tableActive(table)) {
      return const InvalidTableQr(TableQrError.tableInactive);
    }
    return ValidTableQr(table);
  }

  static String payloadFor(int table) =>
      '$prefix${table.toString().padLeft(2, '0')}';
}
