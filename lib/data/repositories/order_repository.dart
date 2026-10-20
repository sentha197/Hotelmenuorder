import 'dart:convert';
import 'dart:math' as math;

import '../../core/utils/currency.dart';
import '../models/order_feedback.dart';
import '../models/order_status.dart';
import '../models/pricing.dart';
import '../models/restaurant_order.dart';
import '../storage/key_value_store.dart';

/// Order backend. The demo implementation keeps everything on the device; a
/// real implementation would call the restaurant's ordering API.
abstract interface class OrderRepository {
  Future<List<RestaurantOrder>> fetchOrders();

  Future<RestaurantOrder> submitOrder(OrderDraft draft);

  Future<RestaurantOrder> advanceStatus(String orderId);

  Future<RestaurantOrder> submitFeedback(
    String orderId,
    OrderFeedback feedback,
  );

  Future<void> reset();
}

/// Generates sequential, human friendly order ids such as `OD12345`.
abstract final class OrderIdGenerator {
  static const prefix = 'OD';
  static const firstNumber = 12345;

  static String next(Iterable<String> existingIds) {
    var highest = firstNumber - 1;
    for (final id in existingIds) {
      if (!id.startsWith(prefix)) continue;
      final number = int.tryParse(id.substring(prefix.length));
      if (number != null) highest = math.max(highest, number);
    }
    return '$prefix${highest + 1}';
  }
}

class LocalOrderRepository implements OrderRepository {
  LocalOrderRepository(
    this._store, {
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 900),
    this.seedDemoOrders = true,
  }) : _clock = clock ?? DateTime.now {
    _orders = _load();
  }

  final KeyValueStore _store;
  final DateTime Function() _clock;

  /// Simulated network delay for order submission.
  final Duration latency;
  final bool seedDemoOrders;

  late List<RestaurantOrder> _orders;

  @override
  Future<List<RestaurantOrder>> fetchOrders() async =>
      List.unmodifiable(_orders);

  @override
  Future<RestaurantOrder> submitOrder(OrderDraft draft) async {
    if (draft.lines.isEmpty) {
      throw StateError('Cannot submit an empty order.');
    }
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final now = _clock();
    final order = RestaurantOrder(
      id: OrderIdGenerator.next(_orders.map((order) => order.id)),
      tableNumber: draft.tableNumber,
      createdAt: now,
      lines: draft.lines,
      bill: draft.bill,
      specialInstructions: draft.specialInstructions,
      status: OrderStatus.placed,
      statusTimes: {OrderStatus.placed: now},
      estimatedReadyAt: now.add(Duration(minutes: draft.estimatedPrepMinutes)),
    );
    _orders = [order, ..._orders];
    await _persist();
    return order;
  }

  @override
  Future<RestaurantOrder> advanceStatus(String orderId) async {
    final current = _find(orderId);
    final updated = current.advanced(_clock());
    _replace(updated);
    await _persist();
    return updated;
  }

  @override
  Future<RestaurantOrder> submitFeedback(
    String orderId,
    OrderFeedback feedback,
  ) async {
    final current = _find(orderId);
    if (current.feedback != null) {
      throw StateError('Feedback was already submitted for $orderId.');
    }
    final error = OrderFeedback.validate(
      rating: feedback.rating,
      comment: feedback.comment,
    );
    if (error != null) throw FeedbackException(error);
    final updated = current.withFeedback(feedback);
    _replace(updated);
    await _persist();
    return updated;
  }

  @override
  Future<void> reset() async {
    _orders = seedDemoOrders ? _demoSamples() : [];
    await _persist();
  }

  RestaurantOrder _find(String id) => _orders.firstWhere(
    (order) => order.id == id,
    orElse: () => throw StateError('Unknown order $id'),
  );

  void _replace(RestaurantOrder updated) {
    _orders = [
      for (final order in _orders) order.id == updated.id ? updated : order,
    ];
  }

  List<RestaurantOrder> _load() {
    final raw = _store.read(StorageKeys.orders);
    if (raw == null) return seedDemoOrders ? _demoSamples() : [];
    try {
      return (jsonDecode(raw) as List)
          .map((json) => RestaurantOrder.fromJson(json as Map<String, dynamic>))
          .toList();
    } on Object {
      // Corrupt data should never brick the app.
      return seedDemoOrders ? _demoSamples() : [];
    }
  }

  Future<void> _persist() => _store.write(
    StorageKeys.orders,
    jsonEncode([for (final order in _orders) order.toJson()]),
  );

  /// Two clearly labelled sample orders so "Past Orders" is not empty on a
  /// fresh install. They are flagged with [RestaurantOrder.isDemoSample].
  List<RestaurantOrder> _demoSamples() {
    final now = _clock();
    const config = PricingConfig();
    RestaurantOrder sample({
      required String id,
      required int table,
      required Duration ago,
      required List<OrderLine> lines,
    }) {
      final placed = now.subtract(ago);
      final subtotal = Money.sum(lines.map((line) => line.lineTotal));
      return RestaurantOrder(
        id: id,
        tableNumber: table,
        createdAt: placed,
        lines: lines,
        bill: BillBreakdown.fromSubtotal(subtotal, config),
        specialInstructions: '',
        status: OrderStatus.served,
        statusTimes: {
          OrderStatus.placed: placed,
          OrderStatus.preparing: placed.add(const Duration(minutes: 2)),
          OrderStatus.readyToServe: placed.add(const Duration(minutes: 18)),
          OrderStatus.served: placed.add(const Duration(minutes: 21)),
        },
        estimatedReadyAt: placed.add(const Duration(minutes: 20)),
        isDemoSample: true,
      );
    }

    return [
      sample(
        id: 'OD12318',
        table: 12,
        ago: const Duration(days: 2, hours: 3),
        lines: const [
          OrderLine(
            itemId: 'chicken_biryani',
            name: 'Chicken Biryani',
            image: 'assets/images/chicken_biryani.jpg',
            isVeg: false,
            unitPrice: Money.rupees(260),
            quantity: 2,
            options: ['Spice: Medium'],
          ),
          OrderLine(
            itemId: 'lassi',
            name: 'Classic Lassi',
            image: 'assets/images/lassi.jpg',
            isVeg: true,
            unitPrice: Money.rupees(90),
            quantity: 2,
          ),
        ],
      ),
      sample(
        id: 'OD12301',
        table: 5,
        ago: const Duration(days: 6, hours: 1),
        lines: const [
          OrderLine(
            itemId: 'masala_dosa',
            name: 'Masala Dosa',
            image: 'assets/images/masala_dosa.jpg',
            isVeg: true,
            unitPrice: Money.rupees(100),
            quantity: 1,
          ),
          OrderLine(
            itemId: 'gulab_jamun',
            name: 'Gulab Jamun',
            image: 'assets/images/gulab_jamun.jpg',
            isVeg: true,
            unitPrice: Money.rupees(90),
            quantity: 1,
          ),
        ],
      ),
    ];
  }
}
