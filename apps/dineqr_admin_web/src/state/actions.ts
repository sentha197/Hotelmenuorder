import { useSyncExternalStore } from 'react';
import { CheckoutError } from '@/api/dineqr';
import { newIdempotencyKey } from '@/api/client';
import { MAX_ROLE_TITLE, passwordProblem, PaymentError, permissionsOfRole, Staff, ValidationError, type Permission, type StaffAccount, type StaffRole } from '@/core/access';
import { validateAmount, type Invoice, type PaymentMethodType, type PaymentTransaction } from '@/core/billing';
import { newInventoryId, Stock, validateInventoryItem, type InventoryItem } from '@/core/inventory';
import type { LegalDocumentDraft } from '@/core/legal';
import { uploadProblem, validateCategory, validateItem, type MenuCategory, type MenuItem } from '@/core/menu';
import { Currency, type Paise } from '@/core/money';
import { Coupons, validateCoupon, validatePromotion, type DiscountOffer, type Promotion } from '@/core/offers';
import { Orders, OrderStatuses, TAKEAWAY_TABLE, type OrderStatus, type RestaurantOrder } from '@/core/orders';
import { CartLines, type CartLine, type CartQuote } from '@/core/pricing';
import { cleanNetworkSettings, Geofence, type GeofenceSettings, type NetworkAccessSettings } from '@/core/restrictions';
import { cleanSettings, validateSettings, validateTable, type RestaurantSettings, type RestaurantTable } from '@/core/settings';
import { automaticUnavailableMessage, Upi, type UpiSettings } from '@/core/upi';
import { requireBackend } from '@/services/backend';
import {
  acceptInvoice,
  acceptMenuItem,
  acceptOrder,
  acceptPromotion,
  keys,
  queryClient,
  removePromotion,
  setAudit,
  setInventory,
  setSettings,
  setStaff,
  setTables,
  type StaffMenu,
} from './data';
import { Session } from './session';

const api = () => requireBackend().api;
const need = (p: Permission) => Session.require(p);
const fail = (message: string): never => {
  throw new ValidationError(message);
};

// ------------------------------------------------------------ busy orders

const busyOrders = new Set<string>();
const busyListeners = new Set<() => void>();
let busyVersion = 0;
const touchBusy = () => {
  busyVersion++;
  busyListeners.forEach((l) => l());
};

/** Whether an order is being updated (OrderController.isBusy). */
export function useOrderBusy(orderId: string): boolean {
  useSyncExternalStore(
    (l) => {
      busyListeners.add(l);
      return () => busyListeners.delete(l);
    },
    () => busyVersion,
  );
  return busyOrders.has(orderId);
}

// ------------------------------------------------------------------ orders

/** Moves an order to [target]. Cancelling needs a reason (OrderController.updateStatus). */
export async function updateOrderStatus(order: RestaurantOrder, target: OrderStatus, reason = ''): Promise<RestaurantOrder> {
  need(OrderStatuses.permissionFor(target));
  if (!OrderStatuses.canTransitionTo(order.status, target)) {
    fail(
      `Order ${order.id} is ${OrderStatuses.shortLabel(order.status).toLowerCase()} and cannot be ${
        target === 'cancelled' ? 'cancelled' : `moved to ${OrderStatuses.shortLabel(target).toLowerCase()}`
      }.`,
    );
  }
  const why = reason.trim();
  if (target === 'cancelled' && why.length < 3) fail('Enter a reason for cancelling.');
  if (busyOrders.has(order.id)) fail('This order is already being updated.');
  busyOrders.add(order.id);
  touchBusy();
  try {
    const updated = await api().updateOrderStatus(order.id, target, why);
    acceptOrder(updated);
    if (target === 'cancelled') {
      // The server voided the bill with the cancellation; show its version.
      try {
        acceptInvoice(await api().billForOrder(order.id));
      } catch {
        // The bills list refreshes with the next live update.
      }
    }
    return updated;
  } finally {
    busyOrders.delete(order.id);
    touchBusy();
  }
}

let placing = false;
let pendingSignature: string | null = null;
let pendingKey: string | null = null;

/**
 * Places a staff order (OrderController.placeOrder with OrderSource.staff).
 * Retrying the same order (e.g. after a timeout) reuses its idempotency key,
 * so the server returns the order it may already have created.
 */
export async function placeStaffOrder(args: {
  lines: CartLine[];
  quote: CartQuote;
  tableNumber: number | null;
  instructions: string;
  isTableOrderable: (table: number) => boolean;
}): Promise<RestaurantOrder> {
  need('createOrders');
  if (placing) throw new CheckoutError('Your order is already being placed.');
  const table = args.tableNumber;
  if (table == null) fail('Choose a table first.');
  if (!args.isTableOrderable(table!)) {
    throw new CheckoutError(
      table === TAKEAWAY_TABLE
        ? 'Takeaway orders are not being taken right now. Please ask a staff member.'
        : 'This table is not taking orders right now. Please ask a staff member.',
    );
  }
  if (args.lines.length === 0) throw new CheckoutError('Your cart is empty. Add a dish to place an order.');
  if (args.lines.some((l) => !CartLines.orderable(l))) throw new CheckoutError('Some dishes in your cart are no longer available. Please review your cart.');
  placing = true;
  try {
    const lines = args.lines.map(CartLines.toJson);
    const instructions = args.instructions.trim();
    const signature = JSON.stringify([table, 'staff', lines, null, instructions]);
    if (signature !== pendingSignature) {
      pendingSignature = signature;
      pendingKey = newIdempotencyKey();
    }
    const order = await api().placeOrder({
      lines,
      instructions,
      idempotencyKey: pendingKey!,
      orderType: table === TAKEAWAY_TABLE ? 'takeaway' : 'dineIn',
      tableNumber: table!,
      expectedTotal: args.quote.bill.total,
    });
    pendingSignature = null;
    pendingKey = null;
    acceptOrder(order);
    try {
      acceptInvoice(await api().billForOrder(order.id));
    } catch {
      // The order exists; its bill arrives with the next live update.
    }
    return order;
  } finally {
    placing = false;
  }
}

// ----------------------------------------------------------------- billing

/** Staff record of money taken at the counter (BillingController.recordCounterPayment). */
export async function recordCounterPayment(invoice: Invoice, amount: Paise, method: PaymentMethodType, reference: string, methodDetail: string) {
  need('collectPayments');
  const problem = validateAmount(invoice, amount);
  if (problem) throw new PaymentError(problem);
  const { payment, invoice: updated } = await api().recordCounterPayment(invoice.id, {
    amount,
    method,
    reference: reference.trim(),
    idempotencyKey: newIdempotencyKey(),
    methodDetail,
  });
  acceptInvoice(updated);
  return { payment, invoice: updated };
}

/** Refunds part or all of one successful payment (BillingController.refund). */
export async function refundPayment(invoice: Invoice, payment: PaymentTransaction, amount: Paise, reason: string) {
  need('issueRefunds');
  if (payment.status !== 'succeeded') throw new PaymentError('Choose a successful payment to refund.');
  const why = reason.trim();
  if (why.length < 3) throw new PaymentError('Enter a reason for the refund.');
  const max = invoice.refundableOn(payment.id);
  if (amount <= 0) throw new PaymentError('Enter an amount.');
  if (amount > max) throw new PaymentError(`At most ${Currency.format(max)} can be refunded on this payment.`);
  const { refund, invoice: updated } = await api().refund(payment.id, { amount, reason: why, idempotencyKey: newIdempotencyKey() });
  acceptInvoice(updated);
  if (refund.status === 'failed') throw new PaymentError('The payment provider declined the refund. Nothing was returned.');
  return refund;
}

/** Asks the server for the final status of pending payments on a bill. */
export async function reconcileBill(invoice: Invoice): Promise<number> {
  need('reconcilePayments');
  const { resolved, invoice: updated } = await api().reconcile(invoice.id);
  acceptInvoice(updated);
  return resolved;
}

/** Staff confirm the money reached the restaurant's account: the only way a UPI-direct payment becomes paid. */
export async function verifyUpiPayment(payment: PaymentTransaction, reference: string) {
  need('collectPayments');
  const cleaned = reference.trim();
  if (!cleaned) throw new PaymentError('Enter the UPI transaction ID shown in your bank or UPI app.');
  acceptInvoice((await api().verifyUpiPayment(payment.id, cleaned)).invoice);
}

/** The money did not arrive: the payment fails and the balance is open again. */
export async function rejectUpiPayment(payment: PaymentTransaction, reason: string) {
  need('collectPayments');
  acceptInvoice((await api().rejectUpiPayment(payment.id, reason.trim())).invoice);
}

/** Cancels a UPI payment the guest started but has not claimed. */
export async function cancelUpiPayment(payment: PaymentTransaction) {
  need('collectPayments');
  acceptInvoice((await api().cancelPayment(payment.id)).invoice);
}

// -------------------------------------------------------------------- menu

const menuData = () => queryClient.getQueryData<StaffMenu>(keys.menu) ?? { categories: [], items: [], promotions: [] };

export async function saveMenuItem(item: MenuItem) {
  need('manageMenu');
  const menu = menuData();
  const error = validateItem(item, menu.items, menu.categories);
  if (error) fail(error);
  const saved: MenuItem = {
    ...item,
    name: item.name.trim(),
    shortDescription: item.shortDescription.trim(),
    description: item.description.trim(),
    category: menu.categories.find((c) => c.id === item.category.id) ?? item.category,
  };
  await api().saveItem(saved);
  acceptMenuItem(saved);
}

export async function setDishAvailable(item: MenuItem, available: boolean) {
  need('manageMenu');
  if (item.isAvailable === available) return;
  const saved = { ...item, isAvailable: available };
  await api().saveItem(saved);
  acceptMenuItem(saved);
}

export async function setDishArchived(item: MenuItem, archived: boolean) {
  need('manageMenu');
  if (item.isArchived === archived) return;
  const saved = { ...item, isArchived: archived };
  await api().saveItem(saved);
  acceptMenuItem(saved);
}

/** Saves the full category list, then re-reads the menu (CatalogController._saveCategories). */
async function saveCategories(categories: MenuCategory[]) {
  await api().saveCategories(categories);
  queryClient.setQueryData(keys.menu, await api().menu());
}

export async function saveCategory(category: MenuCategory) {
  need('manageCategories');
  const { categories } = menuData();
  const error = validateCategory(category, categories);
  if (error) fail(error);
  const exists = categories.some((c) => c.id === category.id);
  const saved = { ...category, label: category.label.trim(), sortOrder: exists ? category.sortOrder : categories.length };
  await saveCategories(exists ? categories.map((c) => (c.id === saved.id ? saved : c)) : [...categories, saved]);
}

export async function setCategoryActive(category: MenuCategory, active: boolean) {
  need('manageCategories');
  await saveCategories(menuData().categories.map((c) => (c.id === category.id ? { ...c, isActive: active } : c)));
}

/** Applies a new display order (ids from first to last). */
export async function reorderCategories(orderedIds: string[]) {
  need('manageCategories');
  const byId = new Map(menuData().categories.map((c) => [c.id, c]));
  if (new Set(orderedIds).size !== byId.size || !orderedIds.every((id) => byId.has(id))) fail('The category list changed. Try again.');
  await saveCategories(orderedIds.map((id, index) => ({ ...byId.get(id)!, sortOrder: index })));
}

/** Only empty categories can be deleted; dishes must be moved first. */
export async function deleteCategory(category: MenuCategory) {
  need('manageCategories');
  const { categories, items } = menuData();
  const used = items.filter((i) => i.category.id === category.id).length;
  if (used > 0) fail(`${category.label} still has ${used} ${used === 1 ? 'dish' : 'dishes'} (including archived). Move them to another category first.`);
  await saveCategories(categories.filter((c) => c.id !== category.id).map((c, index) => ({ ...c, sortOrder: index })));
}

export async function uploadDishPhoto(bytes: Uint8Array): Promise<string> {
  need('manageMenu');
  const problem = uploadProblem(bytes, 'photo');
  if (problem) fail(problem);
  return api().uploadDishImage(bytes);
}

export async function uploadOfferPhoto(bytes: Uint8Array): Promise<string> {
  need('manageOffers');
  const problem = uploadProblem(bytes, 'picture');
  if (problem) fail(problem);
  return api().uploadOfferImage(bytes);
}

export async function savePromotion(promotion: Promotion) {
  need('manageOffers');
  const menu = new Map(menuData().items.map((i) => [i.id, i]));
  const error = validatePromotion(promotion, menu);
  if (error) fail(error);
  acceptPromotion(await api().savePromotion({ ...promotion, title: promotion.title.trim(), description: promotion.description.trim() }));
}

export async function setPromotionActive(promotion: Promotion, active: boolean) {
  need('manageOffers');
  if (promotion.isActive === active) return;
  acceptPromotion(await api().setPromotionActive(promotion.id, active));
}

export async function deletePromotion(promotion: Promotion) {
  need('manageOffers');
  await api().deletePromotion(promotion.id);
  removePromotion(promotion.id);
}

// ---------------------------------------------------------------- settings

const currentSettings = () => queryClient.getQueryData<RestaurantSettings>(keys.settings);

/** Validates and saves the settings; shows what is really in force again if the server refuses. */
export async function updateSettings(next: RestaurantSettings) {
  need('manageSettings');
  const trimmed = cleanSettings(next);
  const error = validateSettings(trimmed);
  if (error) fail(error);
  const previous = currentSettings();
  setSettings(() => trimmed);
  try {
    await api().saveSettings(trimmed);
  } catch (e) {
    if (previous) setSettings(() => previous);
    throw e;
  }
}

/** Validates and saves a coupon; [originalCode] is the code being edited. */
export async function saveCoupon(offer: DiscountOffer, originalCode: string | null) {
  need('manageOffers');
  const existing = currentSettings()?.offers ?? [];
  const error = validateCoupon(offer, existing, originalCode);
  if (error) fail(error);
  const normalized: DiscountOffer = { ...offer, code: Coupons.normalize(offer.code), title: offer.title.trim(), usedCount: 0 };
  const saved = await api().saveOffer(normalized, originalCode);
  const key = originalCode ?? normalized.code;
  setSettings((s) => ({ ...s, offers: s.offers.some((o) => o.code === key) ? s.offers.map((o) => (o.code === key ? saved : o)) : [...s.offers, saved] }));
}

export async function setCouponActive(code: string, active: boolean) {
  need('manageOffers');
  const saved = await api().setOfferActive(code, active);
  setSettings((s) => ({ ...s, offers: s.offers.map((o) => (o.code === code ? saved : o)) }));
}

export async function deleteCoupon(code: string) {
  need('manageOffers');
  await api().deleteOffer(code);
  setSettings((s) => ({ ...s, offers: s.offers.filter((o) => o.code !== code) }));
}

const currentTables = () => queryClient.getQueryData<RestaurantTable[]>(keys.tables) ?? [];

async function saveTables(tables: RestaurantTable[]) {
  const previous = currentTables();
  setTables(tables);
  try {
    await api().saveTables([...tables].sort((a, b) => a.number - b.number));
  } catch (e) {
    setTables(previous);
    throw e;
  }
}

export async function addTable(number: number, seats: number, area: string) {
  need('manageTables');
  const error = validateTable(number, seats);
  if (error) fail(error);
  if (currentTables().some((t) => t.number === number)) fail(`Table ${number} already exists.`);
  await saveTables([...currentTables(), { number, seats, area: area.trim(), isActive: true }]);
}

export async function updateTable(updated: RestaurantTable) {
  need('manageTables');
  const error = validateTable(updated.number, updated.seats);
  if (error) fail(error);
  await saveTables(currentTables().map((t) => (t.number === updated.number ? updated : t)));
}

export async function setTableActive(number: number, active: boolean) {
  need('manageTables');
  if (!currentTables().some((t) => t.number === number)) return;
  await saveTables(currentTables().map((t) => (t.number === number ? { ...t, isActive: active } : t)));
}

/** [hasOpenOrders] guards against removing a table guests are using. */
export async function removeTable(number: number, hasOpenOrders: boolean) {
  need('manageTables');
  if (hasOpenOrders) fail(`Table ${number} has open orders or unpaid bills. Close them first.`);
  await saveTables(currentTables().filter((t) => t.number !== number));
}

/** Validates and saves the UPI details (PaymentSettingsController.save). */
export async function savePaymentSettings(next: UpiSettings, automaticAvailable: boolean) {
  need('manageSettings');
  const cleaned = { ...next, upiId: Upi.normalizeId(next.upiId), payeeName: next.payeeName.trim() };
  const problem = Upi.validate(cleaned);
  if (problem) fail(problem);
  if (cleaned.verificationMode === 'automatic' && !automaticAvailable) fail(automaticUnavailableMessage);
  queryClient.setQueryData(keys.paymentSettings, await api().savePaymentSettings(cleaned));
}

export async function uploadUpiQr(bytes: Uint8Array): Promise<string> {
  need('manageSettings');
  if (bytes.length === 0) fail('Choose a QR image to upload.');
  const problem = uploadProblem(bytes, 'image');
  if (problem) fail(problem);
  return api().uploadUpiQr(bytes);
}

export async function saveNetworkAccess(next: Pick<NetworkAccessSettings, 'enabled' | 'ssid' | 'restrictTakeaway' | 'networks'>) {
  need('manageSettings');
  const cleaned = cleanNetworkSettings(next);
  if (cleaned.error !== undefined) return fail(cleaned.error);
  const saved = await api().saveNetworkAccess(cleaned.value);
  queryClient.setQueryData(keys.networkAccess, saved);
  return saved;
}

export async function saveGeofence(next: Pick<GeofenceSettings, 'enabled' | 'latitude' | 'longitude' | 'radius' | 'takeaway'>) {
  need('manageSettings');
  const problem = Geofence.validate(next);
  if (problem) fail(problem);
  const saved = await api().saveGeofence(next);
  queryClient.setQueryData(keys.geofence, saved);
  return saved;
}

// ------------------------------------------------------------------- staff

const currentStaff = () => queryClient.getQueryData<StaffAccount[]>(keys.staff) ?? [];

async function reloadStaff() {
  const staff = await api().staff();
  setStaff([...staff].sort((a, b) => roleOrder(a.role) - roleOrder(b.role)));
}

const roleOrder = (role: StaffRole) => ['owner', 'manager', 'cashier', 'kitchen', 'waiter', 'accountant', 'custom'].indexOf(role);
export const sortStaff = (staff: StaffAccount[]) => [...staff].sort((a, b) => roleOrder(a.role) - roleOrder(b.role));

/** The name a custom role carries (null for any other role). */
function cleanTitle(role: StaffRole, title: string | null): string | null {
  if (role !== 'custom') return null;
  const clean = (title ?? '').trim();
  if (clean.length < 2 || clean.length > MAX_ROLE_TITLE) fail(`Role name must be 2 to ${MAX_ROLE_TITLE} characters.`);
  return clean;
}

export async function addStaff(input: { name: string; email: string; role: StaffRole; roleTitle: string | null; password: string }) {
  need('manageStaff');
  const title = cleanTitle(input.role, input.roleTitle);
  const name = input.name.trim();
  const email = input.email.trim().toLowerCase();
  if (name.length < 2 || name.length > 40) fail('Name must be 2 to 40 characters.');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) fail('Enter a valid email address.');
  if (currentStaff().some((s) => s.email === email)) fail('An account with this email exists.');
  const weak = passwordProblem(input.password);
  if (weak) fail(weak);
  const created = await api().createStaff({ name, email, role: input.role, roleTitle: title, password: input.password });
  await reloadStaff();
  return created;
}

const isLastActiveOwner = (account: StaffAccount) =>
  account.role === 'owner' && account.isActive && currentStaff().filter((s) => s.role === 'owner' && s.isActive).length === 1;

/** Moves someone to [role]; naming a custom role again renames it and keeps their access. */
export async function changeRole(account: StaffAccount, role: StaffRole, roleTitle: string | null) {
  need('manageStaff');
  const title = cleanTitle(role, roleTitle);
  if (account.role === role && account.roleTitle === title) return;
  if (account.id === Session.actor?.id) fail('You cannot change your own role.');
  if (account.role !== role && isLastActiveOwner(account)) fail('Keep at least one active owner.');
  const updated = await api().updateStaff(account.id, { role, roleTitle: title });
  await reloadStaff();
  Session.refreshActor(updated);
}

/** Gives [account] exactly [permissions]; null (or the role's own set) goes back to the role's defaults. */
export async function changeAccess(account: StaffAccount, permissions: Set<Permission> | null) {
  need('manageStaff');
  if (Session.actor?.role !== 'owner') fail('Only an owner can change what someone can access.');
  if (account.id === Session.actor?.id) fail('You cannot change your own access.');
  if (account.role === 'owner') fail('Owners always have full access.');
  const sameSet = (a: Set<Permission>, b: Set<Permission>) => a.size === b.size && [...a].every((p) => b.has(p));
  const custom = permissions == null || sameSet(permissions, permissionsOfRole(account.role)) ? null : permissions;
  if (custom == null ? !Staff.hasCustomAccess(account) : account.customPermissions != null && sameSet(custom, account.customPermissions)) return;
  const updated = await api().setStaffAccess(account.id, custom);
  await reloadStaff();
  Session.refreshActor(updated);
}

export async function setStaffActive(account: StaffAccount, active: boolean) {
  need('manageStaff');
  if (account.isActive === active) return;
  if (account.id === Session.actor?.id) fail('You cannot deactivate yourself.');
  if (!active && isLastActiveOwner(account)) fail('Keep at least one active owner.');
  const updated = await api().updateStaff(account.id, { active });
  await reloadStaff();
  Session.refreshActor(updated);
}

export async function resetStaffPassword(account: StaffAccount, password: string) {
  need('manageStaff');
  const weak = passwordProblem(password);
  if (weak) fail(weak);
  await api().resetStaffPassword(account.id, password);
}

/** Refreshes the activity log (needs viewAuditLog). */
export async function loadAuditEvents() {
  need('viewAuditLog');
  setAudit(await api().audit());
}

// --------------------------------------------------------------- inventory

const currentInventory = () => queryClient.getQueryData<{ items: InventoryItem[] }>(keys.inventory)?.items ?? [];

async function reloadInventory() {
  setInventory(await api().inventory());
}

export const newInventoryItemId = (name: string) => newInventoryId(name, currentInventory());

/** Creates or edits an item's details; an existing item's quantity changes only through adjustments. */
export async function saveInventoryItem(item: InventoryItem) {
  need('manageInventory');
  const error = validateInventoryItem(item, currentInventory());
  if (error) fail(error);
  const existing = currentInventory().some((i) => i.id === item.id);
  const named = { ...item, name: item.name.trim() };
  if (existing) await api().updateInventoryItem(named);
  else await api().createInventoryItem(named);
  await reloadInventory();
}

/** Adds (positive) or removes (negative) stock with a reason. */
export async function adjustStock(item: InventoryItem, change: number, reason: string) {
  need('manageInventory');
  const why = reason.trim();
  if (change === 0) fail('Enter a quantity.');
  if (why.length < 3) fail('Enter a reason.');
  const balance = Number((item.quantity + change).toFixed(3));
  if (balance < 0) fail(`Only ${Stock.format(item.quantity)} ${item.unit} in stock.`);
  await api().adjustStock(item.id, change, why);
  await reloadInventory();
  // The server may have marked linked dishes sold out or available.
  await queryClient.invalidateQueries({ queryKey: keys.menu });
}

// ------------------------------------------------------------------- legal

async function legalChange<T>(action: () => Promise<T>): Promise<T> {
  if (!Session.can('manageSettings')) need('manageSettings');
  const result = await action();
  queryClient.setQueryData(keys.legal, await api().legalVersions());
  return result;
}

export const createLegalVersion = (draft: LegalDocumentDraft) => legalChange(() => api().createLegal(draft));
export const updateLegalVersion = (id: number, draft: LegalDocumentDraft) => legalChange(() => api().updateLegal(id, draft));
export const deleteLegalVersion = (id: number) => legalChange(() => api().deleteLegal(id));
export const publishLegalVersion = (id: number) => legalChange(() => api().publishLegal(id));
export const unpublishLegalVersion = (id: number) => legalChange(() => api().unpublishLegal(id));

/** Has the order open orders or unpaid bills (removing a table)? */
export function tableInUse(table: number, orders: readonly RestaurantOrder[], bills: readonly Invoice[]) {
  return orders.some((o) => o.tableNumber === table && Orders.isActive(o)) || bills.some((b) => b.tableNumber === table && b.outstanding !== 0);
}
