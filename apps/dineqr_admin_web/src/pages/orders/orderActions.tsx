import { Ban, CircleCheck, CookingPot, ShoppingBag, ConciergeBell, ThumbsUp, type LucideIcon } from 'lucide-react';
import { promptDialog } from '@/components/ui/Dialog';
import { nextOrderAction, OrderStatuses, Orders, type OrderAction, type RestaurantOrder } from '@/core/orders';
import { updateOrderStatus } from '@/state/actions';
import { runAction } from '@/state/run';
import { Session } from '@/state/session';

export const actionIcon: Record<OrderAction['icon'], LucideIcon> = {
  accept: ThumbsUp,
  cook: CookingPot,
  ready: ConciergeBell,
  pickup: ShoppingBag,
  done: CircleCheck,
};

/** The next step for [order] when the signed-in staff member may take it. */
export function allowedAction(order: RestaurantOrder, can: (p: Parameters<typeof Session.can>[0]) => boolean): OrderAction | null {
  const action = nextOrderAction(order.status, Orders.isTakeaway(order));
  return action && can(OrderStatuses.permissionFor(action.target)) ? action : null;
}

/** Moves [order] to its next status. */
export function advanceOrder(order: RestaurantOrder) {
  const action = nextOrderAction(order.status, Orders.isTakeaway(order));
  if (!action) return Promise.resolve(false);
  return runAction(() => updateOrderStatus(order, action.target), {
    success: `Order ${order.id}: ${OrderStatuses.shortLabel(action.target, Orders.isTakeaway(order))}`,
  });
}

/** Asks for a reason, then cancels [order]. */
export async function cancelOrder(order: RestaurantOrder) {
  const reason = await promptDialog({
    title: `Cancel order ${order.id}?`,
    label: 'Reason (shown to the guest)',
    message: 'The guest sees the reason in their tracking screen. Any payment already taken stays recorded and shows as a refund due.',
    confirmLabel: 'Cancel order',
  });
  if (reason == null) return false;
  return runAction(() => updateOrderStatus(order, 'cancelled', reason), { success: `Order ${order.id} cancelled` });
}

export const CancelIcon = Ban;
