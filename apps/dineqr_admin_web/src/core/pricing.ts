import { isOrderable, type MenuItem, type SpiceLevel } from './menu';
import { applyRate, formatRate, sumPaise, type Paise } from './money';
import { Combos, Promotions, type ComboView, type Promotion } from './offers';

type Json = Record<string, unknown>;

/** Pricing rules configured by the restaurant. */
export interface PricingConfig {
  /** Basis points (500 = 5%). */
  taxRateBasisPoints: number;
  /** What the tax is called on bills (e.g. "GST"). */
  taxName: string;
  serviceChargeBasisPoints: number;
}

export type DiscountKind = 'special' | 'combo' | 'coupon';

/** One saving on a bill, e.g. `Snack hour −₹55`. [ref] is the promotion id or coupon code. */
export interface DiscountLine {
  kind: DiscountKind;
  label: string;
  amount: Paise;
  ref: string | null;
}

/**
 * The amounts of one bill, computed with one shared formula everywhere:
 *
 *     discount = min(discount, subtotal)
 *     service  = (subtotal − discount) × service rate
 *     taxable  = subtotal − discount + service
 *     tax      = taxable × tax rate      (each rounded half-up to the paisa)
 *     total    = taxable + tax
 */
export interface BillBreakdown {
  subtotal: Paise;
  discount: Paise;
  discountLabel: string | null;
  discounts: DiscountLine[];
  serviceCharge: Paise;
  serviceChargeBasisPoints: number;
  tax: Paise;
  total: Paise;
  taxRateBasisPoints: number;
  taxName: string;
}

export function billFromSubtotal(subtotal: Paise, config: PricingConfig, discount = 0, discountLabel: string | null = null, discounts: DiscountLine[] = []): BillBreakdown {
  const applied = discount <= 0 ? 0 : Math.min(discount, subtotal);
  const afterDiscount = subtotal - applied;
  const service = applyRate(afterDiscount, config.serviceChargeBasisPoints);
  const taxable = afterDiscount + service;
  const tax = applyRate(taxable, config.taxRateBasisPoints);
  return {
    subtotal,
    discount: applied,
    discountLabel: applied === 0 ? null : discountLabel,
    discounts: applied === 0 ? [] : discounts,
    serviceCharge: service,
    serviceChargeBasisPoints: config.serviceChargeBasisPoints,
    tax,
    total: taxable + tax,
    taxRateBasisPoints: config.taxRateBasisPoints,
    taxName: config.taxName,
  };
}

export function billFromJson(json: Json): BillBreakdown {
  return {
    subtotal: json.subtotal as number,
    discount: (json.discount as number | undefined) ?? 0,
    discountLabel: (json.discountLabel as string | undefined) ?? null,
    discounts: ((json.discounts as Json[] | undefined) ?? []).map((d) => ({
      kind: d.kind === 'combo' ? 'combo' : d.kind === 'coupon' ? 'coupon' : 'special',
      label: (d.label as string | undefined) ?? '',
      amount: (d.amount as number | undefined) ?? 0,
      ref: (d.ref as string | undefined) ?? null,
    })),
    serviceCharge: (json.service as number | undefined) ?? 0,
    serviceChargeBasisPoints: (json.serviceRate as number | undefined) ?? 0,
    tax: json.tax as number,
    total: json.total as number,
    taxRateBasisPoints: json.taxRate as number,
    taxName: (json.taxName as string | undefined) ?? 'Taxes',
  };
}

export const Bills = {
  taxLabel: (b: BillBreakdown) => `${b.taxName} (${formatRate(b.taxRateBasisPoints)})`,
  serviceChargeLabel: (b: BillBreakdown) => `Service charge (${formatRate(b.serviceChargeBasisPoints)})`,
  taxableAmount: (b: BillBreakdown) => b.subtotal - b.discount + b.serviceCharge,
  /** The discount lines to show: itemised ones, or one line for a bill without them. */
  discountLines: (b: BillBreakdown): DiscountLine[] =>
    b.discounts.length ? b.discounts : b.discount !== 0 ? [{ kind: 'coupon', label: b.discountLabel ?? 'Discount', amount: b.discount, ref: null }] : [],
};

/** The options picked for a dish (staff orders use the defaults). */
export interface DishCustomization {
  spice: SpiceLevel | null;
  portionId: string | null;
  addOnIds: string[];
}

export const defaultsFor = (item: MenuItem): DishCustomization => ({
  spice: item.hasSpiceLevel ? item.defaultSpice : null,
  portionId: item.portions[0]?.id ?? null,
  addOnIds: [],
});

/** One line of a staff order: a dish with its options, or a combo. */
export interface CartLine {
  id: string;
  item: MenuItem;
  customization: DishCustomization;
  quantity: number;
  combo: ComboView | null;
}

/** The combo dressed as a dish, so a line can show it like one. */
function comboAsItem(view: ComboView, live: boolean): MenuItem {
  return {
    id: view.combo.id,
    name: view.combo.title,
    category: { id: 'combos', label: 'Combos', coverImage: '', sortOrder: 999, isActive: true },
    description: view.combo.description,
    shortDescription: Combos.partLabels(view).join(', '),
    price: Combos.originalPrice(view),
    image: Combos.image(view),
    gallery: [],
    isVeg: Combos.isVeg(view),
    rating: 0,
    reviewCount: 0,
    isPopular: false,
    isChefSpecial: false,
    isFeatured: false,
    hasSpiceLevel: false,
    defaultSpice: 'medium',
    portions: [],
    addOns: [],
    prepMinutes: Combos.prepMinutes(view),
    isAvailable: live && Combos.dishesOrderable(view),
    isArchived: false,
  };
}

const customizationKey = (c: DishCustomization) => `${c.spice ?? '-'}|${c.portionId ?? '-'}|${[...c.addOnIds].sort().join(',')}`;

export const CartLines = {
  maxQuantity: 20,
  maxInstructionsLength: 200,
  dish(item: MenuItem, quantity = 1): CartLine {
    const customization = defaultsFor(item);
    return { id: `${item.id}::${customizationKey(customization)}`, item, customization, quantity, combo: null };
  },
  combo(view: ComboView, quantity: number, live: boolean): CartLine {
    return { id: `combo::${view.combo.id}`, item: comboAsItem(view, live), customization: { spice: null, portionId: null, addOnIds: [] }, quantity, combo: view };
  },
  /** The full price of one unit (a combo's dishes bought separately). */
  unitPrice(line: CartLine): Paise {
    if (line.combo) return line.item.price;
    const item = line.item;
    let extra = item.portions.find((p) => p.id === line.customization.portionId)?.extraPrice ?? 0;
    for (const id of line.customization.addOnIds) extra += item.addOns.find((a) => a.id === id)?.price ?? 0;
    return item.price + extra;
  },
  lineTotal: (line: CartLine) => CartLines.unitPrice(line) * line.quantity,
  orderable: (line: CartLine) => isOrderable(line.item),
  /** What the server prices: a dish with its options, or a combo by id. */
  toJson(line: CartLine): Json {
    if (line.combo) return { comboId: line.combo.combo.id, quantity: line.quantity };
    const c = line.customization;
    return {
      itemId: line.item.id,
      quantity: line.quantity,
      options: {
        ...(c.spice ? { spice: c.spice } : {}),
        ...(c.portionId ? { portion: c.portionId } : {}),
        ...(c.addOnIds.length ? { addOns: [...c.addOnIds].sort() } : {}),
      },
    };
  },
};

/** The saving on one line: a special offer on its dish, or a combo's saving. */
export interface LineSaving {
  kind: DiscountKind;
  amount: Paise;
  promotionId: string;
  label: string;
}

export interface CartQuote {
  savings: Map<string, LineSaving>;
  discounts: DiscountLine[];
  bill: BillBreakdown;
  itemSavings: Paise;
}

/** The order's discount label when it has several savings (the server's wording). */
export const COMBINED_DISCOUNT_LABEL = 'Offers & savings';

/**
 * How a cart is priced with its offers (OfferPricing.quote; the server's
 * Pricing.Apply has the final word): each dish line gets the best live
 * special offer covering its dish, each combo line its combo's saving; then
 * service charge and tax. Staff orders carry no coupon.
 */
export function quoteCart(lines: readonly CartLine[], liveSpecials: readonly Promotion[], config: PricingConfig): CartQuote {
  const savings = new Map<string, LineSaving>();
  for (const line of lines) {
    if (line.combo) {
      const saving = Combos.saving(line.combo) * line.quantity;
      if (saving > 0) savings.set(line.id, { kind: 'combo', amount: saving, promotionId: line.combo.combo.id, label: line.combo.combo.title });
      continue;
    }
    const best = Promotions.bestSpecial(line.item.id, CartLines.unitPrice(line), liveSpecials);
    if (best) savings.set(line.id, { kind: 'special', amount: best.perUnit * line.quantity, promotionId: best.offer.id, label: best.offer.title });
  }
  // One entry per promotion, in the order its lines appear.
  const discounts: DiscountLine[] = [];
  for (const line of lines) {
    const saving = savings.get(line.id);
    if (!saving) continue;
    const existing = discounts.find((d) => d.ref === saving.promotionId);
    if (existing) existing.amount += saving.amount;
    else discounts.push({ kind: saving.kind, label: saving.label, amount: saving.amount, ref: saving.promotionId });
  }
  const subtotal = sumPaise(lines.map(CartLines.lineTotal));
  const itemSavings = sumPaise([...savings.values()].map((s) => s.amount));
  const label = discounts.length === 0 ? null : discounts.length === 1 ? discounts[0]!.label : COMBINED_DISCOUNT_LABEL;
  return { savings, discounts, bill: billFromSubtotal(subtotal, config, itemSavings, label, discounts), itemSavings };
}
