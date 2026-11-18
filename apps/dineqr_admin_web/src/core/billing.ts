import { Currency, sumPaise, type Paise } from './money';
import { orderLineFromJson, Tables, type OrderLine } from './orders';
import { billFromJson, type BillBreakdown } from './pricing';
import { DateRanges, parseInstant, parseOptionalInstant, type DateRange } from './time';

type Json = Record<string, unknown>;

export type PaymentMethodType = 'upi' | 'card' | 'netBanking' | 'wallet' | 'cash';
export const paymentMethods: readonly PaymentMethodType[] = ['upi', 'card', 'netBanking', 'wallet', 'cash'];
export const paymentMethodLabel: Record<PaymentMethodType, string> = {
  upi: 'UPI',
  card: 'Card',
  netBanking: 'Net banking',
  wallet: 'Wallet',
  cash: 'Cash',
};
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

/** Must match the server's `UpiRules.Provider`. */
export const UPI_DIRECT_PROVIDER = 'UPI direct';
/** Must match the server's `CashfreePaymentProvider.ProviderName`. */
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

  /** `UPI · QR code`, `Card · Counter` or just `Cash`. */
  get methodLabel(): string {
    const label = paymentMethodLabel[this.method];
    return this.methodDetail ? `${label} · ${this.methodDetail}` : label;
  }

  get isUpiDirect(): boolean {
    return this.provider === UPI_DIRECT_PROVIDER;
  }

  get isGateway(): boolean {
    return GATEWAY_PROVIDERS.has(this.provider);
  }

  get isClaimed(): boolean {
    return this.claimedAt != null;
  }

  /** Pending UPI payments say what they wait for; others use [status]. */
  get statusLabel(): string {
    if (this.status === 'pending' && this.isUpiDirect) return this.isClaimed ? 'Pending verification' : 'Payment started';
    return paymentStatusLabel[this.status];
  }
}

/** A UPI payment to the restaurant waits for someone to check the money arrived. */
export const awaitsUpiVerification = (p: PaymentTransaction) => p.isUpiDirect && p.status === 'pending';

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

export type CounterRequestKind = 'cash' | 'counter';
export const counterKindLabel: Record<CounterRequestKind, string> = {
  cash: 'Cash at the counter',
  counter: 'Pay at the counter',
};

/** The guest will pay [amount] at the counter. A notice only: nothing is paid until staff record it. */
export interface CounterRequest {
  kind: CounterRequestKind;
  amount: Paise;
  requestedAt: Date;
}

export type InvoiceStatus = 'unpaid' | 'pending' | 'partiallyPaid' | 'paid' | 'failed' | 'partiallyRefunded' | 'refunded' | 'voided';
export const invoiceStatusLabel: Record<InvoiceStatus, string> = {
  unpaid: 'Unpaid',
  pending: 'Pending verification',
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
    readonly counterRequest: CounterRequest | null,
  ) {}

  static fromJson(json: Json): Invoice {
    const r = (json.restaurant as Json | undefined) ?? {};
    const request = json.counterRequest as Json | undefined | null;
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
      request && typeof request === 'object'
        ? { kind: request.kind === 'cash' ? 'cash' : 'counter', amount: request.amount as number, requestedAt: parseInstant(request.at) }
        : null,
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

  /** The counter request while there is still something to collect, capped at what is payable now. */
  get openCounterRequest(): CounterRequest | null {
    const request = this.counterRequest;
    if (!request || this.payableNow === 0) return null;
    if (request.amount <= this.payableNow) return request;
    return { ...request, amount: this.payableNow };
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
    if (this.isSimulated) return 'Test payment: not verified by any bank or payment provider. No money was charged or transferred.';
    return null;
  }
}

/** Returns a message when [amount] cannot be paid on [invoice] now (BillingController.validateAmount). */
export function validateAmount(invoice: Invoice, amount: Paise, allowPartial = true): string | null {
  if (invoice.isVoid) return 'This bill was cancelled.';
  if (invoice.outstanding === 0) return 'This bill is already paid.';
  if (invoice.hasPendingPayment) return 'A payment for this bill is still being confirmed.';
  if (amount <= 0) return 'Enter an amount to pay.';
  const max = invoice.payableNow;
  if (amount > max) return `You can pay at most ${Currency.format(max)}.`;
  if (!allowPartial && amount !== max) return `Please pay the full ${Currency.format(max)}.`;
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

// ------------------------------------------------------------------ ledger

/** One line of the payment ledger: a payment attempt or a refund. */
export interface LedgerEntry {
  invoice: Invoice;
  payment: PaymentTransaction | null;
  refund: RefundRecord | null;
}

export const Ledger = {
  /** When it counts: a payment's confirmation (or last update), a refund's creation. */
  at: (e: LedgerEntry) => e.payment?.updatedAt ?? e.refund!.createdAt,
  reference: (e: LedgerEntry) => e.payment?.reference ?? e.refund!.reference,
  isSimulated: (e: LedgerEntry) => e.payment?.isSimulated ?? e.refund!.isSimulated,
};

export type LedgerFilter = 'all' | 'succeeded' | 'pending' | 'failed' | 'cancelled' | 'refunds';
export const ledgerFilters: readonly LedgerFilter[] = ['all', 'succeeded', 'pending', 'failed', 'cancelled', 'refunds'];
export const ledgerFilterLabel: Record<LedgerFilter, string> = {
  all: 'All',
  succeeded: 'Successful',
  pending: 'Pending',
  failed: 'Failed',
  cancelled: 'Cancelled',
  refunds: 'Refunds',
};

const ledgerMatches = (filter: LedgerFilter, e: LedgerEntry) =>
  filter === 'all' ? true : filter === 'refunds' ? e.refund != null : e.payment?.status === filter;

/**
 * Every payment attempt and refund in a range, newest first, with totals
 * defined as in the sales report: collected counts successful payments only,
 * refunds count processed refunds only.
 */
export function buildLedger(invoices: readonly Invoice[], range: DateRange, filter: LedgerFilter, method: PaymentMethodType | null, query: string) {
  const needle = query.trim().toLowerCase();
  const entries: LedgerEntry[] = [];
  for (const invoice of invoices) {
    for (const payment of invoice.payments) entries.push({ invoice, payment, refund: null });
    for (const refund of invoice.refunds) entries.push({ invoice, payment: null, refund });
  }
  const shown = entries
    .filter((e) => {
      if (!DateRanges.contains(range, Ledger.at(e))) return false;
      if (!ledgerMatches(filter, e)) return false;
      // Refunds go back by the original method; the method filter applies to payments only.
      if (method != null && e.payment?.method !== method) return false;
      if (!needle) return true;
      return [Ledger.reference(e), e.invoice.billNumber, e.invoice.orderId, `table ${e.invoice.tableNumber}`].some((t) => t.toLowerCase().includes(needle));
    })
    .sort((a, b) => Ledger.at(b).getTime() - Ledger.at(a).getTime());
  const payments = shown.map((e) => e.payment).filter((p): p is PaymentTransaction => p != null);
  const collected = sumPaise(payments.filter((p) => p.status === 'succeeded').map((p) => p.amount));
  const refunded = sumPaise(shown.map((e) => e.refund).filter((r): r is RefundRecord => r != null && r.status === 'processed').map((r) => r.amount));
  return {
    range,
    entries: shown,
    collected,
    refunded,
    netCollected: collected - refunded,
    pendingAmount: sumPaise(payments.filter((p) => p.status === 'pending').map((p) => p.amount)),
    failedCount: payments.filter((p) => p.status === 'failed').length,
    hasSimulated: shown.some(Ledger.isSimulated),
  };
}
