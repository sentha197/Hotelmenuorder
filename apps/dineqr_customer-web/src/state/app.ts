import { createContext, useContext } from 'react';
import { offerByCode } from '../core/settings';
import type { ApiConfig } from '../config';
import { ApiClient } from '../services/api';
import { GuestSession } from '../services/guestSession';
import { LegalService } from '../services/legalService';
import { BrowserLocationProvider, LocationService, type LocationProvider } from '../services/locationService';
import { MenuService } from '../services/menuService';
import { OrderService } from '../services/orderService';
import { PaymentService } from '../services/paymentService';
import { LiveUpdates, RealtimeClient } from '../services/realtime';
import { RestaurantService } from '../services/restaurantService';
import { BrowserStore, type KeyValueStore } from '../services/storage';
import { BillingStore } from './billingStore';
import { CartStore } from './cartStore';
import { CatalogStore } from './catalogStore';
import { LegalStore } from './legalStore';
import { LocationStore } from './locationStore';
import { OrderStore } from './orderStore';
import { SessionStore } from './sessionStore';
import { SettingsStore } from './settingsStore';
import { ToastStore } from './toastStore';

/** Everything the screens use, wired once (like the Flutter app's dependencies). */
export interface AppServices {
  api: ApiClient;
  guest: GuestSession;
  settings: SettingsStore;
  catalog: CatalogStore;
  cart: CartStore;
  orders: OrderStore;
  billing: BillingStore;
  session: SessionStore;
  /** Terms & Conditions, Privacy Policy and the guest's acceptances. */
  legal: LegalStore;
  /** The GPS ordering area: whether the guest is within it. */
  location: LocationStore;
  toasts: ToastStore;
  realtime: RealtimeClient;
  live: LiveUpdates;
  /** The guest session's orders, bills and UPI payee. */
  loadGuestRecords(): Promise<void>;
}

export function createApp(
  config: ApiConfig,
  options: {
    storage?: KeyValueStore;
    fetchImpl?: typeof fetch;
    startNetwork?: boolean;
    /** The device's location (the browser's by default). */
    locationProvider?: LocationProvider;
  } = {},
): AppServices {
  const storage = options.storage ?? new BrowserStore();
  const api = new ApiClient(config, options.fetchImpl);
  const guest = new GuestSession(api, storage);
  const settings = new SettingsStore(new RestaurantService(api));
  const catalog = new CatalogStore(new MenuService(api), storage, () => settings.settings.showSoldOutDishes);
  const cart = new CartStore(
    storage,
    () => settings.pricing,
    (code) => offerByCode(settings.settings, code),
    // Special offers come with the menu; the server applies them to orders.
    () => catalog.specials,
  );
  const billing = new BillingStore(new PaymentService(api), () => settings.settings, () => settings.payments);
  const orders = new OrderStore(new OrderService(api), settings.isOrderable, (order) => billing.createForOrder(order));
  const realtime = new RealtimeClient(api.hubUrl, () => guest.currentToken());
  const legal = new LegalStore(new LegalService(api));

  settings.subscribe(() => {
    cart.pricingChanged();
    catalog.visibilityChanged();
    billing.settingsChanged();
  });
  // Restore the saved cart once the menu is known, and keep it in step with
  // menu changes (new prices, sold-out or removed dishes).
  catalog.subscribe(() => {
    if (catalog.state !== 'ready') return;
    cart.hydrate(catalog.allItems);
    cart.syncWithMenu(catalog.allItems);
    // New or ended special offers change the totals.
    cart.pricingChanged();
  });

  const loadGuestRecords = async () => {
    // A failure leaves the lists as they are; live updates load them again.
    await Promise.allSettled([orders.load(), billing.load(), billing.loadUpiSettings()]);
  };

  // Orders and bills belong to a guest session; without one the server can
  // only refuse them, so polling skips them.
  const inSession = (load: () => Promise<void>) => () => (guest.isActive ? load() : Promise.resolve());
  const live = new LiveUpdates(realtime, {
    orders: inSession(() => orders.load()),
    bills: inSession(() => billing.load()),
    menu: () => catalog.refresh(),
    // Also sent when staff publish or withdraw a document version.
    settings: async () => {
      await Promise.all([settings.load(), inSession(() => billing.loadUpiSettings())(), legal.documentsChanged()]);
    },
    tables: () => settings.load(),
  });

  // Declared before the session so its start can re-check the area.
  let location: LocationStore | null = null;
  const session = new SessionStore(storage, guest, async () => {
    // A new table's session has its own acceptances.
    legal.sessionChanged();
    location?.contextChanged();
    void realtime.start();
    await loadGuestRecords();
  });

  // The GPS ordering area: independent of the restaurant Wi-Fi check (the
  // server runs both on every order).
  location = new LocationStore(
    new LocationService(api),
    options.locationProvider ?? new BrowserLocationProvider(),
    () => settings.settings.location,
    () => (guest.isActive ? session.tableNumber : null),
  );
  const area = location;
  settings.subscribe(() => area.contextChanged());
  if (typeof document !== 'undefined') {
    // Coming back to the tab (the guest may have moved).
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && area.isRequired) void area.verify();
    });
  }

  if (options.startNetwork !== false) {
    // The scanner checks codes against these; nothing waits for them.
    settings.load().catch(() => undefined);
    void settings.loadPaymentConfig();
    void catalog.load();
    if (guest.isActive) {
      // A session from an earlier visit: its own orders and bills.
      void realtime.start();
      void loadGuestRecords();
    }
  }

  return {
    api,
    guest,
    settings,
    catalog,
    cart,
    orders,
    billing,
    session,
    legal,
    location: area,
    toasts: new ToastStore(),
    realtime,
    live,
    loadGuestRecords,
  };
}

export const AppContext = createContext<AppServices | null>(null);

export function useApp(): AppServices {
  const app = useContext(AppContext);
  if (!app) throw new Error('useApp outside <AppContext>');
  return app;
}
