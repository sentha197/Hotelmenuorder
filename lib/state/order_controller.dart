import 'package:flutter/foundation.dart';

import '../data/models/order_feedback.dart';
import '../data/models/restaurant_order.dart';
import '../data/repositories/order_repository.dart';
import 'cart_controller.dart';

enum CheckoutError {
  emptyCart('Your cart is empty. Add a dish to place an order.'),
  missingTable('Scan your table QR code before placing an order.'),
  alreadyPlacing('Your order is already being placed.'),
  failed('We could not place your order. Please try again.');

  const CheckoutError(this.message);

  final String message;
}

class CheckoutException implements Exception {
  const CheckoutException(this.error);

  final CheckoutError error;

  @override
  String toString() => 'CheckoutException(${error.name})';
}

/// Order history, checkout, tracking progression and feedback.
class OrderController extends ChangeNotifier {
  OrderController(this._repository);

  final OrderRepository _repository;

  List<RestaurantOrder> _orders = const [];
  bool _isPlacing = false;
  final Set<String> _busy = {};

  List<RestaurantOrder> get orders => _orders;

  List<RestaurantOrder> get currentOrders =>
      _orders.where((order) => order.isActive).toList(growable: false);

  List<RestaurantOrder> get pastOrders =>
      _orders.where((order) => !order.isActive).toList(growable: false);

  bool get isPlacing => _isPlacing;

  bool isBusy(String orderId) => _busy.contains(orderId);

  RestaurantOrder? byId(String id) {
    for (final order in _orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  Future<void> load() async {
    _orders = await _repository.fetchOrders();
    notifyListeners();
  }

  /// Validates the cart, snapshots it into a new order and clears the cart
  /// only after the order was created. Repeated calls while an order is being
  /// placed are rejected.
  Future<RestaurantOrder> placeOrder({
    required CartController cart,
    required int? tableNumber,
  }) async {
    if (_isPlacing) throw const CheckoutException(CheckoutError.alreadyPlacing);
    if (tableNumber == null) {
      throw const CheckoutException(CheckoutError.missingTable);
    }
    if (cart.isEmpty) throw const CheckoutException(CheckoutError.emptyCart);

    _isPlacing = true;
    notifyListeners();
    try {
      final draft = OrderDraft(
        tableNumber: tableNumber,
        lines: cart.lines.map(OrderLine.fromCartItem),
        bill: cart.bill,
        specialInstructions: cart.specialInstructions.trim(),
        estimatedPrepMinutes: cart.estimatedPrepMinutes + 5,
      );
      final order = await _repository.submitOrder(draft);
      _orders = [
        order,
        ..._orders.where((existing) => existing.id != order.id),
      ];
      cart.clear();
      return order;
    } on CheckoutException {
      rethrow;
    } on Object {
      throw const CheckoutException(CheckoutError.failed);
    } finally {
      _isPlacing = false;
      notifyListeners();
    }
  }

  /// Demo-only: moves an order to its next kitchen status.
  Future<RestaurantOrder?> advanceStatus(String orderId) async {
    final order = byId(orderId);
    if (order == null || order.status.next == null || !_busy.add(orderId)) {
      return null;
    }
    notifyListeners();
    try {
      final updated = await _repository.advanceStatus(orderId);
      _replace(updated);
      return updated;
    } finally {
      _busy.remove(orderId);
      notifyListeners();
    }
  }

  /// Stores a rating against a served order. Throws [FeedbackException] for
  /// invalid input and [StateError] when the order cannot be rated.
  Future<RestaurantOrder> submitFeedback(
    String orderId, {
    required int rating,
    required String comment,
    DateTime? submittedAt,
  }) async {
    final error = OrderFeedback.validate(rating: rating, comment: comment);
    if (error != null) throw FeedbackException(error);
    final order = byId(orderId);
    if (order == null || !order.canRate) {
      throw StateError('Order $orderId cannot be rated.');
    }
    if (!_busy.add(orderId)) throw StateError('Feedback already submitting.');
    notifyListeners();
    try {
      final updated = await _repository.submitFeedback(
        orderId,
        OrderFeedback(
          rating: rating,
          comment: comment.trim(),
          submittedAt: submittedAt ?? DateTime.now(),
        ),
      );
      _replace(updated);
      return updated;
    } finally {
      _busy.remove(orderId);
      notifyListeners();
    }
  }

  Future<void> resetDemo() async {
    await _repository.reset();
    await load();
  }

  void _replace(RestaurantOrder updated) {
    _orders = [
      for (final order in _orders) order.id == updated.id ? updated : order,
    ];
  }
}
