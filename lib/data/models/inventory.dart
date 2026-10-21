/// A stocked ingredient or supply. Quantities change only through recorded
/// adjustments; no recipe consumption is assumed.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.reorderLevel,
    required this.updatedAt,
    this.supplier = '',
    this.linkedDishIds = const [],
    this.isDemoSample = false,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String,
    quantity: (json['qty'] as num).toDouble(),
    reorderLevel: (json['reorder'] as num).toDouble(),
    updatedAt: DateTime.parse(json['updated'] as String),
    supplier: json['supplier'] as String? ?? '',
    linkedDishIds: (json['dishes'] as List? ?? const []).cast<String>(),
    isDemoSample: json['demo'] as bool? ?? false,
  );

  final String id;
  final String name;

  /// e.g. `kg`, `L`, `pcs`.
  final String unit;
  final double quantity;

  /// At or below this level the item is flagged as low stock.
  final double reorderLevel;
  final DateTime updatedAt;
  final String supplier;

  /// Dishes that cannot be served without this item (optional rule).
  final List<String> linkedDishIds;
  final bool isDemoSample;

  bool get isOutOfStock => quantity <= 0;

  bool get isLow => !isOutOfStock && quantity <= reorderLevel;

  InventoryItem copyWith({
    String? name,
    String? unit,
    double? quantity,
    double? reorderLevel,
    DateTime? updatedAt,
    String? supplier,
    List<String>? linkedDishIds,
  }) => InventoryItem(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    reorderLevel: reorderLevel ?? this.reorderLevel,
    updatedAt: updatedAt ?? this.updatedAt,
    supplier: supplier ?? this.supplier,
    linkedDishIds: linkedDishIds ?? this.linkedDishIds,
    isDemoSample: isDemoSample,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'qty': quantity,
    'reorder': reorderLevel,
    'updated': updatedAt.toIso8601String(),
    if (supplier.isNotEmpty) 'supplier': supplier,
    if (linkedDishIds.isNotEmpty) 'dishes': linkedDishIds,
    if (isDemoSample) 'demo': true,
  };
}

/// One change to an item's stock level.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.itemId,
    required this.change,
    required this.balance,
    required this.reason,
    required this.at,
    required this.by,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
    id: json['id'] as String,
    itemId: json['item'] as String,
    change: (json['change'] as num).toDouble(),
    balance: (json['balance'] as num).toDouble(),
    reason: json['reason'] as String? ?? '',
    at: DateTime.parse(json['at'] as String),
    by: json['by'] as String? ?? '',
  );

  final String id;
  final String itemId;

  /// Positive for stock received, negative for usage or waste.
  final double change;

  /// Quantity after the change.
  final double balance;
  final String reason;
  final DateTime at;
  final String by;

  Map<String, dynamic> toJson() => {
    'id': id,
    'item': itemId,
    'change': change,
    'balance': balance,
    'reason': reason,
    'at': at.toIso8601String(),
    'by': by,
  };
}
