import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

/// The guest's ordering session: the table they are seated at, or a
/// takeaway order with no table (stored as [OrderTables.takeaway]).
class SessionController extends ChangeNotifier {
  SessionController(
    this._store, {
    DateTime Function()? clock,
    this._onStart,
    this._hasServerSession,
  }) : _clock = clock ?? DateTime.now,
       _tableNumber = int.tryParse(_store.read(StorageKeys.table) ?? ''),
       _since = DateTime.tryParse(_store.read(StorageKeys.tableSince) ?? '');

  /// How long a scanned table is remembered when the app is reopened. A
  /// meal rarely lasts longer; after that the guest scans again, so a phone
  /// never quietly orders for yesterday's table.
  static const resumeWindow = Duration(hours: 4);

  final KeyValueStore _store;
  final DateTime Function() _clock;

  /// Backend mode: obtains the server's guest session for a table before it
  /// is used. Throws [ApiException] when the server refuses the table.
  final Future<void> Function(int table)? _onStart;

  /// Backend mode: whether the server session is still valid.
  final bool Function()? _hasServerSession;

  int? _tableNumber;
  DateTime? _since;

  int? get tableNumber => _tableNumber;

  /// Whether an ordering session has started at all (a table or takeaway).
  bool get hasTable => _tableNumber != null;

  /// Whether this session is a takeaway order rather than a seated one.
  bool get isTakeaway =>
      _tableNumber != null && OrderTables.isTakeaway(_tableNumber!);

  /// `Table 05`, `Takeaway`, or an empty string before a code is scanned.
  String get tableLabel =>
      _tableNumber == null ? '' : OrderTables.label(_tableNumber!);

  /// The table to resume when the app opens: only a session started within
  /// [resumeWindow] (and, with the API, whose server session is still
  /// valid). Sessions saved before start times were recorded are not
  /// resumed automatically (the scanner still offers them).
  int? get resumableTable {
    final table = _tableNumber;
    final since = _since;
    if (table == null || since == null) return null;
    if (_hasServerSession != null && !_hasServerSession()) return null;
    final age = _clock().difference(since);
    return age.isNegative || age > resumeWindow ? null : table;
  }

  Future<void> startSession(int tableNumber) async {
    await _onStart?.call(tableNumber);
    _tableNumber = tableNumber;
    _since = _clock();
    notifyListeners();
    await _store.write(StorageKeys.table, '$tableNumber');
    await _store.write(StorageKeys.tableSince, _since!.toIso8601String());
  }

  Future<void> clear() async {
    _tableNumber = null;
    _since = null;
    notifyListeners();
    await _store.delete(StorageKeys.table);
    await _store.delete(StorageKeys.tableSince);
  }
}
