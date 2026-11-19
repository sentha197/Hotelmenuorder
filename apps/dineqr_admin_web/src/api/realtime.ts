import type { HubConnection } from '@microsoft/signalr';

/**
 * A change announced by the server (`orders`, `bills`, `menu`, `settings`,
 * `tables`, `inventory`, `staff`), or `connected` after (re)connecting.
 * Events say what changed (an `orders` or `bills` event names the order or
 * bill); the data is always re-read through the REST API, which applies every
 * permission check.
 */
export const realtimeEvents = ['orders', 'bills', 'menu', 'settings', 'tables', 'inventory', 'staff'] as const;
export type RealtimeEvent = (typeof realtimeEvents)[number] | 'connected';

/** The server's SignalR hub (`/hubs/events`), with automatic reconnection. */
export class RealtimeClient {
  private hub: HubConnection | null = null;
  private retry: ReturnType<typeof setTimeout> | null = null;
  private wanted = false;
  private readonly listeners = new Set<(name: RealtimeEvent, payload?: unknown) => void>();
  private readonly stateListeners = new Set<() => void>();

  constructor(
    private readonly hubUrl: string,
    private readonly token: () => Promise<string | null>,
  ) {}

  get isConnected(): boolean {
    return this.hub?.state === 'Connected';
  }

  onEvent(listener: (name: RealtimeEvent, payload?: unknown) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Told when the connection comes up or goes down (for the live indicator). */
  onStateChange(listener: () => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  private emit(name: RealtimeEvent, payload?: unknown): void {
    for (const listener of this.listeners) listener(name, payload);
  }

  private changed(): void {
    for (const listener of this.stateListeners) listener();
  }

  /** Connects (again). Safe to call repeatedly, e.g. after signing in. */
  async start(): Promise<void> {
    this.wanted = true;
    if (this.retry) clearTimeout(this.retry);
    await this.hub?.stop().catch(() => undefined);
    this.hub = null;
    if (!(await this.token())) return; // nothing to authenticate with yet
    const signalr = await import('@microsoft/signalr');
    const hub = new signalr.HubConnectionBuilder()
      .withUrl(this.hubUrl, { accessTokenFactory: async () => (await this.token()) ?? '' })
      .withAutomaticReconnect()
      .configureLogging(signalr.LogLevel.None)
      .build();
    for (const name of realtimeEvents) hub.on(name, (payload?: unknown) => this.emit(name, payload));
    hub.onreconnecting(() => this.changed());
    hub.onreconnected(() => {
      this.changed();
      this.emit('connected');
    });
    hub.onclose(() => {
      this.changed();
      this.scheduleRestart();
    });
    this.hub = hub;
    try {
      await hub.start();
      this.changed();
      this.emit('connected');
    } catch {
      this.changed();
      this.scheduleRestart();
    }
  }

  private scheduleRestart(): void {
    if (!this.wanted) return;
    if (this.retry) clearTimeout(this.retry);
    this.retry = setTimeout(() => void this.start(), 15_000);
  }

  async stop(): Promise<void> {
    this.wanted = false;
    if (this.retry) clearTimeout(this.retry);
    await this.hub?.stop().catch(() => undefined);
    this.hub = null;
    this.changed();
  }
}

/**
 * Re-reads just the changed record named by an event's payload. Returns false
 * when the payload names nothing usable, so the whole list is re-read instead.
 */
export type LivePatcher = (payload: unknown) => Promise<boolean>;

/** At most this many records are patched one by one; a bigger burst re-reads the list. */
const MAX_PATCHES = 8;

/**
 * Keeps screens current: an `orders` or `bills` event re-reads only the record
 * it names (merged into the list), other events re-read their data (bursts
 * merged within 300 ms), a reconnect re-reads everything, and while the live
 * connection is down everything is refreshed every 30 s (LiveUpdates).
 */
export class LiveUpdates {
  private readonly dirty = new Set<string>();
  private readonly pending = new Map<string, unknown[]>();
  private debounce: ReturnType<typeof setTimeout> | null = null;
  private readonly poll: ReturnType<typeof setInterval>;
  private readonly unsubscribe: () => void;

  constructor(
    client: RealtimeClient,
    private readonly handlers: Record<string, () => Promise<unknown>>,
    pollMs = 30_000,
    private readonly patchers: Record<string, LivePatcher> = {},
  ) {
    this.unsubscribe = client.onEvent((name, payload) => {
      if (name === 'connected') this.refresh(Object.keys(handlers));
      else if (name in this.patchers && payload != null) this.patch(name, payload);
      else if (name in handlers) this.refresh([name]);
    });
    this.poll = setInterval(() => {
      if (!client.isConnected) this.refresh(Object.keys(handlers));
    }, pollMs);
  }

  refresh(names: Iterable<string>): void {
    for (const name of names) this.dirty.add(name);
    this.schedule();
  }

  /** Queues a single-record re-read for [name]. */
  private patch(name: string, payload: unknown): void {
    const list = this.pending.get(name) ?? [];
    list.push(payload);
    this.pending.set(name, list);
    this.schedule();
  }

  private schedule(): void {
    if (this.debounce) clearTimeout(this.debounce);
    this.debounce = setTimeout(() => void this.flush(), 300);
  }

  private async flush(): Promise<void> {
    const pending = [...this.pending.entries()];
    this.pending.clear();
    for (const [name, payloads] of pending) {
      // A full re-read is already due, or the burst is too big to patch.
      if (this.dirty.has(name)) continue;
      const unique = [...new Map(payloads.map((p) => [JSON.stringify(p), p])).values()];
      if (unique.length > MAX_PATCHES) {
        this.dirty.add(name);
        continue;
      }
      for (const payload of unique) {
        let ok = false;
        try {
          ok = await this.patchers[name]!(payload);
        } catch {
          ok = false;
        }
        if (!ok) {
          this.dirty.add(name);
          break;
        }
      }
    }
    const due = [...this.dirty];
    this.dirty.clear();
    for (const name of due) {
      try {
        await this.handlers[name]?.();
      } catch {
        // Screens keep what they have; the next event or poll retries.
      }
    }
  }

  dispose(): void {
    if (this.debounce) clearTimeout(this.debounce);
    clearInterval(this.poll);
    this.unsubscribe();
  }
}
