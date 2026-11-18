import type { Permission } from './access';
import { billFromJson, type BillBreakdown } from './pricing';
import { parseInstant } from './time';

type Json = Record<string, unknown>;

/**
 * Kitchen workflow. Orders move forward one step at a time and can be
 * cancelled until they are ready to serve. A takeaway order goes through the
 * same stages; only how the last two read changes.
 */
export type OrderStatus = 'placed' | 'accepted' | 'preparing' | 'readyToServe' | 'served' | 'cancelled';

export const orderFlow: readonly OrderStatus[] = ['placed', 'accepted', 'preparing', 'readyToServe', 'served'];

const statusLabels: Record<OrderStatus, [string, string]> = {
  placed: ['Order Placed', 'Placed'],
  accepted: ['Accepted by Kitchen', 'Accepted'],
  preparing: ['Preparing in Kitchen', 'Preparing'],
  readyToServe: ['Ready to Serve', 'Ready'],
  served: ['Served at Table', 'Served'],
  cancelled: ['Cancelled', 'Cancelled'],
};

export const OrderStatuses = {
  label(status: OrderStatus, takeaway = false): string {
    if (takeaway && status === 'readyToServe') return 'Ready for Pickup';
    if (takeaway && status === 'served') return 'Collected';
    return statusLabels[status][0];
  },
  shortLabel(status: OrderStatus, takeaway = false): string {
    if (takeaway && status === 'served') return 'Collected';
    return statusLabels[status][1];
  },
  next(status: OrderStatus): OrderStatus | null {
    const i = orderFlow.indexOf(status);
    return i === -1 || i === orderFlow.length - 1 ? null : orderFlow[i + 1]!;
  },
  isActive: (s: OrderStatus) => s !== 'served' && s !== 'cancelled',
  /** Restaurant policy: an order can be cancelled until it is ready. */
  canCancel: (s: OrderStatus) => s === 'placed' || s === 'accepted' || s === 'preparing',
  canTransitionTo: (s: OrderStatus, target: OrderStatus) => target === OrderStatuses.next(s) || (target === 'cancelled' && OrderStatuses.canCancel(s)),
  parse: (name: unknown): OrderStatus => (name as OrderStatus) in statusLabels ? (name as OrderStatus) : 'placed',
  /** The permission needed to move an order to [target] (OrderController.permissionFor). */
  permissionFor: (target: OrderStatus): Permission => (target === 'served' ? 'serveOrders' : target === 'cancelled' ? 'cancelOrders' : 'manageKitchen'),
};

/** Table number of a takeaway order (real tables start at 1). */
export const TAKEAWAY_TABLE = 0;

export const Tables = {
  isTakeaway: (table: number) => table === TAKEAWAY_TABLE,
  /** `Table 07` or `Takeaway`. */
  label: (table: number) => (table === TAKEAWAY_TABLE ? 'Takeaway' : `Table ${String(table).padStart(2, '0')}`),
  /** `07`, or `Takeaway` (for places already headed "Table"). */
  shortLabel: (table: number) => (table === TAKEAWAY_TABLE ? 'Takeaway' : String(table).padStart(2, '0')),
};

export interface ComboPart {
  itemId: string;
  name: string;
  quantity: number;
}

/** One ordered dish (or combo), frozen at checkout time. */
export interface OrderLine {
  itemId: string;
  name: string;
  image: string;
  isVeg: boolean;
  /** The full price of one unit. */
  unitPrice: number;
  quantity: number;
  /** The chosen options, or a combo's dishes. */
  options: string[];
  categoryId: string;
  categoryName: string;
  comboId: string | null;
  comboItems: ComboPart[];
  discount: number;
  discountLabel: string | null;
  promotionId: string | null;
}

export function orderLineFromJson(json: Json): OrderLine {
  return {
    itemId: String(json.itemId),
    name: String(json.name ?? ''),
    image: (json.image as string | undefined) ?? '',
    isVeg: Boolean(json.isVeg),
    unitPrice: json.unitPrice as number,
    quantity: json.quantity as number,
    options: ((json.options as unknown[] | undefined) ?? []).map(String),
    categoryId: (json.categoryId as string | undefined) ?? '',
    categoryName: (json.categoryName as string | undefined) ?? '',
    comboId: (json.comboId as string | undefined) ?? null,
    comboItems: ((json.comboItems as Json[] | undefined) ?? []).map((p) => ({
      itemId: String(p.itemId),
      name: (p.name as string | undefined) ?? '',
      quantity: (p.quantity as number | undefined) ?? 1,
    })),
    discount: (json.discount as number | undefined) ?? 0,
    discountLabel: (json.discountLabel as string | undefined) ?? null,
    promotionId: (json.promotionId as string | undefined) ?? null,
  };
}

export const lineTotal = (line: OrderLine) => line.unitPrice * line.quantity;

export type OrderSource = 'guest' | 'staff' | 'demoSeed';

export interface OrderFeedback {
  rating: number;
  comment: string;
  submittedAt: Date;
}

export interface RestaurantOrder {
  id: string;
  /** The table, or [TAKEAWAY_TABLE]. */
  tableNumber: number;
  createdAt: Date;
  lines: OrderLine[];
  /** Pricing snapshot at checkout. */
  bill: BillBreakdown;
  specialInstructions: string;
  status: OrderStatus;
  /** When each reached status happened. */
  statusTimes: Partial<Record<OrderStatus, Date>>;
  estimatedReadyAt: Date;
  feedback: OrderFeedback | null;
  isDemoSample: boolean;
  source: OrderSource;
  cancelReason: string;
}

export function orderFromJson(json: Json): RestaurantOrder {
  const times: Partial<Record<OrderStatus, Date>> = {};
  for (const [key, value] of Object.entries((json.statusTimes as Json | undefined) ?? {})) {
    times[OrderStatuses.parse(key)] = parseInstant(value);
  }
  const feedback = json.feedback as Json | undefined | null;
  return {
    id: String(json.id),
    tableNumber: json.table as number,
    createdAt: parseInstant(json.createdAt),
    lines: ((json.lines as Json[] | undefined) ?? []).map(orderLineFromJson),
    // Pricing keys sit at the top level of the order.
    bill: billFromJson(json),
    specialInstructions: (json.instructions as string | undefined) ?? '',
    status: OrderStatuses.parse(json.status),
    statusTimes: times,
    estimatedReadyAt: parseInstant(json.readyAt),
    feedback: feedback
      ? { rating: feedback.rating as number, comment: (feedback.comment as string | undefined) ?? '', submittedAt: parseInstant(feedback.submittedAt) }
      : null,
    isDemoSample: (json.demo as boolean | undefined) ?? false,
    source: json.source === 'staff' ? 'staff' : json.source === 'demoSeed' ? 'demoSeed' : 'guest',
    cancelReason: (json.cancelReason as string | undefined) ?? '',
  };
}

export const Orders = {
  itemCount: (o: RestaurantOrder) => o.lines.reduce((sum, l) => sum + l.quantity, 0),
  isTakeaway: (o: RestaurantOrder) => o.tableNumber === TAKEAWAY_TABLE,
  tableLabel: (o: RestaurantOrder) => Tables.label(o.tableNumber),
  statusLabel: (o: RestaurantOrder) => OrderStatuses.label(o.status, Orders.isTakeaway(o)),
  shortStatus: (o: RestaurantOrder) => OrderStatuses.shortLabel(o.status, Orders.isTakeaway(o)),
  isActive: (o: RestaurantOrder) => OrderStatuses.isActive(o.status),
  isCancelled: (o: RestaurantOrder) => o.status === 'cancelled',
  /** Whole minutes since the order was placed. */
  ageInMinutes: (o: RestaurantOrder, now: Date) => Math.floor((now.getTime() - o.createdAt.getTime()) / 60_000),
  /** Whether the preparation estimate has passed. */
  isOverdue: (o: RestaurantOrder, now: Date) => Orders.isActive(o) && o.status !== 'readyToServe' && now > o.estimatedReadyAt,
};

/** The next workflow step for an order, as a staff action. */
export interface OrderAction {
  target: OrderStatus;
  label: string;
  icon: 'accept' | 'cook' | 'ready' | 'pickup' | 'done';
}

export function nextOrderAction(status: OrderStatus, takeaway: boolean): OrderAction | null {
  switch (status) {
    case 'placed':
      return { target: 'accepted', label: 'Accept', icon: 'accept' };
    case 'accepted':
      return { target: 'preparing', label: 'Start preparing', icon: 'cook' };
    case 'preparing':
      return { target: 'readyToServe', label: takeaway ? 'Ready for pickup' : 'Mark ready', icon: takeaway ? 'pickup' : 'ready' };
    case 'readyToServe':
      return { target: 'served', label: takeaway ? 'Mark collected' : 'Mark served', icon: 'done' };
    default:
      return null;
  }
}
