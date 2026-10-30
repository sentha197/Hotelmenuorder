import { describe, expect, it } from 'vitest';
import { Invoice, SplitPlan, UpiPaymentLink, UpiSettings, validateAmount } from './billing';
import { CartItem, DishCustomization, MenuItem, applyFilter, defaultFilter } from './menu';
import { applyRate, Currency } from './money';
import { BillBreakdown, DiscountOffer, formatRate } from './pricing';
import { AppFormat, RestaurantTime } from './time';

const category = { id: 'mains', label: 'Main Course', coverImage: '', sortOrder: 0, isActive: true };
const dish = (json: Record<string, unknown> = {}) =>
  MenuItem.fromJson({ id: 'paneer', name: 'Paneer Tikka', category: 'mains', price: 24000, ...json }, new Map([['mains', category]]));

describe('money', () => {
  it('rounds rates half-up to the paisa, like the server', () => {
    expect(applyRate(10050, 500)).toBe(503); // 502.5 -> 503
    expect(applyRate(10030, 500)).toBe(502); // 501.5 -> 502
    expect(applyRate(10010, 500)).toBe(501); // 500.5 -> 501
    expect(applyRate(0, 500)).toBe(0);
  });

  it('formats like the Flutter app', () => {
    Currency.configure('INR');
    expect(Currency.format(18000)).toBe('₹180');
    expect(Currency.format(125000)).toBe('₹1,250');
    expect(Currency.format(10000000)).toBe('₹1,00,000');
    expect(Currency.format(47250)).toBe('₹472.50');
    expect(Currency.formatExtra(4000)).toBe('+₹40');
    expect(Currency.parse('250')).toBe(25000);
    expect(Currency.parse('₹ 250.5')).toBe(25050);
    expect(Currency.parse('2.505')).toBeNull();
    expect(formatRate(500)).toBe('5%');
    expect(formatRate(250)).toBe('2.5%');
  });
});

describe('bill formula', () => {
  it('discount, then service, then tax on both', () => {
    const bill = BillBreakdown.fromSubtotal(100000, { taxRateBasisPoints: 500, taxName: 'GST', serviceChargeBasisPoints: 1000 }, 10000, 'Offer X');
    expect(bill.discount).toBe(10000);
    expect(bill.serviceCharge).toBe(9000);
    expect(bill.tax).toBe(4950);
    expect(bill.total).toBe(103950);
    expect(bill.taxLabel).toBe('GST (5%)');
  });

  it('never discounts more than the subtotal', () => {
    const bill = BillBreakdown.fromSubtotal(5000, { taxRateBasisPoints: 500, taxName: 'Taxes', serviceChargeBasisPoints: 0 }, 9000, 'X');
    expect(bill.discount).toBe(5000);
    expect(bill.total).toBe(0);
  });
});

describe('offers', () => {
  const welcome = DiscountOffer.fromJson({ code: 'WELCOME10', title: 'Welcome', type: 'percent', value: 1000, min: 30000, max: 10000 });
  it('applies above the minimum, capped', () => {
    expect(welcome.check(29999)).toBe('belowMinimum');
    expect(welcome.discountFor(29999)).toBe(0);
    expect(welcome.discountFor(50000)).toBe(5000);
    expect(welcome.discountFor(200000)).toBe(10000);
    expect(welcome.shortfall(25000)).toBe(5000);
    expect(welcome.summary).toBe('10% off · min ₹300 · up to ₹100');
  });

  it('validates codes', () => {
    expect(DiscountOffer.isValidCode(' welcome10 ')).toBe(true);
    expect(DiscountOffer.isValidCode('AB')).toBe(false);
    expect(DiscountOffer.isValidCode('WITH SPACE')).toBe(false);
  });
});

describe('menu', () => {
  it('prices customizations and merges identical ones', () => {
    const item = dish({
      spicy: true,
      portions: [{ id: 'half', label: 'Half' }, { id: 'full', label: 'Full', extra: 8000 }],
      addOns: [{ id: 'cheese', name: 'Cheese', price: 3000 }, { id: 'butter', name: 'Butter', price: 2500 }],
    });
    const a = new DishCustomization('spicy', 'full', ['cheese', 'butter']);
    const b = new DishCustomization('spicy', 'full', ['butter', 'cheese', 'butter']);
    expect(a.key).toBe(b.key);
    const line = new CartItem(item, a, 2);
    expect(line.unitPrice).toBe(24000 + 8000 + 3000 + 2500);
    expect(line.lineTotal).toBe(2 * 37500);
    expect(line.optionLabels).toEqual(['Spice: Spicy', 'Full', 'Butter', 'Cheese']);
    expect(line.toJson()).toEqual({ itemId: 'paneer', quantity: 2, options: { spice: 'spicy', portion: 'full', addOns: ['butter', 'cheese'] } });
  });

  it('filters, searches and puts sold-out dishes last', () => {
    const items = [
      dish({ id: 'a', name: 'Alpha', reviews: 5 }),
      dish({ id: 'b', name: 'Beta', reviews: 50, available: false }),
      dish({ id: 'c', name: 'Gamma', reviews: 20, veg: true, short: 'with alpha sauce' }),
    ];
    expect(applyFilter(defaultFilter, items).map((i) => i.id)).toEqual(['c', 'a', 'b']);
    expect(applyFilter({ ...defaultFilter, diet: 'veg' }, items).map((i) => i.id)).toEqual(['c']);
    // Name matches rank above description matches while searching.
    expect(applyFilter({ ...defaultFilter, query: 'alpha' }, items).map((i) => i.id)).toEqual(['a', 'c']);
  });
});

describe('bills', () => {
  const invoice = (payments: Record<string, unknown>[] = [], extra: Record<string, unknown> = {}) =>
    Invoice.fromJson({
      id: 'INV1',
      number: 'DQ-2026-00001',
      order: 'OD1',
      table: 5,
      createdAt: '2026-10-29T10:00:00Z',
      lines: [],
      amounts: { subtotal: 20000, tax: 1000, total: 21000, taxRate: 500 },
      restaurant: { name: 'DineQR' },
      payments,
      ...extra,
    });
  const payment = (status: string, amount: number, extra: Record<string, unknown> = {}) => ({
    id: `PAY${Math.random()}`,
    invoice: 'INV1',
    order: 'OD1',
    amount,
    method: 'card',
    status,
    provider: 'Simulator',
    createdAt: '2026-10-29T10:05:00Z',
    updatedAt: '2026-10-29T10:05:00Z',
    ...extra,
  });

  it('derives status and balances from payment records only', () => {
    expect(invoice().status).toBe('unpaid');
    const part = invoice([payment('succeeded', 5000)]);
    expect(part.status).toBe('partiallyPaid');
    expect(part.outstanding).toBe(16000);
    const pending = invoice([payment('pending', 16000)]);
    expect(pending.status).toBe('pending');
    expect(pending.payableNow).toBe(5000);
    expect(invoice([payment('failed', 21000)]).status).toBe('failed');
    const paid = invoice([payment('succeeded', 21000, { simulated: true })]);
    expect(paid.status).toBe('paid');
    expect(paid.hasDemoPayments).toBe(true);
    expect(invoice([], { void: true }).status).toBe('voided');
  });

  it('validates amounts like the server', () => {
    const bill = invoice();
    expect(validateAmount(bill, 0)).toBe('Enter an amount to pay.');
    expect(validateAmount(bill, 30000)).toBe('You can pay at most ₹210.');
    expect(validateAmount(bill, 10000, false)).toBe('Please pay the full ₹210.');
    expect(validateAmount(bill, 21000)).toBeNull();
    expect(validateAmount(invoice([payment('pending', 1000)]), 100)).toBe('A payment for this bill is still being confirmed.');
  });

  it('splits only into valid plans', () => {
    const available = new Set(['card', 'cash', 'payAtCounter'] as const);
    expect(SplitPlan.validate([{ option: 'card', amount: 10000 }, { option: 'cash', amount: 11000 }], 21000, new Set(available), true)).toBeNull();
    expect(SplitPlan.validate([{ option: 'card', amount: 10000 }], 21000, new Set(available), true)).toBe('Add at least two parts to split the bill.');
    expect(SplitPlan.validate([{ option: 'cash', amount: 10000 }, { option: 'payAtCounter', amount: 11000 }], 21000, new Set(available), true)).toBe(
      'Choose one way to pay at the counter.',
    );
    expect(SplitPlan.validate([{ option: 'card', amount: 10000 }, { option: 'cash', amount: 1000 }], 21000, new Set(available), true)).toBe(
      'The parts add up to ₹110; ₹100 is still unassigned.',
    );
  });

  it('builds the UPI link the QR code holds', () => {
    const settings = new UpiSettings(true, 'cafe@okhdfcbank', 'Cafe & Co');
    expect(settings.isReady).toBe(true);
    const link = new UpiPaymentLink(settings.upiId, settings.payeeName, 45050, 'Bill DQ-2026-00001 PAY000001');
    expect(link.uriString).toBe('upi://pay?pa=cafe@okhdfcbank&pn=Cafe%20%26%20Co&am=450.50&cu=INR&tn=Bill%20DQ-2026-00001%20PAY000001');
    expect(new UpiSettings(true, 'not an id', 'Cafe').isReady).toBe(false);
  });
});

describe('restaurant time', () => {
  it('shows times in the restaurant time zone, not the device one', () => {
    RestaurantTime.configure(330);
    const instant = new Date('2026-10-29T07:00:00Z');
    expect(AppFormat.time(instant)).toBe('12:30 PM');
    expect(AppFormat.dateTime(instant)).toBe('29 Oct 2026, 12:30 PM');
    expect(AppFormat.table(5)).toBe('05');
  });
});
