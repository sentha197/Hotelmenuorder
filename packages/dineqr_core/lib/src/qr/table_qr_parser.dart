import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/order_type.dart';

enum TableQrError {
  empty('No QR code content was found.'),
  unrecognized('This is not a DineQR code.'),
  invalidTable('This QR code points to a table that does not exist.'),
  tableInactive(
    'This table is not taking orders right now. Please ask a staff member.',
  ),
  takeawayUnavailable(
    'Takeaway orders are not being taken right now. Please ask a staff member.',
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

/// The restaurant's single takeaway code: an order to collect, with no
/// table.
final class ValidTakeawayQr extends TableQrResult {
  const ValidTakeawayQr();
}

final class InvalidTableQr extends TableQrResult {
  const InvalidTableQr(this.error);

  final TableQrError error;
}

/// Parses DineQR QR payloads:
///
/// - `DINEQR:TABLE:05` — order for table 5 (dine-in);
/// - `DINEQR:TAKEAWAY` — order to collect, no table;
/// - with [webBase] set, the same codes as links to the DineQR web app,
///   `<webBase>/t/05` and `<webBase>/takeaway`, which a phone camera or
///   Google Lens opens in the browser.
///
/// A QR code only says where an order is placed. It never grants access to
/// anything else (staff sign-in is separate), and in production the backend
/// must check the table, and that takeaway orders are open, again when an
/// order is submitted. A link is only read for its table, and only from the
/// configured web app; it is never opened.
abstract final class TableQrParser {
  static const prefix = 'DINEQR:TABLE:';

  /// Where the DineQR web app is served, from
  /// `--dart-define=DINEQR_WEB_URL=https://order.example.com`. When set,
  /// printed codes are links to it ([codeFor]) and such links are accepted;
  /// unset, codes stay the plain payloads above. See [webBaseFor] for the
  /// default.
  static final Uri? webBase = webBaseFor(
    const String.fromEnvironment('DINEQR_WEB_URL'),
    apiDefine: const String.fromEnvironment('DINEQR_API_URL'),
    debug: kDebugMode,
  );

  /// The web app address for these defines. Without [webDefine], a profile
  /// or release build on the deployed API ([ApiConfig.productionUrl], no
  /// `DINEQR_API_URL`) uses that same host, which serves the web app, so a
  /// plain `flutter build` prints codes a phone camera opens. A debug build,
  /// or one on another API, keeps the plain payloads.
  @visibleForTesting
  static Uri? webBaseFor(
    String webDefine, {
    required String apiDefine,
    required bool debug,
  }) {
    final given = webBaseFrom(webDefine);
    if (given != null) return given;
    if (debug || apiDefine.trim().isNotEmpty) return null;
    return webBaseFrom(ApiConfig.productionUrl.toString());
  }

  /// [value] as a web app address, or null when it is not an absolute
  /// http(s) URL with a host.
  static Uri? webBaseFrom(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.isAbsolute ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    // Scheme, host, port and path only: no query or fragment.
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
    );
  }

  /// The web app link for [table] (or takeaway), e.g. `https://site/t/05`.
  static String linkFor(int table, Uri base) {
    final root = base.toString().replaceFirst(RegExp(r'/+$'), '');
    return OrderTables.isTakeaway(table)
        ? '$root/takeaway'
        : '$root/t/${table.toString().padLeft(2, '0')}';
  }

  /// What a table's printed code holds: its web link when [webBase] is
  /// set, otherwise its payload.
  static String codeFor(int table) {
    final base = webBase;
    return base == null ? payloadFor(table) : linkFor(table, base);
  }

  static final RegExp _linkTable = RegExp(
    r'^/t/(\d{1,3})/?$',
    caseSensitive: false,
  );
  static final RegExp _linkTakeaway = RegExp(
    r'^/takeaway/?$',
    caseSensitive: false,
  );

  /// The payload a link from one of [bases] stands for; an empty string for
  /// a link that is not one of them (or not a table link); null when
  /// [value] is not a link at all.
  static String? _payloadOfLink(String value, Iterable<Uri> bases) {
    if (!RegExp(
      r'^[a-z][a-z0-9+.-]*://',
      caseSensitive: false,
    ).hasMatch(value)) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return '';
    for (final base in bases) {
      if (uri.scheme != base.scheme ||
          uri.host.toLowerCase() != base.host.toLowerCase() ||
          uri.port != base.port) {
        continue;
      }
      final root = base.path.toLowerCase();
      var path = uri.path;
      if (root.isNotEmpty) {
        if (!path.toLowerCase().startsWith('$root/')) continue;
        path = path.substring(root.length);
      }
      final table = _linkTable.firstMatch(path);
      if (table != null) return '$prefix${table.group(1)}';
      if (_linkTakeaway.hasMatch(path)) return takeawayPayload;
    }
    return '';
  }

  /// The one takeaway code. It carries no table, so every takeaway guest
  /// scans the same code and no duplicate codes can be generated.
  static const takeawayPayload = 'DINEQR:TAKEAWAY';

  /// Codes printed before the DineQR rename keep working.
  static const legacyPrefixes = ['BITEANDDINE:TABLE:'];

  /// Takeaway codes printed while takeaway was called "parcel" (and before
  /// the DineQR rename) keep working.
  static const legacyTakeawayPayloads = ['DINEQR:PARCEL', 'BITEANDDINE:PARCEL'];

  /// Without restaurant configuration, tables are numbered 1 to [maxTable].
  static const maxTable = 30;

  static final RegExp _digits = RegExp(r'^\d{1,3}$');

  /// [tableExists] and [tableActive] check the number against the
  /// restaurant's configured tables when they are known. [takeawayEnabled]
  /// says whether the restaurant is taking takeaway orders; it defaults to
  /// false so a takeaway code is refused unless the setting says otherwise.
  /// [webBases] are the web app addresses whose links are accepted (by
  /// default [webBase], when set).
  static TableQrResult parse(
    String? raw, {
    bool Function(int table)? tableExists,
    bool Function(int table)? tableActive,
    bool takeawayEnabled = false,
    Iterable<Uri>? webBases,
  }) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty) return const InvalidTableQr(TableQrError.empty);
    final fromLink = _payloadOfLink(value, webBases ?? [?webBase]);
    if (fromLink != null) {
      if (fromLink.isEmpty) {
        return const InvalidTableQr(TableQrError.unrecognized);
      }
      value = fromLink;
    }
    final upper = value.toUpperCase();

    if (upper == takeawayPayload || legacyTakeawayPayloads.contains(upper)) {
      return takeawayEnabled
          ? const ValidTakeawayQr()
          : const InvalidTableQr(TableQrError.takeawayUnavailable);
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
    // Table zero is the takeaway sentinel, never a real table a code can
    // name.
    if (OrderTables.isTakeaway(table)) {
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

  static String payloadFor(int table) => OrderTables.isTakeaway(table)
      ? takeawayPayload
      : '$prefix${table.toString().padLeft(2, '0')}';
}
