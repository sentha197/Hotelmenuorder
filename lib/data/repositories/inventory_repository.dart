import '../models/inventory.dart';
import '../storage/key_value_store.dart';

/// Stock levels and their history.
abstract interface class InventoryRepository {
  Future<List<InventoryItem>> fetchItems();

  Future<List<StockMovement>> fetchMovements();

  Future<void> saveItem(InventoryItem item);

  Future<void> addMovement(StockMovement movement);

  Future<void> reset();
}

class LocalInventoryRepository implements InventoryRepository {
  LocalInventoryRepository(KeyValueStore store, {required this.seed})
    : _items = JsonListStore(
        store,
        StorageKeys.inventory,
        InventoryItem.fromJson,
        (i) => i.toJson(),
      ),
      _movements = JsonListStore(
        store,
        StorageKeys.stockMovements,
        StockMovement.fromJson,
        (m) => m.toJson(),
      );

  static const maxMovements = 400;

  final JsonListStore<InventoryItem> _items;
  final JsonListStore<StockMovement> _movements;
  final List<InventoryItem> Function() seed;

  List<InventoryItem>? _cachedItems;
  List<StockMovement>? _cachedMovements;

  List<InventoryItem> get _all => _cachedItems ??= _items.read() ?? seed();

  @override
  Future<List<InventoryItem>> fetchItems() async => List.unmodifiable(_all);

  @override
  Future<List<StockMovement>> fetchMovements() async =>
      List.unmodifiable(_cachedMovements ??= _movements.read() ?? []);

  @override
  Future<void> saveItem(InventoryItem item) async {
    final exists = _all.any((i) => i.id == item.id);
    _cachedItems = exists
        ? [for (final i in _all) i.id == item.id ? item : i]
        : [..._all, item];
    await _items.write(_cachedItems!);
  }

  @override
  Future<void> addMovement(StockMovement movement) async {
    final all = [movement, ...(_cachedMovements ??= _movements.read() ?? [])];
    _cachedMovements = all.length > maxMovements
        ? all.sublist(0, maxMovements)
        : all;
    await _movements.write(_cachedMovements!);
  }

  @override
  Future<void> reset() async {
    _cachedItems = null;
    _cachedMovements = null;
    await _items.clear();
    await _movements.clear();
  }
}
