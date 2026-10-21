import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/utils/currency.dart';
import '../data/models/cart_item.dart';
import '../data/models/discount_offer.dart';
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
  CartController(
    this._store, {
    PricingConfig pricing = const PricingConfig(),
    this._pricingSource,
    this._offerLookup,
  }) : _fixedPricing = pricing,
       _instructions = _store.read(StorageKeys.instructions) ?? '',
       _offerCode = _store.read(StorageKeys.offer);

  static const maxQuantity = 20;
  static const maxInstructionsLength = 200;

  final KeyValueStore _store;
  final PricingConfig _fixedPricing;
  final PricingConfig Function()? _pricingSource;
  final DiscountOffer? Function(String code)? _offerLookup;
  String? _offerCode;

  /// Current pricing rules (from restaurant settings when available).
  PricingConfig get pricing => _pricingSource?.call() ?? _fixedPricing;

  final List<CartItem> _lines = [];
  final Map<String, DishCustomization> _lastCustomization = {};
  String _instructions;
  bool _hydrated = false;

  List<CartItem> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  int get totalQuantity => _lines.fold(0, (sum, line) => sum + line.quantity);

  Money get subtotal => Money.sum(_lines.map((line) => line.lineTotal));

  /// Restaurant pricing (tax, service charge or offers) changed.
  void pricingChanged() => notifyListeners();

  /// Applied offer code, if any (it may not currently qualify).
  String? get offerCode => _offerCode;

  DiscountOffer? get appliedOffer {
    final code = _offerCode;
    if (code == null) return null;
    return _offerLookup?.call(code);
  }

  /// Why the applied offer does not reduce the bill right now, if it doesn't.
  OfferError? get offerProblem {
    final code = _offerCode;
    if (code == null) return null;
    final offer = appliedOffer;
    if (offer == null) return OfferError.unknownCode;
    return offer.check(subtotal);
  }

  Money get discount => appliedOffer?.discountFor(subtotal) ?? Money.zero;

  BillBreakdown get bill {
    final offer = appliedOffer;
    final amount = discount;
    return BillBreakdown.fromSubtotal(
      subtotal,
      pricing,
      discount: amount,
      discountLabel: offer == null || amount.isZero
          ? null
          : 'Offer ${offer.code}',
    );
  }

  /// Applies an offer code. Returns an error when it cannot be used at all;
  /// a code below its minimum is kept so it applies once the cart grows.
  OfferError? applyOffer(String code) {
    final normalized = DiscountOffer.normalize(code);
    final offer = _offerLookup?.call(normalized);
    if (offer == null) return OfferError.unknownCode;
    if (!offer.isActive) return OfferError.inactive;
    _offerCode = normalized;
    notifyListeners();
    _store.write(StorageKeys.offer, normalized);
    return offer.check(subtotal);
  }

  void removeOffer() {
    if (_offerCode == null) return;
    _offerCode = null;
    notifyListeners();
    _store.delete(StorageKeys.offer);
  }

  /// Lines whose dish can no longer be ordered (sold out or removed).
  List<CartItem> get unavailableLines =>
      _lines.where((line) => !line.item.isOrderable).toList(growable: false);

  /// Applies menu edits to the cart: new prices and options take effect
  /// before checkout, and archived dishes are removed. Returns how many
  /// lines were removed.
  int syncWithMenu(Iterable<MenuItem> menu) {
    if (_lines.isEmpty) return 0;
    final byId = {for (final item in menu) item.id: item};
    var removed = 0;
    var changed = false;
    for (var i = _lines.length - 1; i >= 0; i--) {
      final line = _lines[i];
      final latest = byId[line.item.id];
      if (latest == null || latest.isArchived) {
        _lines.removeAt(i);
        removed++;
        changed = true;
      } else if (!identical(latest, line.item)) {
        _lines[i] = CartItem(
          item: latest,
          customization: line.customization,
          quantity: line.quantity,
        );
        changed = true;
      }
    }
    if (changed) _changed();
    return removed;
  }

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
    if (!item.isOrderable) {
      throw StateError('${item.name} is not available right now.');
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
    if (line.quantity >= maxQuantity || !line.item.isOrderable) return;
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
    if (!keepInstructions) {
      _instructions = '';
      _offerCode = null;
      _store.delete(StorageKeys.offer);
    }
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
