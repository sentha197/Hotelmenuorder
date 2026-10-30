import { CheckoutException, RestaurantOrder, type CheckoutError, type OrderType } from '../core/orders';
import { ApiException, SessionExpiredError, type ApiClient } from './api';

type Json = Record<string, unknown>;

export interface OrderSubmission {
  /** `{itemId, quantity, options}` per cart line: never prices. */
  lines: Json[];
  instructions: string;
  offerCode: string | null;
  idempotencyKey: string;
  orderType: OrderType;
  /** The total the guest saw; the server refuses if prices changed. */
  expectedTotal: number;
}

/** Maps the server's refusal to the checkout reasons the screens explain. */
export function checkoutErrorFor(error: ApiException): CheckoutException {
  const reason: CheckoutError = error.isUnauthorized
    ? 'sessionExpired'
    : (({
        tableUnavailable: 'tableUnavailable',
        tableInactive: 'tableUnavailable',
        takeawayUnavailable: 'takeawayUnavailable',
        // From servers before the rename.
        parcelUnavailable: 'takeawayUnavailable',
        orderTypeMismatch: 'sessionExpired',
        itemsUnavailable: 'itemsUnavailable',
        invalidOptions: 'itemsUnavailable',
        emptyCart: 'emptyCart',
        missingTable: 'missingTable',
      }) as Record<string, CheckoutError>)[error.code] ?? 'failed';
  // Known reasons have their own wording; otherwise the server's (e.g.
  // prices changed), unless it was unreachable or failed.
  const known = reason !== 'failed' && reason !== 'itemsUnavailable';
  return new CheckoutException(reason, known || error.isOffline || error.status >= 500 ? null : error.message);
}

/** The guest session's orders. The server prices every order itself. */
export class OrderService {
  constructor(private readonly api: ApiClient) {}

  async orders(): Promise<RestaurantOrder[]> {
    try {
      return (await this.api.get<Json[]>('/orders')).map(RestaurantOrder.fromJson);
    } catch (error) {
      // No session yet (or it ended): there is nothing of the guest's to show.
      if (error instanceof ApiException && (error.status === 401 || error.status === 403)) return [];
      throw error;
    }
  }

  async submit(order: OrderSubmission): Promise<RestaurantOrder> {
    try {
      const json = await this.api.post<Json>('/orders', {
        lines: order.lines,
        instructions: order.instructions,
        ...(order.offerCode ? { offerCode: order.offerCode } : {}),
        idempotencyKey: order.idempotencyKey,
        orderType: order.orderType,
        expectedTotal: order.expectedTotal,
      });
      return RestaurantOrder.fromJson(json);
    } catch (error) {
      if (error instanceof ApiException) throw checkoutErrorFor(error);
      throw new CheckoutException('failed');
    }
  }

  async feedback(orderId: string, rating: number, comment: string): Promise<RestaurantOrder> {
    try {
      return RestaurantOrder.fromJson(
        await this.api.post<Json>(`/orders/${encodeURIComponent(orderId)}/feedback`, { rating, comment }),
      );
    } catch (error) {
      if (error instanceof ApiException && error.isUnauthorized) throw new SessionExpiredError();
      throw error;
    }
  }
}
