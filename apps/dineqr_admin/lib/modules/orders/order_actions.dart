import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../widgets/admin_widgets.dart';

/// The next workflow step for an order, as a staff action.
class OrderAction {
  const OrderAction(this.target, this.label, this.icon);

  final OrderStatus target;
  final String label;
  final IconData icon;

  /// The step after [status]. A takeaway order ([type]) is handed over at
  /// the counter, so its last step reads "Mark collected".
  static OrderAction? next(
    OrderStatus status, [
    OrderType type = OrderType.dineIn,
  ]) => switch (status) {
    OrderStatus.placed => const OrderAction(
      OrderStatus.accepted,
      'Accept',
      Icons.thumb_up_alt_rounded,
    ),
    OrderStatus.accepted => const OrderAction(
      OrderStatus.preparing,
      'Start preparing',
      Icons.soup_kitchen_rounded,
    ),
    OrderStatus.preparing => OrderAction(
      OrderStatus.readyToServe,
      type.isTakeaway ? 'Ready for pickup' : 'Mark ready',
      type.isTakeaway ? Icons.shopping_bag_rounded : Icons.room_service_rounded,
    ),
    OrderStatus.readyToServe => OrderAction(
      OrderStatus.served,
      type.isTakeaway ? 'Mark collected' : 'Mark served',
      Icons.check_circle_rounded,
    ),
    _ => null,
  };

  /// Whether the signed-in staff member may perform this step.
  bool allowedFor(AdminSessionController admin) =>
      admin.can(OrderController.permissionFor(target));
}

/// Moves [order] to its next status (with permission checks in the
/// controller).
Future<bool> advanceOrder(BuildContext context, RestaurantOrder order) {
  final action = OrderAction.next(order.status, order.type);
  if (action == null) return Future.value(false);
  return runAdminAction(
    context,
    () => context.read<OrderController>().updateStatus(order.id, action.target),
    success: 'Order ${order.id}: ${action.target.shortLabelFor(order.type)}',
  );
}

/// Asks for a reason, then cancels [order].
Future<bool> cancelOrder(BuildContext context, RestaurantOrder order) async {
  final reason = await askForText(
    context,
    title: 'Cancel order ${order.id}?',
    label: 'Reason (shown to the guest)',
    message:
        'The guest sees the reason in their tracking screen. Any payment '
        'already taken stays recorded and shows as a refund due.',
    confirmLabel: 'Cancel order',
  );
  if (reason == null || !context.mounted) return false;
  return runAdminAction(
    context,
    () => context.read<OrderController>().updateStatus(
      order.id,
      OrderStatus.cancelled,
      reason: reason,
    ),
    success: 'Order ${order.id} cancelled',
  );
}
