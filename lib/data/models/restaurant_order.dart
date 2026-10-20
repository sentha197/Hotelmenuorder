import '../../core/utils/currency.dart';
import 'cart_item.dart';
import 'order_feedback.dart';
import 'order_status.dart';
import 'pricing.dart';

/// Immutable snapshot of one ordered dish, frozen at checkout time so later
/// menu or cart changes never alter order history.
class OrderLine {
  const OrderLine({
    required this.itemId,
    required this.name,
    required this.image,
    required this.isVeg,
    required this.unitPrice,
    required this.quantity,
    this.options = const [],
  });

  factory OrderLine.fromCartItem(CartItem line) => OrderLine(
    itemId: line.item.id,
    name: line.item.name,
    image: line.item.image,
    isVeg: line.item.isVeg,
    unitPrice: line.unitPrice,
    quantity: line.quantity,
    options: List.unmodifiable(line.optionLabels),
  );

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    itemId: json['itemId'] as String,
    name: json['name'] as String,
    image: json['image'] as String,
    isVeg: json['isVeg'] as bool,
    unitPrice: Money(json['unitPrice'] as int),
    quantity: json['quantity'] as int,
    options: List.unmodifiable(
      (json['options'] as List? ?? const []).cast<String>(),
    ),
  );

  final String itemId;
  final String name;
  final String image;
  final bool isVeg;
  final Money unitPrice;
  final int quantity;
  final List<String> options;

  Money get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'name': name,
    'image': image,
    'isVeg': isVeg,
    'unitPrice': unitPrice.paise,
    'quantity': quantity,
    'options': options,
  };
}

/// Everything needed to submit a new order.
class OrderDraft {
  OrderDraft({
    required this.tableNumber,
    required Iterable<OrderLine> lines,
    required this.bill,
    required this.specialInstructions,
    required this.estimatedPrepMinutes,
  }) : lines = List.unmodifiable(lines);

  final int tableNumber;
  final List<OrderLine> lines;
  final BillBreakdown bill;
  final String specialInstructions;
  final int estimatedPrepMinutes;
}

class RestaurantOrder {
  RestaurantOrder({
    required this.id,
    required this.tableNumber,
    required this.createdAt,
    required Iterable<OrderLine> lines,
    required this.bill,
    required this.specialInstructions,
    required this.status,
    required Map<OrderStatus, DateTime> statusTimes,
    required this.estimatedReadyAt,
    this.feedback,
    this.isDemoSample = false,
  }) : lines = List.unmodifiable(lines),
       statusTimes = Map.unmodifiable(statusTimes);

  factory RestaurantOrder.fromJson(Map<String, dynamic> json) {
    final times = <OrderStatus, DateTime>{};
    (json['statusTimes'] as Map<String, dynamic>? ?? const {}).forEach((
      key,
      value,
    ) {
      times[OrderStatus.parse(key)] = DateTime.parse(value as String);
    });
    return RestaurantOrder(
      id: json['id'] as String,
      tableNumber: json['table'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lines: (json['lines'] as List).map(
        (line) => OrderLine.fromJson(line as Map<String, dynamic>),
      ),
      bill: BillBreakdown(
        subtotal: Money(json['subtotal'] as int),
        tax: Money(json['tax'] as int),
        total: Money(json['total'] as int),
        taxRateBasisPoints: json['taxRate'] as int,
      ),
      specialInstructions: json['instructions'] as String? ?? '',
      status: OrderStatus.parse(json['status'] as String?),
      statusTimes: times,
      estimatedReadyAt: DateTime.parse(json['readyAt'] as String),
      feedback: json['feedback'] == null
          ? null
          : OrderFeedback.fromJson(json['feedback'] as Map<String, dynamic>),
      isDemoSample: json['demo'] as bool? ?? false,
    );
  }

  final String id;
  final int tableNumber;
  final DateTime createdAt;
  final List<OrderLine> lines;
  final BillBreakdown bill;
  final String specialInstructions;
  final OrderStatus status;

  /// When each reached status happened.
  final Map<OrderStatus, DateTime> statusTimes;
  final DateTime estimatedReadyAt;
  final OrderFeedback? feedback;

  /// Seeded example order, not created by the current guest.
  final bool isDemoSample;

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  bool get isActive => status.isActive;

  /// Served orders placed by the guest can be rated once.
  bool get canRate =>
      status == OrderStatus.served && feedback == null && !isDemoSample;

  String get previewImage => lines.isEmpty ? '' : lines.first.image;

  /// Returns a copy moved to the next status, stamped with [at].
  RestaurantOrder advanced(DateTime at) {
    final next = status.next;
    if (next == null) {
      throw StateError('Order $id has already been served.');
    }
    return _copyWith(status: next, statusTimes: {...statusTimes, next: at});
  }

  RestaurantOrder withFeedback(OrderFeedback value) =>
      _copyWith(feedback: value);

  RestaurantOrder _copyWith({
    OrderStatus? status,
    Map<OrderStatus, DateTime>? statusTimes,
    OrderFeedback? feedback,
  }) => RestaurantOrder(
    id: id,
    tableNumber: tableNumber,
    createdAt: createdAt,
    lines: lines,
    bill: bill,
    specialInstructions: specialInstructions,
    status: status ?? this.status,
    statusTimes: statusTimes ?? this.statusTimes,
    estimatedReadyAt: estimatedReadyAt,
    feedback: feedback ?? this.feedback,
    isDemoSample: isDemoSample,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'table': tableNumber,
    'createdAt': createdAt.toIso8601String(),
    'lines': [for (final line in lines) line.toJson()],
    'subtotal': bill.subtotal.paise,
    'tax': bill.tax.paise,
    'total': bill.total.paise,
    'taxRate': bill.taxRateBasisPoints,
    'instructions': specialInstructions,
    'status': status.name,
    'statusTimes': {
      for (final entry in statusTimes.entries)
        entry.key.name: entry.value.toIso8601String(),
    },
    'readyAt': estimatedReadyAt.toIso8601String(),
    if (feedback != null) 'feedback': feedback!.toJson(),
    if (isDemoSample) 'demo': true,
  };
}
