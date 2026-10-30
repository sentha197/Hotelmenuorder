import { createContext, useContext } from 'react';
import { offerByCode } from '../core/settings';
import type { ApiConfig } from '../config';
import { ApiClient } from '../services/api';
import { GuestSession } from '../services/guestSession';
import { MenuService } from '../services/menuService';
import { OrderService } from '../services/orderService';
import { PaymentService } from '../services/paymentService';
import { LiveUpdates, RealtimeClient } from '../services/realtime';
import { RestaurantService } from '../services/restaurantService';
import { BrowserStore, type KeyValueStore } from '../services/storage';
import { BillingStore } from './billingStore';
import { CartStore } from './cartStore';
import { CatalogStore } from './catalogStore';
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
  toasts: ToastStore;
  realtime: RealtimeClient;
  live: LiveUpdates;
  /** The guest session's orders, bills and UPI payee. */
  loadGuestRecords(): Promise<void>;
}

export function createApp(
  config: ApiConfig,
  options: { storage?: KeyValueStore; fetchImpl?: typeof fetch; startNetwork?: boolean } = {},
): AppServices {
  const storage = options.storage ?? new BrowserStore();
  const api = new ApiClient(config, options.fetchImpl);
  const guest = new GuestSession(api, storage);
  const settings = new SettingsStore(new RestaurantService(api));
  const catalog = new CatalogStore(new MenuService(api), storage, () => settings.settings.showSoldOutDishes);
  const cart = new CartStore(storage, () => settings.pricing, (code) => offerByCode(settings.settings, code));
  const billing = new BillingStore(new PaymentService(api), () => settings.settings, () => settings.payments);
  const orders = new OrderStore(new OrderService(api), settings.isOrderable, (order) => billing.createForOrder(order));
  const realtime = new RealtimeClient(api.hubUrl, () => guest.currentToken());

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
    settings: async () => {
      await Promise.all([settings.load(), inSession(() => billing.loadUpiSettings())()]);
    },
    tables: () => settings.load(),
  });

  const session = new SessionStore(storage, guest, async () => {
    void realtime.start();
    await loadGuestRecords();
  });

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
