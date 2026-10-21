import 'dart:convert';

import '../../core/utils/restaurant_time.dart';
import '../models/restaurant_settings.dart';
import '../storage/key_value_store.dart';

/// Restaurant configuration and tables. A production backend would persist
/// these centrally and authorise every write.
abstract interface class SettingsRepository {
  Future<RestaurantSettings> fetchSettings();

  Future<void> saveSettings(RestaurantSettings settings);

  Future<List<RestaurantTable>> fetchTables();

  Future<void> saveTables(List<RestaurantTable> tables);

  Future<void> reset();
}

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._store, {this.defaultTableCount = 30})
    : _tables = JsonListStore(
        _store,
        StorageKeys.tables,
        RestaurantTable.fromJson,
        (t) => t.toJson(),
      );

  final KeyValueStore _store;
  final JsonListStore<RestaurantTable> _tables;

  /// Tables of a fresh install: 1 to [defaultTableCount].
  final int defaultTableCount;

  /// Fresh-install settings use the device's time zone.
  static RestaurantSettings get defaults => const RestaurantSettings().copyWith(
    utcOffsetMinutes: RestaurantTime.deviceOffsetMinutes,
  );

  @override
  Future<RestaurantSettings> fetchSettings() async {
    final raw = _store.read(StorageKeys.settings);
    if (raw == null) return defaults;
    try {
      return RestaurantSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return defaults;
    }
  }

  @override
  Future<void> saveSettings(RestaurantSettings settings) =>
      _store.write(StorageKeys.settings, jsonEncode(settings.toJson()));

  @override
  Future<List<RestaurantTable>> fetchTables() async =>
      _tables.read() ??
      [
        for (var n = 1; n <= defaultTableCount; n++)
          RestaurantTable(
            number: n,
            seats: n % 3 == 0 ? 6 : (n.isEven ? 4 : 2),
            area: n > 24 ? 'Terrace' : '',
          ),
      ];

  @override
  Future<void> saveTables(List<RestaurantTable> tables) =>
      _tables.write([...tables]..sort((a, b) => a.number.compareTo(b.number)));

  @override
  Future<void> reset() async {
    await _store.delete(StorageKeys.settings);
    await _tables.clear();
  }
}
