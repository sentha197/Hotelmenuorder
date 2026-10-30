import { useSyncExternalStore } from 'react';

/**
 * A minimal observable, like Flutter's ChangeNotifier: stores hold plain
 * state, call [notify] after changing it, and React reads them through
 * [useStore] / [useSelect]. Keeping the logic outside React makes it testable
 * on its own and keeps the components thin.
 */
export class Store {
  private readonly listeners = new Set<() => void>();
  private version = 0;

  readonly subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  readonly getVersion = (): number => this.version;

  protected notify(): void {
    this.version++;
    for (const listener of [...this.listeners]) listener();
  }
}

/** Re-renders whenever [store] changes; returns it for direct reads. */
export function useStore<S extends Store>(store: S): S {
  useSyncExternalStore(store.subscribe, store.getVersion, store.getVersion);
  return store;
}

/** Re-renders only when [select] returns a different primitive value. */
export function useSelect<S extends Store, T extends string | number | boolean | null | undefined>(
  store: S,
  select: (store: S) => T,
): T {
  const read = () => select(store);
  return useSyncExternalStore(store.subscribe, read, read);
}
