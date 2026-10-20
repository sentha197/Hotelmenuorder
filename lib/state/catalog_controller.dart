import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models/menu_filter.dart';
import '../data/models/menu_item.dart';
import '../data/repositories/menu_repository.dart';
import '../data/storage/key_value_store.dart';

enum LoadState { loading, ready, error }

/// Menu catalogue and the guest's favourite dishes.
class CatalogController extends ChangeNotifier {
  CatalogController(this._repository, this._store) {
    final raw = _store.read(StorageKeys.favorites);
    if (raw != null) {
      try {
        _favorites = (jsonDecode(raw) as List).cast<String>().toSet();
      } on Object {
        _favorites = {};
      }
    }
  }

  final MenuRepository _repository;
  final KeyValueStore _store;

  LoadState _state = LoadState.loading;
  List<MenuItem> _items = const [];
  Set<String> _favorites = {};
  Future<void>? _pending;

  LoadState get state => _state;

  List<MenuItem> get items => _items;

  Set<String> get favorites => Set.unmodifiable(_favorites);

  List<MenuItem> get popular =>
      _items.where((item) => item.isPopular).toList(growable: false);

  List<MenuItem> get chefSpecials =>
      _items.where((item) => item.isChefSpecial).toList(growable: false);

  List<MenuItem> get favoriteItems => _items
      .where((item) => _favorites.contains(item.id))
      .toList(growable: false);

  /// Loads the menu once; concurrent callers share the same request.
  Future<void> load({bool force = false}) {
    if (!force && _state == LoadState.ready) return Future.value();
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  Future<void> _fetch() async {
    _state = LoadState.loading;
    notifyListeners();
    try {
      _items = await _repository.fetchMenu();
      _state = LoadState.ready;
    } on Object {
      _state = LoadState.error;
    }
    notifyListeners();
  }

  MenuItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<MenuItem> filter(MenuFilter filter) =>
      filter.apply(_items, favorites: _favorites);

  int countIn(MenuCategory? category) => category == null
      ? _items.length
      : _items.where((item) => item.category == category).length;

  bool isFavorite(String itemId) => _favorites.contains(itemId);

  /// Returns the new favourite state.
  bool toggleFavorite(String itemId) {
    final added = !_favorites.remove(itemId);
    if (added) _favorites.add(itemId);
    notifyListeners();
    _persist();
    return added;
  }

  Future<void> clearFavorites() async {
    _favorites = {};
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() =>
      _store.write(StorageKeys.favorites, jsonEncode(_favorites.toList()));
}
