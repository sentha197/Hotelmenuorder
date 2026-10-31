import { useSyncExternalStore } from 'react';

/**
 * Light and dark appearance. The device decides ("system") unless the guest
 * picks one in More; the choice is remembered on this device only.
 *
 * The resolved theme is `data-theme` on <html>, which every colour token in
 * styles/tokens.css keys on. An inline script in index.html sets it before
 * the first paint (no flash of the wrong theme); this module keeps it in
 * step with the device's setting while the app is open, and with the guest's
 * choice. The brand page (/about) is always dark, as it was designed.
 */
export type ThemePreference = 'system' | 'light' | 'dark';
export type Theme = 'light' | 'dark';

export const THEME_KEY = 'dineqr.theme';
const LIGHT_QUERY = '(prefers-color-scheme: light)';

/** The browser bar matches the page; /about keeps its original brand red. */
const barColor: Record<Theme, string> = { dark: '#0b0708', light: '#fbf7f5' };
const LOCKED_BAR = '#B5121B';

const listeners = new Set<() => void>();
let preference: ThemePreference = readPreference();
let locked: Theme | null = null;

function readPreference(): ThemePreference {
  try {
    const saved = window.localStorage.getItem(THEME_KEY);
    return saved === 'light' || saved === 'dark' ? saved : 'system';
  } catch {
    return 'system';
  }
}

function deviceTheme(): Theme {
  return window.matchMedia?.(LIGHT_QUERY).matches ? 'light' : 'dark';
}

export function resolvedTheme(): Theme {
  return locked ?? (preference === 'system' ? deviceTheme() : preference);
}

function apply() {
  const theme = resolvedTheme();
  const root = document.documentElement;
  if (root.dataset.theme !== theme) root.dataset.theme = theme;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', locked ? LOCKED_BAR : barColor[theme]);
  listeners.forEach((listener) => listener());
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

/** Pins a theme while a page that needs one is open (null releases it). */
export function lockTheme(theme: Theme | null) {
  if (locked === theme) return;
  locked = theme;
  apply();
}

let started = false;

/** Follows the device's appearance live; call once at start-up. */
export function startTheme() {
  if (started || typeof window === 'undefined') return;
  started = true;
  const media = window.matchMedia?.(LIGHT_QUERY);
  const onChange = () => preference === 'system' && apply();
  media?.addEventListener?.('change', onChange);
  // Another tab changed the choice.
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

/** The resolved theme and the guest's choice, re-rendering when either changes. */
export function useTheme() {
  const theme = useSyncExternalStore(subscribe, resolvedTheme, () => 'dark' as Theme);
  const choice = useSyncExternalStore(subscribe, () => preference, () => 'system' as ThemePreference);
  return { theme, preference: choice, setPreference: setThemePreference };
}
