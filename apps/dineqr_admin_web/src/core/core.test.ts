import { describe, expect, it, beforeEach } from 'vitest';
import { passwordProblem, permissionsOfRole, roleFromText, staffFromApi, Staff } from './access';
import { counterMethods, Invoice, validateAmount } from './billing';
import { parseLegalText } from './legal';
import { applyRate, Currency, parsePercent, parseRupees, formatRate, csvAmount } from './money';
import { categoryFromJson, itemFromJson, itemToJson, uniqueId, validateItem, type MenuItem } from './menu';
import { Coupons, validateCoupon, validatePromotion, OfferRules, Promotions, type Promotion } from './offers';
import { nextOrderAction, OrderStatuses, Tables } from './orders';
import { billFromSubtotal, CartLines, quoteCart } from './pricing';
import { codeFor, payloadFor, webBaseFor } from './qr';
import { buildReport, reportCsv } from './reports';
import { defaultSettings, settingsFromJson, settingsToJson, validateSettings } from './settings';
import { DateRanges, RestaurantTime, AppFormat } from './time';
import { modulesFor } from '@/routes/modules';

beforeEach(() => {
  RestaurantTime.configure(330);
  Currency.configure('INR');
});

const category = categoryFromJson({ id: 'starters', label: 'Starters', cover: '', sort: 0, active: true });
const dish = (over: Partial<MenuItem> = {}): MenuItem => ({
  ...itemFromJson({ id: 'samosa', name: 'Samosa', category: 'starters', price: 10000, veg: true }, new Map([['starters', category]])),
  ...over,
});

describe('money', () => {
  it('rounds rates half-up to the paisa', () => {
    expect(applyRate(1050, 500)).toBe(53);
    expect(applyRate(-1050, 500)).toBe(-53);
  });
  it('formats and parses amounts like the Flutter app', () => {
    expect(Currency.format(125000)).toBe('₹1,250');
    expect(Currency.format(47250)).toBe('₹472.50');
    expect(parseRupees('₹1,250.5')).toBe(125050);
    expect(parseRupees('12.345')).toBeNull();
    expect(parsePercent('2.5')).toBe(250);
    expect(formatRate(250)).toBe('2.5%');
    expect(csvAmount(-1205)).toBe('-12.05');
  });
});

describe('bill formula', () => {
  it('applies discount, then service charge, then tax', () => {
    const bill = billFromSubtotal(100000, { taxRateBasisPoints: 500, taxName: 'GST', serviceChargeBasisPoints: 1000 }, 20000, 'Offer');
    expect(bill).toMatchObject({ discount: 20000, serviceCharge: 8000, tax: 4400, total: 92400 });
  });
  it('never discounts more than the subtotal', () => {
    expect(billFromSubtotal(5000, { taxRateBasisPoints: 0, taxName: 'Taxes', serviceChargeBasisPoints: 0 }, 9000).total).toBe(0);
  });
});

describe('staff orders priced with offers', () => {
  const special: Promotion = {
    id: 'special_a', kind: 'special', title: 'Snack hour', description: '', image: '', startsOn: null, endsOn: null, isActive: true, usageLimit: null, usedCount: 0, sortOrder: 0,
    discountType: 'percent', discountValue: 2000, comboPrice: null, items: [{ itemId: 'samosa', quantity: 1 }],
  };
  it('gives each dish line its best live special', () => {
    const quote = quoteCart([CartLines.dish(dish(), 3)], [special], { taxRateBasisPoints: 500, taxName: 'Taxes', serviceChargeBasisPoints: 0 });
    expect(quote.itemSavings).toBe(6000);
    expect(quote.bill).toMatchObject({ subtotal: 30000, discount: 6000, discountLabel: 'Snack hour', total: 25200 });
  });
  it('sends dish lines with default options and combos by id', () => {
    const spicy = dish({ hasSpiceLevel: true, defaultSpice: 'spicy', portions: [{ id: 'half', label: 'Half', extraPrice: 0, detail: null }] });
    expect(CartLines.toJson(CartLines.dish(spicy, 2))).toEqual({ itemId: 'samosa', quantity: 2, options: { spice: 'spicy', portion: 'half' } });
  });
});

describe('invoices', () => {
  const invoice = (payments: object[] = [], extra: object = {}) =>
    Invoice.fromJson({
      id: 'INV1', number: 'DQ-1', order: 'OD1', table: 4, createdAt: '2026-11-18T08:00:00Z', lines: [],
      amounts: { subtotal: 10000, tax: 500, total: 10500, taxRate: 500 }, payments, ...extra,
    });
  const pay = (status: string, amount: number, extra: object = {}) => ({ id: `P${amount}${status}`, invoice: 'INV1', order: 'OD1', amount, method: 'cash', status, provider: 'Counter', createdAt: '2026-11-18T08:10:00Z', updatedAt: '2026-11-18T08:10:00Z', ...extra });
  it('derives status from payments and refunds', () => {
    expect(invoice().status).toBe('unpaid');
    expect(invoice([pay('succeeded', 5000)]).status).toBe('partiallyPaid');
    expect(invoice([pay('succeeded', 10500)]).status).toBe('paid');
    expect(invoice([pay('pending', 10500, { provider: 'UPI direct', claimed: '2026-11-18T08:11:00Z' })]).status).toBe('pending');
    expect(invoice([], { void: true }).status).toBe('voided');
    expect(invoice([pay('succeeded', 10500)], { void: true }).refundDue).toBe(true);
  });
  it('reads older online payments as history', () => {
    const upi = invoice([pay('succeeded', 10500, { method: 'upi', provider: 'UPI direct', claimed: '2026-11-18T08:11:00Z' })]);
    expect(upi.status).toBe('paid');
    expect(upi.payments[0]!.isCounter).toBe(false);
    expect(upi.payments[0]!.isGateway).toBe(false);
    expect(invoice([pay('succeeded', 10500, { provider: 'Cashfree' })]).payments[0]!.isGateway).toBe(true);
    expect(invoice([pay('succeeded', 10500)]).payments[0]!.isCounter).toBe(true);
    // A field older servers sent is ignored.
    expect(invoice([], { counterRequest: { kind: 'cash', amount: 10500, at: '2026-11-18T08:05:00Z' } }).status).toBe('unpaid');
  });
  it('refuses amounts the bill cannot take, and the counter takes cash, card or UPI', () => {
    expect(validateAmount(invoice(), 20000)).toBe('At most ₹105 is due.');
    expect(validateAmount(invoice([pay('succeeded', 10500)]), 100)).toBe('This bill is already paid.');
    expect(validateAmount(invoice(), 10500)).toBeNull();
    expect(counterMethods).toEqual(['cash', 'card', 'upi']);
  });
});

describe('restaurant time', () => {
  it('starts days at local midnight and formats in restaurant time', () => {
    const start = RestaurantTime.startOfDay(new Date('2026-11-18T20:00:00Z'));
    expect(start.toISOString()).toBe('2026-11-18T18:30:00.000Z');
    expect(AppFormat.dateTime(new Date('2026-11-18T08:00:00Z'))).toBe('18 Nov 2026, 1:30 PM');
  });
});

describe('reports', () => {
  it('counts orders, money and bills like SalesReport', () => {
    const now = new Date('2026-11-18T12:00:00Z');
    const order = { id: 'OD1', tableNumber: 3, createdAt: new Date('2026-11-18T07:00:00Z'), lines: [{ itemId: 'samosa', name: 'Samosa', image: '', isVeg: true, unitPrice: 10000, quantity: 1, options: [], categoryId: '', categoryName: 'Starters', comboId: null, comboItems: [], discount: 0, discountLabel: null, promotionId: null }], bill: billFromSubtotal(10000, { taxRateBasisPoints: 500, taxName: 'Taxes', serviceChargeBasisPoints: 0 }), specialInstructions: '', status: 'served' as const, statusTimes: {}, estimatedReadyAt: now, feedback: null, isDemoSample: false, source: 'guest' as const, cancelReason: '' };
    const report = buildReport({ orders: [order], invoices: [], range: DateRanges.preset('today', now), now });
    expect(report).toMatchObject({ orderCount: 1, completedCount: 1, grossSales: 10000, billed: 10500, averageOrderValue: 10500 });
    expect(reportCsv(report, defaultSettings)).toContain('Gross sales,100.00');
  });
});

describe('validation messages match the Flutter controllers', () => {
  it('checks settings', () => {
    expect(validateSettings({ ...defaultSettings, name: 'A' })).toBe('Restaurant name must be 2 to 60 characters.');
    expect(validateSettings({ ...defaultSettings, taxRateBasisPoints: 3000 })).toBe('Tax rate must be between 0% and 28%.');
    expect(validateSettings(defaultSettings)).toBeNull();
  });
  it('round-trips settings without coupons, Wi-Fi, GPS or payment options', () => {
    const json = settingsToJson(settingsFromJson({ name: 'Cafe', methods: ['upi', 'qr'], partial: true, takeaway: true }));
    expect(json).toMatchObject({ name: 'Cafe', takeaway: true, parcel: true });
    expect(json).not.toHaveProperty('methods');
    expect(json).not.toHaveProperty('partial');
    expect(json).not.toHaveProperty('offers');
    expect(json).not.toHaveProperty('wifi');
  });
  it('checks dishes', () => {
    expect(validateItem(dish({ name: 'X' }), [], [category])).toBe('Dish name must be 2 to 40 characters.');
    expect(validateItem(dish({ price: 50 }), [], [category])).toBe('Price must be between ₹1 and ₹1,00,000.');
    expect(validateItem(dish(), [dish({ id: 'other' })], [category])).toBe('Another dish is already called "Samosa".');
    expect(itemToJson(dish({ isAvailable: false }))).toMatchObject({ id: 'samosa', category: 'starters', available: false });
  });
  it('checks coupons and promotions', () => {
    const coupon = { code: 'ab', title: 'x', type: 'percent' as const, value: 1000, minSubtotal: 0, maxDiscount: null, isActive: true, startsOn: null, endsOn: null, usageLimit: null, usedCount: 0 };
    expect(validateCoupon(coupon, [], null)).toBe('Codes use 3 to 16 capital letters or digits, e.g. WELCOME10.');
    expect(Coupons.summary({ ...coupon, minSubtotal: 30000, maxDiscount: 10000 })).toBe('10% off · min ₹300 · up to ₹100');
    const combo: Promotion = { id: 'combo_x', kind: 'combo', title: 'Pair', description: '', image: '', startsOn: null, endsOn: null, isActive: true, usageLimit: null, usedCount: 0, sortOrder: 0, discountType: 'percent', discountValue: 0, comboPrice: 30000, items: [{ itemId: 'samosa', quantity: 2 }] };
    expect(validatePromotion(combo, new Map([['samosa', dish()]]))).toBe('A combo must cost less than its dishes do separately (₹200).');
    expect(Promotions.badge({ ...combo, kind: 'special', discountValue: 1250 })).toBe('12.5% OFF');
  });
  it('checks passwords and role names', () => {
    expect(passwordProblem('short1')).toBe('Use at least 8 characters.');
    expect(passwordProblem('longpassword')).toBe('Use letters and numbers.');
    expect(roleFromText('service staff')).toEqual({ role: 'waiter', title: null });
    expect(roleFromText('Officer')).toEqual({ role: 'custom', title: 'Officer' });
  });
});

describe('orders, tables and QR codes', () => {
  it('moves orders one step at a time and words takeaway steps', () => {
    expect(nextOrderAction('preparing', true)?.label).toBe('Ready for pickup');
    expect(nextOrderAction('readyToServe', false)?.label).toBe('Mark served');
    expect(OrderStatuses.canTransitionTo('readyToServe', 'cancelled')).toBe(false);
    expect(Tables.label(0)).toBe('Takeaway');
    expect(Tables.label(7)).toBe('Table 07');
  });
  it('prints payloads, or links when a web base is set', () => {
    expect(payloadFor(5)).toBe('DINEQR:TABLE:05');
    expect(payloadFor(0)).toBe('DINEQR:TAKEAWAY');
    expect(codeFor(5, 'https://order.example.com/')).toBe('https://order.example.com/t/05');
    expect(webBaseFor('', 'https://hotelmenuorder.onrender.com', true, 'https://hotelmenuorder.onrender.com')).toBe('https://hotelmenuorder.onrender.com');
    expect(webBaseFor('', 'http://localhost:5264', false, 'https://hotelmenuorder.onrender.com')).toBeNull();
  });
});

describe('roles and workspaces', () => {
  const account = (role: string, extra: object = {}) => staffFromApi({ id: '1', name: 'A', email: 'a@b.c', role, createdAt: '2026-01-01T00:00:00Z', ...extra });
  it('opens each role on its main module', () => {
    expect(modulesFor(account('kitchen')).map((m) => m.id)).toEqual(['kitchen', 'orders', 'menu']);
    expect(modulesFor(account('cashier'))[0]!.id).toBe('bills');
    expect(modulesFor(account('owner'))).toHaveLength(14);
    // No role has an online-payment module.
    for (const role of ['owner', 'manager', 'cashier', 'accountant']) {
      expect(modulesFor(account(role)).map((m) => m.id)).not.toContain('payments');
    }
  });
  it('uses the access the owner chose instead of the role', () => {
    const custom = account('custom', { roleTitle: 'Officer', customAccess: true, permissions: ['viewOrders', 'viewBills'] });
    expect(Staff.roleLabel(custom)).toBe('Officer');
    expect(modulesFor(custom).map((m) => m.id)).toEqual(['orders', 'bills']);
    expect(permissionsOfRole('owner').size).toBe(22);
  });
});

describe('legal text', () => {
  it('parses headings, bullets, paragraphs and bold only', () => {
    const blocks = parseLegalText('## Title\n\nLine one\nline two **bold**\n\n- item\n<script>x</script>');
    expect(blocks.map((b) => b.type)).toEqual(['heading', 'paragraph', 'bullet', 'paragraph']);
    expect(blocks[1]!.spans).toEqual([{ text: 'Line one line two ', bold: false }, { text: 'bold', bold: true }]);
    expect(blocks[3]!.spans[0]!.text).toBe('<script>x</script>');
  });
});

describe('offer days', () => {
  it('reads calendar days and validity', () => {
    const day = OfferRules.parseDay('2026-11-01')!;
    expect(OfferRules.dayJson(day)).toBe('2026-11-01');
    expect(OfferRules.validity(day, null)).toBe('From 1 Nov 2026');
    expect(uniqueId('Paneer Roll!', new Set(['paneer_roll']), 'dish')).toBe('paneer_roll_2');
  });
});
