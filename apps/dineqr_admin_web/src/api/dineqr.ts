import type { AxiosInstance } from 'axios';
import { auditFromJson, SessionExpiredError, staffFromApi, ValidationError, type AuditEvent, type Permission, type StaffAccount, type StaffRole, allPermissions } from '@/core/access';
import { Invoice, PaymentTransaction, refundFromJson, type PaymentMethodType, type RefundRecord } from '@/core/billing';
import { inventoryItemFromJson, movementFromJson, type InventoryItem, type StockMovement } from '@/core/inventory';
import { acceptanceFromJson, legalVersionFromJson, type LegalAcceptanceRecord, type LegalDocumentDraft, type LegalDocumentKind, type LegalDocumentVersion } from '@/core/legal';
import { categoryFromJson, categoryToJson, extensionFor, itemFromJson, itemToJson, type MenuCategory, type MenuItem } from '@/core/menu';
import { offerFromJson, offerToJson, promotionFromJson, promotionToJson, type DiscountOffer, type Promotion } from '@/core/offers';
import { orderFromJson, type OrderStatus, type RestaurantOrder } from '@/core/orders';
import { geofenceFromJson, geofenceToJson, networkSettingsFromJson, networkSettingsToJson, type GeofenceSettings, type NetworkAccessSettings } from '@/core/restrictions';
import { settingsFromJson, settingsToJson, tableFromJson, tableToJson, type RestaurantSettings, type RestaurantTable } from '@/core/settings';
import { paymentSettingsFromJson, upiToJson, type PaymentSettingsSnapshot, type UpiSettings } from '@/core/upi';
import { ApiException } from './client';

type Json = Record<string, unknown>;

const enc = encodeURIComponent;
const list = (data: unknown): Json[] => (Array.isArray(data) ? (data as Json[]) : []);

/** How far back staff screens load orders and bills (open ones always load). */
const HISTORY_DAYS = 90;
const historyFrom = () => new Date(Date.now() - HISTORY_DAYS * 86_400_000).toISOString();

/** Staff data the signed-in role may not see loads as [fallback] instead of failing the screen. */
async function visible<T>(call: () => Promise<T>, fallback: T): Promise<T> {
  try {
    return await call();
  } catch (error) {
    if (error instanceof ApiException && (error.isUnauthorized || error.isForbidden)) return fallback;
    throw error;
  }
}

/** A 401 on a change means the session ended (rethrowAsAppError). */
async function guarded<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch (error) {
    if (error instanceof ApiException && error.isUnauthorized) throw new SessionExpiredError();
    throw error;
  }
}

/** The order could not be placed: staff see the server's reason or a known one (CheckoutError). */
export class CheckoutError extends Error {}

const checkoutMessages: Record<string, string> = {
  tableUnavailable: 'This table is not taking orders right now. Please ask a staff member.',
  tableInactive: 'This table is not taking orders right now. Please ask a staff member.',
  takeawayUnavailable: 'Takeaway orders are not being taken right now. Please ask a staff member.',
  parcelUnavailable: 'Takeaway orders are not being taken right now. Please ask a staff member.',
  emptyCart: 'Your cart is empty. Add a dish to place an order.',
  missingTable: 'Scan your table QR code, or the takeaway code at the counter, before placing an order.',
  legalAcceptanceRequired: 'Please accept the Terms & Conditions and Privacy Policy to place your order.',
};

export interface PaymentConfig {
  providerName: string;
  /** A real gateway takes online payments. */
  available: boolean;
  /** Online methods the gateway takes (null: an older server that does not say). */
  methods: Set<PaymentMethodType> | null;
}

export interface StaffOrderRequest {
  lines: Json[];
  instructions: string;
  idempotencyKey: string;
  orderType: 'dineIn' | 'takeaway';
  tableNumber: number;
  expectedTotal: number;
}

/**
 * Every DineQR API call the admin app makes, with the exact paths, methods
 * and bodies of the Flutter app's HTTP repositories (dineqr_core
 * api_repositories.dart). The server authorises each one.
 */
export class DineQrApi {
  constructor(private readonly http: AxiosInstance) {}

  private async get<T = unknown>(path: string, params?: Record<string, string>): Promise<T> {
    return (await this.http.get(path, { params })).data as T;
  }

  private async send<T = unknown>(method: 'post' | 'put' | 'patch' | 'delete', path: string, body?: unknown): Promise<T> {
    const response = method === 'delete' ? await this.http.delete(path) : await this.http[method](path, body);
    return response.data as T;
  }

  /** `multipart/form-data` with the file in field `file`. Never retried (a retry would store a second copy). */
  private async upload(path: string, bytes: Uint8Array, filename: string, missingUrl: string): Promise<string> {
    const form = new FormData();
    form.append('file', new Blob([bytes as BlobPart]), filename);
    const data = (await this.http.post(path, form)).data as Json | null;
    const url = data?.url;
    if (typeof url !== 'string' || !url) throw new ApiException(502, 'badUploadResponse', missingUrl);
    return url;
  }

  // ------------------------------------------------------------------ warm-up

  /** Wakes an idle hosted server while the splash plays; the answer is not kept. */
  async warmUp(): Promise<void> {
    try {
      await this.get('/settings');
    } catch {
      // Nothing waits for it.
    }
  }

  async paymentConfig(): Promise<PaymentConfig> {
    const json = await this.get<Json>('/payments/config');
    // Older servers describe only the provider in use.
    const live = (json.liveAvailable as boolean | undefined) ?? (Boolean(json.available) && json.simulated !== true);
    const methods = Array.isArray(json.liveMethods)
      ? new Set((json.liveMethods as unknown[]).filter((m): m is PaymentMethodType => ['upi', 'card', 'netBanking', 'wallet', 'cash'].includes(m as string)))
      : null;
    return {
      providerName: (json.liveProvider as string | undefined) ?? (json.provider as string | undefined) ?? 'Server',
      available: live,
      methods,
    };
  }

  // --------------------------------------------------------------------- menu

  /** The full menu (archived dishes and inactive categories included) with every offer. */
  async menu(): Promise<{ categories: MenuCategory[]; items: MenuItem[]; promotions: Promotion[] }> {
    const json = await this.get<Json>('/admin/menu');
    const categories = list(json.categories).map(categoryFromJson);
    const byId = new Map(categories.map((c) => [c.id, c]));
    return {
      categories,
      items: list(json.items).map((i) => itemFromJson(i, byId)),
      promotions: list(json.promotions).map(promotionFromJson),
    };
  }

  saveItem(item: MenuItem) {
    return guarded(() => this.send('put', `/admin/menu/items/${enc(item.id)}`, itemToJson(item)));
  }

  saveCategories(categories: MenuCategory[]) {
    return guarded(() => this.send('put', '/admin/menu/categories', categories.map(categoryToJson)));
  }

  async savePromotion(p: Promotion): Promise<Promotion> {
    return guarded(async () => promotionFromJson(await this.send<Json>('put', `/admin/promotions/${enc(p.id)}`, promotionToJson(p))));
  }

  async setPromotionActive(id: string, active: boolean): Promise<Promotion> {
    return guarded(async () => promotionFromJson(await this.send<Json>('patch', `/admin/promotions/${enc(id)}`, { active })));
  }

  deletePromotion(id: string) {
    return guarded(() => this.send('delete', `/admin/promotions/${enc(id)}`));
  }

  uploadDishImage(bytes: Uint8Array) {
    return this.upload('/admin/uploads/dish-images', bytes, `dish.${extensionFor(bytes) ?? 'img'}`, 'The photo was uploaded but the server did not return its address.');
  }

  uploadOfferImage(bytes: Uint8Array) {
    return this.upload('/admin/uploads/offer-images', bytes, `offer.${extensionFor(bytes) ?? 'img'}`, 'The picture was uploaded but the server did not return its address.');
  }

  // ---------------------------------------------------------------- settings

  async settings(): Promise<RestaurantSettings> {
    return settingsFromJson(await this.get<Json>('/admin/settings'));
  }

  saveSettings(settings: RestaurantSettings) {
    return guarded(() => this.send('put', '/admin/settings', settingsToJson(settings)));
  }

  async tables(): Promise<RestaurantTable[]> {
    return list(await this.get('/admin/tables')).map(tableFromJson).sort((a, b) => a.number - b.number);
  }

  saveTables(tables: RestaurantTable[]) {
    return guarded(() => this.send('put', '/admin/tables', tables.map(tableToJson)));
  }

  /** Saves a coupon; [originalCode] is the code being edited (it may be renamed). */
  async saveOffer(offer: DiscountOffer, originalCode: string | null): Promise<DiscountOffer> {
    return guarded(async () => offerFromJson(await this.send<Json>('put', `/admin/offers/${enc(originalCode ?? offer.code)}`, offerToJson(offer))));
  }

  async setOfferActive(code: string, active: boolean): Promise<DiscountOffer> {
    return guarded(async () => offerFromJson(await this.send<Json>('patch', `/admin/offers/${enc(code)}`, { active })));
  }

  deleteOffer(code: string) {
    return guarded(() => this.send('delete', `/admin/offers/${enc(code)}`));
  }

  // ------------------------------------------------- payment settings (UPI)

  async paymentSettings(): Promise<PaymentSettingsSnapshot> {
    try {
      return paymentSettingsFromJson(await this.get<Json>('/admin/payments/settings'));
    } catch (error) {
      if (error instanceof ApiException && error.isNotFound) {
        throw new ValidationError('This server does not support UPI payment settings yet. Deploy the latest DineQR API (and apply its database migration), then try again.');
      }
      if (error instanceof ApiException && error.status >= 500) {
        throw new ValidationError('The server could not load the payment settings. If the API was just updated, apply its "AddUpiPayments" database migration, then try again.');
      }
      throw error;
    }
  }

  async savePaymentSettings(settings: UpiSettings): Promise<PaymentSettingsSnapshot> {
    return guarded(async () => paymentSettingsFromJson(await this.send<Json>('put', '/admin/payments/settings', upiToJson(settings))));
  }

  uploadUpiQr(bytes: Uint8Array) {
    return guarded(() => this.upload('/admin/uploads/upi-qr', bytes, `upi-qr.${extensionFor(bytes) ?? 'img'}`, 'The QR image was uploaded but the server did not return its address.'));
  }

  // ------------------------------------------------ Wi-Fi and GPS restrictions

  async networkAccess(): Promise<NetworkAccessSettings> {
    return guarded(async () => networkSettingsFromJson(await this.get<Json>('/admin/network-access')));
  }

  async saveNetworkAccess(settings: Pick<NetworkAccessSettings, 'enabled' | 'ssid' | 'restrictTakeaway' | 'networks'>): Promise<NetworkAccessSettings> {
    return guarded(async () => networkSettingsFromJson(await this.send<Json>('put', '/admin/network-access', networkSettingsToJson(settings))));
  }

  private async geofenceCall(request: () => Promise<Json>): Promise<GeofenceSettings> {
    return guarded(async () => {
      try {
        return geofenceFromJson(await request());
      } catch (error) {
        if (error instanceof ApiException && error.isNotFound) {
          throw new ValidationError('This server does not support the GPS ordering restriction yet. Deploy the latest DineQR API (and apply its "GeofenceRestriction" database migration), then try again.');
        }
        throw error;
      }
    });
  }

  geofence() {
    return this.geofenceCall(() => this.get<Json>('/admin/geofence'));
  }

  saveGeofence(settings: Pick<GeofenceSettings, 'enabled' | 'latitude' | 'longitude' | 'radius' | 'takeaway'>) {
    return this.geofenceCall(() => this.send<Json>('put', '/admin/geofence', geofenceToJson(settings)));
  }

  // ------------------------------------------------------------------ orders

  async orders(): Promise<RestaurantOrder[]> {
    return visible(async () => list(await this.get('/admin/orders', { from: historyFrom() })).map(orderFromJson), []);
  }

  /** Places a staff order; the server prices it from its own menu and refuses if the total changed. */
  async placeOrder(request: StaffOrderRequest): Promise<RestaurantOrder> {
    try {
      return orderFromJson(await this.send<Json>('post', '/admin/orders', request));
    } catch (error) {
      if (!(error instanceof ApiException)) throw new CheckoutError('We could not place your order. Please try again.');
      if (error.isUnauthorized) throw new SessionExpiredError();
      const known = checkoutMessages[error.code];
      if (known) throw new CheckoutError(known);
      if (error.code === 'itemsUnavailable' || error.code === 'invalidOptions') {
        throw new CheckoutError(error.isOffline || error.status >= 500 ? 'Some dishes in your cart are no longer available. Please review your cart.' : error.message);
      }
      if (error.code === 'offerUnavailable') {
        throw new CheckoutError(error.isOffline || error.status >= 500 ? 'An offer in your cart is no longer available. Please review your cart.' : error.message);
      }
      throw new CheckoutError(error.isOffline || error.status >= 500 ? 'We could not place your order. Please try again.' : error.message);
    }
  }

  async updateOrderStatus(orderId: string, target: OrderStatus, reason = ''): Promise<RestaurantOrder> {
    return guarded(async () => orderFromJson(await this.send<Json>('post', `/admin/orders/${enc(orderId)}/status`, { target, ...(reason ? { reason } : {}) })));
  }

  // ------------------------------------------------------------------- bills

  async bills(): Promise<Invoice[]> {
    return visible(async () => list(await this.get('/admin/bills', { from: historyFrom() })).map(Invoice.fromJson), []);
  }

  async billForOrder(orderId: string): Promise<Invoice> {
    return guarded(async () => Invoice.fromJson(await this.get<Json>(`/orders/${enc(orderId)}/bill`)));
  }

  private static paymentResult(json: Json): { payment: PaymentTransaction; invoice: Invoice } {
    return { payment: PaymentTransaction.fromJson(json.payment as Json), invoice: Invoice.fromJson(json.invoice as Json) };
  }

  /** The current status of a payment (pending ones are re-checked by the server). */
  async refreshPayment(paymentId: string) {
    return guarded(async () => DineQrApi.paymentResult(await this.get<Json>(`/payments/${enc(paymentId)}`)));
  }

  async recordCounterPayment(invoiceId: string, body: { amount: number; method: PaymentMethodType; reference: string; idempotencyKey: string; methodDetail: string }) {
    return guarded(async () =>
      DineQrApi.paymentResult(
        await this.send<Json>('post', `/admin/bills/${enc(invoiceId)}/payments`, {
          amount: body.amount,
          method: body.method,
          reference: body.reference,
          idempotencyKey: body.idempotencyKey,
          ...(body.methodDetail ? { methodDetail: body.methodDetail } : {}),
        }),
      ),
    );
  }

  async refund(paymentId: string, body: { amount: number; reason: string; idempotencyKey: string }): Promise<{ refund: RefundRecord; invoice: Invoice }> {
    return guarded(async () => {
      const json = await this.send<Json>('post', `/admin/payments/${enc(paymentId)}/refunds`, body);
      return { refund: refundFromJson(json.refund as Json), invoice: Invoice.fromJson(json.invoice as Json) };
    });
  }

  async reconcile(invoiceId: string): Promise<{ resolved: number; invoice: Invoice }> {
    return guarded(async () => {
      const json = await this.send<Json>('post', `/admin/bills/${enc(invoiceId)}/reconcile`);
      return { resolved: json.resolved as number, invoice: Invoice.fromJson(json.invoice as Json) };
    });
  }

  verifyUpiPayment(paymentId: string, reference: string) {
    return guarded(async () => DineQrApi.paymentResult(await this.send<Json>('post', `/admin/payments/${enc(paymentId)}/verify`, { reference })));
  }

  rejectUpiPayment(paymentId: string, reason: string) {
    return guarded(async () => DineQrApi.paymentResult(await this.send<Json>('post', `/admin/payments/${enc(paymentId)}/reject`, reason ? { reason } : {})));
  }

  cancelPayment(paymentId: string) {
    return guarded(async () => DineQrApi.paymentResult(await this.send<Json>('post', `/payments/${enc(paymentId)}/cancel`)));
  }

  // ------------------------------------------------------------------- staff

  async staff(): Promise<StaffAccount[]> {
    return visible(async () => list(await this.get('/admin/staff')).map(staffFromApi), []);
  }

  async audit(): Promise<AuditEvent[]> {
    return visible(async () => list(await this.get('/admin/audit', { limit: '500' })).map(auditFromJson), []);
  }

  async createStaff(body: { name: string; email: string; role: StaffRole; roleTitle: string | null; password: string }): Promise<StaffAccount> {
    return guarded(async () =>
      staffFromApi(
        await this.send<Json>('post', '/admin/staff', {
          name: body.name,
          email: body.email,
          role: body.role,
          ...(body.roleTitle != null ? { roleTitle: body.roleTitle } : {}),
          password: body.password,
        }),
      ),
    );
  }

  async updateStaff(id: string, changes: { name?: string; role?: StaffRole; roleTitle?: string | null; active?: boolean }): Promise<StaffAccount> {
    return guarded(async () =>
      staffFromApi(
        await this.send<Json>('patch', `/admin/staff/${enc(id)}`, {
          ...(changes.name != null ? { name: changes.name } : {}),
          ...(changes.role != null ? { role: changes.role } : {}),
          ...(changes.roleTitle != null ? { roleTitle: changes.roleTitle } : {}),
          ...(changes.active != null ? { active: changes.active } : {}),
        }),
      ),
    );
  }

  /** Replaces what the person's role allows; null goes back to the role's defaults. */
  async setStaffAccess(id: string, permissions: Set<Permission> | null): Promise<StaffAccount> {
    return guarded(async () =>
      staffFromApi(
        await this.send<Json>('put', `/admin/staff/${enc(id)}/access`, {
          permissions: permissions == null ? null : allPermissions.filter((p) => permissions.has(p)),
        }),
      ),
    );
  }

  resetStaffPassword(id: string, password: string) {
    return guarded(() => this.send('post', `/admin/staff/${enc(id)}/password`, { password }));
  }

  // --------------------------------------------------------------- inventory

  async inventory(): Promise<{ items: InventoryItem[]; movements: StockMovement[] }> {
    const json = await visible(async () => this.get<Json>('/admin/inventory'), { items: [], movements: [] } as Json);
    return {
      items: list(json.items).map(inventoryItemFromJson).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)),
      movements: list(json.movements).map(movementFromJson),
    };
  }

  private static inventoryBody(item: InventoryItem, initial?: number): Json {
    return {
      name: item.name,
      unit: item.unit,
      reorder: item.reorderLevel,
      supplier: item.supplier,
      dishes: item.linkedDishIds,
      ...(initial != null ? { initialQuantity: initial } : {}),
    };
  }

  async createInventoryItem(item: InventoryItem): Promise<InventoryItem> {
    return guarded(async () => inventoryItemFromJson(await this.send<Json>('post', '/admin/inventory', DineQrApi.inventoryBody(item, item.quantity))));
  }

  async updateInventoryItem(item: InventoryItem): Promise<InventoryItem> {
    return guarded(async () => inventoryItemFromJson(await this.send<Json>('put', `/admin/inventory/${enc(item.id)}`, DineQrApi.inventoryBody(item))));
  }

  async adjustStock(itemId: string, change: number, reason: string): Promise<InventoryItem> {
    return guarded(async () => inventoryItemFromJson(await this.send<Json>('post', `/admin/inventory/${enc(itemId)}/adjustments`, { change, reason })));
  }

  // ------------------------------------------------------------------- legal

  private async legalCall<T>(call: () => Promise<T>): Promise<T> {
    return guarded(async () => {
      try {
        return await call();
      } catch (error) {
        if (error instanceof ApiException && error.isNotFound && error.code !== 'notFound') {
          throw new ValidationError('This server does not support Terms & Conditions yet. Deploy the latest DineQR API (and apply its "LegalDocuments" database migration), then try again.');
        }
        throw error;
      }
    });
  }

  private static version(json: Json): LegalDocumentVersion {
    const version = legalVersionFromJson(json);
    if (!version) throw new ApiException(502, 'badResponse', 'The server sent a document of an unknown kind.');
    return version;
  }

  legalVersions(): Promise<LegalDocumentVersion[]> {
    return this.legalCall(async () => list(await this.get('/admin/legal/documents')).map(legalVersionFromJson).filter((v): v is LegalDocumentVersion => v != null));
  }

  private static draftJson(d: LegalDocumentDraft): Json {
    return { kind: d.kind, title: d.title, body: d.body, changeSummary: d.changeSummary, requiresReacceptance: d.requiresReacceptance };
  }

  createLegal(draft: LegalDocumentDraft) {
    return this.legalCall(async () => DineQrApi.version(await this.send<Json>('post', '/admin/legal/documents', DineQrApi.draftJson(draft))));
  }

  updateLegal(id: number, draft: LegalDocumentDraft) {
    return this.legalCall(async () => DineQrApi.version(await this.send<Json>('put', `/admin/legal/documents/${id}`, DineQrApi.draftJson(draft))));
  }

  deleteLegal(id: number) {
    return this.legalCall(() => this.send('delete', `/admin/legal/documents/${id}`));
  }

  publishLegal(id: number) {
    return this.legalCall(async () => DineQrApi.version(await this.send<Json>('post', `/admin/legal/documents/${id}/publish`, {})));
  }

  unpublishLegal(id: number) {
    return this.legalCall(async () => DineQrApi.version(await this.send<Json>('post', `/admin/legal/documents/${id}/unpublish`, {})));
  }

  legalAcceptances(filter: { kind?: LegalDocumentKind | null; version?: number | null; customerId?: string | null; limit?: number } = {}): Promise<LegalAcceptanceRecord[]> {
    const params: Record<string, string> = { limit: String(filter.limit ?? 300) };
    if (filter.kind) params.kind = filter.kind;
    if (filter.version != null) params.version = String(filter.version);
    if (filter.customerId) params.customer = filter.customerId;
    return this.legalCall(async () => list(await this.get('/admin/legal/acceptances', params)).map(acceptanceFromJson).filter((r): r is LegalAcceptanceRecord => r != null));
  }
}
