import { BillBreakdown } from '../core/pricing';

type Json = Record<string, unknown>;

/**
 * An in-memory DineQR API for tests: the same routes, bodies and JSON
 * shapes as the backend (guest sessions, menu, orders, bills, the demo
 * payment simulator, counter requests). It prices orders itself and refuses
 * a changed total, like the server.
 */
export class FakeApi {
  requests: { method: string; path: string; body: Json | null; auth: string | null }[] = [];
  takeaway = false;
  tables = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map((n) => ({ number: n, active: n !== 9 }));
  orders: Json[] = [];
  bills: Json[] = [];
  /** Makes the next POST /orders fail with this problem. */
  failNextOrder: { status: number; code: string; title: string } | null = null;
  /** Delays answers (ms), to observe loading states. */
  delay = 0;
  private sessions = new Map<string, number>();
  private nextOrder = 1;
  private nextPay = 1;

  readonly items = [
    { id: 'paneer_tikka', name: 'Paneer Tikka', category: 'starters', short: 'Smoky cottage cheese', description: 'Char-grilled paneer.', price: 24000, image: 'assets/images/paneer_tikka.jpg', veg: true, rating: 4.6, reviews: 120, popular: true, featured: true, spicy: true, defaultSpice: 'medium', addOns: [{ id: 'cheese', name: 'Extra Cheese', price: 3000 }], prep: 15 },
    { id: 'butter_chicken', name: 'Butter Chicken', category: 'mainCourse', short: 'Creamy makhani gravy', description: 'Chicken in tomato butter gravy.', price: 28000, image: 'assets/images/butter_chicken.jpg', veg: false, rating: 4.7, reviews: 189, popular: true, special: true, prep: 20 },
    { id: 'lassi', name: 'Sweet Lassi', category: 'beverages', short: 'Chilled yoghurt drink', description: 'Thick and sweet.', price: 9000, image: 'assets/images/lassi.jpg', veg: true, rating: 4.4, reviews: 60, prep: 5 },
    { id: 'gulab_jamun', name: 'Gulab Jamun', category: 'desserts', short: 'Warm syrup dumplings', description: 'Two pieces.', price: 11000, image: 'assets/images/gulab_jamun.jpg', veg: true, rating: 4.5, reviews: 80, available: false, prep: 5 },
  ];

  readonly settings: Json = {
    name: 'Test Bistro',
    taxName: 'GST',
    taxRate: 500,
    serviceRate: 0,
    utcOffset: 330,
    partial: true,
    methods: ['upi', 'card', 'netBanking', 'wallet'],
    footer: 'Thank you!',
    showSoldOut: true,
    prepBuffer: 5,
    offers: [{ code: 'WELCOME10', title: 'Welcome', type: 'percent', value: 1000, min: 30000, max: 10000, active: true }],
    currency: 'INR',
    paymentMode: 'demo',
  };

  readonly fetch: typeof fetch = async (input, init) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url, 'http://api.test');
    const method = (init?.method ?? 'GET').toUpperCase();
    const body = init?.body ? (JSON.parse(String(init.body)) as Json) : null;
    const headers = new Headers(init?.headers);
    const auth = headers.get('Authorization');
    const path = url.pathname.replace(/^\/api\/v1/, '');
    this.requests.push({ method, path, body, auth });
    if (this.delay) await new Promise((r) => setTimeout(r, this.delay));
    try {
      const result = this.route(method, path, body, auth);
      return new Response(JSON.stringify(result), { status: 200, headers: { 'Content-Type': 'application/json' } });
    } catch (error) {
      if (error instanceof Problem) {
        return new Response(JSON.stringify({ title: error.title, code: error.code, status: error.status }), { status: error.status, headers: { 'Content-Type': 'application/problem+json' } });
      }
      throw error;
    }
  };

  /** Moves an order on, as staff would. */
  setStatus(orderId: string, status: string): void {
    const order = this.orders.find((o) => o.id === orderId)!;
    order.status = status;
    (order.statusTimes as Json)[status] = new Date().toISOString();
  }

  private table(auth: string | null): number {
    const table = auth ? this.sessions.get(auth.replace('Bearer ', '')) : undefined;
    if (table == null) throw new Problem(401, 'unauthorized', 'Your session has ended.');
    return table;
  }

  private route(method: string, path: string, body: Json | null, auth: string | null): unknown {
    const key = `${method} ${path}`;
    if (key === 'GET /settings') return { ...this.settings, takeaway: this.takeaway };
    if (key === 'GET /tables') return this.tables;
    if (key === 'GET /payments/config') return { provider: 'Simulator', available: true, simulated: true, mode: 'demo', liveProvider: 'None', liveAvailable: false, methods: ['upi', 'card', 'netBanking', 'wallet'], liveMethods: [] };
    if (key === 'GET /menu') {
      return {
        categories: [
          { id: 'starters', label: 'Starters', cover: 'assets/images/chicken_65.jpg', sort: 0, active: true },
          { id: 'mainCourse', label: 'Main Course', cover: 'assets/images/butter_chicken.jpg', sort: 1, active: true },
          { id: 'beverages', label: 'Beverages', cover: 'assets/images/cold_coffee.jpg', sort: 2, active: true },
          { id: 'desserts', label: 'Desserts', cover: 'assets/images/gulab_jamun.jpg', sort: 3, active: true },
        ],
        items: this.items,
      };
    }
    if (key === 'POST /guest/sessions') {
      const payload = String(body?.qrPayload ?? '');
      let table: number;
      if (payload === 'DINEQR:TAKEAWAY') {
        if (!this.takeaway) throw new Problem(409, 'takeawayUnavailable', 'Takeaway orders are not being taken right now. Please ask a staff member.');
        table = 0;
      } else {
        const match = /^DINEQR:TABLE:(\d{1,3})$/i.exec(payload);
        if (!match) throw new Problem(400, 'unrecognized', 'This is not a DineQR code.');
        table = Number(match[1]);
        const found = this.tables.find((t) => t.number === table);
        if (!found) throw new Problem(404, 'notFound', 'This QR code points to a table that does not exist.');
        if (!found.active) throw new Problem(409, 'tableInactive', 'This table is not taking orders right now. Please ask a staff member.');
      }
      const token = `guest-${table}-${this.sessions.size + 1}`;
      this.sessions.set(token, table);
      return { guestToken: token, tableNumber: table, expiresAt: new Date(Date.now() + 6 * 3600_000).toISOString(), orderType: table === 0 ? 'takeaway' : 'dineIn' };
    }
    if (key === 'GET /orders') return this.orders.filter((o) => o.table === this.table(auth));
    if (key === 'GET /bills') return this.bills.filter((b) => b.table === this.table(auth));
    if (key === 'POST /orders') return this.placeOrder(body!, this.table(auth));
    let match = /^\/orders\/([^/]+)\/bill$/.exec(path);
    if (method === 'GET' && match) return this.bills.find((b) => b.order === decodeURIComponent(match![1]!));
    match = /^\/orders\/([^/]+)\/feedback$/.exec(path);
    if (method === 'POST' && match) {
      const order = this.orders.find((o) => o.id === match![1])!;
      order.feedback = { rating: body!.rating, comment: body!.comment, submittedAt: new Date().toISOString() };
      return order;
    }
    if (key === 'POST /payments/intents') {
      this.table(auth);
      const bill = this.bills.find((b) => b.id === body!.invoiceId)!;
      const existing = (bill.payments as Json[]).find((p) => p.key === body!.idempotencyKey);
      if (existing) return { payment: existing, invoice: bill, simulated: true };
      const payment = this.payment(bill, body!.amount as number, body!.method as string, (body!.methodDetail as string) ?? '', body!.idempotencyKey as string);
      return { payment, invoice: bill, simulated: true };
    }
    match = /^\/payments\/([^/]+)\/confirm$/.exec(path);
    if (method === 'POST' && match) {
      const { bill, payment } = this.findPayment(match[1]!);
      const outcome = body!.simulatedOutcome;
      payment.status = outcome === 'success' ? 'succeeded' : outcome === 'cancel' ? 'cancelled' : 'failed';
      payment.ref = outcome === 'success' ? 'DEMO-TESTREF' : '';
      payment.failure = outcome === 'failure' ? 'Declined by the demo simulator. No money was taken.' : '';
      payment.updatedAt = new Date().toISOString();
      if (outcome === 'success') bill.counterRequest = null;
      return { payment, invoice: bill };
    }
    match = /^\/payments\/([^/]+)$/.exec(path);
    if (method === 'GET' && match && match[1] !== 'upi' && match[1] !== 'config') {
      const { bill, payment } = this.findPayment(match[1]!);
      return { payment, invoice: bill };
    }
    if (key === 'GET /payments/upi') return { enabled: false, upiId: '', payeeName: '', qrImage: '', verificationMode: 'manual' };
    match = /^\/bills\/([^/]+)\/counter-request$/.exec(path);
    if (match) {
      const bill = this.bills.find((b) => b.id === match![1])!;
      bill.counterRequest = method === 'DELETE' ? null : { kind: body!.kind, amount: (body!.amount as number) ?? 0, at: new Date().toISOString() };
      return bill;
    }
    throw new Problem(404, 'notFound', `No route ${key}`);
  }

  private placeOrder(body: Json, table: number): Json {
    if (this.failNextOrder) {
      const problem = this.failNextOrder;
      this.failNextOrder = null;
      throw new Problem(problem.status, problem.code, problem.title);
    }
    const existing = this.orders.find((o) => o.key === body.idempotencyKey);
    if (existing) return existing;
    const lines = (body.lines as Json[]).map((line) => {
      const item = this.items.find((i) => i.id === line.itemId)!;
      const options = (line.options as Json) ?? {};
      const addOns = (options.addOns as string[] | undefined) ?? [];
      const extra = addOns.reduce((sum, id) => sum + (item.addOns?.find((a) => a.id === id)?.price ?? 0), 0);
      return { itemId: item.id, name: item.name, image: item.image, isVeg: item.veg, unitPrice: item.price + extra, quantity: line.quantity, options: [] };
    });
    const subtotal = lines.reduce((sum, l) => sum + l.unitPrice * (l.quantity as number), 0);
    const offer = body.offerCode === 'WELCOME10' && subtotal >= 30000 ? Math.min(Math.floor((subtotal * 1000 + 5000) / 10000), 10000) : 0;
    const bill = BillBreakdown.fromSubtotal(subtotal, { taxRateBasisPoints: 500, taxName: 'GST', serviceChargeBasisPoints: 0 }, offer, offer ? 'Offer WELCOME10' : null);
    if (bill.total !== body.expectedTotal) throw new Problem(409, 'priceChanged', 'Prices changed since you opened the menu. Please review your cart.');
    const id = `OD${String(this.nextOrder++).padStart(5, '0')}`;
    const now = new Date();
    const amounts = { subtotal: bill.subtotal, discount: bill.discount, discountLabel: bill.discountLabel, tax: bill.tax, total: bill.total, taxRate: 500, taxName: 'GST' };
    const order: Json = {
      id,
      key: body.idempotencyKey,
      table,
      createdAt: now.toISOString(),
      lines,
      ...amounts,
      instructions: body.instructions,
      status: 'placed',
      statusTimes: { placed: now.toISOString() },
      readyAt: new Date(now.getTime() + 25 * 60_000).toISOString(),
      source: 'guest',
    };
    this.orders.push(order);
    this.bills.push({ id: `INV${id}`, number: `DQ-2026-${String(this.nextOrder).padStart(5, '0')}`, order: id, table, createdAt: now.toISOString(), lines, amounts, restaurant: { name: 'Test Bistro', footer: 'Thank you!' }, payments: [] });
    return order;
  }

  private payment(bill: Json, amount: number, method: string, detail: string, key: string): Json {
    const now = new Date().toISOString();
    const payment: Json = { id: `PAY${String(this.nextPay++).padStart(6, '0')}`, invoice: bill.id, order: bill.order, amount, method, detail, status: 'pending', provider: 'Demo simulator', createdAt: now, updatedAt: now, key, simulated: true };
    (bill.payments as Json[]).push(payment);
    return payment;
  }

  private findPayment(id: string): { bill: Json; payment: Json } {
    for (const bill of this.bills) {
      const payment = (bill.payments as Json[]).find((p) => p.id === id);
      if (payment) return { bill, payment };
    }
    throw new Problem(404, 'notFound', 'Payment not found.');
  }
}

class Problem extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly title: string,
  ) {
    super(title);
  }
}
