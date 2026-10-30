/**
 * Amounts are integer minor units ("paise"), as on the server and in the
 * Flutter apps, so totals never drift through floating point rounding.
 * Every supported currency has two decimal places.
 */
export type Paise = number;

/** Applies a rate in basis points (500 = 5%), rounding half-up to the paisa. */
export function applyRate(paise: Paise, basisPoints: number): Paise {
  const scaled = paise * basisPoints;
  return scaled >= 0 ? Math.floor((scaled + 5000) / 10000) : -Math.floor((-scaled + 5000) / 10000);
}

export const sum = (values: Iterable<Paise>): Paise => {
  let total = 0;
  for (const value of values) total += value;
  return total;
};

export const rupees = (value: number): Paise => value * 100;

export interface CurrencyInfo {
  code: string;
  symbol: string;
  name: string;
  /** Digit grouping: en-IN writes 1,00,000; en-US writes 100,000. */
  locale: string;
}

export const supportedCurrencies: CurrencyInfo[] = [
  { code: 'INR', symbol: '₹', name: 'Indian Rupee', locale: 'en-IN' },
  { code: 'USD', symbol: '$', name: 'US Dollar', locale: 'en-US' },
  { code: 'EUR', symbol: '€', name: 'Euro', locale: 'en-US' },
  { code: 'GBP', symbol: '£', name: 'British Pound', locale: 'en-GB' },
  { code: 'AED', symbol: 'AED ', name: 'UAE Dirham', locale: 'en-US' },
  { code: 'SGD', symbol: 'S$', name: 'Singapore Dollar', locale: 'en-US' },
];

let current: CurrencyInfo = supportedCurrencies[0]!;
let whole = new Intl.NumberFormat(current.locale, { maximumFractionDigits: 0 });
let fractional = new Intl.NumberFormat(current.locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** The single place where amounts become text, in the restaurant's currency. */
export const Currency = {
  /** Switches every amount shown to [code]. Unknown codes are ignored. */
  configure(code: string): void {
    const found = supportedCurrencies.find((c) => c.code === code);
    if (!found || found === current) return;
    current = found;
    whole = new Intl.NumberFormat(found.locale, { maximumFractionDigits: 0 });
    fractional = new Intl.NumberFormat(found.locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  },
  get code(): string {
    return current.code;
  },
  /** `₹`, for amount fields. */
  get symbol(): string {
    return current.symbol.trim();
  },
  /** `₹180`, `₹1,250` or `₹472.50` (decimals only when there are paise). */
  format(paise: Paise): string {
    const sign = paise < 0 ? '-' : '';
    const abs = Math.abs(paise);
    const text = abs % 100 === 0 ? whole.format(abs / 100) : fractional.format(abs / 100);
    return `${sign}${current.symbol}${text}`;
  },
  /** `+₹40`, for add-on and portion surcharges. */
  formatExtra(paise: Paise): string {
    return `+${Currency.format(paise)}`;
  },
  /** `472.50` or `180`: as typed into a field, without symbol. */
  plain(paise: Paise): string {
    return paise % 100 === 0 ? `${paise / 100}` : (paise / 100).toFixed(2);
  },
  /** A rupees text field to paise, or null when invalid (`250`, `250.5`). */
  parse(text: string): Paise | null {
    const cleaned = text.replaceAll(Currency.symbol, '').replace(/[₹,\s]/g, '');
    if (!cleaned) return null;
    const match = /^(\d{1,7})(?:\.(\d{1,2}))?$/.exec(cleaned);
    if (!match) return null;
    return Number(match[1]) * 100 + Number((match[2] ?? '0').padEnd(2, '0'));
  },
};
