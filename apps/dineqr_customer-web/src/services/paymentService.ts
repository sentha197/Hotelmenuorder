import { GatewayCheckout, Invoice, PaymentTransaction, UpiSettings, type CounterRequestKind } from '../core/billing';
import type { Paise } from '../core/money';
import type { PaymentMethodType } from '../core/settings';
import { ApiException, PaymentError, SessionExpiredError, type ApiClient } from './api';

type Json = Record<string, unknown>;

export type SimulatedOutcome = 'success' | 'failure' | 'cancel';

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
   * An online payment through the server. Only the demo simulator is
   * integrated for card / net banking / wallet: the server confirms it with
   * the guest's chosen outcome and labels it a demo payment.
   */
  payOnline(args: {
    invoiceId: string;
    amount: Paise;
    method: PaymentMethodType;
    idempotencyKey: string;
    methodDetail: string;
    outcome: SimulatedOutcome;
  }): Promise<PaymentResult> {
    return this.guard(async () => {
      const intent = await this.api.post<Json>('/payments/intents', {
        invoiceId: args.invoiceId,
        amount: args.amount,
        method: args.method,
        idempotencyKey: args.idempotencyKey,
        ...(args.methodDetail ? { methodDetail: args.methodDetail } : {}),
      });
      if (intent.simulated !== true) {
        // A real provider would open its checkout here; none is integrated
        // for these methods.
        throw new PaymentError('Online payment is not available in this app yet. Please pay at the counter.');
      }
      const payment = intent.payment as Json;
      return result(
        await this.api.post<Json>(`/payments/${encodeURIComponent(payment.id as string)}/confirm`, {
          simulatedOutcome: args.outcome,
        }),
      );
    });
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

  /** Records a UPI payment to the restaurant as pending (holds the amount). */
  startUpi(invoiceId: string, amount: Paise, idempotencyKey: string): Promise<PaymentResult> {
    return this.guard(async () => result(await this.api.post<Json>('/payments/upi', { invoiceId, amount, idempotencyKey })));
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
