import 'dart:convert';

import '../models/discount_offer.dart';
import '../models/restaurant_settings.dart';
import '../storage/key_value_store.dart';
import '../utils/restaurant_time.dart';

/// Restaurant configuration and tables. A production backend would persist
/// these centrally and authorise every write.
abstract interface class SettingsRepository {
  Future<RestaurantSettings> fetchSettings();

  /// Saves the settings. Coupons are saved on their own (below).
  Future<void> saveSettings(RestaurantSettings settings);

  /// Creates a coupon, or updates [originalCode] (possibly renaming it).
  /// Returns it as saved: its usage count is the restaurant's, never the
  /// app's.
  Future<DiscountOffer> saveOffer(DiscountOffer offer, {String? originalCode});

  Future<DiscountOffer> setOfferActive(String code, bool active);

  Future<void> deleteOffer(String code);

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

  /// Fresh-install settings use the device's time zone. The offline demo
  /// takes takeaway orders so both ordering modes can be tried; a real
  /// backend starts with them closed until an owner opens them.
  static RestaurantSettings get defaults => const RestaurantSettings().copyWith(
    utcOffsetMinutes: RestaurantTime.deviceOffsetMinutes,
    takeawayOrdersEnabled: true,
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
  Future<void> saveSettings(RestaurantSettings settings) async {
    // Coupons are kept as they are stored.
    final stored = await fetchSettings();
    await _write(settings.copyWith(offers: stored.offers));
  }

  Future<void> _write(RestaurantSettings settings) =>
      _store.write(StorageKeys.settings, jsonEncode(settings.toJson()));

  @override
  Future<DiscountOffer> saveOffer(
    DiscountOffer offer, {
    String? originalCode,
  }) async {
    final settings = await fetchSettings();
    final key = originalCode ?? offer.code;
    final previous = settings.offerByCode(key);
    final saved = offer.copyWith(usedCount: previous?.usedCount ?? 0);
    await _write(
      settings.copyWith(
        offers: previous == null
            ? [...settings.offers, saved]
            : [for (final o in settings.offers) o.code == key ? saved : o],
      ),
    );
    return saved;
  }

  @override
  Future<DiscountOffer> setOfferActive(String code, bool active) async {
    final settings = await fetchSettings();
    final offer = settings.offerByCode(code)!.copyWith(isActive: active);
    await _write(
      settings.copyWith(
        offers: [for (final o in settings.offers) o.code == code ? offer : o],
      ),
    );
    return offer;
  }

  @override
  Future<void> deleteOffer(String code) async {
    final settings = await fetchSettings();
    await _write(
      settings.copyWith(
        offers: [
          for (final o in settings.offers)
            if (o.code != code) o,
        ],
      ),
    );
  }

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
