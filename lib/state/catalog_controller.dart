import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/utils/currency.dart';
import '../data/models/menu_filter.dart';
import '../data/models/menu_item.dart';
import '../data/models/staff.dart';
import '../data/repositories/menu_repository.dart';
import '../data/storage/key_value_store.dart';
import 'admin_session_controller.dart';
import 'settings_controller.dart';

enum LoadState { loading, ready, error }

/// Menu catalogue (guest view and admin editing) and the guest's favourites.
class CatalogController extends ChangeNotifier {
  CatalogController(
    this._repository,
    this._store, {
    this._guard,
    this._audit,
    bool Function()? showSoldOut,
  }) : _showSoldOut = showSoldOut ?? (() => true) {
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
  final AccessGuard? _guard;
  final AuditLog? _audit;
  final bool Function() _showSoldOut;

  LoadState _state = LoadState.loading;
  List<MenuItem> _all = const [];
  List<MenuCategory> _categories = const [];
  Set<String> _favorites = {};
  Future<void>? _pending;

  LoadState get state => _state;

  /// Dishes guests can see: not archived, in an active category, and (unless
  /// sold-out dishes are hidden) also those that are temporarily sold out.
  List<MenuItem> get items => [
    for (final item in _all)
      if (!item.isArchived &&
          item.category.isActive &&
          (item.isAvailable || _showSoldOut()))
        item,
  ];

  /// Every dish, including archived ones (admin).
  List<MenuItem> get allItems => _all;

  /// Active categories in display order (guest view).
  List<MenuCategory> get categories => [
    for (final c in _categories)
      if (c.isActive) c,
  ];

  /// All categories in display order (admin).
  List<MenuCategory> get allCategories => _categories;

  Set<String> get favorites => Set.unmodifiable(_favorites);

  List<MenuItem> get popular =>
      items.where((item) => item.isPopular).toList(growable: false);

  List<MenuItem> get chefSpecials =>
      items.where((item) => item.isChefSpecial).toList(growable: false);

  /// Highly rated dishes not already featured as popular (nor, when there
  /// are enough others, as chef's specials).
  List<MenuItem> get recommended {
    final orderable = items.where((i) => i.isOrderable && !i.isPopular);
    final fresh = orderable.where((i) => !i.isChefSpecial).toList();
    final candidates = (fresh.length >= 3 ? fresh : orderable.toList())
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return candidates.take(6).toList(growable: false);
  }

  List<MenuItem> get favoriteItems => items
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
      _categories = await _repository.fetchCategories();
      _all = await _repository.fetchMenu();
      _state = LoadState.ready;
    } on Object {
      _state = LoadState.error;
    }
    notifyListeners();
  }

  /// Settings that change what guests see were updated.
  void refreshVisibility() => notifyListeners();

  MenuItem? byId(String id) {
    for (final item in _all) {
      if (item.id == id) return item;
    }
    return null;
  }

  MenuCategory? categoryById(String id) =>
      _categories.where((c) => c.id == id).firstOrNull;

  List<MenuItem> filter(MenuFilter filter) =>
      filter.apply(items, favorites: _favorites);

  int countIn(MenuCategory? category) => category == null
      ? items.length
      : items.where((item) => item.category == category).length;

  /// Non-archived dishes in a category (admin).
  int dishCountIn(String categoryId) => _all
      .where((item) => !item.isArchived && item.category.id == categoryId)
      .length;

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

  // ------------------------------------------------------------ admin: dishes

  static const bundledImages = [
    'assets/images/affogato.jpg',
    'assets/images/butter_chicken.jpg',
    'assets/images/butter_naan.jpg',
    'assets/images/chicken_65.jpg',
    'assets/images/chicken_biryani.jpg',
    'assets/images/chilli_chicken.jpg',
    'assets/images/cold_coffee.jpg',
    'assets/images/dal_makhani.jpg',
    'assets/images/french_fries.jpg',
    'assets/images/fresh_lime_soda.jpg',
    'assets/images/gulab_jamun.jpg',
    'assets/images/lassi.jpg',
    'assets/images/masala_dosa.jpg',
    'assets/images/paneer_butter_masala.jpg',
    'assets/images/paneer_tikka.jpg',
    'assets/images/rasmalai.jpg',
    'assets/images/samosa.jpg',
    'assets/images/spring_roll.jpg',
    'assets/images/tandoori_chicken.jpg',
    'assets/images/veg_biryani.jpg',
    'assets/images/veg_manchurian.jpg',
  ];

  /// Returns a message for the first invalid field, or null.
  String? validateItem(MenuItem item) {
    final name = item.name.trim();
    if (name.length < 2 || name.length > 40) {
      return 'Dish name must be 2 to 40 characters.';
    }
    final duplicate = _all.any(
      (other) =>
          other.id != item.id &&
          !other.isArchived &&
          other.name.trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) return 'Another dish is already called "$name".';
    if (item.shortDescription.trim().length > 60) {
      return 'Short description can be at most 60 characters.';
    }
    if (item.description.trim().length > 400) {
      return 'Description can be at most 400 characters.';
    }
    if (item.price.paise < 100 || item.price.paise > 10000000) {
      return 'Price must be between ₹1 and ₹1,00,000.';
    }
    if (item.prepMinutes < 1 || item.prepMinutes > 180) {
      return 'Preparation time must be 1 to 180 minutes.';
    }
    if (categoryById(item.category.id) == null) {
      return 'Choose a category.';
    }
    final portionIds = <String>{};
    for (final portion in item.portions) {
      if (portion.label.trim().isEmpty) return 'Every portion needs a name.';
      if (!portionIds.add(portion.id)) return 'Portion names must be unique.';
      if (portion.extraPrice.paise < 0) {
        return 'Portion surcharges cannot be negative.';
      }
    }
    final addOnIds = <String>{};
    for (final addOn in item.addOns) {
      if (addOn.name.trim().isEmpty) return 'Every add-on needs a name.';
      if (!addOnIds.add(addOn.id)) return 'Add-on names must be unique.';
      if (addOn.price.paise < 0 || addOn.price.paise > 1000000) {
        return 'Add-on prices must be between ₹0 and ₹10,000.';
      }
    }
    if (item.image.isNotEmpty && !bundledImages.contains(item.image)) {
      return 'Choose one of the available photos.';
    }
    return null;
  }

  /// A unique id derived from [name], e.g. `paneer_roll`.
  String newItemId(String name) =>
      _uniqueId(name, _all.map((i) => i.id).toSet(), fallback: 'dish');

  static String _uniqueId(
    String name,
    Set<String> taken, {
    required String fallback,
  }) {
    var base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty) base = fallback;
    var id = base;
    var n = 2;
    while (taken.contains(id)) {
      id = '${base}_${n++}';
    }
    return id;
  }

  /// Option ids from labels, used by the dish editor.
  static String optionId(String label, Set<String> taken) =>
      _uniqueId(label, taken, fallback: 'option');

  Future<void> saveItem(MenuItem item) async {
    _require(Permission.manageMenu);
    final error = validateItem(item);
    if (error != null) throw ValidationException(error);
    final previous = byId(item.id);
    final saved = item.copyWith(
      name: item.name.trim(),
      shortDescription: item.shortDescription.trim(),
      description: item.description.trim(),
      category: categoryById(item.category.id),
    );
    await _repository.saveItem(saved);
    _replaceItem(saved);
    await _audit?.record(
      previous == null ? 'menu.create' : 'menu.update',
      previous == null
          ? 'Added dish ${saved.name} (${CurrencyFormatter.format(saved.price)})'
          : _describeItemChange(previous, saved),
      targetId: saved.id,
    );
  }

  static String _describeItemChange(MenuItem a, MenuItem b) {
    final changes = [
      if (a.price != b.price)
        'price ${CurrencyFormatter.format(a.price)} → '
            '${CurrencyFormatter.format(b.price)}',
      if (a.name != b.name) 'name',
      if (a.category.id != b.category.id) 'category',
      if (a.isVeg != b.isVeg) b.isVeg ? 'marked veg' : 'marked non-veg',
      if (a.description != b.description ||
          a.shortDescription != b.shortDescription)
        'description',
      if (a.addOns.length != b.addOns.length) 'add-ons',
      if (a.portions.length != b.portions.length) 'portions',
      if (a.isAvailable != b.isAvailable)
        b.isAvailable ? 'available' : 'sold out',
      if (a.image != b.image) 'photo',
    ];
    return 'Updated ${b.name}'
        '${changes.isEmpty ? '' : ': ${changes.join(', ')}'}';
  }

  /// [system] is used by automatic stock rules (still audited).
  Future<void> setAvailable(
    String itemId,
    bool available, {
    bool system = false,
    String reason = '',
  }) async {
    if (!system) _require(Permission.manageMenu);
    final item = byId(itemId);
    if (item == null || item.isAvailable == available) return;
    final saved = item.copyWith(isAvailable: available);
    await _repository.saveItem(saved);
    _replaceItem(saved);
    await _audit?.record(
      'menu.availability',
      '${available ? 'Marked available' : 'Marked sold out'}: ${item.name}'
          '${reason.isEmpty ? '' : ' ($reason)'}',
      targetId: itemId,
    );
  }

  Future<void> setArchived(String itemId, bool archived) async {
    _require(Permission.manageMenu);
    final item = byId(itemId);
    if (item == null || item.isArchived == archived) return;
    final saved = item.copyWith(isArchived: archived);
    await _repository.saveItem(saved);
    _replaceItem(saved);
    await _audit?.record(
      archived ? 'menu.archive' : 'menu.restore',
      '${archived ? 'Archived' : 'Restored'} ${item.name}',
      targetId: itemId,
    );
  }

  void _replaceItem(MenuItem saved) {
    final exists = _all.any((i) => i.id == saved.id);
    _all = exists
        ? [for (final i in _all) i.id == saved.id ? saved : i]
        : [..._all, saved];
    notifyListeners();
  }

  // -------------------------------------------------------- admin: categories

  String? validateCategory(MenuCategory category) {
    final label = category.label.trim();
    if (label.length < 2 || label.length > 24) {
      return 'Category name must be 2 to 24 characters.';
    }
    final duplicate = _categories.any(
      (c) =>
          c.id != category.id &&
          c.label.trim().toLowerCase() == label.toLowerCase(),
    );
    if (duplicate) return 'A category called "$label" already exists.';
    if (category.coverImage.isNotEmpty &&
        !bundledImages.contains(category.coverImage)) {
      return 'Choose one of the available photos.';
    }
    return null;
  }

  String newCategoryId(String label) => _uniqueId(
    label,
    _categories.map((c) => c.id).toSet(),
    fallback: 'category',
  );

  Future<void> saveCategory(MenuCategory category) async {
    _require(Permission.manageCategories);
    final error = validateCategory(category);
    if (error != null) throw ValidationException(error);
    final exists = _categories.any((c) => c.id == category.id);
    final saved = category.copyWith(
      label: category.label.trim(),
      sortOrder: exists ? category.sortOrder : _categories.length,
    );
    await _saveCategories(
      exists
          ? [for (final c in _categories) c.id == saved.id ? saved : c]
          : [..._categories, saved],
    );
    await _audit?.record(
      exists ? 'category.update' : 'category.create',
      '${exists ? 'Updated' : 'Added'} category ${saved.label}',
      targetId: saved.id,
    );
  }

  Future<void> setCategoryActive(String id, bool active) async {
    _require(Permission.manageCategories);
    final category = categoryById(id);
    if (category == null) return;
    await _saveCategories([
      for (final c in _categories)
        c.id == id ? c.copyWith(isActive: active) : c,
    ]);
    await _audit?.record(
      'category.toggle',
      '${active ? 'Showed' : 'Hid'} category ${category.label}',
      targetId: id,
    );
  }

  /// Applies a new display order (ids from first to last).
  Future<void> reorderCategories(List<String> orderedIds) async {
    _require(Permission.manageCategories);
    final byId = {for (final c in _categories) c.id: c};
    if (orderedIds.toSet().length != byId.length ||
        !orderedIds.every(byId.containsKey)) {
      throw const ValidationException('The category list changed. Try again.');
    }
    await _saveCategories([
      for (final (index, id) in orderedIds.indexed)
        byId[id]!.copyWith(sortOrder: index),
    ]);
    await _audit?.record('category.reorder', 'Reordered categories');
  }

  /// Only empty categories can be deleted; dishes must be moved first.
  Future<void> deleteCategory(String id) async {
    _require(Permission.manageCategories);
    final category = categoryById(id);
    if (category == null) return;
    final used = _all.where((item) => item.category.id == id).length;
    if (used > 0) {
      throw ValidationException(
        '${category.label} still has $used '
        '${used == 1 ? 'dish' : 'dishes'} (including archived). '
        'Move them to another category first.',
      );
    }
    await _saveCategories([
      for (final (index, c) in _categories.where((c) => c.id != id).indexed)
        c.copyWith(sortOrder: index),
    ]);
    await _audit?.record(
      'category.delete',
      'Deleted category ${category.label}',
      targetId: id,
    );
  }

  Future<void> _saveCategories(List<MenuCategory> categories) async {
    await _repository.saveCategories(categories);
    _categories = await _repository.fetchCategories();
    _all = await _repository.fetchMenu();
    notifyListeners();
  }

  /// Restores the original menu (demo reset).
  Future<void> resetMenu() async {
    await _repository.reset();
    await load(force: true);
  }

  void _require(Permission permission) {
    final guard = _guard;
    if (guard == null) {
      throw StateError('Admin changes need an AccessGuard.');
    }
    guard.require(permission);
  }
}
