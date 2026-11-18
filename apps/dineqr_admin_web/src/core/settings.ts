import type { PaymentMethodType } from './billing';
import { lookupCurrency } from './money';
import { offerFromJson, type DiscountOffer } from './offers';
import type { PricingConfig } from './pricing';

type Json = Record<string, unknown>;

/**
 * The online options guests may be offered, each switched on and off by
 * itself (settings key `upi`, `qr`, `card`, `netBanking`, `wallet`). UPI from
 * a UPI app and UPI by QR code are separate options; both record `upi`.
 */
export type OnlineOption = 'upi' | 'scanAndPay' | 'card' | 'netBanking' | 'wallet';
export const onlineOptions: readonly OnlineOption[] = ['upi', 'scanAndPay', 'card', 'netBanking', 'wallet'];

export const onlineOptionInfo: Record<OnlineOption, { settingKey: string; settingLabel: string; method: PaymentMethodType }> = {
  upi: { settingKey: 'upi', settingLabel: 'UPI Payment', method: 'upi' },
  scanAndPay: { settingKey: 'qr', settingLabel: 'QR Code Payment', method: 'upi' },
  card: { settingKey: 'card', settingLabel: 'Card', method: 'card' },
  netBanking: { settingKey: 'netBanking', settingLabel: 'Net Banking', method: 'netBanking' },
  wallet: { settingKey: 'wallet', settingLabel: 'Wallet', method: 'wallet' },
};

const optionFromKey = (key: unknown) => onlineOptions.find((o) => onlineOptionInfo[o].settingKey === key) ?? null;

/** The dine-in Wi-Fi restriction as guests see it (read only here). */
export interface DineInWifi {
  enabled: boolean;
  ssid: string;
  takeaway: boolean;
}

/** The GPS ordering area as guests see it (read only here). */
export interface DineInLocation {
  enabled: boolean;
  radius: number;
  takeaway: boolean;
}

/** Restaurant configuration, edited in Settings. */
export interface RestaurantSettings {
  name: string;
  phone: string;
  email: string;
  address: string;
  /** Tax registration number (e.g. a GSTIN). Printed only when set. */
  taxRegistration: string;
  taxName: string;
  taxRateBasisPoints: number;
  serviceChargeBasisPoints: number;
  /** Restaurant time zone as a fixed offset from UTC, in minutes. */
  utcOffsetMinutes: number;
  allowPartialPayments: boolean;
  onlineOptions: Set<OnlineOption>;
  receiptFooter: string;
  showSoldOutDishes: boolean;
  autoUnavailableWhenOutOfStock: boolean;
  prepBufferMinutes: number;
  takeawayOrdersEnabled: boolean;
  offers: DiscountOffer[];
  currencyCode: string;
  wifi: DineInWifi;
  location: DineInLocation;
}

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
  onlineOptions: new Set(onlineOptions),
  receiptFooter: 'Thank you for dining with us!',
  showSoldOutDishes: true,
  autoUnavailableWhenOutOfStock: true,
  prepBufferMinutes: 5,
  takeawayOrdersEnabled: false,
  offers: [],
  currencyCode: 'INR',
  wifi: { enabled: false, ssid: '', takeaway: false },
  location: { enabled: false, radius: 0, takeaway: false },
};

export function settingsFromJson(json: Json): RestaurantSettings {
  const d = defaultSettings;
  const wifi = json.wifi as Json | undefined | null;
  const location = json.location as Json | undefined | null;
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
    onlineOptions: Array.isArray(json.methods)
      ? new Set(json.methods.map(optionFromKey).filter((o): o is OnlineOption => o != null))
      : new Set(d.onlineOptions),
    receiptFooter: (json.footer as string | undefined) ?? d.receiptFooter,
    showSoldOutDishes: (json.showSoldOut as boolean | undefined) ?? true,
    autoUnavailableWhenOutOfStock: (json.autoUnavailable as boolean | undefined) ?? true,
    prepBufferMinutes: (json.prepBuffer as number | undefined) ?? 5,
    // Servers from before takeaway was renamed from "parcel" send only the old key.
    takeawayOrdersEnabled: (json.takeaway as boolean | undefined) ?? (json.parcel as boolean | undefined) ?? false,
    offers: ((json.offers as Json[] | undefined) ?? []).map(offerFromJson),
    currencyCode: (json.currency as string | undefined) ?? 'INR',
    wifi: wifi ? { enabled: Boolean(wifi.enabled), ssid: (wifi.ssid as string | undefined) ?? '', takeaway: Boolean(wifi.takeaway) } : d.wifi,
    location: location
      ? { enabled: Boolean(location.enabled), radius: (location.radius as number | undefined) ?? 0, takeaway: Boolean(location.takeaway) }
      : d.location,
  };
}

/**
 * The body of `PUT /admin/settings`: RestaurantSettings.toJson without the
 * coupons, the Wi-Fi restriction and the GPS area, which have their own
 * endpoints (a settings save must never undo a change made there).
 */
export function settingsToJson(s: RestaurantSettings): Json {
  return {
    name: s.name,
    phone: s.phone,
    email: s.email,
    address: s.address,
    taxReg: s.taxRegistration,
    taxName: s.taxName,
    taxRate: s.taxRateBasisPoints,
    serviceRate: s.serviceChargeBasisPoints,
    utcOffset: s.utcOffsetMinutes,
    partial: s.allowPartialPayments,
    // In display order, so the server keeps them in that order too.
    methods: onlineOptions.filter((o) => s.onlineOptions.has(o)).map((o) => onlineOptionInfo[o].settingKey),
    footer: s.receiptFooter,
    showSoldOut: s.showSoldOutDishes,
    autoUnavailable: s.autoUnavailableWhenOutOfStock,
    prepBuffer: s.prepBufferMinutes,
    takeaway: s.takeawayOrdersEnabled,
    // Also under its old name, which servers from before the rename read.
    parcel: s.takeawayOrdersEnabled,
    currency: s.currencyCode,
  };
}

export const pricingOf = (s: RestaurantSettings): PricingConfig => ({
  taxRateBasisPoints: s.taxRateBasisPoints,
  taxName: s.taxName,
  serviceChargeBasisPoints: s.serviceChargeBasisPoints,
});

/** The payment methods behind the switched-on options (UPI and QR are both UPI). */
export const onlineMethodsOf = (s: RestaurantSettings) => new Set([...s.onlineOptions].map((o) => onlineOptionInfo[o].method));

/** Returns a message for the first invalid field, or null (SettingsController.validate). */
export function validateSettings(s: RestaurantSettings): string | null {
  const name = s.name.trim();
  if (name.length < 2 || name.length > 60) return 'Restaurant name must be 2 to 60 characters.';
  if (s.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s.email)) return 'Enter a valid email address or leave it empty.';
  if (s.phone && !/^[0-9+()\-\s]{6,20}$/.test(s.phone)) return 'Enter a valid phone number or leave it empty.';
  if (s.address.length > 160) return 'Address can be at most 160 characters.';
  if (s.taxRegistration && !/^[A-Za-z0-9-]{5,20}$/.test(s.taxRegistration)) return 'Tax registration must be 5 to 20 letters or digits.';
  const taxName = s.taxName.trim();
  if (!taxName || taxName.length > 20) return 'Tax name must be 1 to 20 characters.';
  if (s.taxRateBasisPoints < 0 || s.taxRateBasisPoints > 2800) return 'Tax rate must be between 0% and 28%.';
  if (s.serviceChargeBasisPoints < 0 || s.serviceChargeBasisPoints > 2000) return 'Service charge must be between 0% and 20%.';
  if (s.utcOffsetMinutes < -720 || s.utcOffsetMinutes > 840) return 'Choose a valid time zone.';
  if (s.receiptFooter.length > 120) return 'Receipt note can be at most 120 characters.';
  if (s.prepBufferMinutes < 0 || s.prepBufferMinutes > 60) return 'Preparation buffer must be 0 to 60 minutes.';
  if (!lookupCurrency(s.currencyCode)) return 'Choose a supported currency.';
  return null;
}

/** The trimming `SettingsController.updateSettings` applies before saving. */
export function cleanSettings(s: RestaurantSettings): RestaurantSettings {
  return {
    ...s,
    name: s.name.trim(),
    phone: s.phone.trim(),
    email: s.email.trim().toLowerCase(),
    address: s.address.trim(),
    taxRegistration: s.taxRegistration.trim().toUpperCase(),
    taxName: s.taxName.trim(),
    receiptFooter: s.receiptFooter.trim(),
  };
}

/** A dining table. */
export interface RestaurantTable {
  number: number;
  seats: number;
  /** Optional zone, e.g. "Terrace". */
  area: string;
  /** Inactive tables cannot start new orders. */
  isActive: boolean;
}

export const tableFromJson = (json: Json): RestaurantTable => ({
  number: json.number as number,
  seats: (json.seats as number | undefined) ?? 4,
  area: (json.area as string | undefined) ?? '',
  isActive: (json.active as boolean | undefined) ?? true,
});

export const tableToJson = (t: RestaurantTable): Json => ({
  number: t.number,
  seats: t.seats,
  ...(t.area ? { area: t.area } : {}),
  active: t.isActive,
});

export function validateTable(number: number, seats: number): string | null {
  if (number < 1 || number > 999) return 'Table numbers go from 1 to 999.';
  if (seats < 1 || seats > 30) return 'Seats must be between 1 and 30.';
  return null;
}
