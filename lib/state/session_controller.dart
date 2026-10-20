import 'package:flutter/foundation.dart';

import '../core/utils/formatters.dart';
import '../data/storage/key_value_store.dart';

/// The guest's dining session: which table they are ordering from.
class SessionController extends ChangeNotifier {
  SessionController(this._store)
    : _tableNumber = int.tryParse(_store.read(StorageKeys.table) ?? '');

  final KeyValueStore _store;
  int? _tableNumber;

  int? get tableNumber => _tableNumber;

  bool get hasTable => _tableNumber != null;

  /// `Table 05`, or an empty string when no table is selected.
  String get tableLabel =>
      _tableNumber == null ? '' : 'Table ${AppFormat.table(_tableNumber!)}';

  Future<void> startSession(int tableNumber) async {
    _tableNumber = tableNumber;
    notifyListeners();
    await _store.write(StorageKeys.table, '$tableNumber');
  }

  Future<void> clear() async {
    _tableNumber = null;
    notifyListeners();
    await _store.delete(StorageKeys.table);
  }
}
