import { applyRate, type Paise } from './money';

type Json = Record<string, unknown>;

/**
 * A special offer: a discount on the listed dishes, live today (the server
 * sends guests only offers that are switched on, within their dates and with
 * uses left). The server prices every order with them; the cart applies the
 * same rules, so the total the guest sees is the one the server accepts.
 */
export interface SpecialOffer {
  id: string;
  title: string;
  description: string;
  discountType: 'percent' | 'flat';
  /** Basis points for percent (5000 = 50%), paise for flat. */
  value: number;
  itemIds: ReadonlySet<string>;
  sortOrder: number;
}

/** The special offers in a `GET /menu` answer (combos are not offered here). */
export function specialsFromJson(json: unknown): SpecialOffer[] {
  if (!Array.isArray(json)) return [];
  return (json as Json[])
    .filter((p) => p.kind === 'special' && p.active !== false)
    .map((p) => ({
      id: String(p.id),
      title: String(p.title ?? ''),
      description: String(p.description ?? ''),
      discountType: p.discountType === 'flat' ? ('flat' as const) : ('percent' as const),
      value: Number(p.value ?? 0),
      itemIds: new Set(((p.items as Json[] | undefined) ?? []).map((i) => String(i.itemId))),
      sortOrder: Number(p.sort ?? 0),
    }))
    // The server's order: sort order, then id (the first of equal offers wins).
    .sort((a, b) => a.sortOrder - b.sortOrder || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/** What [special] takes off one unit costing [unitPrice]: never more than the unit. */
export function unitDiscount(special: SpecialOffer, unitPrice: Paise): Paise {
  const amount = special.discountType === 'percent' ? applyRate(unitPrice, special.value) : special.value;
  return Math.min(Math.max(amount, 0), unitPrice);
}

/** A cart line's saving from the best special offer on its dish. */
export interface LineSaving {
  offer: SpecialOffer;
  /** For the whole line (all units). */
  amount: Paise;
}

/** The best special offer for [quantity] units of [itemId] at [unitPrice], like the server's. */
export function bestSaving(specials: readonly SpecialOffer[], itemId: string, unitPrice: Paise, quantity: number): LineSaving | null {
  let best: SpecialOffer | null = null;
  let bestUnit = 0;
  for (const special of specials) {
    if (!special.itemIds.has(itemId)) continue;
    const unit = unitDiscount(special, unitPrice);
    if (unit > bestUnit) {
      best = special;
      bestUnit = unit;
    }
  }
  return best ? { offer: best, amount: bestUnit * quantity } : null;
}

/** `50% off` or `₹40 off` (for badges). */
export function specialBenefit(special: SpecialOffer, format: (paise: Paise) => string): string {
  if (special.discountType === 'flat') return `${format(special.value)} off`;
  const percent = special.value / 100;
  return `${Number.isInteger(percent) ? percent.toFixed(0) : percent.toFixed(1)}% off`;
}

/** The bill's discount label when more than one offer applies (the server's wording). */
export const COMBINED_DISCOUNT_LABEL = 'Offers & savings';
