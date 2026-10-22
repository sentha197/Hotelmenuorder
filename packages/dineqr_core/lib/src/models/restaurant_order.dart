import '../utils/currency.dart';
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
    this.categoryId = '',
    this.categoryName = '',
  });

  factory OrderLine.fromCartItem(CartItem line) => OrderLine(
    itemId: line.item.id,
    name: line.item.name,
    image: line.item.image,
    isVeg: line.item.isVeg,
    unitPrice: line.unitPrice,
    quantity: line.quantity,
    options: List.unmodifiable(line.optionLabels),
    categoryId: line.item.category.id,
    categoryName: line.item.category.label,
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
    categoryId: json['categoryId'] as String? ?? '',
    categoryName: json['categoryName'] as String? ?? '',
  );

  final String itemId;
  final String name;
  final String image;
  final bool isVeg;
  final Money unitPrice;
  final int quantity;
  final List<String> options;

  /// Category at the time of ordering (empty for orders saved before
  /// categories were recorded).
  final String categoryId;
  final String categoryName;

  Money get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'name': name,
    'image': image,
    'isVeg': isVeg,
    'unitPrice': unitPrice.paise,
    'quantity': quantity,
    'options': options,
    if (categoryId.isNotEmpty) 'categoryId': categoryId,
    if (categoryName.isNotEmpty) 'categoryName': categoryName,
  };
}

/// Where an order came from.
enum OrderSource {
  /// Placed by the guest in the customer app on this device.
  guest,

  /// Entered by staff in the admin dashboard.
  staff,

  /// Seed data for the demo dashboard and reports.
  demoSeed;

  static OrderSource parse(String? name) => OrderSource.values.firstWhere(
    (source) => source.name == name,
    orElse: () => OrderSource.guest,
  );
}

/// Everything needed to submit a new order.
class OrderDraft {
  OrderDraft({
    required this.tableNumber,
    required Iterable<OrderLine> lines,
    required this.bill,
    required this.specialInstructions,
    required this.estimatedPrepMinutes,
    this.source = OrderSource.guest,
  }) : lines = List.unmodifiable(lines);

  final int tableNumber;
  final List<OrderLine> lines;
  final BillBreakdown bill;
  final String specialInstructions;
  final int estimatedPrepMinutes;
  final OrderSource source;
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
    this.source = OrderSource.guest,
    this.cancelReason = '',
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
      // Pricing keys sit at the top level of the order (as before).
      bill: BillBreakdown.fromJson(json),
      specialInstructions: json['instructions'] as String? ?? '',
      status: OrderStatus.parse(json['status'] as String?),
      statusTimes: times,
      estimatedReadyAt: DateTime.parse(json['readyAt'] as String),
      feedback: json['feedback'] == null
          ? null
          : OrderFeedback.fromJson(json['feedback'] as Map<String, dynamic>),
      isDemoSample: json['demo'] as bool? ?? false,
      source: OrderSource.parse(json['source'] as String?),
      cancelReason: json['cancelReason'] as String? ?? '',
    );
  }

  final String id;
  final int tableNumber;
  final DateTime createdAt;
  final List<OrderLine> lines;

  /// Pricing snapshot at checkout. Menu price changes never alter it.
  final BillBreakdown bill;
  final String specialInstructions;
  final OrderStatus status;

  /// When each reached status happened.
  final Map<OrderStatus, DateTime> statusTimes;
  final DateTime estimatedReadyAt;
  final OrderFeedback? feedback;

  /// Sample data, not created by the current guest or staff.
  final bool isDemoSample;
  final OrderSource source;
  final String cancelReason;

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  bool get isActive => status.isActive;

  bool get isCancelled => status == OrderStatus.cancelled;

  /// Shown in the guest's "My Orders" on this device.
  bool get isGuestVisible => source == OrderSource.guest;

  /// Served orders placed by the guest can be rated once.
  bool get canRate =>
      status == OrderStatus.served && feedback == null && !isDemoSample;

  String get previewImage => lines.isEmpty ? '' : lines.first.image;

  /// Minutes since the order was placed (for kitchen screens).
  int ageInMinutes(DateTime now) => now.difference(createdAt).inMinutes;

  /// Whether the configured preparation estimate has passed.
  bool isOverdue(DateTime now) =>
      isActive &&
      status != OrderStatus.readyToServe &&
      now.isAfter(estimatedReadyAt);

  /// Returns a copy moved to the next status, stamped with [at].
  RestaurantOrder advanced(DateTime at) {
    final next = status.next;
    if (next == null) {
      throw StateError('Order $id cannot move forward from ${status.name}.');
    }
    return withStatus(next, at);
  }

  /// Returns a copy in [target], which must be a valid transition.
  RestaurantOrder withStatus(
    OrderStatus target,
    DateTime at, {
    String reason = '',
  }) {
    if (!status.canTransitionTo(target)) {
      throw StateError(
        'Order $id cannot go from ${status.name} to ${target.name}.',
      );
    }
    return _copyWith(
      status: target,
      statusTimes: {...statusTimes, target: at},
      cancelReason: target == OrderStatus.cancelled ? reason : null,
    );
  }

  RestaurantOrder withFeedback(OrderFeedback value) =>
      _copyWith(feedback: value);

  RestaurantOrder _copyWith({
    OrderStatus? status,
    Map<OrderStatus, DateTime>? statusTimes,
    OrderFeedback? feedback,
    String? cancelReason,
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
    source: source,
    cancelReason: cancelReason ?? this.cancelReason,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'table': tableNumber,
    'createdAt': createdAt.toIso8601String(),
    'lines': [for (final line in lines) line.toJson()],
    ...bill.toJson(),
    'instructions': specialInstructions,
    'status': status.name,
    'statusTimes': {
      for (final entry in statusTimes.entries)
        entry.key.name: entry.value.toIso8601String(),
    },
    'readyAt': estimatedReadyAt.toIso8601String(),
    if (feedback != null) 'feedback': feedback!.toJson(),
    if (isDemoSample) 'demo': true,
    if (source != OrderSource.guest) 'source': source.name,
    if (cancelReason.isNotEmpty) 'cancelReason': cancelReason,
  };
}
