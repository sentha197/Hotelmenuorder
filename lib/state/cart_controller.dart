import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/utils/currency.dart';
import '../data/models/cart_item.dart';
import '../data/models/menu_item.dart';
import '../data/models/pricing.dart';
import '../data/storage/key_value_store.dart';

enum DecrementResult {
  decremented,
  removed,

  /// The dish is in the cart with several customizations, so the caller must
  /// pick which line to change (in the cart screen).
  ambiguous,
  notInCart,
}

/// A removed line plus its position, so the removal can be undone.
typedef RemovedLine = ({CartItem line, int index});

/// The guest's cart: lines, quantities, special instructions and totals.
class CartController extends ChangeNotifier {
  CartController(this._store, {this.pricing = const PricingConfig()})
    : _instructions = _store.read(StorageKeys.instructions) ?? '';

  static const maxQuantity = 20;
  static const maxInstructionsLength = 200;

  final KeyValueStore _store;
  final PricingConfig pricing;

  final List<CartItem> _lines = [];
  final Map<String, DishCustomization> _lastCustomization = {};
  String _instructions;
  bool _hydrated = false;

  List<CartItem> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  int get totalQuantity => _lines.fold(0, (sum, line) => sum + line.quantity);

  Money get subtotal => Money.sum(_lines.map((line) => line.lineTotal));

  BillBreakdown get bill => BillBreakdown.fromSubtotal(subtotal, pricing);

  String get specialInstructions => _instructions;

  /// Longest preparation time among the dishes in the cart.
  int get estimatedPrepMinutes => _lines.isEmpty
      ? 0
      : _lines
            .map((line) => line.item.prepMinutes)
            .reduce((a, b) => a > b ? a : b);

  /// Restores the cart saved on the device once the menu is known. Lines for
  /// dishes no longer on the menu are dropped.
  void hydrate(Iterable<MenuItem> menu) {
    if (_hydrated) return;
    _hydrated = true;
    if (_lines.isNotEmpty) return;
    final raw = _store.read(StorageKeys.cart);
    if (raw == null) return;
    try {
      final byId = {for (final item in menu) item.id: item};
      for (final json
          in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        final item = byId[json['itemId']];
        if (item == null) continue;
        final quantity = (json['quantity'] as int).clamp(1, maxQuantity);
        final customization = DishCustomization.fromJson(
          (json['options'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
        _lines.add(
          CartItem(
            item: item,
            customization: customization,
            quantity: quantity,
          ),
        );
      }
    } on Object {
      _lines.clear();
    }
    notifyListeners();
  }

  int quantityOfItem(String itemId) => _lines
      .where((line) => line.item.id == itemId)
      .fold(0, (sum, line) => sum + line.quantity);

  int linesForItem(String itemId) =>
      _lines.where((line) => line.item.id == itemId).length;

  CartItem? lineById(String lineId) {
    for (final line in _lines) {
      if (line.id == lineId) return line;
    }
    return null;
  }

  /// Adds [quantity] of [item]. Identical customizations merge into one line;
  /// different customizations stay separate.
  CartItem add(
    MenuItem item, {
    DishCustomization? customization,
    int quantity = 1,
  }) {
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'must be at least 1');
    }
    final options = customization ?? DishCustomization.defaultsFor(item);
    final lineId = CartItem.lineIdFor(item, options);
    final index = _lines.indexWhere((line) => line.id == lineId);
    final CartItem result;
    if (index == -1) {
      result = CartItem(
        item: item,
        customization: options,
        quantity: quantity.clamp(1, maxQuantity),
      );
      _lines.add(result);
    } else {
      final merged = (_lines[index].quantity + quantity).clamp(1, maxQuantity);
      result = _lines[index].copyWith(quantity: merged);
      _lines[index] = result;
    }
    _lastCustomization[item.id] = options;
    _changed();
    return result;
  }

  /// "+" from a menu list: repeats the last customization chosen for this
  /// dish, or adds the default configuration.
  CartItem quickAdd(MenuItem item) =>
      add(item, customization: _lastCustomization[item.id]);

  /// "−" from a menu list.
  DecrementResult quickRemove(MenuItem item) {
    final matching = _lines.where((line) => line.item.id == item.id).toList();
    if (matching.isEmpty) return DecrementResult.notInCart;
    if (matching.length > 1) return DecrementResult.ambiguous;
    return decrement(matching.single.id);
  }

  void increment(String lineId) {
    final index = _indexOf(lineId);
    final line = _lines[index];
    if (line.quantity >= maxQuantity) return;
    _lines[index] = line.copyWith(quantity: line.quantity + 1);
    _changed();
  }

  /// Decreases the quantity; a line at quantity 1 is removed.
  DecrementResult decrement(String lineId) {
    final index = _indexOf(lineId);
    final line = _lines[index];
    if (line.quantity <= 1) {
      _lines.removeAt(index);
      _changed();
      return DecrementResult.removed;
    }
    _lines[index] = line.copyWith(quantity: line.quantity - 1);
    _changed();
    return DecrementResult.decremented;
  }

  RemovedLine? remove(String lineId) {
    final index = _lines.indexWhere((line) => line.id == lineId);
    if (index == -1) return null;
    final line = _lines.removeAt(index);
    _changed();
    return (line: line, index: index);
  }

  /// Puts back a line removed with [remove] (undo).
  void restore(RemovedLine removed) {
    if (lineById(removed.line.id) != null) {
      add(
        removed.line.item,
        customization: removed.line.customization,
        quantity: removed.line.quantity,
      );
      return;
    }
    _lines.insert(removed.index.clamp(0, _lines.length), removed.line);
    _changed();
  }

  /// Empties the cart. Special instructions are cleared too unless
  /// [keepInstructions] is set.
  void clear({bool keepInstructions = false}) {
    _lines.clear();
    if (!keepInstructions) _instructions = '';
    _changed();
  }

  void updateInstructions(String value) {
    final text = value.length > maxInstructionsLength
        ? value.substring(0, maxInstructionsLength)
        : value;
    if (text == _instructions) return;
    _instructions = text;
    notifyListeners();
    _store.write(StorageKeys.instructions, _instructions);
  }

  int _indexOf(String lineId) {
    final index = _lines.indexWhere((line) => line.id == lineId);
    if (index == -1) throw StateError('No cart line $lineId');
    return index;
  }

  void _changed() {
    notifyListeners();
    _store.write(
      StorageKeys.cart,
      jsonEncode([for (final line in _lines) line.toJson()]),
    );
    _store.write(StorageKeys.instructions, _instructions);
  }
}
