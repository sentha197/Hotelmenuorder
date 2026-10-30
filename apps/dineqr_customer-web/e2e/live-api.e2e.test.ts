/**
 * The web app's own services and stores against a running DineQR API.
 *
 *   DINEQR_E2E_API_URL=http://localhost:5265 \
 *   DINEQR_E2E_OWNER_EMAIL=... DINEQR_E2E_OWNER_PASSWORD=... \
 *   npm run test:e2e
 *
 * Point it only at a throwaway database: it places orders and payments. The
 * owner account plays the kitchen and the cashier (staff endpoints).
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { CheckoutException } from '../src/core/orders';
import { linkFor, parseTableQr, tableOf, toPayload } from '../src/core/qr';
import { ApiException } from '../src/services/api';
import { MemoryStore } from '../src/services/storage';
import { createApp, type AppServices } from '../src/state/app';

const baseUrl = process.env.DINEQR_E2E_API_URL ?? '';
const ownerEmail = process.env.DINEQR_E2E_OWNER_EMAIL ?? '';
const ownerPassword = process.env.DINEQR_E2E_OWNER_PASSWORD ?? '';
const site = 'https://order.example.test';

async function staff(path: string, body: unknown, token: string) {
  const response = await fetch(`${baseUrl}/api/v1${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${path} → ${response.status} ${await response.text()}`);
  return response.json() as Promise<Record<string, unknown>>;
}

describe.skipIf(!baseUrl)('live API', () => {
  let app: AppServices;
  let staffToken = '';

  beforeAll(async () => {
    app = createApp({ baseUrl, timeoutMs: 20_000 }, { storage: new MemoryStore(), startNetwork: false });
    if (ownerEmail) {
      const login = await fetch(`${baseUrl}/api/v1/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: ownerEmail, password: ownerPassword }),
      });
      expect(login.status).toBe(200);
      staffToken = ((await login.json()) as { accessToken: string }).accessToken;
    }
  });

  afterAll(async () => {
    app?.live.dispose();
    await app?.realtime.stop();
  });

  it('reads the public restaurant data', async () => {
    await app.settings.load();
    await app.catalog.load();
    expect(app.settings.state).toBe('ready');
    expect(app.settings.tables.length).toBeGreaterThan(0);
    expect(app.catalog.state).toBe('ready');
    expect(app.catalog.items.length).toBeGreaterThan(0);
  });

  it('turns a printed table link into a server guest session', async () => {
    const table = app.settings.tables.find((t) => t.isActive)!.number;
    const scanned = linkFor(table, site);
    const result = parseTableQr(scanned, {
      allowedOrigins: [site],
      tableExists: app.settings.isKnownTable,
      tableActive: app.settings.isOrderable,
      takeawayEnabled: app.settings.settings.takeawayOrdersEnabled,
    });
    expect(tableOf(result)).toBe(table);
    expect(toPayload('https://elsewhere.example/t/05', { allowedOrigins: [site] })).toEqual({ error: 'foreignLink' });
    await app.session.startSession(table);
    expect(app.guest.isActive).toBe(true);
    expect(app.guest.table).toBe(table);
    expect(app.session.canOrder).toBe(true);
  });

  it('lets the server refuse a table that does not exist', async () => {
    const other = createApp({ baseUrl, timeoutMs: 20_000 }, { storage: new MemoryStore(), startNetwork: false });
    await expect(other.session.startSession(998)).rejects.toBeInstanceOf(ApiException);
    expect(other.guest.isActive).toBe(false);
    other.live.dispose();
  });

  let orderId = '';
  let invoiceId = '';

  it('places an order the server prices to the same total', async () => {
    const items = app.catalog.items.filter((i) => i.isOrderable);
    app.cart.add(items[0]!, null, 2);
    if (items[1]) app.cart.add(items[1]);
    const offer = app.settings.settings.offers.find((o) => o.isActive && o.check(app.cart.subtotal) == null);
    if (offer) expect(app.cart.applyOffer(offer.code)).toBeNull();
    app.cart.updateInstructions('Less spicy please (web e2e)');
    const seen = app.cart.bill.total;
    const placing = app.orders.placeOrder(app.cart, app.session.tableNumber);
    // A second tap while it is placed is refused, not sent.
    await expect(app.orders.placeOrder(app.cart, app.session.tableNumber)).rejects.toMatchObject({ reason: 'alreadyPlacing' });
    const order = await placing;
    orderId = order.id;
    expect(order.bill.total).toBe(seen);
    expect(order.status).toBe('placed');
    expect(order.specialInstructions).toBe('Less spicy please (web e2e)');
    expect(app.cart.isEmpty).toBe(true);
    const invoice = app.billing.forOrder(order.id)!;
    invoiceId = invoice.id;
    expect(invoice.total).toBe(seen);
    expect(invoice.status).toBe('unpaid');
  });

  it('refuses an empty cart', async () => {
    await expect(app.orders.placeOrder(app.cart, app.session.tableNumber)).rejects.toBeInstanceOf(CheckoutException);
  });

  it('records demo payments only as the server reports them', async () => {
    expect(app.billing.isSimulated).toBe(true);
    const invoice = app.billing.byId(invoiceId)!;
    const failed = await app.billing.payOnline({
      invoiceId,
      amount: invoice.payableNow,
      method: 'card',
      methodDetail: 'Credit',
      idempotencyKey: `e2e-fail-${Date.now()}`,
      outcome: 'failure',
    });
    expect(failed.status).toBe('failed');
    expect(app.billing.byId(invoiceId)!.amountPaid).toBe(0);

    const part = Math.floor(invoice.payableNow / 200) * 100;
    const paid = await app.billing.payOnline({
      invoiceId,
      amount: part,
      method: 'card',
      methodDetail: 'Debit',
      idempotencyKey: `e2e-ok-${Date.now()}`,
      outcome: 'success',
    });
    expect(paid.status).toBe('succeeded');
    expect(paid.isSimulated).toBe(true);
    const after = app.billing.byId(invoiceId)!;
    expect(after.amountPaid).toBe(part);
    expect(after.status).toBe('partiallyPaid');
    expect(after.demoNotice).toMatch(/No money was charged/);
  });

  it('tells staff about the rest without marking it paid', async () => {
    const updated = await app.billing.requestCounterPayment(invoiceId, 'cash', null);
    expect(updated.openCounterRequest?.kind).toBe('cash');
    expect(updated.status).toBe('partiallyPaid');
  });

  it.skipIf(!ownerEmail)('follows the kitchen, takes a rating, and shows the cashier’s payment', async () => {
    for (const target of ['accepted', 'preparing', 'readyToServe', 'served']) {
      await staff(`/admin/orders/${orderId}/status`, { target }, staffToken);
    }
    await app.orders.load();
    const order = app.orders.byId(orderId)!;
    expect(order.status).toBe('served');
    expect(order.canRate).toBe(true);
    const rated = await app.orders.submitFeedback(orderId, 5, 'Lovely (web e2e)');
    expect(rated.feedback?.rating).toBe(5);

    const due = app.billing.byId(invoiceId)!.payableNow;
    await staff(`/admin/bills/${invoiceId}/payments`, { amount: due, method: 'cash', reference: '', idempotencyKey: `e2e-cash-${Date.now()}` }, staffToken);
    await app.billing.load();
    const bill = app.billing.byId(invoiceId)!;
    expect(bill.status).toBe('paid');
    expect(bill.outstanding).toBe(0);
    expect(bill.openCounterRequest).toBeNull();
  });
});
