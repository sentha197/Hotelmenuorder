import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

/// The guest's dining session: which table they are ordering from.
class SessionController extends ChangeNotifier {
  SessionController(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _tableNumber = int.tryParse(_store.read(StorageKeys.table) ?? ''),
      _since = DateTime.tryParse(_store.read(StorageKeys.tableSince) ?? '');

  /// How long a scanned table is remembered when the app is reopened. A
  /// meal rarely lasts longer; after that the guest scans again, so a phone
  /// never quietly orders for yesterday's table.
  static const resumeWindow = Duration(hours: 4);

  final KeyValueStore _store;
  final DateTime Function() _clock;
  int? _tableNumber;
  DateTime? _since;

  int? get tableNumber => _tableNumber;

  bool get hasTable => _tableNumber != null;

  /// `Table 05`, or an empty string when no table is selected.
  String get tableLabel =>
      _tableNumber == null ? '' : 'Table ${AppFormat.table(_tableNumber!)}';

  /// The table to resume when the app opens: only a session started within
  /// [resumeWindow]. Sessions saved before start times were recorded are
  /// not resumed automatically (the scanner still offers them).
  int? get resumableTable {
    final table = _tableNumber;
    final since = _since;
    if (table == null || since == null) return null;
    final age = _clock().difference(since);
    return age.isNegative || age > resumeWindow ? null : table;
  }

  Future<void> startSession(int tableNumber) async {
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
