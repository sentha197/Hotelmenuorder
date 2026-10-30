import { LEGACY_TAKEAWAY_PAYLOAD } from './restaurantService';
import { ApiException, type ApiClient } from './api';
import { StorageKeys, type KeyValueStore } from './storage';
import { TAKEAWAY_PAYLOAD } from '../core/qr';

interface GuestSessionResponse {
  guestToken: string;
  tableNumber: number;
  expiresAt: string;
}

/**
 * The guest's table session on the server: the scanned code is exchanged
 * for a token scoped to that table (it grants no staff access). Like the
 * Flutter app, the token stays on this device until it expires, so the
 * guest's orders and bills are still reachable after closing the tab.
 */
export class GuestSession {
  private token: string | null = null;
  private tableNumber: number | null = null;
  private expires: Date | null = null;

  constructor(
    private readonly api: ApiClient,
    private readonly store: KeyValueStore,
    private readonly clock: () => Date = () => new Date(),
  ) {
    this.restore();
    api.token = () => this.currentToken();
  }

  get isActive(): boolean {
    return this.token != null && this.expires != null && this.clock() < this.expires;
  }

  get table(): number | null {
    return this.isActive ? this.tableNumber : null;
  }

  currentToken(): string | null {
    return this.isActive ? this.token : null;
  }

  /**
   * Validates [qrPayload] with the server and starts (or keeps) the session:
   * presenting the current token for the same table keeps the same session,
   * so earlier orders stay visible. Throws [ApiException].
   */
  async start(qrPayload: string): Promise<number> {
    let json: GuestSessionResponse;
    try {
      json = await this.api.post<GuestSessionResponse>('/guest/sessions', { qrPayload });
    } catch (error) {
      // A server from before takeaway was renamed knows only its old code.
      if (!(error instanceof ApiException) || error.code !== 'unrecognized' || qrPayload !== TAKEAWAY_PAYLOAD) throw error;
      json = await this.api.post<GuestSessionResponse>('/guest/sessions', { qrPayload: LEGACY_TAKEAWAY_PAYLOAD });
    }
    this.token = json.guestToken;
    this.tableNumber = json.tableNumber;
    this.expires = new Date(json.expiresAt);
    this.store.write(
      StorageKeys.guestSession,
      JSON.stringify({ token: this.token, table: this.tableNumber, expires: this.expires.toISOString() }),
    );
    return this.tableNumber;
  }

  clear(): void {
    this.token = null;
    this.tableNumber = null;
    this.expires = null;
    this.store.delete(StorageKeys.guestSession);
  }

  private restore(): void {
    const raw = this.store.read(StorageKeys.guestSession);
    if (!raw) return;
    try {
      const json = JSON.parse(raw) as { token: string; table: number; expires: string };
      if (typeof json.token !== 'string' || typeof json.table !== 'number') throw new Error('bad session');
      const expires = new Date(json.expires);
      if (Number.isNaN(expires.getTime())) throw new Error('bad date');
      this.token = json.token;
      this.tableNumber = json.table;
      this.expires = expires;
    } catch {
      this.store.delete(StorageKeys.guestSession);
    }
  }
}
