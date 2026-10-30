import { Currency, sum, type Paise } from './money';
import { orderLineFromJson, OrderTables, type OrderLine } from './orders';
import { BillBreakdown } from './pricing';
import { methodLabel, parseMethod, type PaymentMethodType } from './settings';

type Json = Record<string, unknown>;

export type PaymentStatus = 'pending' | 'succeeded' | 'failed' | 'cancelled';

const paymentStatusLabel: Record<PaymentStatus, string> = {
  pending: 'Pending',
  succeeded: 'Successful',
  failed: 'Failed',
  cancelled: 'Cancelled',
};

const parsePaymentStatus = (name: unknown): PaymentStatus =>
  typeof name === 'string' && name in paymentStatusLabel ? (name as PaymentStatus) : 'failed';

/** Must match the server's `UpiRules.Provider`. */
export const UPI_DIRECT_PROVIDER = 'UPI direct';

/** Gateways that settle UPI on their own (server's Cashfree provider name). */
export const GATEWAY_PROVIDERS = new Set(['Cashfree']);

/** One attempt to collect money against a bill. */
export class PaymentTransaction {
  constructor(
    readonly id: string,
    readonly invoiceId: string,
    readonly orderId: string,
    readonly amount: Paise,
    readonly method: PaymentMethodType,
    readonly status: PaymentStatus,
    readonly provider: string,
    readonly createdAt: Date,
    readonly updatedAt: Date,
    readonly idempotencyKey: string,
    readonly reference: string,
    readonly failureReason: string,
    /** True for demo payments: no money moved. */
    readonly isSimulated: boolean,
    readonly recordedBy: string,
    readonly methodDetail: string,
    readonly currency: string,
    /** UPI to the restaurant: when the guest said they had paid. */
    readonly claimedAt: Date | null,
  ) {}

  static fromJson(json: Json): PaymentTransaction {
    return new PaymentTransaction(
      json.id as string,
      json.invoice as string,
      json.order as string,
      json.amount as number,
      parseMethod(json.method) ?? 'cash',
      parsePaymentStatus(json.status),
      (json.provider as string | undefined) ?? '',
      new Date(json.createdAt as string),
      new Date(json.updatedAt as string),
      (json.key as string | undefined) ?? '',
      (json.ref as string | undefined) ?? '',
      (json.failure as string | undefined) ?? '',
      (json.simulated as boolean | undefined) ?? false,
      (json.by as string | undefined) ?? '',
      (json.detail as string | undefined) ?? '',
      (json.currency as string | undefined) ?? 'INR',
      json.claimed == null ? null : new Date(json.claimed as string),
    );
  }

  /** `UPI · QR code`, `Card · Credit` or just `Cash`. */
  get methodLabel(): string {
    return this.methodDetail ? `${methodLabel[this.method]} · ${this.methodDetail}` : methodLabel[this.method];
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

  get statusLabel(): string {
    if (this.status === 'pending' && this.isUpiDirect) {
      return this.isClaimed ? 'Pending verification' : 'Payment started';
    }
    return paymentStatusLabel[this.status];
  }
}

export type RefundStatus = 'processed' | 'pending' | 'failed';

export const refundStatusLabel: Record<RefundStatus, string> = {
  processed: 'Refunded',
  pending: 'Refund pending',
  failed: 'Refund failed',
};

export interface RefundRecord {
  id: string;
  paymentId: string;
  amount: Paise;
  reason: string;
  status: RefundStatus;
  createdAt: Date;
  processedBy: string;
  reference: string;
  isSimulated: boolean;
}

const refundFromJson = (json: Json): RefundRecord => ({
  id: json.id as string,
  paymentId: json.payment as string,
  amount: json.amount as number,
  reason: (json.reason as string | undefined) ?? '',
  status: json.status === 'processed' || json.status === 'pending' ? json.status : 'failed',
  createdAt: new Date(json.createdAt as string),
  processedBy: (json.by as string | undefined) ?? '',
  reference: (json.ref as string | undefined) ?? '',
  isSimulated: (json.simulated as boolean | undefined) ?? false,
});

/** Restaurant details printed on a bill, frozen when the bill was made. */
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

/** The guest will pay [amount] at the counter. Moves no money. */
export interface CounterRequest {
  kind: CounterRequestKind;
  amount: Paise;
  requestedAt: Date;
}

export type InvoiceStatus =
  | 'unpaid'
  | 'pending'
  | 'partiallyPaid'
  | 'paid'
  | 'failed'
  | 'partiallyRefunded'
  | 'refunded'
  | 'voided';

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

/**
 * The bill for one order. What has been paid comes only from its payment
 * and refund records, never from the order status.
 */
export class Invoice {
  constructor(
    readonly id: string,
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
    const request = json.counterRequest as Json | null | undefined;
    return new Invoice(
      json.id as string,
      json.number as string,
      json.order as string,
      json.table as number,
      new Date(json.createdAt as string),
      ((json.lines as Json[] | undefined) ?? []).map(orderLineFromJson),
      BillBreakdown.fromJson(json.amounts as Json),
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
        ? {
            kind: request.kind === 'cash' ? 'cash' : 'counter',
            amount: request.amount as number,
            requestedAt: new Date(request.at as string),
          }
        : null,
    );
  }

  get isTakeaway(): boolean {
    return OrderTables.isTakeaway(this.tableNumber);
  }

  get tableLabel(): string {
    return OrderTables.label(this.tableNumber);
  }

  get total(): Paise {
    return this.amounts.total;
  }

  get amountPaid(): Paise {
    return sum(this.payments.filter((p) => p.status === 'succeeded').map((p) => p.amount));
  }

  get amountRefunded(): Paise {
    return sum(this.refunds.filter((r) => r.status === 'processed').map((r) => r.amount));
  }

  get netPaid(): Paise {
    return this.amountPaid - this.amountRefunded;
  }

  get pendingAmount(): Paise {
    return sum(this.payments.filter((p) => p.status === 'pending').map((p) => p.amount));
  }

  get hasPendingPayment(): boolean {
    return this.payments.some((p) => p.status === 'pending');
  }

  /** Still owed by the guest. Refunds never re-open a balance. */
  get outstanding(): Paise {
    return this.isVoid ? 0 : Math.max(0, this.total - this.amountPaid);
  }

  /** What may be charged now without risking an overpayment. */
  get payableNow(): Paise {
    return Math.max(0, this.outstanding - this.pendingAmount);
  }

  /** The counter request while there is still something to collect. */
  get openCounterRequest(): CounterRequest | null {
    const request = this.counterRequest;
    const payable = this.payableNow;
    if (!request || payable === 0) return null;
    return request.amount <= payable ? request : { ...request, amount: payable };
  }

  get refundDue(): boolean {
    return this.isVoid && this.netPaid > 0;
  }

  get lastPayment(): PaymentTransaction | null {
    return this.payments.reduce<PaymentTransaction | null>(
      (a, b) => (a == null || b.createdAt > a.createdAt ? b : a),
      null,
    );
  }

  get latestSuccessfulPayment(): PaymentTransaction | null {
    return this.payments
      .filter((p) => p.status === 'succeeded')
      .reduce<PaymentTransaction | null>((a, b) => (a == null || b.updatedAt > a.updatedAt ? b : a), null);
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

  /** Methods of successful payments, e.g. "UPI + Cash". */
  get methodsLabel(): string {
    const methods = new Set(this.payments.filter((p) => p.status === 'succeeded').map((p) => methodLabel[p.method]));
    return methods.size ? [...methods].join(' + ') : '—';
  }

  get isSimulated(): boolean {
    return this.payments.some((p) => p.isSimulated);
  }

  get hasDemoPayments(): boolean {
    return this.payments.some((p) => p.isSimulated && p.status === 'succeeded');
  }

  /** Notice printed on demo bills and receipts, or null for real ones. */
  get demoNotice(): string | null {
    if (this.isDemoSample && this.isSimulated) {
      return 'Sample bill included with the demo. Its payments are simulated: no money was charged or transferred.';
    }
    if (this.isDemoSample) return 'Sample bill included with the demo, not a real sale.';
    if (this.isSimulated) {
      return 'Demo payment: simulated, not verified by any bank or payment provider. No money was charged or transferred.';
    }
    return null;
  }
}

/** Returns a message when [amount] cannot be paid on [invoice] now. */
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

// ------------------------------------------------------------ payment options

export type PaymentOption = 'upi' | 'scanAndPay' | 'card' | 'netBanking' | 'wallet' | 'cash' | 'payAtCounter';

interface OptionInfo {
  label: string;
  /** The recorded method; null for "any method at the counter". */
  method: PaymentMethodType | null;
  /** Default method detail sent with the payment. */
  detail: string;
  counter: CounterRequestKind | null;
  description: string;
}

export const paymentOptionInfo: Record<PaymentOption, OptionInfo> = {
  upi: { label: 'UPI', method: 'upi', detail: 'UPI ID', counter: null, description: 'Pay to the restaurant UPI ID' },
  scanAndPay: { label: 'QR Payment', method: 'upi', detail: 'QR code', counter: null, description: 'Scan a QR code with any UPI app' },
  card: { label: 'Card', method: 'card', detail: '', counter: null, description: 'Credit or debit card' },
  netBanking: { label: 'Net Banking', method: 'netBanking', detail: '', counter: null, description: 'Pay from your bank account' },
  wallet: { label: 'Wallet', method: 'wallet', detail: '', counter: null, description: 'Pay from a mobile wallet' },
  cash: { label: 'Cash', method: 'cash', detail: '', counter: 'cash', description: 'Pay cash to staff or at the counter' },
  payAtCounter: { label: 'Pay at Counter', method: null, detail: '', counter: 'counter', description: 'Pay by any method at the counter' },
};

/** In display order. */
export const paymentOptions: PaymentOption[] = ['upi', 'scanAndPay', 'card', 'netBanking', 'wallet', 'cash', 'payAtCounter'];

export const isOnlineOption = (option: PaymentOption) => paymentOptionInfo[option].counter == null;

export interface SplitPart {
  option: PaymentOption;
  amount: Paise;
}

export const SplitPlan = {
  maxParts: 4,
  /** A message when [parts] cannot pay [payable], or null. */
  validate(parts: SplitPart[], payable: Paise, available: Set<PaymentOption>, allowPartial: boolean): string | null {
    if (!allowPartial) return 'This restaurant takes the full amount in one payment.';
    if (parts.length < 2) return 'Add at least two parts to split the bill.';
    if (parts.length > SplitPlan.maxParts) return `Split the bill into at most ${SplitPlan.maxParts} parts.`;
    for (const part of parts) {
      if (!available.has(part.option)) return `${paymentOptionInfo[part.option].label} is not available right now.`;
      if (part.amount <= 0) return 'Every part needs an amount.';
    }
    if (parts.filter((p) => !isOnlineOption(p.option)).length > 1) return 'Choose one way to pay at the counter.';
    const total = sum(parts.map((p) => p.amount));
    if (total > payable) {
      return `The parts add up to ${Currency.format(total)}, more than the ${Currency.format(payable)} due.`;
    }
    if (total !== payable) {
      return `The parts add up to ${Currency.format(total)}; ${Currency.format(payable - total)} is still unassigned.`;
    }
    return null;
  },
};

// ------------------------------------------------------------------- UPI

/** The restaurant's UPI payee for payments straight to its own account. */
export class UpiSettings {
  constructor(
    readonly enabled = false,
    readonly upiId = '',
    readonly payeeName = '',
    readonly qrImageUrl = '',
  ) {}

  static fromJson(json: Json): UpiSettings {
    return new UpiSettings(
      (json.enabled as boolean | undefined) ?? false,
      (json.upiId as string | undefined) ?? '',
      (json.payeeName as string | undefined) ?? '',
      (json.qrImage as string | undefined) ?? '',
    );
  }

  static isValidId(id: string): boolean {
    return /^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9]{1,31}$/.test(id.trim().toLowerCase());
  }

  static isValidName(name: string): boolean {
    // eslint-disable-next-line no-control-regex
    return name.length >= 2 && name.length <= 60 && !/[<>\u0000-\u001F\u007F-\u009F]/.test(name);
  }

  get hasQrImage(): boolean {
    return this.qrImageUrl !== '';
  }

  /** Switched on and fully set up. */
  get isReady(): boolean {
    return this.enabled && UpiSettings.isValidId(this.upiId) && UpiSettings.isValidName(this.payeeName.trim());
  }
}

/** The bank's UPI transaction ID (UTR): 6 to 40 letters or digits. */
export const UpiReference = {
  rule: 'The UPI transaction ID is 6 to 40 letters or digits.',
  normalize: (reference: string) => reference.trim().toUpperCase(),
  isValid: (reference: string) => /^[A-Z0-9][A-Z0-9._/-]{5,39}$/.test(reference),
};

/** `upi://pay` for one payment: what the QR code holds. */
export class UpiPaymentLink {
  constructor(
    readonly payeeUpiId: string,
    readonly payeeName: string,
    readonly amount: Paise,
    readonly note: string,
  ) {}

  static forPayment(settings: UpiSettings, invoice: Invoice, payment: PaymentTransaction): UpiPaymentLink {
    return new UpiPaymentLink(settings.upiId, settings.payeeName, payment.amount, `Bill ${invoice.billNumber} ${payment.id}`);
  }

  /** Rupees with two decimals, e.g. `450.00`. */
  get amountText(): string {
    return `${Math.floor(this.amount / 100)}.${(this.amount % 100).toString().padStart(2, '0')}`;
  }

  private static encode(value: string): string {
    return encodeURIComponent(value).replaceAll('%40', '@');
  }

  get uriString(): string {
    const e = UpiPaymentLink.encode;
    return `upi://pay?pa=${e(this.payeeUpiId)}&pn=${e(this.payeeName)}&am=${this.amountText}&cu=INR&tn=${e(this.note)}`;
  }
}

/** A gateway UPI payment's app links and QR code (`/payments/{id}/checkout`). */
export class GatewayCheckout {
  constructor(
    readonly links: Record<string, string>,
    readonly qrImage: string,
    readonly qrText: string,
    readonly expiresAt: Date | null,
  ) {}

  static fromJson(json: Json): GatewayCheckout {
    const links: Record<string, string> = {};
    for (const [key, value] of Object.entries((json.links as Json | undefined) ?? {})) {
      if (typeof value === 'string') links[key] = value;
    }
    return new GatewayCheckout(
      links,
      (json.qrImage as string | undefined) ?? '',
      (json.qrText as string | undefined) ?? '',
      typeof json.expiresAt === 'string' ? new Date(json.expiresAt) : null,
    );
  }

  /** `default`, else any `upi:` link, else whatever the gateway gave. */
  get payLink(): string | null {
    const values = Object.values(this.links);
    const plain = this.links.default ?? values.find((l) => l.startsWith('upi:')) ?? values[0];
    return plain ? plain : null;
  }

  /** A `data:image/...` picture, if the gateway sent one. */
  get qrDataUrl(): string | null {
    return this.qrImage.startsWith('data:image/') && this.qrImage.includes(',') ? this.qrImage : null;
  }

  get hasQr(): boolean {
    return this.qrDataUrl != null || this.qrText !== '';
  }
}

/** `Paid · UPI` or `Due ₹120`, for lists. */
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
