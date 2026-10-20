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

abstract final class StorageKeys {
  static const table = 'session.table';
  static const cart = 'cart.lines';
  static const instructions = 'cart.instructions';
  static const favorites = 'menu.favorites';
  static const orders = 'orders.history';
}
