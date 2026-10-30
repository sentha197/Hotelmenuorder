import type { HubConnection } from '@microsoft/signalr';

/**
 * The server's change announcements (`/hubs/events`). An event only says
 * what changed (`orders`, `bills`, `menu`, `settings`, `tables`); the data is
 * always re-read through the REST API, which applies every permission check.
 */
export class RealtimeClient {
  static readonly eventNames = ['orders', 'bills', 'menu', 'settings', 'tables'] as const;

  private hub: HubConnection | null = null;
  private retry: ReturnType<typeof setTimeout> | null = null;
  private wanted = false;
  private readonly listeners = new Set<(name: string) => void>();

  constructor(
    private readonly hubUrl: string,
    private readonly token: () => string | null,
  ) {}

  get isConnected(): boolean {
    return this.hub?.state === 'Connected';
  }

  onEvent(listener: (name: string) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(name: string): void {
    for (const listener of this.listeners) listener(name);
  }

  /** Connects (again). Safe to call repeatedly, e.g. after a new session. */
  async start(): Promise<void> {
    this.wanted = true;
    if (this.retry) clearTimeout(this.retry);
    await this.hub?.stop().catch(() => undefined);
    this.hub = null;
    if (!this.token()) return; // nothing to authenticate with yet
    const signalr = await import('@microsoft/signalr');
    const hub = new signalr.HubConnectionBuilder()
      .withUrl(this.hubUrl, { accessTokenFactory: () => this.token() ?? '' })
      .withAutomaticReconnect()
      .configureLogging(signalr.LogLevel.None)
      .build();
    for (const name of RealtimeClient.eventNames) hub.on(name, () => this.emit(name));
    hub.onreconnected(() => this.emit('connected'));
    hub.onclose(() => this.scheduleRestart());
    this.hub = hub;
    try {
      await hub.start();
      this.emit('connected');
    } catch {
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
  }
}

/**
 * Keeps screens current: each event re-reads its data (bursts merged), a
 * reconnect re-reads everything, and while the connection is down data is
 * refreshed every [pollMs].
 */
export class LiveUpdates {
  private readonly dirty = new Set<string>();
  private debounce: ReturnType<typeof setTimeout> | null = null;
  private readonly poll: ReturnType<typeof setInterval>;
  private readonly unsubscribe: () => void;

  constructor(
    client: RealtimeClient,
    private readonly handlers: Record<string, () => Promise<void>>,
    pollMs = 30_000,
  ) {
    this.unsubscribe = client.onEvent((name) => {
      if (name === 'connected') this.refresh(Object.keys(handlers));
      else if (name in handlers) this.refresh([name]);
    });
    this.poll = setInterval(() => {
      const visible = typeof document === 'undefined' || document.visibilityState === 'visible';
      if (!client.isConnected && visible) this.refresh(Object.keys(handlers));
    }, pollMs);
  }

  /** Re-reads [names] now (merged with anything already due). */
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
