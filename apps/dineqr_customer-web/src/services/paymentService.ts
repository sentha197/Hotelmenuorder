import { GatewayCheckout, Invoice, PaymentTransaction, UpiSettings, type CounterRequestKind } from '../core/billing';
import type { Paise } from '../core/money';
import { methodLabel, type PaymentMethodType } from '../core/settings';
import { ApiException, PaymentError, SessionExpiredError, type ApiClient } from './api';

type Json = Record<string, unknown>;

export type PaymentResult = { payment: PaymentTransaction; invoice: Invoice };

const result = (json: Json): PaymentResult => ({
  payment: PaymentTransaction.fromJson(json.payment as Json),
  invoice: Invoice.fromJson(json.invoice as Json),
});

/**
 * Bills and payments, decided and recorded by the server. The app never
 * writes payment state: every call returns the server's version of the bill,
 * and only a verified result marks money as paid.
 */
export class PaymentService {
  constructor(private readonly api: ApiClient) {}

  private async guard<T>(call: () => Promise<T>): Promise<T> {
    try {
      return await call();
    } catch (error) {
      if (error instanceof ApiException) {
        if (error.isUnauthorized) throw new SessionExpiredError();
        throw new PaymentError(error.message);
      }
      throw error;
    }
  }

  async bills(): Promise<Invoice[]> {
    try {
      return (await this.api.get<Json[]>('/bills')).map(Invoice.fromJson);
    } catch (error) {
      if (error instanceof ApiException && (error.status === 401 || error.status === 403)) return [];
      throw error;
    }
  }

  billForOrder(orderId: string): Promise<Invoice> {
    return this.guard(async () => Invoice.fromJson(await this.api.get<Json>(`/orders/${encodeURIComponent(orderId)}/bill`)));
  }

  /**
   * Card, net banking and wallet need the gateway's own checkout in the app,
   * and no gateway with one is integrated (Cashfree takes UPI, which goes
   * through [startGateway]). Nothing simulates one either, so this refuses
   * before anything starts: no payment is left pending on the bill.
   */
  payOnline(args: {
    invoiceId: string;
    amount: Paise;
    method: PaymentMethodType;
    idempotencyKey: string;
    methodDetail: string;
  }): Promise<PaymentResult> {
    return Promise.reject(
      new PaymentError(`${methodLabel[args.method]} payment is not available in this app. Please pay at the counter.`),
    );
  }

  /** The current status of a payment (pending ones are re-checked). */
  refresh(paymentId: string): Promise<PaymentResult> {
    return this.guard(async () => result(await this.api.get<Json>(`/payments/${encodeURIComponent(paymentId)}`)));
  }

  /** The guest will pay at the counter ([amount] null: all payable now). */
  requestCounter(invoiceId: string, kind: CounterRequestKind, amount: Paise | null): Promise<Invoice> {
    return this.guard(async () =>
      Invoice.fromJson(
        await this.api.post<Json>(`/bills/${encodeURIComponent(invoiceId)}/counter-request`, {
          kind,
          ...(amount != null ? { amount } : {}),
        }),
      ),
    );
  }

  cancelCounter(invoiceId: string): Promise<Invoice> {
    return this.guard(async () =>
      Invoice.fromJson(await this.api.delete<Json>(`/bills/${encodeURIComponent(invoiceId)}/counter-request`)),
    );
  }

  /** The restaurant's UPI payee (disabled and empty when switched off). */
  upiSettings(): Promise<UpiSettings> {
    return this.guard(async () => UpiSettings.fromJson(await this.api.get<Json>('/payments/upi')));
  }

  /**
   * Records a UPI payment to the restaurant as pending (holds the amount).
   * [qr]: paid by scanning the QR code rather than from a UPI app; the
   * server checks that option is switched on.
   */
  startUpi(invoiceId: string, amount: Paise, idempotencyKey: string, qr = false): Promise<PaymentResult> {
    return this.guard(async () =>
      result(
        await this.api.post<Json>('/payments/upi', { invoiceId, amount, idempotencyKey, channel: qr ? 'qr' : 'upi' }),
      ),
    );
  }

  /** The guest says they paid. Only flags the payment for staff. */
  claimUpi(paymentId: string, reference: string): Promise<PaymentResult> {
    return this.guard(async () =>
      result(
        await this.api.post<Json>(`/payments/${encodeURIComponent(paymentId)}/upi/claim`, reference ? { reference } : {}),
      ),
    );
  }

  /** Cancels a pending payment (a gateway one is ended at the gateway). */
  cancel(paymentId: string): Promise<PaymentResult> {
    return this.guard(async () => result(await this.api.post<Json>(`/payments/${encodeURIComponent(paymentId)}/cancel`)));
  }

  /** Starts a UPI payment through the live gateway (server holds the amount). */
  startGateway(invoiceId: string, amount: Paise, idempotencyKey: string, methodDetail: string): Promise<PaymentResult> {
    return this.guard(async () => {
      const intent = await this.api.post<Json>('/payments/intents', {
        invoiceId,
        amount,
        method: 'upi',
        idempotencyKey,
        ...(methodDetail ? { methodDetail } : {}),
      });
      const payment = PaymentTransaction.fromJson(intent.payment as Json);
      if (intent.invoice && typeof intent.invoice === 'object') {
        return { payment, invoice: Invoice.fromJson(intent.invoice as Json) };
      }
      // An older server: read the bill the payment is on.
      return result(await this.api.get<Json>(`/payments/${encodeURIComponent(payment.id)}`));
    });
  }

  /** The gateway's UPI app links, or (with [qr]) its QR code. */
  gatewayCheckout(paymentId: string, qr: boolean): Promise<GatewayCheckout> {
    return this.guard(async () =>
      GatewayCheckout.fromJson(
        await this.api.post<Json>(`/payments/${encodeURIComponent(paymentId)}/checkout`, { channel: qr ? 'qr' : 'apps' }),
      ),
    );
  }
}
