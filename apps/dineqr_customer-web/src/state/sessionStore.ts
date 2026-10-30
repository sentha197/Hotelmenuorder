import { OrderTables } from '../core/orders';
import { payloadFor } from '../core/qr';
import type { GuestSession } from '../services/guestSession';
import { StorageKeys, type KeyValueStore } from '../services/storage';
import { Store } from './store';

/**
 * Where the guest is ordering: a table, or takeaway (table 0). Starting a
 * session asks the server for the table's guest session first, so a table
 * that is unknown, inactive (or takeaway that is closed) never starts one.
 */
export class SessionStore extends Store {
  /** A meal rarely lasts longer; after that a reopened tab scans again. */
  static readonly resumeWindowMs = 4 * 60 * 60 * 1000;

  tableNumber: number | null;
  private since: Date | null;
  /** Set once a session started in this page, so the guard lets it through. */
  startedHere = false;

  constructor(
    private readonly storage: KeyValueStore,
    private readonly guest: GuestSession,
    private readonly onStart: () => Promise<void>,
    private readonly clock: () => Date = () => new Date(),
  ) {
    super();
    const table = Number.parseInt(storage.read(StorageKeys.table) ?? '', 10);
    this.tableNumber = Number.isFinite(table) ? table : null;
    const since = new Date(storage.read(StorageKeys.tableSince) ?? '');
    this.since = Number.isNaN(since.getTime()) ? null : since;
  }

  get hasTable(): boolean {
    return this.tableNumber != null;
  }

  get isTakeaway(): boolean {
    return this.tableNumber != null && OrderTables.isTakeaway(this.tableNumber);
  }

  /** `Table 05`, `Takeaway`, or empty before a code is scanned. */
  get tableLabel(): string {
    return this.tableNumber == null ? '' : OrderTables.label(this.tableNumber);
  }

  get hasServerSession(): boolean {
    return this.guest.isActive;
  }

  /** The table to resume when the app opens: recent, with a live server session. */
  get resumableTable(): number | null {
    if (this.tableNumber == null || this.since == null || !this.guest.isActive) return null;
    const age = this.clock().getTime() - this.since.getTime();
    return age < 0 || age > SessionStore.resumeWindowMs ? null : this.tableNumber;
  }

  /** Whether ordering screens may open: a session from this page or a resumable one. */
  get canOrder(): boolean {
    return this.guest.isActive && this.tableNumber != null && (this.startedHere || this.resumableTable != null);
  }

  /** Throws [ApiException] when the server refuses the table. */
  async startSession(table: number): Promise<void> {
    await this.guest.start(payloadFor(table));
    this.tableNumber = table;
    this.since = this.clock();
    this.startedHere = true;
    this.storage.write(StorageKeys.table, `${table}`);
    this.storage.write(StorageKeys.tableSince, this.since.toISOString());
    this.notify();
    await this.onStart();
  }
}
