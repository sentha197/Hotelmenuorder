import type { HubConnection } from '@microsoft/signalr';

/**
 * A change announced by the server (`orders`, `bills`, `menu`, `settings`,
 * `tables`, `inventory`, `staff`), or `connected` after (re)connecting.
 * Events only say what changed; the data is always re-read through the REST
 * API, which applies every permission check.
 */
export const realtimeEvents = ['orders', 'bills', 'menu', 'settings', 'tables', 'inventory', 'staff'] as const;
export type RealtimeEvent = (typeof realtimeEvents)[number] | 'connected';

/** The server's SignalR hub (`/hubs/events`), with automatic reconnection. */
export class RealtimeClient {
  private hub: HubConnection | null = null;
  private retry: ReturnType<typeof setTimeout> | null = null;
  private wanted = false;
  private readonly listeners = new Set<(name: RealtimeEvent) => void>();
  private readonly stateListeners = new Set<() => void>();

  constructor(
    private readonly hubUrl: string,
    private readonly token: () => Promise<string | null>,
  ) {}

  get isConnected(): boolean {
    return this.hub?.state === 'Connected';
  }

  onEvent(listener: (name: RealtimeEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Told when the connection comes up or goes down (for the live indicator). */
  onStateChange(listener: () => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  private emit(name: RealtimeEvent): void {
    for (const listener of this.listeners) listener(name);
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
    for (const name of realtimeEvents) hub.on(name, () => this.emit(name));
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
 * Keeps screens current: each event re-reads its data (bursts merged within
 * 300 ms), a reconnect re-reads everything, and while the live connection is
 * down everything is refreshed every 30 s (LiveUpdates).
 */
export class LiveUpdates {
  private readonly dirty = new Set<string>();
  private debounce: ReturnType<typeof setTimeout> | null = null;
  private readonly poll: ReturnType<typeof setInterval>;
  private readonly unsubscribe: () => void;

  constructor(
    client: RealtimeClient,
    private readonly handlers: Record<string, () => Promise<unknown>>,
    pollMs = 30_000,
  ) {
    this.unsubscribe = client.onEvent((name) => {
      if (name === 'connected') this.refresh(Object.keys(handlers));
      else if (name in handlers) this.refresh([name]);
    });
    this.poll = setInterval(() => {
      if (!client.isConnected) this.refresh(Object.keys(handlers));
    }, pollMs);
  }

  refresh(names: Iterable<string>): void {
    for (const name of names) this.dirty.add(name);
    if (this.debounce) clearTimeout(this.debounce);
    this.debounce = setTimeout(async () => {
      const due = [...this.dirty];
      this.dirty.clear();
      for (const name of due) {
        try {
          await this.handlers[name]?.();
        } catch {
          // Screens keep what they have; the next event or poll retries.
        }
      }
    }, 300);
  }

  dispose(): void {
    if (this.debounce) clearTimeout(this.debounce);
    clearInterval(this.poll);
    this.unsubscribe();
  }
}
