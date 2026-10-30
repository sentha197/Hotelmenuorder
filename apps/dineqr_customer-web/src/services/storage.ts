/**
 * Small key/value persistence with the same keys the Flutter app keeps in
 * SharedPreferences. Every access is guarded: private windows, blocked site
 * data and quota errors fall back to memory instead of breaking the app.
 */
export interface KeyValueStore {
  read(key: string): string | null;
  write(key: string, value: string): void;
  delete(key: string): void;
}

export class MemoryStore implements KeyValueStore {
  private readonly values = new Map<string, string>();

  read(key: string): string | null {
    return this.values.get(key) ?? null;
  }

  write(key: string, value: string): void {
    this.values.set(key, value);
  }

  delete(key: string): void {
    this.values.delete(key);
  }
}

export class BrowserStore implements KeyValueStore {
  private readonly fallback = new MemoryStore();

  read(key: string): string | null {
    try {
      return window.localStorage.getItem(key) ?? this.fallback.read(key);
    } catch {
      return this.fallback.read(key);
    }
  }

  write(key: string, value: string): void {
    this.fallback.write(key, value);
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Memory only for this visit.
    }
  }

  delete(key: string): void {
    this.fallback.delete(key);
    try {
      window.localStorage.removeItem(key);
    } catch {
      // Nothing stored to remove.
    }
  }
}

export const StorageKeys = {
  table: 'session.table',
  tableSince: 'session.tableSince',
  cart: 'cart.lines',
  instructions: 'cart.instructions',
  offer: 'cart.offer',
  favorites: 'menu.favorites',
  guestSession: 'guest.session',
} as const;
