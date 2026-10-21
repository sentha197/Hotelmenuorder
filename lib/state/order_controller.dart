import 'package:flutter/foundation.dart';

import '../core/utils/formatters.dart';
import '../data/models/order_feedback.dart';
import '../data/models/order_status.dart';
import '../data/models/restaurant_order.dart';
import '../data/models/staff.dart';
import '../data/repositories/order_repository.dart';
import 'admin_session_controller.dart';
import 'cart_controller.dart';
import 'settings_controller.dart';

enum CheckoutError {
  emptyCart('Your cart is empty. Add a dish to place an order.'),
  missingTable('Scan your table QR code before placing an order.'),
  tableUnavailable(
    'This table is not taking orders right now. Please ask a staff member.',
  ),
  itemsUnavailable(
    'Some dishes in your cart are no longer available. Please review your cart.',
  ),
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

/// Orders: guest checkout, history, tracking, feedback, and the admin
/// workflow (status changes, cancellations, staff-entered orders).
class OrderController extends ChangeNotifier {
  OrderController(
    this._repository, {
    this._guard,
    this._audit,
    this._isTableOrderable,
    this._prepBuffer,
    this._onPlaced,
    this._onCancelled,
  });

  final OrderRepository _repository;
  final AccessGuard? _guard;
  final AuditLog? _audit;
  final bool Function(int table)? _isTableOrderable;
  final int Function()? _prepBuffer;

  /// Creates the bill for a new order.
  final Future<void> Function(RestaurantOrder order)? _onPlaced;

  /// Voids the bill of a cancelled order.
  final Future<void> Function(RestaurantOrder order)? _onCancelled;

  List<RestaurantOrder> _orders = const [];
  bool _isPlacing = false;
  final Set<String> _busy = {};

  /// Every order (admin, reports).
  List<RestaurantOrder> get orders => _orders;

  /// Orders the guest placed on this device (plus labelled examples).
  List<RestaurantOrder> get guestOrders =>
      _orders.where((order) => order.isGuestVisible).toList(growable: false);

  List<RestaurantOrder> get currentOrders =>
      guestOrders.where((order) => order.isActive).toList(growable: false);

  List<RestaurantOrder> get pastOrders =>
      guestOrders.where((order) => !order.isActive).toList(growable: false);

  /// All orders still in progress, oldest first (admin, kitchen).
  List<RestaurantOrder> get activeOrders =>
      _orders.where((order) => order.isActive).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool get isPlacing => _isPlacing;

  bool isBusy(String orderId) => _busy.contains(orderId);

  RestaurantOrder? byId(String id) {
    for (final order in _orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  /// Orders for one table that are still active.
  List<RestaurantOrder> activeForTable(int table) => _orders
      .where((o) => o.tableNumber == table && o.isActive)
      .toList(growable: false);

  Future<void> load() async {
    _orders = await _repository.fetchOrders();
    notifyListeners();
  }

  /// Validates the cart, snapshots it into a new order and clears the cart
  /// only after the order was created. Repeated calls while an order is being
  /// placed are rejected. Staff orders need [Permission.createOrders].
  Future<RestaurantOrder> placeOrder({
    required CartController cart,
    required int? tableNumber,
    OrderSource source = OrderSource.guest,
  }) async {
    if (source == OrderSource.staff) {
      _requireGuard().require(Permission.createOrders);
    }
    if (_isPlacing) throw const CheckoutException(CheckoutError.alreadyPlacing);
    if (tableNumber == null) {
      throw const CheckoutException(CheckoutError.missingTable);
    }
    final tableOk = _isTableOrderable;
    if (tableOk != null && !tableOk(tableNumber)) {
      throw const CheckoutException(CheckoutError.tableUnavailable);
    }
    if (cart.isEmpty) throw const CheckoutException(CheckoutError.emptyCart);
    if (cart.unavailableLines.isNotEmpty) {
      throw const CheckoutException(CheckoutError.itemsUnavailable);
    }

    _isPlacing = true;
    notifyListeners();
    try {
      final draft = OrderDraft(
        tableNumber: tableNumber,
        lines: cart.lines.map(OrderLine.fromCartItem),
        bill: cart.bill,
        specialInstructions: cart.specialInstructions.trim(),
        estimatedPrepMinutes:
            cart.estimatedPrepMinutes + (_prepBuffer?.call() ?? 5),
        source: source,
      );
      final order = await _repository.submitOrder(draft);
      _orders = [
        order,
        ..._orders.where((existing) => existing.id != order.id),
      ];
      cart.clear();
      try {
        await _onPlaced?.call(order);
      } on Object catch (error) {
        // The order exists; the bill can be created again from the order.
        debugPrint('Bill creation failed for ${order.id}: $error');
      }
      if (source == OrderSource.staff) {
        await _audit?.record(
          'order.create',
          'Created order ${order.id} for table '
              '${AppFormat.table(order.tableNumber)}',
          targetId: order.id,
        );
      }
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

  /// Demo-only: simulates the kitchen moving an order to its next status.
  /// Shown to guests only in the offline demo, clearly labelled.
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

  /// The permission needed to move an order to [target].
  static Permission permissionFor(OrderStatus target) => switch (target) {
    OrderStatus.served => Permission.serveOrders,
    OrderStatus.cancelled => Permission.cancelOrders,
    _ => Permission.manageKitchen,
  };

  /// Admin: moves an order to [target]. Cancelling needs a [reason].
  Future<RestaurantOrder> updateStatus(
    String orderId,
    OrderStatus target, {
    String reason = '',
  }) async {
    _requireGuard().require(permissionFor(target));
    final order = byId(orderId);
    if (order == null) throw StateError('Unknown order $orderId');
    if (!order.status.canTransitionTo(target)) {
      throw ValidationException(
        'Order ${order.id} is ${order.status.shortLabel.toLowerCase()} and '
        'cannot be ${target == OrderStatus.cancelled ? 'cancelled' : 'moved to ${target.shortLabel.toLowerCase()}'}.',
      );
    }
    final why = reason.trim();
    if (target == OrderStatus.cancelled && why.length < 3) {
      throw const ValidationException('Enter a reason for cancelling.');
    }
    if (!_busy.add(orderId)) {
      throw const ValidationException('This order is already being updated.');
    }
    notifyListeners();
    try {
      final updated = await _repository.updateStatus(
        orderId,
        target,
        reason: why,
      );
      _replace(updated);
      if (target == OrderStatus.cancelled) {
        await _onCancelled?.call(updated);
      }
      await _audit?.record(
        target == OrderStatus.cancelled ? 'order.cancel' : 'order.status',
        target == OrderStatus.cancelled
            ? 'Cancelled order $orderId: $why'
            : 'Order $orderId: ${order.status.shortLabel} → ${target.shortLabel}',
        targetId: orderId,
      );
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

  /// Restores demo orders. When [orders] is given (full reset) they replace
  /// the history so they match freshly seeded bills.
  Future<void> resetDemo({List<RestaurantOrder>? orders}) async {
    final repository = _repository;
    if (orders != null && repository is LocalOrderRepository) {
      await repository.replaceAll(orders);
    } else {
      await repository.reset();
    }
    await load();
  }

  AccessGuard _requireGuard() {
    final guard = _guard;
    if (guard == null) throw StateError('Admin actions need an AccessGuard.');
    return guard;
  }

  void _replace(RestaurantOrder updated) {
    _orders = [
      for (final order in _orders) order.id == updated.id ? updated : order,
    ];
  }
}
