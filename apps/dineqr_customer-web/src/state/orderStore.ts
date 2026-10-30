import { CheckoutException, OrderTables, validateFeedback, type RestaurantOrder } from '../core/orders';
import { randomId } from '../core/time';
import type { OrderService } from '../services/orderService';
import type { CartStore } from './cartStore';
import { Store } from './store';

/** The guest session's orders: checkout, history, tracking and feedback. */
export class OrderStore extends Store {
  orders: RestaurantOrder[] = [];
  isPlacing = false;
  private readonly busy = new Set<string>();
  // The cart being submitted and its idempotency key, kept until it
  // succeeds so a retry cannot create a duplicate order.
  private pendingSignature: string | null = null;
  private pendingKey: string | null = null;

  constructor(
    private readonly service: OrderService,
    private readonly isTableOrderable: (table: number) => boolean,
    private readonly onPlaced: (order: RestaurantOrder) => Promise<unknown>,
  ) {
    super();
  }

  get guestOrders(): RestaurantOrder[] {
    return this.orders.filter((o) => o.isGuestVisible);
  }

  get currentOrders(): RestaurantOrder[] {
    return this.guestOrders.filter((o) => o.isActive);
  }

  get pastOrders(): RestaurantOrder[] {
    return this.guestOrders.filter((o) => !o.isActive);
  }

  byId(id: string): RestaurantOrder | null {
    return this.orders.find((o) => o.id === id) ?? null;
  }

  isBusy(id: string): boolean {
    return this.busy.has(id);
  }

  async load(): Promise<void> {
    const orders = await this.service.orders();
    this.orders = [...orders].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
    this.notify();
  }

  /**
   * Validates the cart, submits it and clears the cart only once the order
   * exists. Calls while an order is being placed are refused.
   */
  async placeOrder(cart: CartStore, tableNumber: number | null): Promise<RestaurantOrder> {
    if (this.isPlacing) throw new CheckoutException('alreadyPlacing');
    if (tableNumber == null) throw new CheckoutException('missingTable');
    if (!this.isTableOrderable(tableNumber)) {
      throw new CheckoutException(OrderTables.isTakeaway(tableNumber) ? 'takeawayUnavailable' : 'tableUnavailable');
    }
    if (cart.isEmpty) throw new CheckoutException('emptyCart');
    if (cart.unavailableLines.length) throw new CheckoutException('itemsUnavailable');

    this.isPlacing = true;
    this.notify();
    try {
      const bill = cart.bill;
      const lines = cart.lines.map((l) => l.toJson());
      const offerCode = bill.hasDiscount ? cart.offerCode : null;
      const instructions = cart.instructions.trim();
      // Retrying the same cart reuses the key, so the server returns the
      // order it may already have created.
      const signature = JSON.stringify([tableNumber, 'guest', lines, offerCode, instructions]);
      if (signature !== this.pendingSignature) {
        this.pendingSignature = signature;
        this.pendingKey = randomId(24);
      }
      const order = await this.service.submit({
        lines,
        instructions,
        offerCode,
        idempotencyKey: this.pendingKey!,
        orderType: OrderTables.typeOf(tableNumber),
        expectedTotal: bill.total,
      });
      this.pendingSignature = null;
      this.pendingKey = null;
      this.orders = [order, ...this.orders.filter((o) => o.id !== order.id)];
      cart.clear();
      try {
        await this.onPlaced(order);
      } catch {
        // The order exists; its bill is fetched again when it is opened.
      }
      return order;
    } catch (error) {
      if (error instanceof CheckoutException) throw error;
      throw new CheckoutException('failed');
    } finally {
      this.isPlacing = false;
      this.notify();
    }
  }

  /** Throws a message string for invalid input or a refused request. */
  async submitFeedback(orderId: string, rating: number, comment: string): Promise<RestaurantOrder> {
    const problem = validateFeedback(rating, comment);
    if (problem) throw new Error(problem);
    const order = this.byId(orderId);
    if (!order || !order.canRate) throw new Error('This order has already been rated.');
    if (this.busy.has(orderId)) throw new Error('Your rating is already being sent.');
    this.busy.add(orderId);
    this.notify();
    try {
      const updated = await this.service.feedback(orderId, rating, comment.trim());
      this.orders = this.orders.map((o) => (o.id === updated.id ? updated : o));
      return updated;
    } finally {
      this.busy.delete(orderId);
      this.notify();
    }
  }

  clear(): void {
    this.orders = [];
    this.notify();
  }
}
