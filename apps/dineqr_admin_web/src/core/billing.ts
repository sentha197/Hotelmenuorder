import { Currency, sumPaise, type Paise } from './money';
import { orderLineFromJson, Tables, type OrderLine } from './orders';
import { billFromJson, type BillBreakdown } from './pricing';
import { parseInstant, parseOptionalInstant } from './time';

type Json = Record<string, unknown>;

/**
 * How a bill was paid. The billing counter takes [counterMethods]; net banking
 * and wallet appear only on payments made before online payment was retired.
 */
export type PaymentMethodType = 'upi' | 'card' | 'netBanking' | 'wallet' | 'cash';
export const paymentMethods: readonly PaymentMethodType[] = ['upi', 'card', 'netBanking', 'wallet', 'cash'];
export const paymentMethodLabel: Record<PaymentMethodType, string> = {
  upi: 'UPI',
  card: 'Card',
  netBanking: 'Net banking',
  wallet: 'Wallet',
  cash: 'Cash',
};
/** What staff can record at the billing counter, in display order. */
export const counterMethods: readonly PaymentMethodType[] = ['cash', 'card', 'upi'];
const parseMethod = (name: unknown): PaymentMethodType | null => (paymentMethods.includes(name as PaymentMethodType) ? (name as PaymentMethodType) : null);

export type PaymentStatus = 'pending' | 'succeeded' | 'failed' | 'cancelled';
export const paymentStatusLabel: Record<PaymentStatus, string> = {
  pending: 'Pending',
  succeeded: 'Successful',
  failed: 'Failed',
  cancelled: 'Cancelled',
};
const parsePaymentStatus = (name: unknown): PaymentStatus =>
  name === 'pending' || name === 'succeeded' || name === 'cancelled' ? name : 'failed';

/** Every payment recorded at the billing counter (the server's `BillingService.CounterProvider`). */
export const COUNTER_PROVIDER = 'Counter';
/** The online gateway that took payments before online payment was retired (history only). */
export const GATEWAY_PROVIDERS: ReadonlySet<string> = new Set(['Cashfree']);

/** One attempt to collect money against a bill. */
export class PaymentTransaction {
  constructor(
    readonly id: string,
    readonly invoiceId: string,
    readonly orderId: string,
    readonly amount: Paise,
    readonly method: PaymentMethodType,
    readonly status: PaymentStatus,
    /** Who processed it, e.g. "Cashfree", "UPI direct" or "Counter". */
    readonly provider: string,
    readonly createdAt: Date,
    readonly updatedAt: Date,
    readonly idempotencyKey: string,
    /** Provider transaction id (or a staff-entered reference). */
    readonly reference: string,
    readonly failureReason: string,
    /** A test payment: no money moved. */
    readonly isSimulated: boolean,
    /** Staff member who recorded (or confirmed) it. */
    readonly recordedBy: string,
    /** Display-only detail, e.g. `QR code`. */
    readonly methodDetail: string,
    readonly currency: string,
    /** UPI to the restaurant: when the guest said they had paid (a claim only). */
    readonly claimedAt: Date | null,
  ) {}

  static fromJson(json: Json): PaymentTransaction {
    return new PaymentTransaction(
      String(json.id),
      String(json.invoice),
      String(json.order),
      json.amount as number,
      parseMethod(json.method) ?? 'cash',
      parsePaymentStatus(json.status),
      (json.provider as string | undefined) ?? '',
      parseInstant(json.createdAt),
      parseInstant(json.updatedAt),
      (json.key as string | undefined) ?? '',
      (json.ref as string | undefined) ?? '',
      (json.failure as string | undefined) ?? '',
      (json.simulated as boolean | undefined) ?? false,
      (json.by as string | undefined) ?? '',
      (json.detail as string | undefined) ?? '',
      (json.currency as string | undefined) ?? 'INR',
      parseOptionalInstant(json.claimed),
    );
  }

  /** `Card · Counter` or just `Cash`. */
  get methodLabel(): string {
    const label = paymentMethodLabel[this.method];
    return this.methodDetail ? `${label} · ${this.methodDetail}` : label;
  }

  get isCounter(): boolean {
    return this.provider === COUNTER_PROVIDER;
  }

  /** Taken through the retired online gateway: refunded at the gateway, not here. */
  get isGateway(): boolean {
    return GATEWAY_PROVIDERS.has(this.provider);
  }

  get statusLabel(): string {
    return paymentStatusLabel[this.status];
  }
}

export type RefundStatus = 'processed' | 'pending' | 'failed';
export const refundStatusLabel: Record<RefundStatus, string> = {
  processed: 'Refunded',
  pending: 'Refund pending',
  failed: 'Refund failed',
};

/** Money returned to the guest against one payment. */
export interface RefundRecord {
  id: string;
  invoiceId: string;
  paymentId: string;
  amount: Paise;
  reason: string;
  status: RefundStatus;
  createdAt: Date;
  processedBy: string;
  reference: string;
  isSimulated: boolean;
}

export function refundFromJson(json: Json): RefundRecord {
  const status = json.status === 'processed' || json.status === 'pending' ? json.status : 'failed';
  return {
    id: String(json.id),
    invoiceId: String(json.invoice),
    paymentId: String(json.payment),
    amount: json.amount as number,
    reason: (json.reason as string | undefined) ?? '',
    status,
    createdAt: parseInstant(json.createdAt),
    processedBy: (json.by as string | undefined) ?? '',
    reference: (json.ref as string | undefined) ?? '',
    isSimulated: (json.simulated as boolean | undefined) ?? false,
  };
}

/** Restaurant details printed on a bill, frozen when the bill is created. */
export interface RestaurantSnapshot {
  name: string;
  phone: string;
  email: string;
  address: string;
  taxRegistration: string;
  footer: string;
}

export type InvoiceStatus = 'unpaid' | 'pending' | 'partiallyPaid' | 'paid' | 'failed' | 'partiallyRefunded' | 'refunded' | 'voided';
export const invoiceStatusLabel: Record<InvoiceStatus, string> = {
  unpaid: 'Unpaid',
  pending: 'Pending',
  partiallyPaid: 'Partially paid',
  paid: 'Paid',
  failed: 'Payment failed',
  partiallyRefunded: 'Partly refunded',
  refunded: 'Refunded',
  voided: 'Void',
};

/** The bill for one order: amounts from the order's snapshot, payments from the server's records. */
export class Invoice {
  constructor(
    readonly id: string,
    /** Printed bill number, e.g. `DQ-2026-00012`. */
    readonly billNumber: string,
    readonly orderId: string,
    readonly tableNumber: number,
    readonly createdAt: Date,
    readonly lines: OrderLine[],
    readonly amounts: BillBreakdown,
    readonly restaurant: RestaurantSnapshot,
    readonly payments: PaymentTransaction[],
    readonly refunds: RefundRecord[],
    readonly isVoid: boolean,
    readonly voidReason: string,
    readonly isDemoSample: boolean,
  ) {}

  static fromJson(json: Json): Invoice {
    const r = (json.restaurant as Json | undefined) ?? {};
    return new Invoice(
      String(json.id),
      String(json.number),
      String(json.order),
      json.table as number,
      parseInstant(json.createdAt),
      ((json.lines as Json[] | undefined) ?? []).map(orderLineFromJson),
      billFromJson(json.amounts as Json),
      {
        name: (r.name as string | undefined) ?? '',
        phone: (r.phone as string | undefined) ?? '',
        email: (r.email as string | undefined) ?? '',
        address: (r.address as string | undefined) ?? '',
        taxRegistration: (r.taxReg as string | undefined) ?? '',
        footer: (r.footer as string | undefined) ?? '',
      },
      ((json.payments as Json[] | undefined) ?? []).map(PaymentTransaction.fromJson),
      ((json.refunds as Json[] | undefined) ?? []).map(refundFromJson),
      (json.void as boolean | undefined) ?? false,
      (json.voidReason as string | undefined) ?? '',
      (json.demo as boolean | undefined) ?? false,
    );
  }

  get isTakeaway(): boolean {
    return Tables.isTakeaway(this.tableNumber);
  }

  /** "Table 07" or "Takeaway". */
  get tableLabel(): string {
    return Tables.label(this.tableNumber);
  }

  get total(): Paise {
    return this.amounts.total;
  }

  get amountPaid(): Paise {
    return sumPaise(this.payments.filter((p) => p.status === 'succeeded').map((p) => p.amount));
  }

  get amountRefunded(): Paise {
    return sumPaise(this.refunds.filter((r) => r.status === 'processed').map((r) => r.amount));
  }

  /** Paid minus refunded. */
  get netPaid(): Paise {
    return this.amountPaid - this.amountRefunded;
  }

  get pendingAmount(): Paise {
    return sumPaise(this.payments.filter((p) => p.status === 'pending').map((p) => p.amount));
  }

  get hasPendingPayment(): boolean {
    return this.payments.some((p) => p.status === 'pending');
  }

  /** Still owed by the guest. Refunds never re-open a balance. */
  get outstanding(): Paise {
    if (this.isVoid) return 0;
    return Math.max(0, this.total - this.amountPaid);
  }

  /** What may be charged now without risking an overpayment. */
  get payableNow(): Paise {
    return Math.max(0, this.outstanding - this.pendingAmount);
  }

  /** Refundable amount left on one payment. */
  refundableOn(paymentId: string): Paise {
    const payment = this.payments.find((p) => p.id === paymentId);
    if (!payment || payment.status !== 'succeeded') return 0;
    const already = sumPaise(this.refunds.filter((r) => r.paymentId === paymentId && r.status !== 'failed').map((r) => r.amount));
    return Math.max(0, payment.amount - already);
  }

  /** A cancelled order whose payment has not been returned yet. */
  get refundDue(): boolean {
    return this.isVoid && this.netPaid > 0;
  }

  get lastPayment(): PaymentTransaction | null {
    return this.payments.reduce<PaymentTransaction | null>((a, b) => (a == null || b.createdAt > a.createdAt ? b : a), null);
  }

  get latestSuccessfulPayment(): PaymentTransaction | null {
    return this.payments.filter((p) => p.status === 'succeeded').reduce<PaymentTransaction | null>((a, b) => (a == null || b.updatedAt > a.updatedAt ? b : a), null);
  }

  get status(): InvoiceStatus {
    const paid = this.amountPaid;
    const refunded = this.amountRefunded;
    if (this.isVoid && paid === 0) return 'voided';
    if (paid > 0 && refunded >= paid) return 'refunded';
    if (refunded > 0) return 'partiallyRefunded';
    if (this.hasPendingPayment) return 'pending';
    if (this.outstanding === 0) return 'paid';
    if (paid > 0) return 'partiallyPaid';
    if (this.lastPayment?.status === 'failed') return 'failed';
    return 'unpaid';
  }

  /** Methods used for successful payments, e.g. "UPI + Cash". */
  get methodsLabel(): string {
    const methods = new Set(this.payments.filter((p) => p.status === 'succeeded').map((p) => paymentMethodLabel[p.method]));
    return methods.size ? [...methods].join(' + ') : '—';
  }

  get isSimulated(): boolean {
    return this.payments.some((p) => p.isSimulated);
  }

  /** Some of the money counted as paid came from test payments. */
  get hasDemoPayments(): boolean {
    return this.payments.some((p) => p.isSimulated && p.status === 'succeeded');
  }

  /** Notice printed on sample bills and bills with test payments, or null for real ones. */
  get demoNotice(): string | null {
    if (this.isDemoSample && this.isSimulated) return 'Sample bill included with the demo. Its payments are simulated: no money was charged or transferred.';
    if (this.isDemoSample) return 'Sample bill included with the demo, not a real sale.';
    if (this.isSimulated) return 'Test payment: no money was charged or transferred.';
    return null;
  }
}

/** Returns a message when [amount] cannot be recorded on [invoice] now (BillingController.validateAmount). */
export function validateAmount(invoice: Invoice, amount: Paise): string | null {
  if (invoice.isVoid) return 'This bill was cancelled.';
  if (invoice.outstanding === 0) return 'This bill is already paid.';
  if (amount <= 0) return 'Enter an amount.';
  const max = invoice.payableNow;
  if (amount > max) return `At most ${Currency.format(max)} is due.`;
  return null;
}

/** Payment summary line for lists: `Paid · UPI` or `Due ₹120`. */
export function shortStatus(invoice: Invoice): string {
  switch (invoice.status) {
    case 'paid':
      return `Paid · ${invoice.methodsLabel}`;
    case 'partiallyPaid':
    case 'unpaid':
    case 'failed':
      return `Due ${Currency.format(invoice.outstanding)}`;
    default:
      return invoiceStatusLabel[invoice.status];
  }
}
