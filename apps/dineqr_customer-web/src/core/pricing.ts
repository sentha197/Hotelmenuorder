import { applyRate, Currency, type Paise } from './money';

type Json = Record<string, unknown>;

/** `5%`, `2.5%` */
export function formatRate(basisPoints: number): string {
  const percent = basisPoints / 100;
  const text = Number.isInteger(percent) ? percent.toFixed(0) : percent.toFixed(2).replace(/0$/, '');
  return `${text}%`;
}

/** Pricing rules configured by the restaurant. */
export interface PricingConfig {
  /** Basis points (500 = 5%). */
  taxRateBasisPoints: number;
  /** What the tax is called on bills (e.g. "GST"). */
  taxName: string;
  serviceChargeBasisPoints: number;
}

export const defaultPricing: PricingConfig = {
  taxRateBasisPoints: 500,
  taxName: 'Taxes',
  serviceChargeBasisPoints: 0,
};

/**
 * The amounts of one bill, with the formula the server and every Flutter
 * screen use:
 *
 *     discount = min(discount, subtotal)
 *     service  = (subtotal − discount) × service rate
 *     taxable  = subtotal − discount + service
 *     tax      = taxable × tax rate      (each rounded half-up to the paisa)
 *     total    = taxable + tax
 */
export class BillBreakdown {
  constructor(
    readonly subtotal: Paise,
    readonly tax: Paise,
    readonly total: Paise,
    readonly taxRateBasisPoints: number,
    readonly discount: Paise = 0,
    readonly discountLabel: string | null = null,
    readonly serviceCharge: Paise = 0,
    readonly serviceChargeBasisPoints = 0,
    readonly taxName = 'Taxes',
  ) {}

  static fromSubtotal(
    subtotal: Paise,
    config: PricingConfig,
    discount: Paise = 0,
    discountLabel: string | null = null,
  ): BillBreakdown {
    const applied = discount <= 0 ? 0 : Math.min(discount, subtotal);
    const afterDiscount = subtotal - applied;
    const service = applyRate(afterDiscount, config.serviceChargeBasisPoints);
    const taxable = afterDiscount + service;
    const tax = applyRate(taxable, config.taxRateBasisPoints);
    return new BillBreakdown(
      subtotal,
      tax,
      taxable + tax,
      config.taxRateBasisPoints,
      applied,
      applied === 0 ? null : discountLabel,
      service,
      config.serviceChargeBasisPoints,
      config.taxName,
    );
  }

  /** Pricing keys as orders and bills carry them. */
  static fromJson(json: Json): BillBreakdown {
    return new BillBreakdown(
      json.subtotal as number,
      json.tax as number,
      json.total as number,
      json.taxRate as number,
      (json.discount as number | undefined) ?? 0,
      (json.discountLabel as string | undefined) ?? null,
      (json.service as number | undefined) ?? 0,
      (json.serviceRate as number | undefined) ?? 0,
      (json.taxName as string | undefined) ?? 'Taxes',
    );
  }

  static readonly empty = new BillBreakdown(0, 0, 0, 0);

  get hasDiscount(): boolean {
    return this.discount !== 0;
  }

  get hasServiceCharge(): boolean {
    return this.serviceCharge !== 0;
  }

  get taxLabel(): string {
    return `${this.taxName} (${formatRate(this.taxRateBasisPoints)})`;
  }

  get serviceChargeLabel(): string {
    return `Service charge (${formatRate(this.serviceChargeBasisPoints)})`;
  }
}

export type OfferError = 'unknownCode' | 'inactive' | 'belowMinimum';

export const offerErrorMessage: Record<OfferError, string> = {
  unknownCode: 'That code is not valid.',
  inactive: 'This offer is not active right now.',
  belowMinimum: 'Add a little more to use this offer.',
};

/** A coupon, e.g. 10% off orders above ₹300 capped at ₹100. */
export class DiscountOffer {
  constructor(
    readonly code: string,
    readonly title: string,
    readonly type: 'percent' | 'flat',
    /** Basis points for percent, paise for flat. */
    readonly value: number,
    readonly minSubtotal: Paise = 0,
    readonly maxDiscount: Paise | null = null,
    readonly isActive = true,
  ) {}

  static fromJson(json: Json): DiscountOffer {
    return new DiscountOffer(
      json.code as string,
      (json.title as string | undefined) ?? '',
      json.type === 'flat' ? 'flat' : 'percent',
      json.value as number,
      (json.min as number | undefined) ?? 0,
      json.max == null ? null : (json.max as number),
      (json.active as boolean | undefined) ?? true,
    );
  }

  static normalize(code: string): string {
    return code.trim().toUpperCase();
  }

  static isValidCode(code: string): boolean {
    return /^[A-Z0-9]{3,16}$/.test(DiscountOffer.normalize(code));
  }

  /** `10% off` or `₹75 off`. */
  get benefit(): string {
    if (this.type === 'flat') return `${Currency.format(this.value)} off`;
    const percent = this.value / 100;
    return `${Number.isInteger(percent) ? percent.toFixed(0) : percent.toFixed(1)}% off`;
  }

  /** `10% off · min ₹300 · up to ₹100` */
  get summary(): string {
    return [
      this.benefit,
      ...(this.minSubtotal !== 0 ? [`min ${Currency.format(this.minSubtotal)}`] : []),
      ...(this.maxDiscount != null ? [`up to ${Currency.format(this.maxDiscount)}`] : []),
    ].join(' · ');
  }

  /** Null when the offer applies to [subtotal]. */
  check(subtotal: Paise): OfferError | null {
    if (!this.isActive) return 'inactive';
    if (subtotal < this.minSubtotal) return 'belowMinimum';
    return null;
  }

  discountFor(subtotal: Paise): Paise {
    if (this.check(subtotal) != null) return 0;
    let amount = this.type === 'percent' ? applyRate(subtotal, this.value) : this.value;
    if (this.maxDiscount != null && amount > this.maxDiscount) amount = this.maxDiscount;
    return Math.min(amount, subtotal);
  }

  /** How much more the guest must add before the offer applies. */
  shortfall(subtotal: Paise): Paise {
    return Math.max(0, this.minSubtotal - subtotal);
  }
}
