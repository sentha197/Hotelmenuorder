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

/// Stores dish photos and returns the URL to save on the dish. Implemented
/// by menu repositories backed by a server with image storage; the offline
/// demo has nowhere to put a photo, so it does not implement this.
abstract interface class DishImageUploader {
  /// Largest photo the backend accepts. Mirrored here so the app can refuse
  /// an oversized file before spending time uploading it. Keep in step with
  /// `ImageStorage:MaxBytes` on the server.
  static const maxBytes = 10 * 1024 * 1024;

  /// A file extension for [bytes] based on their leading bytes, or null when
  /// they look like nothing known. Only used to name the upload sensibly:
  /// which formats are *accepted* is the server's call (it decodes the file
  /// and answers with a message), so the app keeps no list of its own and
  /// never refuses a photo because of its type.
  static String? extensionFor(List<int> bytes) {
    bool matches(int offset, List<int> signature) {
      if (bytes.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[offset + i] != signature[i]) return false;
      }
      return true;
    }

    // 'ftyp' at offset 4, then a brand: avif/avis, or one of HEIC's.
    bool brand(String name) =>
        matches(4, [0x66, 0x74, 0x79, 0x70]) && matches(8, name.codeUnits);

    if (matches(0, [0xFF, 0xD8, 0xFF])) return 'jpg';
    if (matches(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'png';
    }
    if (matches(0, 'GIF8'.codeUnits)) return 'gif';
    // 'RIFF' .... 'WEBP'
    if (matches(0, [0x52, 0x49, 0x46, 0x46]) &&
        matches(8, [0x57, 0x45, 0x42, 0x50])) {
      return 'webp';
    }
    if (matches(0, 'BM'.codeUnits)) return 'bmp';
    if (matches(0, [0x49, 0x49, 0x2A, 0x00]) ||
        matches(0, [0x4D, 0x4D, 0x00, 0x2A])) {
      return 'tif';
    }
    if (matches(0, [0x00, 0x00, 0x01, 0x00])) return 'ico';
    if (brand('avif') || brand('avis')) return 'avif';
    if (brand('heic') || brand('heix') || brand('mif1') || brand('msf1')) {
      return 'heic';
    }
    return null;
  }

  /// Uploads [bytes] and returns the stored photo's URL.
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  });
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
