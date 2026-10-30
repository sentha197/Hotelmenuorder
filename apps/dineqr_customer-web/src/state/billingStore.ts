import {
  isOnlineOption,
  paymentOptionInfo,
  paymentOptions as allOptions,
  UpiSettings,
  validateAmount,
  type CounterRequestKind,
  type GatewayCheckout,
  type Invoice,
  type PaymentOption,
  type PaymentTransaction,
} from '../core/billing';
import type { Paise } from '../core/money';
import type { RestaurantOrder } from '../core/orders';
import {
  methodLabel,
  onlineMethods as allOnlineMethods,
  type PaymentMethodType,
  type RestaurantSettings,
} from '../core/settings';
import { randomId } from '../core/time';
import { PaymentError } from '../services/api';
import type { PaymentResult, PaymentService, SimulatedOutcome } from '../services/paymentService';
import type { PaymentConfig } from '../services/restaurantService';
import { Store } from './store';

/**
 * Bills and payments of the guest session. With the API every payment is
 * decided and recorded by the server; this store only shows what it returns.
 */
export class BillingStore extends Store {
  invoices: Invoice[] = [];
  upiSettings = new UpiSettings();
  private readonly inFlight = new Set<string>();

  constructor(
    private readonly service: PaymentService,
    private readonly settings: () => RestaurantSettings,
    private readonly paymentConfig: () => PaymentConfig,
  ) {
    super();
  }

  /** Restaurant settings or the gateway changed: options are re-derived. */
  settingsChanged(): void {
    this.notify();
  }

  /** Demo mode: online payments are simulated, no money moves. */
  get isSimulated(): boolean {
    return this.settings().paymentMode === 'demo';
  }

  get allowPartialPayments(): boolean {
    return this.settings().allowPartialPayments;
  }

  /** A real gateway is connected. */
  get liveAvailable(): boolean {
    const config = this.paymentConfig();
    return config.liveAvailable && (config.liveMethods == null || config.liveMethods.size > 0);
  }

  /** The provider of the current mode: the demo simulator, the live gateway, or none. */
  get providerName(): string {
    if (this.isSimulated) return 'Demo simulator';
    return this.liveAvailable ? this.paymentConfig().providerName : 'Not configured';
  }

  private get supportedMethods(): Set<PaymentMethodType> {
    if (this.isSimulated) return new Set(allOnlineMethods);
    if (!this.liveAvailable) return new Set();
    return this.paymentConfig().liveMethods ?? new Set(allOnlineMethods);
  }

  /** Enabled by the restaurant and supported by the provider; UPI only in INR. */
  get onlineMethods(): PaymentMethodType[] {
    const settings = this.settings();
    const supported = this.supportedMethods;
    return allOnlineMethods.filter(
      (m) => settings.onlineMethods.has(m) && supported.has(m) && (m !== 'upi' || settings.currencyCode === 'INR'),
    );
  }

  /** UPI through the live gateway: settled from the gateway's own report. */
  get gatewayUpiAvailable(): boolean {
    return !this.isSimulated && this.onlineMethods.includes('upi');
  }

  /** UPI straight to the restaurant's account, confirmed by staff. */
  get upiDirectAvailable(): boolean {
    return this.upiSettings.isReady && this.settings().currencyCode === 'INR' && !this.gatewayUpiAvailable;
  }

  isDirectUpiOption(option: PaymentOption): boolean {
    return paymentOptionInfo[option].method === 'upi' && this.upiDirectAvailable;
  }

  isGatewayOption(option: PaymentOption): boolean {
    return paymentOptionInfo[option].method === 'upi' && this.gatewayUpiAvailable;
  }

  /** UPI to the restaurant first (when set up), then the provider's methods. */
  get guestMethods(): PaymentMethodType[] {
    const direct = this.upiDirectAvailable;
    return [...(direct ? (['upi'] as PaymentMethodType[]) : []), ...this.onlineMethods.filter((m) => !(m === 'upi' && direct))];
  }

  get onlinePaymentsAvailable(): boolean {
    return this.guestMethods.length > 0;
  }

  /** Online options of [guestMethods], then cash and the counter. */
  get paymentOptions(): PaymentOption[] {
    const online = this.guestMethods;
    return allOptions.filter((o) => !isOnlineOption(o) || online.includes(paymentOptionInfo[o].method!));
  }

  /** UPI settled later (staff or gateway) cannot be one part of several. */
  get splitOptions(): PaymentOption[] {
    return this.paymentOptions.filter((o) => !this.isDirectUpiOption(o) && !this.isGatewayOption(o));
  }

  get canSplit(): boolean {
    return this.allowPartialPayments && this.splitOptions.some(isOnlineOption);
  }

  byId(id: string): Invoice | null {
    return this.invoices.find((i) => i.id === id) ?? null;
  }

  forOrder(orderId: string): Invoice | null {
    return this.invoices.find((i) => i.orderId === orderId) ?? null;
  }

  forOrders(orders: RestaurantOrder[]): Invoice[] {
    const ids = new Set(orders.map((o) => o.id));
    return this.invoices.filter((i) => ids.has(i.orderId));
  }

  isProcessing(invoiceId: string): boolean {
    return this.inFlight.has(invoiceId);
  }

  validate(invoice: Invoice, amount: Paise): string | null {
    return validateAmount(invoice, amount, this.allowPartialPayments);
  }

  /** Puts the server's version of a bill in the list. */
  private accept(invoice: Invoice): void {
    const exists = this.invoices.some((i) => i.id === invoice.id);
    const next = exists ? this.invoices.map((i) => (i.id === invoice.id ? invoice : i)) : [invoice, ...this.invoices];
    this.invoices = next.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
    this.notify();
  }

  private settle({ payment, invoice }: PaymentResult): PaymentTransaction {
    this.accept(invoice);
    return payment;
  }

  async load(): Promise<void> {
    const bills = await this.service.bills();
    this.invoices = [...bills].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
    this.notify();
    // Payments interrupted before confirmation (the tab was closed).
    for (const invoice of this.invoices.filter((i) => i.hasPendingPayment)) {
      await this.resolvePending(invoice.id).catch(() => 0);
    }
  }

  /** Keeps the last known details on failure (UPI then is not offered). */
  async loadUpiSettings(): Promise<void> {
    try {
      this.upiSettings = await this.service.upiSettings();
      this.notify();
    } catch {
      // Offline, or no session yet.
    }
  }

  /** The bill of [order]: the server created it with the order. */
  async createForOrder(order: RestaurantOrder): Promise<Invoice> {
    const existing = this.forOrder(order.id);
    if (existing) return existing;
    const fetched = await this.service.billForOrder(order.id);
    this.accept(fetched);
    return fetched;
  }

  private begin(invoiceId: string): void {
    if (this.inFlight.has(invoiceId)) throw new PaymentError('A payment for this bill is in progress.');
    this.inFlight.add(invoiceId);
    this.notify();
  }

  private end(invoiceId: string): void {
    this.inFlight.delete(invoiceId);
    this.notify();
  }

  private requireInvoice(invoiceId: string): Invoice {
    const invoice = this.byId(invoiceId);
    if (!invoice) throw new PaymentError('Bill not found.');
    return invoice;
  }

  /**
   * Card, net banking and wallet (and UPI where neither UPI path applies)
   * through the provider of the current mode. Pass the same key to retry an
   * attempt whose result never arrived.
   */
  async payOnline(args: {
    invoiceId: string;
    amount: Paise;
    method: PaymentMethodType;
    methodDetail: string;
    idempotencyKey: string;
    outcome: SimulatedOutcome;
  }): Promise<PaymentTransaction> {
    const invoice = this.requireInvoice(args.invoiceId);
    if (args.method === 'upi' && this.upiDirectAvailable) {
      throw new PaymentError('Use the UPI payment to pay the restaurant directly.');
    }
    if (args.method === 'upi' && this.gatewayUpiAvailable) throw new PaymentError('Choose a UPI app or the QR code to pay.');
    if (!this.onlineMethods.includes(args.method)) {
      throw new PaymentError(`${methodLabel[args.method]} is not available right now.`);
    }
    const replay = invoice.payments.some((p) => p.idempotencyKey === args.idempotencyKey);
    if (!replay) {
      const problem = this.validate(invoice, args.amount);
      if (problem) throw new PaymentError(problem);
    }
    this.begin(args.invoiceId);
    try {
      return this.settle(await this.service.payOnline(args));
    } finally {
      this.end(args.invoiceId);
    }
  }

  /** Records a UPI payment to the restaurant as pending; staff confirm it. */
  async startUpiPayment(invoiceId: string, amount: Paise): Promise<PaymentTransaction> {
    const invoice = this.requireInvoice(invoiceId);
    if (!this.upiDirectAvailable) throw new PaymentError('UPI payment is not available right now. Please pay at the counter.');
    const problem = this.validate(invoice, amount);
    if (problem) throw new PaymentError(problem);
    this.begin(invoiceId);
    try {
      return this.settle(await this.service.startUpi(invoiceId, amount, randomId()));
    } finally {
      this.end(invoiceId);
    }
  }

  /** The guest says they paid. It stays pending until staff confirm it. */
  async claimUpiPayment(paymentId: string, reference: string): Promise<PaymentTransaction> {
    return this.settle(await this.service.claimUpi(paymentId, reference.trim()));
  }

  /** Cancels a pending online payment (gateway: ended at the gateway first). */
  async cancelPayment(paymentId: string): Promise<PaymentTransaction> {
    return this.settle(await this.service.cancel(paymentId));
  }

  /** Starts a gateway UPI payment; it is paid only when the gateway reports it. */
  async startGatewayUpi(invoiceId: string, amount: Paise, idempotencyKey: string, methodDetail: string): Promise<PaymentTransaction> {
    const invoice = this.requireInvoice(invoiceId);
    if (!this.gatewayUpiAvailable) throw new PaymentError('UPI payment is not available right now. Please pay at the counter.');
    if (!invoice.payments.some((p) => p.idempotencyKey === idempotencyKey)) {
      const problem = this.validate(invoice, amount);
      if (problem) throw new PaymentError(problem);
    }
    this.begin(invoiceId);
    try {
      return this.settle(await this.service.startGateway(invoiceId, amount, idempotencyKey, methodDetail));
    } finally {
      this.end(invoiceId);
    }
  }

  gatewayCheckout(paymentId: string, qr: boolean): Promise<GatewayCheckout> {
    return this.service.gatewayCheckout(paymentId, qr);
  }

  /** Asks the server for the final status of pending payments on a bill. */
  checkPending(invoiceId: string): Promise<number> {
    return this.resolvePending(invoiceId);
  }

  private async resolvePending(invoiceId: string): Promise<number> {
    const invoice = this.byId(invoiceId);
    if (!invoice || this.inFlight.has(invoiceId)) return 0;
    let resolved = 0;
    for (const pending of invoice.payments.filter((p) => p.status === 'pending')) {
      const payment = this.settle(await this.service.refresh(pending.id));
      if (payment.status !== 'pending') resolved++;
    }
    return resolved;
  }

  /** "I will pay at the counter": a notice for staff; nothing is paid. */
  async requestCounterPayment(invoiceId: string, kind: CounterRequestKind, amount: Paise | null): Promise<Invoice> {
    const invoice = this.requireInvoice(invoiceId);
    const problem = this.validate(invoice, amount ?? invoice.payableNow);
    if (problem) throw new PaymentError(problem);
    const updated = await this.service.requestCounter(invoiceId, kind, amount);
    this.accept(updated);
    return updated;
  }

  async cancelCounterRequest(invoiceId: string): Promise<Invoice> {
    this.requireInvoice(invoiceId);
    const updated = await this.service.cancelCounter(invoiceId);
    this.accept(updated);
    return updated;
  }

  clear(): void {
    this.invoices = [];
    this.upiSettings = new UpiSettings();
    this.notify();
  }
}
