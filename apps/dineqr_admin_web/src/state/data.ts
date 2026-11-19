import { QueryClient, useQuery } from '@tanstack/react-query';
import { ApiException } from '@/api/client';
import type { LivePatcher } from '@/api/realtime';
import type { AuditEvent, StaffAccount } from '@/core/access';
import type { Invoice } from '@/core/billing';
import type { InventoryItem, StockMovement } from '@/core/inventory';
import type { LegalDocumentVersion } from '@/core/legal';
import type { MenuCategory, MenuItem } from '@/core/menu';
import { Currency } from '@/core/money';
import type { Promotion } from '@/core/offers';
import type { RestaurantOrder } from '@/core/orders';
import type { GeofenceSettings, NetworkAccessSettings } from '@/core/restrictions';
import { defaultSettings, type RestaurantSettings, type RestaurantTable } from '@/core/settings';
import { RestaurantTime } from '@/core/time';
import { requireBackend } from '@/services/backend';
import { useAccess } from './session';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Live updates (and a 30 s poll while they are down) keep data current.
      staleTime: 60_000,
      gcTime: 30 * 60_000,
      refetchOnWindowFocus: false,
      // GETs are already retried once by the API client.
      retry: (count, error) => count < 1 && !(error instanceof ApiException && error.status >= 400 && error.status < 500),
    },
  },
});

export const keys = {
  settings: ['settings'] as const,
  tables: ['tables'] as const,
  menu: ['menu'] as const,
  orders: ['orders'] as const,
  bills: ['bills'] as const,
  staff: ['staff'] as const,
  audit: ['audit'] as const,
  inventory: ['inventory'] as const,
  networkAccess: ['networkAccess'] as const,
  geofence: ['geofence'] as const,
  legal: ['legal'] as const,
  legalHistory: (filter: unknown) => ['legal', 'history', filter] as const,
};

export interface StaffMenu {
  categories: MenuCategory[];
  items: MenuItem[];
  promotions: Promotion[];
}

/** Time zone and currency are read everywhere through static helpers. */
function applyGlobals(settings: RestaurantSettings) {
  RestaurantTime.configure(settings.utcOffsetMinutes);
  Currency.configure(settings.currencyCode);
}

const api = () => requireBackend().api;

// ------------------------------------------------------------------ queries

export function useSettings() {
  const { actor } = useAccess();
  const query = useQuery({
    queryKey: keys.settings,
    enabled: actor != null,
    queryFn: async () => {
      const settings = await api().settings();
      applyGlobals(settings);
      return settings;
    },
  });
  return { ...query, settings: query.data ?? defaultSettings };
}

export function useTables() {
  const { actor } = useAccess();
  return useQuery({ queryKey: keys.tables, enabled: actor != null, queryFn: () => api().tables() });
}

export function useMenu() {
  const { actor } = useAccess();
  return useQuery<StaffMenu>({ queryKey: keys.menu, enabled: actor != null, queryFn: () => api().menu() });
}

export function useOrders() {
  const { actor } = useAccess();
  return useQuery({ queryKey: keys.orders, enabled: actor != null, queryFn: () => api().orders() });
}

/** Bills, newest first. Guests pay at the billing counter; staff record it on the bill. */
export function useBills() {
  const { actor } = useAccess();
  return useQuery({
    queryKey: keys.bills,
    enabled: actor != null,
    queryFn: async () => sortBills(await api().bills()),
  });
}

/** Bills by order id, built once per bills list (not a scan per card). */
const billsByOrder = new WeakMap<Invoice[], Map<string, Invoice>>();

/** The bill of [orderId], if loaded. */
export function useBillForOrder(orderId: string): Invoice | undefined {
  const bills = useBills().data;
  if (!bills) return undefined;
  let index = billsByOrder.get(bills);
  if (!index) {
    index = new Map(bills.map((i) => [i.orderId, i]));
    billsByOrder.set(bills, index);
  }
  return index.get(orderId);
}

export function useStaff() {
  const { can } = useAccess();
  return useQuery({ queryKey: keys.staff, enabled: can('manageStaff'), queryFn: () => api().staff() });
}

export function useAudit(enabled = true) {
  const { can } = useAccess();
  return useQuery({ queryKey: keys.audit, enabled: enabled && can('viewAuditLog'), queryFn: () => api().audit() });
}

export function useInventory() {
  const { can } = useAccess();
  return useQuery({ queryKey: keys.inventory, enabled: can('manageInventory'), queryFn: () => api().inventory() });
}

export function useNetworkAccess() {
  const { can } = useAccess();
  return useQuery<NetworkAccessSettings>({ queryKey: keys.networkAccess, enabled: can('manageSettings'), queryFn: () => api().networkAccess(), retry: false });
}

export function useGeofence() {
  const { can } = useAccess();
  return useQuery<GeofenceSettings>({ queryKey: keys.geofence, enabled: can('manageSettings'), queryFn: () => api().geofence(), retry: false });
}

export function useLegalVersions() {
  const { can } = useAccess();
  return useQuery<LegalDocumentVersion[]>({
    queryKey: keys.legal,
    enabled: can('manageSettings') || can('viewAuditLog'),
    queryFn: () => api().legalVersions(),
    retry: false,
  });
}

// ------------------------------------------------------------ cache helpers

export const sortBills = (bills: Invoice[]) => [...bills].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

/** Puts the server's version of a bill in the list (BillingController._accept). */
export function acceptInvoice(invoice: Invoice) {
  queryClient.setQueryData<Invoice[]>(keys.bills, (bills = []) => {
    const exists = bills.some((i) => i.id === invoice.id);
    return sortBills(exists ? bills.map((i) => (i.id === invoice.id ? invoice : i)) : [invoice, ...bills]);
  });
}

export function acceptOrder(order: RestaurantOrder) {
  queryClient.setQueryData<RestaurantOrder[]>(keys.orders, (orders = []) =>
    orders.some((o) => o.id === order.id) ? orders.map((o) => (o.id === order.id ? order : o)) : [order, ...orders],
  );
}

export function acceptMenuItem(item: MenuItem) {
  queryClient.setQueryData<StaffMenu>(keys.menu, (menu) =>
    menu ? { ...menu, items: menu.items.some((i) => i.id === item.id) ? menu.items.map((i) => (i.id === item.id ? item : i)) : [...menu.items, item] } : menu,
  );
}

export function acceptPromotion(promotion: Promotion) {
  queryClient.setQueryData<StaffMenu>(keys.menu, (menu) =>
    menu
      ? {
          ...menu,
          promotions: menu.promotions.some((p) => p.id === promotion.id) ? menu.promotions.map((p) => (p.id === promotion.id ? promotion : p)) : [...menu.promotions, promotion],
        }
      : menu,
  );
}

export function removePromotion(id: string) {
  queryClient.setQueryData<StaffMenu>(keys.menu, (menu) => (menu ? { ...menu, promotions: menu.promotions.filter((p) => p.id !== id) } : menu));
}

export function setSettings(updater: (s: RestaurantSettings) => RestaurantSettings) {
  queryClient.setQueryData<RestaurantSettings>(keys.settings, (s) => {
    const next = updater(s ?? defaultSettings);
    applyGlobals(next);
    return next;
  });
}

export function setTables(tables: RestaurantTable[]) {
  queryClient.setQueryData<RestaurantTable[]>(keys.tables, [...tables].sort((a, b) => a.number - b.number));
}

export function setStaff(staff: StaffAccount[]) {
  queryClient.setQueryData<StaffAccount[]>(keys.staff, staff);
}

export function setInventory(data: { items: InventoryItem[]; movements: StockMovement[] }) {
  queryClient.setQueryData(keys.inventory, data);
}

export function setAudit(events: AuditEvent[]) {
  queryClient.setQueryData(keys.audit, events);
}

/**
 * Single-record updates for `orders` and `bills` events: the event names the
 * order or bill, so only that one is re-read and merged into the cached list
 * instead of re-downloading every order or bill of the last 90 days. Only for
 * lists already loaded; anything unusable falls back to a full re-read.
 */
export const livePatchers: Record<string, LivePatcher> = {
  orders: async (payload) => {
    const id = (payload as { orderId?: unknown } | null)?.orderId;
    if (typeof id !== 'string' || !queryClient.getQueryData(keys.orders)) return false;
    acceptOrder(await api().order(id));
    return true;
  },
  bills: async (payload) => {
    const id = (payload as { invoiceId?: unknown } | null)?.invoiceId;
    if (typeof id !== 'string' || !queryClient.getQueryData(keys.bills)) return false;
    acceptInvoice(await api().bill(id));
    return true;
  },
};

/** What each live-update event re-reads (AdminDependencies' LiveUpdates handlers). */
export const liveHandlers: Record<string, () => Promise<unknown>> = {
  orders: () => queryClient.invalidateQueries({ queryKey: keys.orders }),
  bills: () => queryClient.invalidateQueries({ queryKey: keys.bills }),
  menu: () => queryClient.invalidateQueries({ queryKey: keys.menu }),
  settings: () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: keys.settings }),
      queryClient.invalidateQueries({ queryKey: keys.networkAccess }),
      queryClient.invalidateQueries({ queryKey: keys.geofence }),
      queryClient.invalidateQueries({ queryKey: keys.legal }),
    ]),
  tables: () => Promise.all([queryClient.invalidateQueries({ queryKey: keys.settings }), queryClient.invalidateQueries({ queryKey: keys.tables })]),
  inventory: () => queryClient.invalidateQueries({ queryKey: keys.inventory }),
  staff: () => queryClient.invalidateQueries({ queryKey: keys.staff }),
};
