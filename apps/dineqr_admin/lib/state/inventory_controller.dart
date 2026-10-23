import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

/// Stock levels. Quantities change only through recorded adjustments; no
/// ingredient usage is inferred from orders (no recipes are configured).
class InventoryController extends ChangeNotifier {
  InventoryController(
    this._repository,
    this._guard,
    this._audit,
    this._catalog, {
    required this.autoUnavailable,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final InventoryRepository _repository;
  final AccessGuard _guard;
  final AuditLog _audit;
  final CatalogController _catalog;

  /// Settings rule: mark linked dishes sold out when an item runs out.
  final bool Function() autoUnavailable;
  final DateTime Function() _clock;

  List<InventoryItem> _items = const [];
  List<StockMovement> _movements = const [];

  /// Set in backend mode: the server applies every stock change (and marks
  /// linked dishes sold out or available again).
  StockLedger? get _ledger =>
      _repository is StockLedger ? _repository as StockLedger : null;

  List<InventoryItem> get items => _items;

  List<InventoryItem> get lowStock =>
      _items.where((i) => i.isLow || i.isOutOfStock).toList(growable: false);

  InventoryItem? byId(String id) => _items.where((i) => i.id == id).firstOrNull;

  List<StockMovement> movementsFor(String itemId) =>
      _movements.where((m) => m.itemId == itemId).toList(growable: false);

  Future<void> load() async {
    _items = [...await _repository.fetchItems()]
      ..sort((a, b) => a.name.compareTo(b.name));
    _movements = await _repository.fetchMovements();
    notifyListeners();
  }

  static const units = ['kg', 'g', 'L', 'ml', 'pcs', 'packs'];

  String? validate(InventoryItem item) {
    final name = item.name.trim();
    if (name.length < 2 || name.length > 40) {
      return 'Item name must be 2 to 40 characters.';
    }
    if (_items.any(
      (i) => i.id != item.id && i.name.toLowerCase() == name.toLowerCase(),
    )) {
      return '"$name" is already in the inventory.';
    }
    if (!units.contains(item.unit)) return 'Choose a unit.';
    if (item.quantity < 0 || item.quantity > 100000) {
      return 'Quantity must be between 0 and 100000.';
    }
    if (item.reorderLevel < 0 || item.reorderLevel > 100000) {
      return 'Reorder level must be between 0 and 100000.';
    }
    if (item.supplier.length > 40) {
      return 'Supplier can be at most 40 characters.';
    }
    return null;
  }

  /// Creates or edits an item's details. Quantity of an existing item is
  /// changed only through [adjust].
  Future<InventoryItem> saveItem(InventoryItem item) async {
    _guard.require(Permission.manageInventory);
    final error = validate(item);
    if (error != null) throw ValidationException(error);
    final existing = byId(item.id);
    final ledger = _ledger;
    if (ledger != null) {
      final saved = existing == null
          ? await ledger.create(item.copyWith(name: item.name.trim()))
          : await ledger.update(item.copyWith(name: item.name.trim()));
      await load();
      return saved;
    }
    final saved = existing == null
        ? item.copyWith(name: item.name.trim(), updatedAt: _clock())
        : item.copyWith(
            name: item.name.trim(),
            quantity: existing.quantity,
            updatedAt: _clock(),
          );
    await _repository.saveItem(saved);
    if (existing == null && saved.quantity > 0) {
      await _repository.addMovement(
        StockMovement(
          id: Ids.sequential('MOV', _movements.map((m) => m.id)),
          itemId: saved.id,
          change: saved.quantity,
          balance: saved.quantity,
          reason: 'Opening stock',
          at: _clock(),
          by: _guard.actor?.name ?? '',
        ),
      );
    }
    await load();
    await _audit.record(
      existing == null ? 'inventory.create' : 'inventory.update',
      '${existing == null ? 'Added' : 'Updated'} ${saved.name}',
      targetId: saved.id,
    );
    return saved;
  }

  String newItemId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    var id = 'inv_${base.isEmpty ? 'item' : base}';
    var n = 2;
    while (byId(id) != null) {
      id = 'inv_${base}_${n++}';
    }
    return id;
  }

  /// Adds (positive) or removes (negative) stock with a reason.
  Future<void> adjust(String itemId, double change, String reason) async {
    _guard.require(Permission.manageInventory);
    final item = byId(itemId);
    if (item == null) return;
    final why = reason.trim();
    if (change == 0) throw const ValidationException('Enter a quantity.');
    if (why.length < 3) throw const ValidationException('Enter a reason.');
    final balance = double.parse((item.quantity + change).toStringAsFixed(3));
    if (balance < 0) {
      throw ValidationException(
        'Only ${_format(item.quantity)} ${item.unit} in stock.',
      );
    }
    final ledger = _ledger;
    if (ledger != null) {
      await ledger.adjust(itemId, change, why);
      await load();
      // The server may have marked linked dishes sold out or available.
      await _catalog.refresh();
      return;
    }
    final wasOut = item.isOutOfStock;
    final updated = item.copyWith(quantity: balance, updatedAt: _clock());
    await _repository.saveItem(updated);
    await _repository.addMovement(
      StockMovement(
        id: Ids.sequential('MOV', _movements.map((m) => m.id)),
        itemId: itemId,
        change: change,
        balance: balance,
        reason: why,
        at: _clock(),
        by: _guard.actor?.name ?? '',
      ),
    );
    await load();
    await _audit.record(
      'inventory.adjust',
      '${item.name}: ${change > 0 ? '+' : ''}${_format(change)} ${item.unit} '
          '($why) → ${_format(balance)} ${item.unit}',
      targetId: itemId,
    );
    if (autoUnavailable()) {
      if (!wasOut && updated.isOutOfStock) {
        for (final dishId in item.linkedDishIds) {
          await _catalog.setAvailable(
            dishId,
            false,
            system: true,
            reason: '${item.name} out of stock',
          );
        }
      } else if (wasOut && !updated.isOutOfStock) {
        for (final dishId in item.linkedDishIds) {
          await _catalog.setAvailable(
            dishId,
            true,
            system: true,
            reason: '${item.name} restocked',
          );
        }
      }
    }
  }

  static String format(double value) => _format(value);

  static String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(
          value * 10 == (value * 10).roundToDouble() ? 1 : 2,
        );

  Future<void> resetDemo() async {
    await _repository.reset();
    await load();
  }
}
