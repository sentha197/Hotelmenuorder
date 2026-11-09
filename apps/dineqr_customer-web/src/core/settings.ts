import { DiscountOffer, type PricingConfig } from './pricing';
import { TAKEAWAY_TABLE } from './orders';

type Json = Record<string, unknown>;

export type PaymentMethodType = 'upi' | 'card' | 'netBanking' | 'wallet' | 'cash';

export const onlineMethods: PaymentMethodType[] = ['upi', 'card', 'netBanking', 'wallet'];

export const methodLabel: Record<PaymentMethodType, string> = {
  upi: 'UPI',
  card: 'Card',
  netBanking: 'Net banking',
  wallet: 'Wallet',
  cash: 'Cash',
};

export const parseMethod = (name: unknown): PaymentMethodType | null =>
  typeof name === 'string' && name in methodLabel ? (name as PaymentMethodType) : null;

/** demo: payments simulated, no money moves. live: a verified gateway. */
export type PaymentMode = 'demo' | 'live';

/** The restaurant's public settings (`GET /settings`). */
export interface RestaurantSettings {
  name: string;
  phone: string;
  email: string;
  address: string;
  taxRegistration: string;
  taxName: string;
  taxRateBasisPoints: number;
  serviceChargeBasisPoints: number;
  utcOffsetMinutes: number;
  allowPartialPayments: boolean;
  onlineMethods: Set<PaymentMethodType>;
  receiptFooter: string;
  showSoldOutDishes: boolean;
  prepBufferMinutes: number;
  /** The takeaway QR code is refused while this is off. */
  takeawayOrdersEnabled: boolean;
  offers: DiscountOffer[];
  paymentMode: PaymentMode;
  currencyCode: string;
  /** The GPS ordering area (the server keeps the coordinates). */
  location: DineInLocation;
}

/** Whether guests must share their location to order, and the radius. */
export interface DineInLocation {
  enabled: boolean;
  radius: number;
  takeaway: boolean;
}

/** Whether the GPS ordering area covers a session at [table] (0: takeaway). */
export const locationAppliesTo = (location: DineInLocation, table: number): boolean =>
  location.enabled && (table !== 0 || location.takeaway);

export const defaultSettings: RestaurantSettings = {
  name: 'DineQR Demo Restaurant',
  phone: '',
  email: '',
  address: '',
  taxRegistration: '',
  taxName: 'Taxes',
  taxRateBasisPoints: 500,
  serviceChargeBasisPoints: 0,
  utcOffsetMinutes: 330,
  allowPartialPayments: true,
  onlineMethods: new Set(onlineMethods),
  receiptFooter: 'Thank you for dining with us!',
  showSoldOutDishes: true,
  prepBufferMinutes: 5,
  takeawayOrdersEnabled: false,
  offers: [],
  paymentMode: 'demo',
  currencyCode: 'INR',
  location: { enabled: false, radius: 0, takeaway: false },
};

export function settingsFromJson(json: Json): RestaurantSettings {
  const d = defaultSettings;
  const methods = (json.methods as string[] | undefined) ?? onlineMethods;
  return {
    name: (json.name as string | undefined) ?? d.name,
    phone: (json.phone as string | undefined) ?? '',
    email: (json.email as string | undefined) ?? '',
    address: (json.address as string | undefined) ?? '',
    taxRegistration: (json.taxReg as string | undefined) ?? '',
    taxName: (json.taxName as string | undefined) ?? d.taxName,
    taxRateBasisPoints: (json.taxRate as number | undefined) ?? d.taxRateBasisPoints,
    serviceChargeBasisPoints: (json.serviceRate as number | undefined) ?? 0,
    utcOffsetMinutes: (json.utcOffset as number | undefined) ?? d.utcOffsetMinutes,
    allowPartialPayments: (json.partial as boolean | undefined) ?? true,
    onlineMethods: new Set(methods.map(parseMethod).filter((m): m is PaymentMethodType => m != null && m !== 'cash')),
    receiptFooter: (json.footer as string | undefined) ?? d.receiptFooter,
    showSoldOutDishes: (json.showSoldOut as boolean | undefined) ?? true,
    prepBufferMinutes: (json.prepBuffer as number | undefined) ?? 5,
    // Servers from before takeaway was renamed send only `parcel`.
    takeawayOrdersEnabled: (json.takeaway as boolean | undefined) ?? (json.parcel as boolean | undefined) ?? false,
    offers: ((json.offers as Json[] | undefined) ?? []).map(DiscountOffer.fromJson),
    paymentMode: json.paymentMode === 'live' ? 'live' : 'demo',
    currencyCode: (json.currency as string | undefined) ?? 'INR',
    location: locationFromJson(json.location),
  };
}

function locationFromJson(value: unknown): DineInLocation {
  const json = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  return {
    enabled: json.enabled === true,
    radius: typeof json.radius === 'number' ? json.radius : 0,
    takeaway: json.takeaway === true,
  };
}

export const pricingOf = (s: RestaurantSettings): PricingConfig => ({
  taxRateBasisPoints: s.taxRateBasisPoints,
  taxName: s.taxName,
  serviceChargeBasisPoints: s.serviceChargeBasisPoints,
});

export function offerByCode(s: RestaurantSettings, code: string): DiscountOffer | null {
  const normalized = DiscountOffer.normalize(code);
  return s.offers.find((o) => o.code === normalized) ?? null;
}

/** A dining table as guests see it. */
export interface RestaurantTable {
  number: number;
  isActive: boolean;
  /** Null from servers that do not send it. */
  seats: number | null;
}

export const tableFromJson = (json: Json): RestaurantTable => ({
  number: json.number as number,
  isActive: (json.active as boolean | undefined) ?? true,
  seats: typeof json.seats === 'number' && json.seats > 0 ? json.seats : null,
});

/** Whether guests can order at [table]: an active table, or open takeaway. */
export function isOrderable(settings: RestaurantSettings, tables: RestaurantTable[], table: number): boolean {
  return table === TAKEAWAY_TABLE
    ? settings.takeawayOrdersEnabled
    : (tables.find((t) => t.number === table)?.isActive ?? false);
}
