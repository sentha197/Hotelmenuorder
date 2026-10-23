import '../models/order_type.dart';

enum TableQrError {
  empty('No QR code content was found.'),
  unrecognized('This is not a DineQR code.'),
  invalidTable('This QR code points to a table that does not exist.'),
  tableInactive(
    'This table is not taking orders right now. Please ask a staff member.',
  ),
  parcelUnavailable(
    'Parcel orders are not being taken right now. Please ask a staff member.',
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

/// The restaurant's single parcel code: an order to collect, with no table.
final class ValidParcelQr extends TableQrResult {
  const ValidParcelQr();
}

final class InvalidTableQr extends TableQrResult {
  const InvalidTableQr(this.error);

  final TableQrError error;
}

/// Parses DineQR QR payloads:
///
/// - `DINEQR:TABLE:05` — order for table 5 (dine-in);
/// - `DINEQR:PARCEL` — order to collect, no table.
///
/// A QR code only says where an order is placed. It never grants access to
/// anything else (staff sign-in is separate), and in production the backend
/// must check the table, and that parcel orders are open, again when an
/// order is submitted.
abstract final class TableQrParser {
  static const prefix = 'DINEQR:TABLE:';

  /// The one parcel code. It carries no table, so every parcel guest scans
  /// the same code and no duplicate codes can be generated.
  static const parcelPayload = 'DINEQR:PARCEL';

  /// Codes printed before the DineQR rename keep working.
  static const legacyPrefixes = ['BITEANDDINE:TABLE:'];
  static const legacyParcelPayloads = ['BITEANDDINE:PARCEL'];

  /// Without restaurant configuration, tables are numbered 1 to [maxTable].
  static const maxTable = 30;

  static final RegExp _digits = RegExp(r'^\d{1,3}$');

  /// [tableExists] and [tableActive] check the number against the
  /// restaurant's configured tables when they are known. [parcelEnabled]
  /// says whether the restaurant is taking parcel orders; it defaults to
  /// false so a parcel code is refused unless the setting says otherwise.
  static TableQrResult parse(
    String? raw, {
    bool Function(int table)? tableExists,
    bool Function(int table)? tableActive,
    bool parcelEnabled = false,
  }) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return const InvalidTableQr(TableQrError.empty);
    final upper = value.toUpperCase();

    if (upper == parcelPayload || legacyParcelPayloads.contains(upper)) {
      return parcelEnabled
          ? const ValidParcelQr()
          : const InvalidTableQr(TableQrError.parcelUnavailable);
    }

    final matched = [prefix, ...legacyPrefixes].where(upper.startsWith);
    if (matched.isEmpty) {
      return const InvalidTableQr(TableQrError.unrecognized);
    }
    final tablePart = value.substring(matched.first.length).trim();
    if (!_digits.hasMatch(tablePart)) {
      return const InvalidTableQr(TableQrError.unrecognized);
    }
    final table = int.parse(tablePart);
    // Table zero is the parcel sentinel, never a real table a code can name.
    if (OrderTables.isParcel(table)) {
      return const InvalidTableQr(TableQrError.invalidTable);
    }
    final exists = tableExists == null
        ? table >= 1 && table <= maxTable
        : table >= 1 && tableExists(table);
    if (!exists) return const InvalidTableQr(TableQrError.invalidTable);
    if (tableActive != null && !tableActive(table)) {
      return const InvalidTableQr(TableQrError.tableInactive);
    }
    return ValidTableQr(table);
  }

  static String payloadFor(int table) => OrderTables.isParcel(table)
      ? parcelPayload
      : '$prefix${table.toString().padLeft(2, '0')}';
}
