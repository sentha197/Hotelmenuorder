import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

/// The tables each staff member is covering, saved on this device.
///
/// This is a personal working filter for the Service board, not a
/// restaurant-wide assignment: any server may still serve any table. With a
/// backend, section assignments would come from the server so the whole
/// team sees them (see docs/BACKEND_INTEGRATION.md).
class ServiceSectionController extends ChangeNotifier {
  ServiceSectionController(this._store) : _sections = _read(_store);

  static const storageKey = 'admin.serviceSections';

  final KeyValueStore _store;
  final Map<String, Set<int>> _sections;

  static Map<String, Set<int>> _read(KeyValueStore store) {
    final raw = store.read(storageKey);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final MapEntry(:key, :value) in json.entries)
          key: {for (final n in value as List) n as int},
      };
    } on Object {
      // A damaged preference is not worth an error; start over.
      return {};
    }
  }

  /// The tables [staffId] covers; empty means "all tables".
  Set<int> tablesFor(String staffId) =>
      Set.unmodifiable(_sections[staffId] ?? const <int>{});

  Future<void> setTables(String staffId, Set<int> tables) async {
    if (tables.isEmpty) {
      _sections.remove(staffId);
    } else {
      _sections[staffId] = {...tables};
    }
    notifyListeners();
    await _store.write(
      storageKey,
      jsonEncode({
        for (final MapEntry(:key, :value) in _sections.entries)
          key: value.toList()..sort(),
      }),
    );
  }
}
