import 'dart:convert';
import 'dart:math' as math;

import '../demo/demo_seed.dart';
import '../models/order_feedback.dart';
import '../models/order_status.dart';
import '../models/restaurant_order.dart';
import '../storage/key_value_store.dart';

/// Order backend. The demo implementation keeps everything on the device; a
/// real implementation would call the restaurant's ordering API, which must
/// also authorise status changes.
abstract interface class OrderRepository {
  Future<List<RestaurantOrder>> fetchOrders();

  Future<RestaurantOrder> submitOrder(OrderDraft draft);

  /// Moves an order one step along the kitchen workflow.
  Future<RestaurantOrder> advanceStatus(String orderId);

  /// Moves an order to [target] (any valid transition, including cancel).
  Future<RestaurantOrder> updateStatus(
    String orderId,
    OrderStatus target, {
    String reason = '',
  });

  Future<RestaurantOrder> submitFeedback(
    String orderId,
    OrderFeedback feedback,
  );

  /// Restores the demo state.
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
    this.seed,
  }) : _clock = clock ?? DateTime.now {
    _orders = _load();
  }

  final KeyValueStore _store;
  final DateTime Function() _clock;

  /// Simulated network delay for order submission.
  final Duration latency;
  final bool seedDemoOrders;

  /// Samples for a fresh install (defaults to [DemoSeed]).
  final List<RestaurantOrder>? seed;

  late List<RestaurantOrder> _orders;

  List<RestaurantOrder> _seedOrders() {
    if (!seedDemoOrders) return [];
    return [...(seed ?? DemoSeed.generate(_clock()).orders)];
  }

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
      source: draft.source,
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
  Future<RestaurantOrder> updateStatus(
    String orderId,
    OrderStatus target, {
    String reason = '',
  }) async {
    final current = _find(orderId);
    final updated = current.withStatus(target, _clock(), reason: reason);
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
    _orders = seedDemoOrders ? DemoSeed.generate(_clock()).orders : [];
    await _persist();
  }

  /// Replaces every order (used by a full demo reset so orders and bills are
  /// regenerated from the same seed).
  Future<void> replaceAll(List<RestaurantOrder> orders) async {
    _orders = [...orders];
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
    if (raw == null) return _seedOrders();
    try {
      return (jsonDecode(raw) as List)
          .map((json) => RestaurantOrder.fromJson(json as Map<String, dynamic>))
          .toList();
    } on Object {
      // Corrupt data should never brick the app.
      return _seedOrders();
    }
  }

  Future<void> _persist() => _store.write(
    StorageKeys.orders,
    jsonEncode([for (final order in _orders) order.toJson()]),
  );
}
