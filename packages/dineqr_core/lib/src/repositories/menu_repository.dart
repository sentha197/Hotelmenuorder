import '../demo/demo_menu_data.dart';
import '../models/menu_item.dart';
import '../storage/key_value_store.dart';

/// Source of the restaurant menu. Swap [DemoMenuRepository] for an
/// API-backed implementation without touching the UI. Writes are expected
/// to be authorised by the backend; the demo checks permissions in the
/// state layer.
abstract interface class MenuRepository {
  Future<List<MenuCategory>> fetchCategories();

  Future<List<MenuItem>> fetchMenu();

  /// Creates or replaces a dish.
  Future<void> saveItem(MenuItem item);

  /// Replaces the full category list (order, names, active flags).
  Future<void> saveCategories(List<MenuCategory> categories);

  /// Restores the original menu.
  Future<void> reset();
}

/// Offline menu seeded from [demoMenuItems]. Edits made in the admin
/// dashboard are kept on the device when a [store] is given.
class DemoMenuRepository implements MenuRepository {
  DemoMenuRepository({
    this.latency = const Duration(milliseconds: 450),
    List<MenuItem> items = demoMenuItems,
    List<MenuCategory> categories = MenuCategory.defaults,
    KeyValueStore? store,
  }) : _seedItems = items,
       _seedCategories = categories,
       _itemStore = store == null
           ? null
           : JsonListStore<Map<String, dynamic>>(
               store,
               StorageKeys.menuItems,
               (json) => json,
               (json) => json,
             ),
       _categoryStore = store == null
           ? null
           : JsonListStore(
               store,
               StorageKeys.menuCategories,
               MenuCategory.fromJson,
               (c) => c.toJson(),
             );

  /// Simulated network delay so loading states are visible in the demo.
  final Duration latency;
  final List<MenuItem> _seedItems;
  final List<MenuCategory> _seedCategories;
  final JsonListStore<Map<String, dynamic>>? _itemStore;
  final JsonListStore<MenuCategory>? _categoryStore;

  List<MenuCategory>? _categories;
  List<MenuItem>? _items;

  List<MenuCategory> _loadCategories() =>
      _categories ??= [...(_categoryStore?.read() ?? _seedCategories)]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<MenuItem> _loadItems() {
    final cached = _items;
    if (cached != null) return cached;
    final byId = {for (final c in _loadCategories()) c.id: c};
    final stored = _itemStore?.read();
    final items = stored == null
        ? [
            for (final item in _seedItems)
              item.copyWith(category: byId[item.category.id] ?? item.category),
          ]
        : [
            for (final json in stored)
              MenuItem.fromJson(json, categories: byId),
          ];
    return _items = items;
  }

  @override
  Future<List<MenuCategory>> fetchCategories() async =>
      List.unmodifiable(_loadCategories());

  @override
  Future<List<MenuItem>> fetchMenu() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return List.unmodifiable(_loadItems());
  }

  @override
  Future<void> saveItem(MenuItem item) async {
    final items = _loadItems();
    final index = items.indexWhere((existing) => existing.id == item.id);
    _items = index == -1
        ? [...items, item]
        : [
            for (final existing in items)
              existing.id == item.id ? item : existing,
          ];
    await _itemStore?.write([for (final i in _items!) i.toJson()]);
  }

  @override
  Future<void> saveCategories(List<MenuCategory> categories) async {
    _categories = [...categories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    // Keep dishes pointing at the updated category objects.
    final byId = {for (final c in _categories!) c.id: c};
    _items = [
      for (final item in _loadItems())
        item.copyWith(category: byId[item.category.id] ?? item.category),
    ];
    await _categoryStore?.write(_categories!);
    await _itemStore?.write([for (final i in _items!) i.toJson()]);
  }

  @override
  Future<void> reset() async {
    _categories = null;
    _items = null;
    await _categoryStore?.clear();
    await _itemStore?.clear();
  }
}
