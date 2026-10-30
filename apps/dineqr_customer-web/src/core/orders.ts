import { BillBreakdown } from './pricing';
import type { Paise } from './money';

type Json = Record<string, unknown>;

export type OrderType = 'dineIn' | 'takeaway';

/** Table number of a takeaway order (real tables start at 1). */
export const TAKEAWAY_TABLE = 0;

export const OrderTables = {
  isTakeaway: (table: number) => table === TAKEAWAY_TABLE,
  typeOf: (table: number): OrderType => (table === TAKEAWAY_TABLE ? 'takeaway' : 'dineIn'),
  /** `Table 07` or `Takeaway`. */
  label: (table: number) => (table === TAKEAWAY_TABLE ? 'Takeaway' : `Table ${table.toString().padStart(2, '0')}`),
};

export type OrderStatus = 'placed' | 'accepted' | 'preparing' | 'readyToServe' | 'served' | 'cancelled';

const statusLabels: Record<OrderStatus, [label: string, short: string]> = {
  placed: ['Order Placed', 'Placed'],
  accepted: ['Accepted by Kitchen', 'Accepted'],
  preparing: ['Preparing in Kitchen', 'Preparing'],
  readyToServe: ['Ready to Serve', 'Ready'],
  served: ['Served at Table', 'Served'],
  cancelled: ['Cancelled', 'Cancelled'],
};

export const OrderStatuses = {
  /** The forward workflow, without cancelled. */
  flow: ['placed', 'accepted', 'preparing', 'readyToServe', 'served'] as OrderStatus[],
  /** The four stages shown to guests; accepted shows as part of placed. */
  customerStages: ['placed', 'preparing', 'readyToServe', 'served'] as OrderStatus[],
  parse(name: unknown): OrderStatus {
    return typeof name === 'string' && name in statusLabels ? (name as OrderStatus) : 'placed';
  },
  label(status: OrderStatus, type: OrderType = 'dineIn'): string {
    if (type === 'takeaway' && status === 'readyToServe') return 'Ready for Pickup';
    if (type === 'takeaway' && status === 'served') return 'Collected';
    return statusLabels[status][0];
  },
  shortLabel(status: OrderStatus, type: OrderType = 'dineIn'): string {
    if (type === 'takeaway' && status === 'served') return 'Collected';
    return statusLabels[status][1];
  },
  next(status: OrderStatus): OrderStatus | null {
    const flow = OrderStatuses.flow;
    const index = flow.indexOf(status);
    return index === -1 || index === flow.length - 1 ? null : flow[index + 1]!;
  },
  isActive: (status: OrderStatus) => status !== 'served' && status !== 'cancelled',
  customerStage: (status: OrderStatus): OrderStatus => (status === 'accepted' ? 'placed' : status),
};

/** One ordered dish, frozen at checkout. */
export interface OrderLine {
  itemId: string;
  name: string;
  image: string;
  isVeg: boolean;
  unitPrice: Paise;
  quantity: number;
  options: string[];
  categoryId: string;
  categoryName: string;
}

export function orderLineFromJson(json: Json): OrderLine {
  return {
    itemId: json.itemId as string,
    name: json.name as string,
    image: (json.image as string | undefined) ?? '',
    isVeg: (json.isVeg as boolean | undefined) ?? false,
    unitPrice: json.unitPrice as number,
    quantity: json.quantity as number,
    options: ((json.options as string[] | undefined) ?? []).slice(),
    categoryId: (json.categoryId as string | undefined) ?? '',
    categoryName: (json.categoryName as string | undefined) ?? '',
  };
}

export const lineTotal = (line: OrderLine): Paise => line.unitPrice * line.quantity;

export interface OrderFeedback {
  rating: number;
  comment: string;
  submittedAt: Date;
}

export const MAX_FEEDBACK_COMMENT = 300;

/** Null when the input is valid. */
export function validateFeedback(rating: number, comment: string): string | null {
  if (rating === 0) return 'Please select a star rating.';
  if (rating < 1 || rating > 5) return 'Ratings go from 1 to 5 stars.';
  if (comment.trim().length > MAX_FEEDBACK_COMMENT) return 'Feedback can be at most 300 characters.';
  return null;
}

export class RestaurantOrder {
  constructor(
    readonly id: string,
    readonly tableNumber: number,
    readonly createdAt: Date,
    readonly lines: OrderLine[],
    readonly bill: BillBreakdown,
    readonly specialInstructions: string,
    readonly status: OrderStatus,
    readonly statusTimes: Partial<Record<OrderStatus, Date>>,
    readonly estimatedReadyAt: Date,
    readonly feedback: OrderFeedback | null,
    readonly isDemoSample: boolean,
    /** `guest`, `staff` or `demoSeed`. */
    readonly source: string,
    readonly cancelReason: string,
  ) {}

  static fromJson(json: Json): RestaurantOrder {
    const times: Partial<Record<OrderStatus, Date>> = {};
    for (const [key, value] of Object.entries((json.statusTimes as Json | undefined) ?? {})) {
      times[OrderStatuses.parse(key)] = new Date(value as string);
    }
    const feedback = json.feedback as Json | null | undefined;
    return new RestaurantOrder(
      json.id as string,
      json.table as number,
      new Date(json.createdAt as string),
      ((json.lines as Json[] | undefined) ?? []).map(orderLineFromJson),
      BillBreakdown.fromJson(json),
      (json.instructions as string | undefined) ?? '',
      OrderStatuses.parse(json.status),
      times,
      new Date(json.readyAt as string),
      feedback
        ? {
            rating: feedback.rating as number,
            comment: (feedback.comment as string | undefined) ?? '',
            submittedAt: new Date(feedback.submittedAt as string),
          }
        : null,
      (json.demo as boolean | undefined) ?? false,
      (json.source as string | undefined) ?? 'guest',
      (json.cancelReason as string | undefined) ?? '',
    );
  }

  get itemCount(): number {
    return this.lines.reduce((sum, line) => sum + line.quantity, 0);
  }

  get type(): OrderType {
    return OrderTables.typeOf(this.tableNumber);
  }

  get isTakeaway(): boolean {
    return this.type === 'takeaway';
  }

  get tableLabel(): string {
    return OrderTables.label(this.tableNumber);
  }

  get statusLabel(): string {
    return OrderStatuses.label(this.status, this.type);
  }

  get isActive(): boolean {
    return OrderStatuses.isActive(this.status);
  }

  get isCancelled(): boolean {
    return this.status === 'cancelled';
  }

  /** Shown in the guest's "My Orders". */
  get isGuestVisible(): boolean {
    return this.source === 'guest';
  }

  /** Served orders placed by the guest can be rated once. */
  get canRate(): boolean {
    return this.status === 'served' && this.feedback == null && !this.isDemoSample;
  }

  get previewImage(): string {
    return this.lines[0]?.image ?? '';
  }
}

export type CheckoutError =
  | 'emptyCart'
  | 'missingTable'
  | 'tableUnavailable'
  | 'takeawayUnavailable'
  | 'sessionExpired'
  | 'itemsUnavailable'
  | 'alreadyPlacing'
  | 'failed';

export const checkoutMessage: Record<CheckoutError, string> = {
  emptyCart: 'Your cart is empty. Add a dish to place an order.',
  missingTable: 'Scan your table QR code, or the takeaway code at the counter, before placing an order.',
  tableUnavailable: 'This table is not taking orders right now. Please ask a staff member.',
  takeawayUnavailable: 'Takeaway orders are not being taken right now. Please ask a staff member.',
  sessionExpired: 'Your ordering session has ended. Scan the QR code again to continue.',
  itemsUnavailable: 'Some dishes in your cart are no longer available. Please review your cart.',
  alreadyPlacing: 'Your order is already being placed.',
  failed: 'We could not place your order. Please try again.',
};

export class CheckoutException extends Error {
  constructor(
    readonly reason: CheckoutError,
    /** The server's own explanation, when it gave one (e.g. prices changed). */
    readonly detail: string | null = null,
  ) {
    super(detail ?? checkoutMessage[reason]);
  }
}
