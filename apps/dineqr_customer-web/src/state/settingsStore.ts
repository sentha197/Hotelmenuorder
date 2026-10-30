import { Currency } from '../core/money';
import { defaultSettings, isOrderable, pricingOf, type RestaurantSettings, type RestaurantTable } from '../core/settings';
import { RestaurantTime } from '../core/time';
import { unavailablePaymentConfig, type PaymentConfig, type RestaurantService } from '../services/restaurantService';
import { Store } from './store';

export type LoadState = 'idle' | 'loading' | 'ready' | 'error';

/** Restaurant settings and tables, which every QR code is checked against. */
export class SettingsStore extends Store {
  settings: RestaurantSettings = defaultSettings;
  tables: RestaurantTable[] = [];
  state: LoadState = 'idle';
  error: unknown = null;
  payments: PaymentConfig = unavailablePaymentConfig;
  paymentsLoaded = false;

  private pending: Promise<void> | null = null;
  private paymentPending: Promise<void> | null = null;

  constructor(private readonly service: RestaurantService) {
    super();
  }

  get pricing() {
    return pricingOf(this.settings);
  }

  /** Settings and tables side by side; concurrent callers share a request. */
  load(): Promise<void> {
    return (this.pending ??= (async () => {
      if (this.state !== 'ready') {
        this.state = 'loading';
        this.notify();
      }
      try {
        const [settings, tables] = await Promise.all([this.service.settings(), this.service.tables()]);
        this.settings = settings;
        this.tables = tables;
        this.state = 'ready';
        this.error = null;
        // Time zone and currency are read everywhere through static helpers.
        RestaurantTime.configure(settings.utcOffsetMinutes);
        Currency.configure(settings.currencyCode);
      } catch (error) {
        // A refresh failure keeps the settings already shown.
        if (this.state !== 'ready') this.state = 'error';
        this.error = error;
        throw error;
      } finally {
        this.pending = null;
        this.notify();
      }
    })());
  }

  /** The live gateway. A failed read leaves it "not available". */
  loadPaymentConfig(): Promise<void> {
    return (this.paymentPending ??= (async () => {
      try {
        this.payments = await this.service.paymentConfig();
      } catch {
        // Demo and counter payments still work.
      } finally {
        this.paymentsLoaded = true;
        this.paymentPending = null;
        this.notify();
      }
    })());
  }

  isKnownTable = (table: number): boolean => this.tables.some((t) => t.number === table);

  isOrderable = (table: number): boolean => isOrderable(this.settings, this.tables, table);
}
