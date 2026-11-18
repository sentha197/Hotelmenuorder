import { useSyncExternalStore } from 'react';

/**
 * Light and dark appearance. The device decides ("system") unless the staff
 * member picks one; the choice is remembered in this browser. The resolved
 * theme is `data-theme` on <html>, which every colour token keys on. An
 * inline script in index.html sets it before the first paint.
 */
export type ThemePreference = 'system' | 'light' | 'dark';
export type Theme = 'light' | 'dark';

export const THEME_KEY = 'dineqr.admin.theme';
const LIGHT_QUERY = '(prefers-color-scheme: light)';
const barColor: Record<Theme, string> = { dark: '#140a0c', light: '#f6f2f1' };

const listeners = new Set<() => void>();
let preference: ThemePreference = readPreference();

function readPreference(): ThemePreference {
  try {
    const saved = window.localStorage.getItem(THEME_KEY);
    return saved === 'light' || saved === 'dark' ? saved : 'system';
  } catch {
    return 'system';
  }
}

const deviceTheme = (): Theme => (window.matchMedia?.(LIGHT_QUERY).matches ? 'light' : 'dark');

export const resolvedTheme = (): Theme => (preference === 'system' ? deviceTheme() : preference);

function apply() {
  const theme = resolvedTheme();
  const root = document.documentElement;
  if (root.dataset.theme !== theme) root.dataset.theme = theme;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', barColor[theme]);
  listeners.forEach((l) => l());
}

export function setThemePreference(next: ThemePreference) {
  preference = next;
  try {
    if (next === 'system') window.localStorage.removeItem(THEME_KEY);
    else window.localStorage.setItem(THEME_KEY, next);
  } catch {
    // Private browsing: the choice lasts until the page closes.
  }
  apply();
}

let started = false;

/** Follows the device's appearance live and other tabs' choices; call once. */
export function startTheme() {
  if (started || typeof window === 'undefined') return;
  started = true;
  window.matchMedia?.(LIGHT_QUERY).addEventListener?.('change', () => preference === 'system' && apply());
  window.addEventListener('storage', (event) => {
    if (event.key !== THEME_KEY) return;
    preference = readPreference();
    apply();
  });
  apply();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useTheme() {
  const theme = useSyncExternalStore(subscribe, resolvedTheme, () => 'dark' as Theme);
  const choice = useSyncExternalStore(subscribe, () => preference, () => 'system' as ThemePreference);
  return { theme, preference: choice, setPreference: setThemePreference };
}
