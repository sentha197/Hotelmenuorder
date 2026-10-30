import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/discount_offer.dart';
import '../models/menu_item.dart';
import '../models/offer_pricing.dart';
import '../models/pricing.dart';
import '../models/promotion.dart';
import '../storage/key_value_store.dart';
import '../utils/currency.dart';

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

/// The guest's cart: lines (dishes and combos), quantities, special
/// instructions, the coupon and totals with every offer applied.
class CartController extends ChangeNotifier {
  CartController(
    this._store, {
    PricingConfig pricing = const PricingConfig(),
    this._pricingSource,
    this._offerLookup,
    this._promotionSource,
    DateTime Function()? clock,
  }) : _fixedPricing = pricing,
       _clock = clock ?? DateTime.now,
       _instructions = _store.read(StorageKeys.instructions) ?? '',
       _offerCode = _store.read(StorageKeys.offer);

  static const maxQuantity = 20;
  static const maxInstructionsLength = 200;

  final KeyValueStore _store;
  final PricingConfig _fixedPricing;
  final PricingConfig Function()? _pricingSource;
  final DiscountOffer? Function(String code)? _offerLookup;

  /// The special offers and combos the restaurant has (guests are sent the
  /// live ones; staff apps know all of them, so liveness is checked here).
  final List<Promotion> Function()? _promotionSource;
  final DateTime Function() _clock;
  String? _offerCode;

  /// Current pricing rules (from restaurant settings when available).
  PricingConfig get pricing => _pricingSource?.call() ?? _fixedPricing;

  /// Today in restaurant time: offers are live by restaurant days.
  DateTime get today => OfferRules.today(_clock());

  List<Promotion> get _promotions => _promotionSource?.call() ?? const [];

  final List<CartItem> _lines = [];
  final Map<String, DishCustomization> _lastCustomization = {};
  String _instructions;
  bool _hydrated = false;

  List<CartItem> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  int get totalQuantity => _lines.fold(0, (sum, line) => sum + line.quantity);

  /// Every line at its full price (before any saving).
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

  /// The cart priced with its special offers, combos and coupon.
  CartQuote get quote {
    final offer = appliedOffer;
    return OfferPricing.quote(
      lines: _lines,
      specials: OfferPricing.liveSpecials(_promotions, today),
      config: pricing,
      coupon: offer != null && offer.isLiveOn(today) ? offer : null,
    );
  }

  /// Why the applied offer does not reduce the bill right now, if it doesn't.
  /// Its minimum spend counts what is left after item savings.
  OfferError? get offerProblem {
    final code = _offerCode;
    if (code == null) return null;
    final offer = appliedOffer;
    if (offer == null) return OfferError.unknownCode;
    return offer.check(quote.subtotalAfterSavings, today: today);
  }

  /// Everything the guest saves: special offers, combos and the coupon.
  Money get discount => quote.bill.discount;

  /// What the line [lineId] saves (a special offer or its combo), or null.
  LineSaving? savingFor(String lineId) => quote.savingFor(lineId);

  BillBreakdown get bill => quote.bill;

  /// Applies an offer code. Returns an error when it cannot be used at all
  /// (unknown, paused, outside its dates or used up); a code below its
  /// minimum is kept so it applies once the cart grows.
  OfferError? applyOffer(String code) {
    final normalized = DiscountOffer.normalize(code);
    final offer = _offerLookup?.call(normalized);
    if (offer == null) return OfferError.unknownCode;
    final unavailable = offer.availabilityOn(today);
    if (unavailable != null) return unavailable;
    _offerCode = normalized;
    notifyListeners();
    _store.write(StorageKeys.offer, normalized);
    return offer.check(quote.subtotalAfterSavings, today: today);
  }

  void removeOffer() {
    if (_offerCode == null) return;
    _offerCode = null;
    notifyListeners();
    _store.delete(StorageKeys.offer);
  }

  /// Lines that can no longer be ordered (a sold-out or removed dish, or a
  /// combo that ended or holds one).
  List<CartItem> get unavailableLines =>
      _lines.where((line) => !line.item.isOrderable).toList(growable: false);

  /// Applies menu and offer edits to the cart: new prices and options take
  /// effect before checkout, and archived dishes and withdrawn combos are
  /// removed. Returns how many lines were removed.
  int syncWithMenu(Iterable<MenuItem> menu) {
    if (_lines.isEmpty) return 0;
    final byId = {for (final item in menu) item.id: item};
    var removed = 0;
    var changed = false;
    for (var i = _lines.length - 1; i >= 0; i--) {
      final line = _lines[i];
      if (line.isCombo) {
        final latest = _comboLine(line.combo!.combo.id, byId, line.quantity);
        if (latest == null) {
          _lines.removeAt(i);
          removed++;
        } else {
          _lines[i] = latest;
        }
        changed = true;
        continue;
      }
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

  /// The combo [comboId] as a cart line built from [menu], or null when the
  /// restaurant no longer has it (or one of its dishes).
  CartItem? _comboLine(
    String comboId,
    Map<String, MenuItem> menu,
    int quantity,
  ) {
    final combo = _promotions
        .where((p) => p.isCombo && p.id == comboId)
        .firstOrNull;
    final view = combo?.comboView(menu);
    if (combo == null ||
        view == null ||
        view.dishes.any((d) => d.item.isArchived)) {
      return null;
    }
    return CartItem.combo(
      view,
      quantity: quantity,
      live: combo.isLiveOn(today),
    );
  }

  String get specialInstructions => _instructions;

  /// Longest preparation time among the dishes in the cart.
  int get estimatedPrepMinutes => _lines.isEmpty
      ? 0
      : _lines
            .map((line) => line.item.prepMinutes)
            .reduce((a, b) => a > b ? a : b);

  /// Restores the cart saved on the device once the menu (and its offers)
  /// is known. Lines for dishes or combos no longer offered are dropped.
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
        final quantity = (json['quantity'] as int).clamp(1, maxQuantity);
        final comboId = json['comboId'] as String?;
        if (comboId != null) {
          final line = _comboLine(comboId, byId, quantity);
          if (line != null) _lines.add(line);
          continue;
        }
        final item = byId[json['itemId']];
        if (item == null) continue;
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
      .where((line) => !line.isCombo && line.item.id == itemId)
      .fold(0, (sum, line) => sum + line.quantity);

  int linesForItem(String itemId) =>
      _lines.where((line) => !line.isCombo && line.item.id == itemId).length;

  /// How many of the combo [comboId] are in the cart.
  int quantityOfCombo(String comboId) =>
      lineById(CartItem.comboLineId(comboId))?.quantity ?? 0;

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

  /// Adds [quantity] of a combo; the same combo again adds to its line.
  CartItem addCombo(ComboView combo, {int quantity = 1}) {
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'must be at least 1');
    }
    final line = CartItem.combo(
      combo,
      quantity: quantity.clamp(1, maxQuantity),
      live: combo.combo.isLiveOn(today),
    );
    if (!line.item.isOrderable) {
      throw StateError('${combo.combo.title} is not available right now.');
    }
    final index = _lines.indexWhere((existing) => existing.id == line.id);
    final CartItem result;
    if (index == -1) {
      result = line;
      _lines.add(result);
    } else {
      final merged = (_lines[index].quantity + quantity).clamp(1, maxQuantity);
      result = line.copyWith(quantity: merged);
      _lines[index] = result;
    }
    _changed();
    return result;
  }

  /// "+" from a menu list: repeats the last customization chosen for this
  /// dish, or adds the default configuration.
  CartItem quickAdd(MenuItem item) =>
      add(item, customization: _lastCustomization[item.id]);

  /// "−" from a menu list.
  DecrementResult quickRemove(MenuItem item) {
    final matching = _lines
        .where((line) => !line.isCombo && line.item.id == item.id)
        .toList();
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

  /// Puts back a line removed with [remove] (undo). If the same dish (or
  /// combo) was added again meanwhile, the quantities merge.
  void restore(RemovedLine removed) {
    final line = removed.line;
    final existing = _lines.indexWhere((l) => l.id == line.id);
    if (existing != -1) {
      final merged = (_lines[existing].quantity + line.quantity).clamp(
        1,
        maxQuantity,
      );
      _lines[existing] = _lines[existing].copyWith(quantity: merged);
    } else {
      _lines.insert(removed.index.clamp(0, _lines.length), line);
    }
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
