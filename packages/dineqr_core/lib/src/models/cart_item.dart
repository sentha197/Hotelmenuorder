import '../utils/currency.dart';
import 'menu_item.dart';
import 'promotion.dart';

/// The options a guest picked for a dish. Two customizations with the same
/// [key] are considered identical and merge into one cart line.
class DishCustomization {
  DishCustomization({
    this.spice,
    this.portionId,
    Iterable<String> addOnIds = const [],
  }) : addOnIds = List.unmodifiable(addOnIds.toSet().toList()..sort());

  factory DishCustomization.defaultsFor(MenuItem item) => DishCustomization(
    spice: item.hasSpiceLevel ? item.defaultSpice : null,
    portionId: item.defaultPortion?.id,
  );

  factory DishCustomization.fromJson(Map<String, dynamic> json) =>
      DishCustomization(
        spice: SpiceLevel.tryParse(json['spice'] as String?),
        portionId: json['portion'] as String?,
        addOnIds: (json['addOns'] as List? ?? const []).cast<String>(),
      );

  final SpiceLevel? spice;
  final String? portionId;

  /// Sorted, de-duplicated add-on ids.
  final List<String> addOnIds;

  String get key =>
      '${spice?.name ?? '-'}|${portionId ?? '-'}|${addOnIds.join(',')}';

  /// Extra cost on top of the dish's base price.
  Money extraFor(MenuItem item) {
    var extra = item.portionById(portionId)?.extraPrice ?? Money.zero;
    for (final id in addOnIds) {
      extra += item.addOnById(id)?.price ?? Money.zero;
    }
    return extra;
  }

  /// Human readable option labels, e.g. `['Spicy', 'Large', 'Extra Cheese']`.
  List<String> describe(MenuItem item) {
    final portion = item.portionById(portionId);
    return [
      if (spice != null) 'Spice: ${spice!.label}',
      if (portion != null && item.portions.length > 1) portion.label,
      for (final id in addOnIds)
        if (item.addOnById(id) case final addOn?) addOn.name,
    ];
  }

  Map<String, dynamic> toJson() => {
    if (spice != null) 'spice': spice!.name,
    if (portionId != null) 'portion': portionId,
    if (addOnIds.isNotEmpty) 'addOns': addOnIds,
  };

  @override
  bool operator ==(Object other) =>
      other is DishCustomization && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// One line in the cart: a dish, its customization and a quantity; or a
/// combo and a quantity.
class CartItem {
  const CartItem({
    required this.item,
    required this.customization,
    required this.quantity,
    this.combo,
  });

  /// A combo line. [item] then stands for the combo (its name, picture and
  /// what its dishes cost separately); the combo's saving is applied as a
  /// discount when the cart is priced. [live]: whether the combo can be
  /// ordered today.
  factory CartItem.combo(
    ComboView combo, {
    required int quantity,
    required bool live,
  }) => CartItem(
    item: combo.asItem(live: live),
    customization: DishCustomization(),
    quantity: quantity,
    combo: combo,
  );

  final MenuItem item;
  final DishCustomization customization;
  final int quantity;

  /// Set for a combo line.
  final ComboView? combo;

  bool get isCombo => combo != null;

  static String lineIdFor(MenuItem item, DishCustomization customization) =>
      '${item.id}::${customization.key}';

  static String comboLineId(String comboId) => 'combo::$comboId';

  String get id => combo == null
      ? lineIdFor(item, customization)
      : comboLineId(combo!.combo.id);

  /// The full price of one unit (a combo's dishes bought separately).
  Money get unitPrice =>
      isCombo ? item.price : item.price + customization.extraFor(item);

  Money get lineTotal => unitPrice * quantity;

  /// The chosen options, or a combo's dishes (`2 × Punjabi Samosa`).
  List<String> get optionLabels =>
      combo?.partLabels ?? customization.describe(item);

  CartItem copyWith({int? quantity}) => CartItem(
    item: item,
    customization: customization,
    quantity: quantity ?? this.quantity,
    combo: combo,
  );

  /// What the server prices: a dish with its options, or a combo by id.
  Map<String, dynamic> toJson() => combo == null
      ? {
          'itemId': item.id,
          'quantity': quantity,
          'options': customization.toJson(),
        }
      : {'comboId': combo!.combo.id, 'quantity': quantity};
}
