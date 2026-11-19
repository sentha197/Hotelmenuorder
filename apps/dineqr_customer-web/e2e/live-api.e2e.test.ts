/**
 * The web app's own services and stores against a running DineQR API.
 *
 *   DINEQR_E2E_API_URL=http://localhost:5265 \
 *   DINEQR_E2E_OWNER_EMAIL=... DINEQR_E2E_OWNER_PASSWORD=... \
 *   npm run test:e2e
 *
 * Point it only at a throwaway database: it places orders and records a
 * counter payment. The owner account plays the kitchen and the cashier
 * (staff endpoints). Guests never pay in the app.
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

async function get<T>(path: string, token: string): Promise<T> {
  const response = await fetch(`${baseUrl}/api/v1${path}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`${path} → ${response.status} ${await response.text()}`);
  return response.json() as Promise<T>;
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
    // The server billed it at once; the guest pays at the counter.
    const invoice = await get<{ id: string; status: string; amounts: { total: number } }>(`/orders/${order.id}/bill`, app.guest.currentToken()!);
    invoiceId = invoice.id;
    expect(invoice.amounts.total).toBe(seen);
    expect(invoice.status).toBe('unpaid');
  });

  it('refuses an empty cart', async () => {
    await expect(app.orders.placeOrder(app.cart, app.session.tableNumber)).rejects.toBeInstanceOf(CheckoutException);
  });

  it('has no online payment endpoint', async () => {
    for (const path of ['/payments/config', '/payments/upi']) {
      const response = await fetch(`${baseUrl}/api/v1${path}`, { headers: { Authorization: `Bearer ${app.guest.currentToken()}` } });
      expect(response.status).toBe(404);
    }
  });

  it.skipIf(!ownerEmail)('follows the kitchen to served without payment, takes a rating, and settles at the counter', async () => {
    for (const target of ['accepted', 'preparing', 'readyToServe', 'served']) {
      await staff(`/admin/orders/${orderId}/status`, { target }, staffToken);
    }
    await app.orders.load();
    const order = app.orders.byId(orderId)!;
    expect(order.status).toBe('served');
    expect(order.canRate).toBe(true);
    const rated = await app.orders.submitFeedback(orderId, 5, 'Lovely (web e2e)');
    expect(rated.feedback?.rating).toBe(5);

    const before = await get<{ status: string; payableNow: number }>(`/orders/${orderId}/bill`, app.guest.currentToken()!);
    expect(before.status).toBe('unpaid');
    await staff(`/admin/bills/${invoiceId}/payments`, { amount: before.payableNow, method: 'cash', reference: '', idempotencyKey: `e2e-cash-${Date.now()}` }, staffToken);
    const bill = await get<{ status: string; outstanding: number }>(`/orders/${orderId}/bill`, app.guest.currentToken()!);
    expect(bill.status).toBe('paid');
    expect(bill.outstanding).toBe(0);
  });
});
