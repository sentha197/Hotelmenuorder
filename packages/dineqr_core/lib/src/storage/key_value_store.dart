import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal persistence abstraction so state classes stay testable.
abstract interface class KeyValueStore {
  String? read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SharedPrefsStore implements KeyValueStore {
  SharedPrefsStore._(this._prefs);

  static Future<SharedPrefsStore> create() async =>
      SharedPrefsStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> delete(String key) => _prefs.remove(key);
}

/// In-memory store used in tests and as a fallback when device storage is
/// unavailable.
class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// A JSON list stored under one key. Corrupt data reads as `null` so it can
/// never brick the app.
class JsonListStore<T> {
  const JsonListStore(this._store, this.key, this._fromJson, this._toJson);

  final KeyValueStore _store;
  final String key;
  final T Function(Map<String, dynamic> json) _fromJson;
  final Map<String, dynamic> Function(T value) _toJson;

  /// The stored list, or null when nothing (valid) is stored.
  List<T>? read() {
    final raw = _store.read(key);
    if (raw == null) return null;
    try {
      return [
        for (final json in jsonDecode(raw) as List)
          _fromJson(json as Map<String, dynamic>),
      ];
    } on Object {
      return null;
    }
  }

  Future<void> write(Iterable<T> values) =>
      _store.write(key, jsonEncode([for (final v in values) _toJson(v)]));

  Future<void> clear() => _store.delete(key);
}

abstract final class StorageKeys {
  static const table = 'session.table';
  static const tableSince = 'session.tableSince';
  static const cart = 'cart.lines';
  static const instructions = 'cart.instructions';
  static const offer = 'cart.offer';
  static const favorites = 'menu.favorites';
  static const orders = 'orders.history';
  static const menuItems = 'menu.items';
  static const menuCategories = 'menu.categories';
  static const promotions = 'menu.promotions';
  static const settings = 'restaurant.settings';
  static const tables = 'restaurant.tables';
  static const invoices = 'billing.invoices';
  static const staff = 'admin.staff';
  static const adminSession = 'admin.session';
  static const audit = 'admin.audit';
  static const inventory = 'inventory.items';
  static const stockMovements = 'inventory.movements';
}
