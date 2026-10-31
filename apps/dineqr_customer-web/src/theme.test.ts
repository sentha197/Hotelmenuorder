import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/** A device appearance the test can flip, like the OS setting changing. */
function fakeDevice(light: boolean) {
  const listeners = new Set<() => void>();
  const media = {
    get matches() {
      return light;
    },
    addEventListener: (_: string, listener: () => void) => listeners.add(listener),
    removeEventListener: (_: string, listener: () => void) => listeners.delete(listener),
  };
  vi.spyOn(window, 'matchMedia').mockImplementation((query: string) =>
    (query.includes('prefers-color-scheme') ? media : { matches: false, addEventListener() {}, removeEventListener() {} }) as unknown as MediaQueryList,
  );
  return {
    set(next: boolean) {
      light = next;
      listeners.forEach((listener) => listener());
    },
  };
}

const loadTheme = async () => {
  vi.resetModules();
  return import('./theme');
};
const current = () => document.documentElement.dataset.theme;

describe('theme', () => {
  beforeEach(() => {
    delete document.documentElement.dataset.theme;
    document.head.innerHTML = '<meta name="theme-color" content="#B5121B">';
  });
  afterEach(() => vi.restoreAllMocks());

  it('follows the device, live, while the guest has not chosen', async () => {
    const device = fakeDevice(true);
    const theme = await loadTheme();
    theme.startTheme();
    expect(current()).toBe('light');
    expect(document.querySelector('meta[name="theme-color"]')!.getAttribute('content')).toBe('#fbf7f5');
    device.set(false);
    expect(current()).toBe('dark');
    device.set(true);
    expect(current()).toBe('light');
  });

  it("keeps the guest's choice over the device and remembers it", async () => {
    const device = fakeDevice(true);
    const theme = await loadTheme();
    theme.startTheme();
    theme.setThemePreference('dark');
    expect(current()).toBe('dark');
    expect(window.localStorage.getItem(theme.THEME_KEY)).toBe('dark');
    device.set(false);
    device.set(true);
    expect(current()).toBe('dark');

    // A new visit starts from the saved choice.
    const again = await loadTheme();
    again.startTheme();
    expect(again.resolvedTheme()).toBe('dark');

    // "Device" forgets it.
    again.setThemePreference('system');
    expect(window.localStorage.getItem(again.THEME_KEY)).toBeNull();
    expect(current()).toBe('light');
  });

  it('pins /about dark with its original bar colour, and lets go after', async () => {
    fakeDevice(true);
    const theme = await loadTheme();
    theme.startTheme();
    theme.lockTheme('dark');
    expect(current()).toBe('dark');
    expect(document.querySelector('meta[name="theme-color"]')!.getAttribute('content')).toBe('#B5121B');
    theme.setThemePreference('light');
    expect(current()).toBe('dark');
    theme.lockTheme(null);
    expect(current()).toBe('light');
  });
});
