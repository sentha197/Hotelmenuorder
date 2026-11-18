import { defaultUnitPrice, isAllowedImage, type MenuItem } from './menu';
import { applyRate, Currency, formatPercent1, sumPaise, type Paise } from './money';
import { AppFormat, RestaurantTime } from './time';

type Json = Record<string, unknown>;

/**
 * When coupons and promotions can be used (the server's OfferRules):
 * switched on, within their dates and with uses left. Offer dates are
 * restaurant days, both ends included, held as UTC midnights.
 */
export const OfferRules = {
  /** Today in the restaurant's time zone, as a UTC midnight. */
  today(now = new Date()): Date {
    const w = RestaurantTime.wall(now);
    return new Date(Date.UTC(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate()));
  },
  /** Reads `2026-11-01`; anything else is null. */
  parseDay(value: unknown): Date | null {
    if (typeof value !== 'string') return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
    return m ? new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]))) : null;
  },
  /** `2026-11-01` */
  dayJson(day: Date): string {
    return day.toISOString().slice(0, 10);
  },
  inDates(startsOn: Date | null, endsOn: Date | null, today: Date): boolean {
    return (startsOn == null || today >= startsOn) && (endsOn == null || today <= endsOn);
  },
  hasUsesLeft(limit: number | null, used: number): boolean {
    return limit == null || used < limit;
  },
  status(o: { isActive: boolean; startsOn: Date | null; endsOn: Date | null; usageLimit: number | null; usedCount: number }, today: Date): OfferStatus {
    if (!o.isActive) return 'paused';
    if (o.endsOn != null && today > o.endsOn) return 'ended';
    if (!OfferRules.hasUsesLeft(o.usageLimit, o.usedCount)) return 'usedUp';
    if (o.startsOn != null && today < o.startsOn) return 'scheduled';
    return 'live';
  },
  /** `1 Nov – 30 Nov 2026`, `From 1 Nov 2026`, `Until 30 Nov 2026`, or `Always`. */
  validity(startsOn: Date | null, endsOn: Date | null): string {
    if (startsOn == null && endsOn == null) return 'Always';
    if (startsOn == null) return `Until ${AppFormat.day(endsOn!)}`;
    if (endsOn == null) return `From ${AppFormat.day(startsOn)}`;
    if (startsOn.getTime() === endsOn.getTime()) return `On ${AppFormat.day(startsOn)}`;
    return `${AppFormat.shortDay(startsOn)} – ${AppFormat.day(endsOn)}`;
  },
};

export type OfferStatus = 'live' | 'scheduled' | 'ended' | 'paused' | 'usedUp';
export const offerStatusLabel: Record<OfferStatus, string> = {
  live: 'Live',
  scheduled: 'Scheduled',
  ended: 'Ended',
  paused: 'Paused',
  usedUp: 'Used up',
};

/** `Used 3 times` or `Used 3 of 100`. */
export const usageText = (used: number, limit: number | null) =>
  limit == null ? `Used ${used} ${used === 1 ? 'time' : 'times'}` : `Used ${used} of ${limit}`;

export type DiscountType = 'percent' | 'flat';
export const discountTypeLabel: Record<DiscountType, string> = { percent: 'Percentage', flat: 'Flat amount' };

/** A coupon guests type in their cart, e.g. WELCOME10. */
export interface DiscountOffer {
  code: string;
  title: string;
  type: DiscountType;
  /** Basis points for percent, paise for flat. */
  value: number;
  minSubtotal: Paise;
  maxDiscount: Paise | null;
  isActive: boolean;
  startsOn: Date | null;
  endsOn: Date | null;
  usageLimit: number | null;
  usedCount: number;
}

export function offerFromJson(json: Json): DiscountOffer {
  return {
    code: String(json.code),
    title: (json.title as string | undefined) ?? '',
    type: json.type === 'flat' ? 'flat' : 'percent',
    value: json.value as number,
    minSubtotal: (json.min as number | undefined) ?? 0,
    maxDiscount: json.max == null ? null : (json.max as number),
    isActive: (json.active as boolean | undefined) ?? true,
    startsOn: OfferRules.parseDay(json.startsOn),
    endsOn: OfferRules.parseDay(json.endsOn),
    usageLimit: (json.limit as number | null | undefined) ?? null,
    usedCount: (json.used as number | undefined) ?? 0,
  };
}

export function offerToJson(o: DiscountOffer): Json {
  return {
    code: o.code,
    title: o.title,
    type: o.type,
    value: o.value,
    ...(o.minSubtotal !== 0 ? { min: o.minSubtotal } : {}),
    ...(o.maxDiscount != null ? { max: o.maxDiscount } : {}),
    active: o.isActive,
    ...(o.startsOn ? { startsOn: OfferRules.dayJson(o.startsOn) } : {}),
    ...(o.endsOn ? { endsOn: OfferRules.dayJson(o.endsOn) } : {}),
    ...(o.usageLimit != null ? { limit: o.usageLimit } : {}),
    ...(o.usedCount !== 0 ? { used: o.usedCount } : {}),
  };
}

export const Coupons = {
  normalize: (code: string) => code.trim().toUpperCase(),
  isValidCode: (code: string) => /^[A-Z0-9]{3,16}$/.test(Coupons.normalize(code)),
  /** `10% off` or `₹75 off`. */
  benefit: (o: DiscountOffer) => (o.type === 'percent' ? `${formatPercent1(o.value)} off` : `${Currency.format(o.value)} off`),
  /** `10% off · min ₹300 · up to ₹100` */
  summary: (o: DiscountOffer) =>
    [
      Coupons.benefit(o),
      ...(o.minSubtotal !== 0 ? [`min ${Currency.format(o.minSubtotal)}`] : []),
      ...(o.maxDiscount != null ? [`up to ${Currency.format(o.maxDiscount)}`] : []),
    ].join(' · '),
  status: (o: DiscountOffer, today: Date) => OfferRules.status(o, today),
  isLiveOn: (o: DiscountOffer, today: Date) => Coupons.status(o, today) === 'live',
};

export type PromotionKind = 'special' | 'combo';
export const promotionKindLabel: Record<PromotionKind, string> = { special: 'Special offer', combo: 'Combo' };

export interface PromotionItem {
  itemId: string;
  quantity: number;
}

/** A special offer or a combo set up by the restaurant (Offers section). */
export interface Promotion {
  id: string;
  kind: PromotionKind;
  title: string;
  description: string;
  /** A picture for banners and combo cards ('' uses a dish photo). */
  image: string;
  startsOn: Date | null;
  endsOn: Date | null;
  isActive: boolean;
  usageLimit: number | null;
  usedCount: number;
  sortOrder: number;
  /** Special offers: percent (basis points) or flat (paise) off each unit. */
  discountType: DiscountType;
  discountValue: number;
  /** Combos: the price of the whole package. */
  comboPrice: Paise | null;
  items: PromotionItem[];
}

export function promotionFromJson(json: Json): Promotion {
  return {
    id: String(json.id),
    kind: json.kind === 'combo' ? 'combo' : 'special',
    title: (json.title as string | undefined) ?? '',
    description: (json.description as string | undefined) ?? '',
    image: (json.image as string | undefined) ?? '',
    startsOn: OfferRules.parseDay(json.startsOn),
    endsOn: OfferRules.parseDay(json.endsOn),
    isActive: (json.active as boolean | undefined) ?? true,
    usageLimit: (json.limit as number | null | undefined) ?? null,
    usedCount: (json.used as number | undefined) ?? 0,
    sortOrder: (json.sort as number | undefined) ?? 0,
    discountType: json.discountType === 'flat' ? 'flat' : 'percent',
    discountValue: (json.value as number | undefined) ?? 0,
    comboPrice: json.comboPrice == null ? null : (json.comboPrice as number),
    items: ((json.items as Json[] | undefined) ?? []).map((i) => ({ itemId: String(i.itemId), quantity: (i.quantity as number | undefined) ?? 1 })),
  };
}

export function promotionToJson(p: Promotion): Json {
  return {
    id: p.id,
    kind: p.kind,
    title: p.title,
    description: p.description,
    image: p.image,
    ...(p.startsOn ? { startsOn: OfferRules.dayJson(p.startsOn) } : {}),
    ...(p.endsOn ? { endsOn: OfferRules.dayJson(p.endsOn) } : {}),
    active: p.isActive,
    items: p.items.map((i) => ({ itemId: i.itemId, quantity: i.quantity })),
    ...(p.kind === 'special' ? { discountType: p.discountType, value: p.discountValue } : {}),
    ...(p.kind === 'combo' && p.comboPrice != null ? { comboPrice: p.comboPrice } : {}),
    ...(p.usageLimit != null ? { limit: p.usageLimit } : {}),
    used: p.usedCount,
    sort: p.sortOrder,
  };
}

export const Promotions = {
  /** Display (and tie-break) order: sort order, then id. */
  byOrder: (a: Promotion, b: Promotion) => a.sortOrder - b.sortOrder || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  isLiveOn: (p: Promotion, today: Date) =>
    p.isActive && OfferRules.inDates(p.startsOn, p.endsOn, today) && OfferRules.hasUsesLeft(p.usageLimit, p.usedCount),
  status: (p: Promotion, today: Date) => OfferRules.status(p, today),
  covers: (p: Promotion, itemId: string) => p.items.some((i) => i.itemId === itemId),
  /** What a special offer takes off one unit: never more than the unit. */
  unitDiscount(p: Promotion, unitPrice: Paise): Paise {
    const amount = p.discountType === 'percent' ? applyRate(unitPrice, p.discountValue) : p.discountValue;
    if (amount < 0) return 0;
    return Math.min(amount, unitPrice);
  },
  /** `20% OFF` or `₹50 OFF`. */
  badge: (p: Promotion) => (p.discountType === 'percent' ? `${formatPercent1(p.discountValue)} OFF` : `${Currency.format(p.discountValue)} OFF`),
  /** Special offers live on [today], in tie-break order. */
  liveSpecials: (promotions: readonly Promotion[], today: Date) =>
    promotions.filter((p) => p.kind === 'special' && Promotions.isLiveOn(p, today)).sort(Promotions.byOrder),
  /** The best special (live, in tie-break order) for one unit, or null when none takes anything off. */
  bestSpecial(itemId: string, unitPrice: Paise, specials: readonly Promotion[]): { offer: Promotion; perUnit: Paise } | null {
    let best: { offer: Promotion; perUnit: Paise } | null = null;
    for (const special of specials) {
      if (special.kind !== 'special' || !Promotions.covers(special, itemId)) continue;
      const perUnit = Promotions.unitDiscount(special, unitPrice);
      if (perUnit > (best?.perUnit ?? 0)) best = { offer: special, perUnit };
    }
    return best;
  },
};

/** A combo with its dishes from the current menu. */
export interface ComboView {
  combo: Promotion;
  dishes: { item: MenuItem; quantity: number }[];
}

/** The combo with its dishes, or null when one of its dishes is not on the menu. */
export function comboViewOf(combo: Promotion, menu: Map<string, MenuItem>): ComboView | null {
  if (combo.kind !== 'combo') return null;
  const dishes: ComboView['dishes'] = [];
  for (const part of combo.items) {
    const item = menu.get(part.itemId);
    if (!item) return null;
    dishes.push({ item, quantity: part.quantity });
  }
  return dishes.length ? { combo, dishes } : null;
}

export const Combos = {
  /** What the dishes cost separately. */
  originalPrice: (v: ComboView) => sumPaise(v.dishes.map((d) => defaultUnitPrice(d.item) * d.quantity)),
  price: (v: ComboView) => v.combo.comboPrice ?? Combos.originalPrice(v),
  /** What one combo saves (none if its dishes became cheaper than it). */
  saving: (v: ComboView) => Math.max(0, Combos.originalPrice(v) - Combos.price(v)),
  dishesOrderable: (v: ComboView) => v.dishes.every((d) => d.item.isAvailable && !d.item.isArchived && d.item.category.isActive),
  isVeg: (v: ComboView) => v.dishes.every((d) => d.item.isVeg),
  partLabel: (quantity: number, name: string) => (quantity > 1 ? `${quantity} × ${name}` : name),
  partLabels: (v: ComboView) => v.dishes.map((d) => Combos.partLabel(d.quantity, d.item.name)),
  image: (v: ComboView) => v.combo.image || v.dishes[0]!.item.image,
  prepMinutes: (v: ComboView) => Math.max(...v.dishes.map((d) => d.item.prepMinutes)),
};

export const MAX_USAGE_LIMIT = 1_000_000;
export const MAX_SPECIAL_DISHES = 100;
export const MAX_COMBO_DISHES = 10;
export const MAX_COMBO_QUANTITY = 10;

/** Shared by coupons, special offers and combos (the server's PromotionService). */
export const validateDates = (startsOn: Date | null, endsOn: Date | null) =>
  startsOn != null && endsOn != null && endsOn < startsOn ? 'The last day cannot be before the first day.' : null;

export const validateUsageLimit = (limit: number | null) =>
  limit != null && (limit < 1 || limit > MAX_USAGE_LIMIT) ? 'A usage limit is 1 to 10,00,000 orders, or none.' : null;

/** SettingsController.saveOffer's checks, in order. */
export function validateCoupon(offer: DiscountOffer, existing: readonly DiscountOffer[], originalCode: string | null): string | null {
  const code = Coupons.normalize(offer.code);
  if (!Coupons.isValidCode(code)) return 'Codes use 3 to 16 capital letters or digits, e.g. WELCOME10.';
  if (existing.some((o) => o.code === code && o.code !== originalCode)) return `${code} already exists.`;
  const title = offer.title.trim();
  if (!title || title.length > 40) return 'Give the offer a title (up to 40 characters).';
  if (offer.type === 'percent' && (offer.value < 100 || offer.value > 9000)) return 'Percentage must be between 1% and 90%.';
  if (offer.type === 'flat' && (offer.value < 100 || offer.value > 10_000_000)) {
    return `Flat discount must be at least ${Currency.format(100)}.`;
  }
  if (offer.minSubtotal < 0) return 'Minimum order cannot be negative.';
  return validateDates(offer.startsOn, offer.endsOn) ?? validateUsageLimit(offer.usageLimit);
}

/** CatalogController.validatePromotion. */
export function validatePromotion(p: Promotion, menu: Map<string, MenuItem>): string | null {
  const title = p.title.trim();
  if (title.length < 2 || title.length > 60) return 'Give it a title of 2 to 60 characters.';
  if (p.description.trim().length > 300) return 'The description can be at most 300 characters.';
  if (!isAllowedImage(p.image)) return 'Choose a bundled photo or upload a picture.';
  const dates = validateDates(p.startsOn, p.endsOn);
  if (dates) return dates;
  const limit = validateUsageLimit(p.usageLimit);
  if (limit) return limit;
  const ids = p.items.map((i) => i.itemId);
  if (new Set(ids).size !== ids.length) return 'Each dish can be listed once.';
  for (const id of ids) {
    const dish = menu.get(id);
    if (!dish || dish.isArchived) return 'Some of the chosen dishes are no longer on the menu.';
  }
  if (p.kind === 'special') {
    if (ids.length === 0 || ids.length > MAX_SPECIAL_DISHES) return `Choose 1 to ${MAX_SPECIAL_DISHES} dishes for the offer.`;
    const value = p.discountValue;
    if (p.discountType === 'percent') {
      if (value < 100 || value > 10_000) return 'A percentage discount is 1% to 100%.';
    } else if (value < 100 || value > 10_000_000) {
      return `A flat discount is ${Currency.format(100)} to ${Currency.format(10_000_000)}.`;
    }
    return null;
  }
  const units = p.items.reduce((sum, i) => sum + i.quantity, 0);
  if (ids.length === 0 || ids.length > MAX_COMBO_DISHES || units < 2) {
    return `A combo holds at least two dishes, from 1 to ${MAX_COMBO_DISHES} different ones.`;
  }
  if (p.items.some((i) => i.quantity < 1 || i.quantity > MAX_COMBO_QUANTITY)) {
    return `Each dish can be in a combo 1 to ${MAX_COMBO_QUANTITY} times.`;
  }
  const price = p.comboPrice;
  if (price == null || price < 100 || price > 10_000_000) {
    return `The combo price must be between ${Currency.format(100)} and ${Currency.format(10_000_000)}.`;
  }
  const original = Combos.originalPrice(comboViewOf(p, menu)!);
  if (price >= original) return `A combo must cost less than its dishes do separately (${Currency.format(original)}).`;
  return null;
}
