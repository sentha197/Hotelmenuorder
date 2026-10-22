import '../utils/currency.dart';
import 'menu_item.dart';

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

/// One line in the cart: a dish, its customization and a quantity.
class CartItem {
  const CartItem({
    required this.item,
    required this.customization,
    required this.quantity,
  });

  final MenuItem item;
  final DishCustomization customization;
  final int quantity;

  static String lineIdFor(MenuItem item, DishCustomization customization) =>
      '${item.id}::${customization.key}';

  String get id => lineIdFor(item, customization);

  Money get unitPrice => item.price + customization.extraFor(item);

  Money get lineTotal => unitPrice * quantity;

  List<String> get optionLabels => customization.describe(item);

  CartItem copyWith({int? quantity}) => CartItem(
    item: item,
    customization: customization,
    quantity: quantity ?? this.quantity,
  );

  Map<String, dynamic> toJson() => {
    'itemId': item.id,
    'quantity': quantity,
    'options': customization.toJson(),
  };
}
