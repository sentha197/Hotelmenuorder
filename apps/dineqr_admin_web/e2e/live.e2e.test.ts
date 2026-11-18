import { beforeAll, describe, expect, it } from 'vitest';
import { AuthService } from '@/api/auth';
import { createApiClient } from '@/api/client';
import { Staff } from '@/core/access';
import { isOrderable, type MenuItem } from '@/core/menu';
import { CartLines, quoteCart } from '@/core/pricing';
import { Promotions, OfferRules } from '@/core/offers';
import { pricingOf } from '@/core/settings';
import { requireBackend } from '@/services/backend';
import * as actions from '@/state/actions';
import { keys, queryClient } from '@/state/data';
import { Session } from '@/state/session';

/**
 * Drives the web app's own API client, sign-in and actions against a live
 * DineQR API, one module at a time, checking what the server answers.
 */
const ownerEmail = process.env.DINEQR_E2E_OWNER_EMAIL ?? '';
const ownerPassword = process.env.DINEQR_E2E_OWNER_PASSWORD ?? '';
const run = Boolean(process.env.DINEQR_E2E_API && ownerEmail && ownerPassword);
const stamp = Date.now().toString(36).slice(-5);

const api = () => requireBackend().api;

/** Loads what the screens would have in their caches. */
async function prime() {
  queryClient.setQueryData(keys.settings, await api().settings());
  queryClient.setQueryData(keys.tables, await api().tables());
  queryClient.setQueryData(keys.menu, await api().menu());
  queryClient.setQueryData(keys.orders, await api().orders());
  queryClient.setQueryData(keys.bills, await api().bills());
  queryClient.setQueryData(keys.staff, await api().staff());
  queryClient.setQueryData(keys.inventory, await api().inventory());
}

const bills = () => queryClient.getQueryData<import('@/core/billing').Invoice[]>(keys.bills) ?? [];
const menu = () => queryClient.getQueryData<{ items: MenuItem[]; categories: import('@/core/menu').MenuCategory[]; promotions: import('@/core/offers').Promotion[] }>(keys.menu)!;

describe.runIf(run)('live API', () => {
  beforeAll(async () => {
    await Session.signIn(ownerEmail, ownerPassword);
    await prime();
  });

  it('signs in as the owner with every permission', () => {
    const actor = Session.actor!;
    expect(actor.role).toBe('owner');
    expect(Session.can('manageSettings')).toBe(true);
    expect(Staff.permissions(actor).size).toBe(24);
  });

  it('refreshes the session with the stored refresh token (restore)', async () => {
    const other = new AuthService(createApiClient({ baseUrl: process.env.DINEQR_E2E_API!, timeoutMs: 20_000 }));
    const restored = await other.restore();
    expect(restored?.staff.email).toBe(ownerEmail.toLowerCase());
    // The rotated token is stored again, so this tab's next refresh still works.
    expect(await requireBackend().auth.renew()).toBe(true);
  });

  it('rejects a wrong password with the sign-in wording', async () => {
    const other = new AuthService(createApiClient({ baseUrl: process.env.DINEQR_E2E_API!, timeoutMs: 20_000 }));
    await expect(other.signIn(ownerEmail, 'wrong-password-1')).rejects.toMatchObject({ message: 'Incorrect email or password.' });
  });

  it('saves restaurant settings and opens takeaway', async () => {
    const s = queryClient.getQueryData<import('@/core/settings').RestaurantSettings>(keys.settings)!;
    await actions.updateSettings({ ...s, name: `Web Test ${stamp}`, takeawayOrdersEnabled: true, receiptFooter: 'Thanks from the web!' });
    const fresh = await api().settings();
    expect(fresh.name).toBe(`Web Test ${stamp}`);
    expect(fresh.takeawayOrdersEnabled).toBe(true);
    expect(fresh.receiptFooter).toBe('Thanks from the web!');
  });

  it('adds, edits, deactivates and removes a table', async () => {
    const number = 900 + Math.floor(Math.random() * 90);
    await actions.addTable(number, 6, 'Terrace');
    expect((await api().tables()).find((t) => t.number === number)).toMatchObject({ seats: 6, area: 'Terrace', isActive: true });
    await actions.updateTable({ number, seats: 8, area: 'Roof', isActive: true });
    await actions.setTableActive(number, false);
    expect((await api().tables()).find((t) => t.number === number)).toMatchObject({ seats: 8, area: 'Roof', isActive: false });
    await actions.removeTable(number, false);
    expect((await api().tables()).some((t) => t.number === number)).toBe(false);
  });

  it('creates a dish with portions and add-ons, sells it out and back', async () => {
    const category = menu().categories[0]!;
    const dish: MenuItem = {
      id: `web_dish_${stamp}`,
      name: `Web Dish ${stamp}`,
      category,
      description: 'Made in the end-to-end test.',
      shortDescription: 'Test dish',
      price: 25000,
      image: 'assets/images/samosa.jpg',
      gallery: [],
      isVeg: true,
      rating: 0,
      reviewCount: 0,
      isPopular: true,
      isChefSpecial: false,
      isFeatured: false,
      hasSpiceLevel: true,
      defaultSpice: 'medium',
      portions: [
        { id: 'regular', label: 'Regular', extraPrice: 0, detail: null },
        { id: 'large', label: 'Large', extraPrice: 5000, detail: 'Serves two' },
      ],
      addOns: [{ id: 'cheese', name: 'Cheese', price: 3000 }],
      prepMinutes: 12,
      isAvailable: true,
      isArchived: false,
    };
    await actions.saveMenuItem(dish);
    let saved = (await api().menu()).items.find((i) => i.id === dish.id)!;
    expect(saved).toMatchObject({ name: dish.name, price: 25000, prepMinutes: 12, isPopular: true, hasSpiceLevel: true });
    expect(saved.portions.map((p) => p.extraPrice)).toEqual([0, 5000]);
    expect(saved.addOns[0]).toMatchObject({ name: 'Cheese', price: 3000 });
    await actions.setDishAvailable(saved, false);
    saved = (await api().menu()).items.find((i) => i.id === dish.id)!;
    expect(saved.isAvailable).toBe(false);
    await actions.setDishAvailable(saved, true);
    queryClient.setQueryData(keys.menu, await api().menu());
  });

  it('adds, hides, reorders and deletes a category', async () => {
    const id = `web_cat_${stamp}`;
    await actions.saveCategory({ id, label: `Web Cat ${stamp}`, coverImage: 'assets/images/lassi.jpg', sortOrder: 0, isActive: true });
    let cats = menu().categories;
    expect(cats.some((c) => c.id === id)).toBe(true);
    await actions.setCategoryActive(cats.find((c) => c.id === id)!, false);
    expect(menu().categories.find((c) => c.id === id)!.isActive).toBe(false);
    cats = [...menu().categories].sort((a, b) => a.sortOrder - b.sortOrder);
    const order = [id, ...cats.filter((c) => c.id !== id).map((c) => c.id)];
    await actions.reorderCategories(order);
    expect([...menu().categories].sort((a, b) => a.sortOrder - b.sortOrder)[0]!.id).toBe(id);
    await actions.deleteCategory(menu().categories.find((c) => c.id === id)!);
    expect(menu().categories.some((c) => c.id === id)).toBe(false);
    // Put the original order back.
    await actions.reorderCategories(cats.filter((c) => c.id !== id).map((c) => c.id));
  });

  it('uploads a dish photo and gets its address back', async () => {
    // A 1×1 PNG.
    const png = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='), (c) => c.charCodeAt(0));
    const url = await actions.uploadDishPhoto(png);
    expect(url).toMatch(/^https?:\/\//);
  });

  it('creates, pauses and deletes a coupon', async () => {
    const code = `WEB${stamp.toUpperCase()}`.slice(0, 16);
    await actions.saveCoupon({ code, title: 'Web test', type: 'percent', value: 1000, minSubtotal: 30000, maxDiscount: 10000, isActive: true, startsOn: null, endsOn: null, usageLimit: 50, usedCount: 0 }, null);
    let offer = (await api().settings()).offers.find((o) => o.code === code);
    expect(offer).toMatchObject({ value: 1000, minSubtotal: 30000, maxDiscount: 10000, usageLimit: 50 });
    await actions.setCouponActive(code, false);
    offer = (await api().settings()).offers.find((o) => o.code === code);
    expect(offer?.isActive).toBe(false);
    await actions.deleteCoupon(code);
    expect((await api().settings()).offers.some((o) => o.code === code)).toBe(false);
  });

  it('creates a special offer and a combo, pauses one and deletes both', async () => {
    const dishes = menu().items.filter((i) => isOrderable(i)).slice(0, 2);
    await actions.savePromotion({
      id: `special_web_${stamp}`, kind: 'special', title: `Web special ${stamp}`, description: '', image: '', startsOn: OfferRules.today(), endsOn: null, isActive: true,
      usageLimit: null, usedCount: 0, sortOrder: 0, discountType: 'percent', discountValue: 2000, comboPrice: null, items: dishes.map((d) => ({ itemId: d.id, quantity: 1 })),
    });
    const original = dishes.reduce((s, d) => s + d.price + (d.portions[0]?.extraPrice ?? 0), 0);
    await actions.savePromotion({
      id: `combo_web_${stamp}`, kind: 'combo', title: `Web combo ${stamp}`, description: 'Two together', image: '', startsOn: null, endsOn: null, isActive: true,
      usageLimit: 10, usedCount: 0, sortOrder: 0, discountType: 'percent', discountValue: 0, comboPrice: original - 1000, items: dishes.map((d) => ({ itemId: d.id, quantity: 1 })),
    });
    let promos = (await api().menu()).promotions;
    expect(promos.find((p) => p.id === `special_web_${stamp}`)).toMatchObject({ kind: 'special', discountValue: 2000 });
    expect(promos.find((p) => p.id === `combo_web_${stamp}`)).toMatchObject({ kind: 'combo', comboPrice: original - 1000 });
    await actions.setPromotionActive(promos.find((p) => p.id === `combo_web_${stamp}`)!, false);
    promos = (await api().menu()).promotions;
    expect(promos.find((p) => p.id === `combo_web_${stamp}`)?.isActive).toBe(false);
    for (const p of promos.filter((x) => x.id.endsWith(stamp))) await actions.deletePromotion(p);
    expect((await api().menu()).promotions.some((p) => p.id.endsWith(stamp))).toBe(false);
  });

  it('saves the UPI details, the Wi-Fi restriction and the GPS area', async () => {
    await actions.savePaymentSettings({ enabled: true, upiId: ' Cafe.Test@okhdfcbank ', payeeName: 'Cafe Test', qrImageUrl: '', verificationMode: 'manual' }, false);
    const upi = await api().paymentSettings();
    expect(upi.upi).toMatchObject({ enabled: true, upiId: 'cafe.test@okhdfcbank', payeeName: 'Cafe Test', verificationMode: 'manual' });
    await expect(actions.savePaymentSettings({ ...upi.upi, verificationMode: 'automatic' }, false)).rejects.toThrow(/Automatic verification needs/);

    const wifi = await actions.saveNetworkAccess({ enabled: false, ssid: 'Cafe Guest', restrictTakeaway: false, networks: [{ value: '203.0.113.7', label: 'Shop', resolved: [] }] });
    expect(wifi).toMatchObject({ enabled: false, ssid: 'Cafe Guest' });
    // The server stores an address as a range (203.0.113.7/32).
    expect(wifi.networks[0]?.value).toMatch(/^203\.0\.113\.7(\/32)?$/);
    expect(wifi.you).not.toBeNull();

    const gps = await actions.saveGeofence({ enabled: false, latitude: 13.0827, longitude: 80.2707, radius: 50, takeaway: false });
    expect(gps).toMatchObject({ configured: true, latitude: 13.0827, longitude: 80.2707, radius: 50 });
  });

  it('adds a cashier, makes them a custom role with chosen access, and resets the password', async () => {
    const email = `cashier.${stamp}@dineqr.test`;
    const created = await actions.addStaff({ name: `Cashier ${stamp}`, email, role: 'cashier', roleTitle: null, password: 'Cashier123' });
    expect(created).toMatchObject({ role: 'cashier', isActive: true });
    await actions.changeRole(created, 'custom', 'Officer');
    let account = (await api().staff()).find((s) => s.email === email)!;
    expect(Staff.roleLabel(account)).toBe('Officer');
    queryClient.setQueryData(keys.staff, await api().staff());
    await actions.changeAccess(account, new Set(['viewOrders', 'viewBills', 'collectPayments']));
    account = (await api().staff()).find((s) => s.email === email)!;
    expect([...Staff.permissions(account)].sort()).toEqual(['collectPayments', 'viewBills', 'viewOrders']);
    await actions.setStaffActive(account, false);
    expect((await api().staff()).find((s) => s.email === email)!.isActive).toBe(false);
    account = (await api().staff()).find((s) => s.email === email)!;
    await actions.setStaffActive(account, true);
    await actions.resetStaffPassword(account, 'NewPass123');
    const login = new AuthService(createApiClient({ baseUrl: process.env.DINEQR_E2E_API!, timeoutMs: 20_000 }));
    const signedIn = await login.signIn(email, 'NewPass123');
    expect([...Staff.permissions(signedIn.staff)].sort()).toEqual(['collectPayments', 'viewBills', 'viewOrders']);
  });

  it('adds stock, adjusts it and refuses to go below zero', async () => {
    const dish = menu().items.find((i) => isOrderable(i))!;
    await actions.saveInventoryItem({ id: actions.newInventoryItemId(`Web flour ${stamp}`), name: `Web flour ${stamp}`, unit: 'kg', quantity: 10, reorderLevel: 3, updatedAt: new Date(), supplier: 'Mill', linkedDishIds: [dish.id], isDemoSample: false });
    let item = (await api().inventory()).items.find((i) => i.name === `Web flour ${stamp}`)!;
    expect(item).toMatchObject({ quantity: 10, reorderLevel: 3, supplier: 'Mill', linkedDishIds: [dish.id] });
    await actions.adjustStock(item, 2.5, 'Delivery received');
    item = (await api().inventory()).items.find((i) => i.id === item.id)!;
    expect(item.quantity).toBe(12.5);
    await expect(actions.adjustStock(item, -20, 'Used in kitchen')).rejects.toThrow('Only 12.5 kg in stock.');
    await actions.saveInventoryItem({ ...item, reorderLevel: 4 });
    const moves = (await api().inventory()).movements.filter((m) => m.itemId === item.id);
    expect(moves.length).toBeGreaterThanOrEqual(2);
  });

  it('places a staff order, runs it through the kitchen, takes cash and refunds part', async () => {
    await prime();
    const settings = queryClient.getQueryData<import('@/core/settings').RestaurantSettings>(keys.settings)!;
    const table = (await api().tables()).find((t) => t.isActive)!;
    const dishes = menu().items.filter((i) => isOrderable(i)).slice(0, 2);
    const lines = [CartLines.dish(dishes[0]!, 2), CartLines.dish(dishes[1]!, 1)];
    const quote = quoteCart(lines, Promotions.liveSpecials(menu().promotions, OfferRules.today()), pricingOf(settings));
    const order = await actions.placeStaffOrder({ lines, quote, tableNumber: table.number, instructions: 'No onions', isTableOrderable: () => true });
    expect(order).toMatchObject({ tableNumber: table.number, source: 'staff', status: 'placed', specialInstructions: 'No onions' });
    // The server priced it from its own menu and agreed with the web quote.
    expect(order.bill.total).toBe(quote.bill.total);
    let current = order;
    for (const target of ['accepted', 'preparing', 'readyToServe', 'served'] as const) {
      current = await actions.updateOrderStatus(current, target);
      expect(current.status).toBe(target);
    }
    const invoice = bills().find((i) => i.orderId === order.id)!;
    expect(invoice.outstanding).toBe(order.bill.total);
    const { invoice: paid } = await actions.recordCounterPayment(invoice, invoice.payableNow, 'cash', '', '');
    expect(paid.status).toBe('paid');
    const payment = paid.payments[0]!;
    const refund = await actions.refundPayment(paid, payment, 1000, 'Cold dish');
    expect(refund.status).toBe('processed');
    const after = bills().find((i) => i.id === invoice.id)!;
    expect(after.status).toBe('partiallyRefunded');
    expect(after.amountRefunded).toBe(1000);
    expect((await actions.reconcileBill(after))).toBe(0);
  });

  it('takes a takeaway order and cancels it, voiding the bill', async () => {
    const settings = queryClient.getQueryData<import('@/core/settings').RestaurantSettings>(keys.settings)!;
    const dish = menu().items.filter((i) => isOrderable(i))[2]!;
    const lines = [CartLines.dish(dish)];
    const quote = quoteCart(lines, Promotions.liveSpecials(menu().promotions, OfferRules.today()), pricingOf(settings));
    const order = await actions.placeStaffOrder({ lines, quote, tableNumber: 0, instructions: '', isTableOrderable: () => true });
    expect(order.tableNumber).toBe(0);
    await expect(actions.updateOrderStatus(order, 'cancelled', 'no')).rejects.toThrow('Enter a reason for cancelling.');
    const cancelled = await actions.updateOrderStatus(order, 'cancelled', 'Guest left');
    expect(cancelled).toMatchObject({ status: 'cancelled', cancelReason: 'Guest left' });
    const bill = bills().find((i) => i.orderId === order.id)!;
    expect(bill.isVoid).toBe(true);
    expect(bill.status).toBe('voided');
  });

  it('writes, publishes and unpublishes Terms & Conditions', async () => {
    const body = '## Ordering\n\nBy ordering you agree to pay the bill for **everything** you order at {{restaurant.name}}.\n\n- Prices include taxes shown on the bill.';
    const draft = await actions.createLegalVersion({ kind: 'terms', title: 'Terms of ordering', body, changeSummary: 'First version', requiresReacceptance: true });
    expect(draft.status).toBe('draft');
    const edited = await actions.updateLegalVersion(draft.id, { kind: 'terms', title: 'Terms of ordering (web)', body, changeSummary: 'First version', requiresReacceptance: true });
    expect(edited.title).toBe('Terms of ordering (web)');
    const published = await actions.publishLegalVersion(draft.id);
    expect(published.status).toBe('published');
    expect(Array.isArray(await api().legalAcceptances({ kind: 'terms', limit: 1000 }))).toBe(true);
    const retired = await actions.unpublishLegalVersion(draft.id);
    expect(retired.status).not.toBe('published');
  });

  it('reads the activity log, the payment gateway and the pending-payment check', async () => {
    await actions.loadAuditEvents();
    const events = queryClient.getQueryData<import('@/core/access').AuditEvent[]>(keys.audit)!;
    expect(events.length).toBeGreaterThan(5);
    expect(events.some((e) => e.action.startsWith('order.'))).toBe(true);
    const config = await api().paymentConfig();
    expect(config.available).toBe(false);
    const any = bills()[0]!;
    expect(any.payments.length >= 0).toBe(true);
  });

  it('signs out and the refresh token stops working', async () => {
    await Session.signOut();
    expect(Session.actor).toBeNull();
    const other = new AuthService(createApiClient({ baseUrl: process.env.DINEQR_E2E_API!, timeoutMs: 20_000 }));
    expect(await other.restore()).toBeNull();
  });
});
