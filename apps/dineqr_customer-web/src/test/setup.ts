import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { MotionGlobalConfig } from 'motion/react';
import { afterEach, vi } from 'vitest';

// Animations finish at once in tests (jsdom has no real frames).
MotionGlobalConfig.skipAnimations = true;

// No live hub in tests: the client connects to nothing and stays quiet.
vi.mock('@microsoft/signalr', () => {
  class Hub {
    state = 'Disconnected';
    on() {}
    onreconnected() {}
    onclose() {}
    start() {
      return Promise.reject(new Error('no hub in tests'));
    }
    stop() {
      return Promise.resolve();
    }
  }
  class HubConnectionBuilder {
    withUrl() {
      return this;
    }
    withAutomaticReconnect() {
      return this;
    }
    configureLogging() {
      return this;
    }
    build() {
      return new Hub();
    }
  }
  return { HubConnectionBuilder, LogLevel: { None: 6 } };
});

afterEach(() => {
  cleanup();
  window.localStorage.clear();
});

// jsdom has no matchMedia. Tests run with reduced motion (shorter waits).
if (!window.matchMedia) {
  window.matchMedia = (query: string) =>
    ({
      matches: query.includes('prefers-reduced-motion: reduce'),
      media: query,
      onchange: null,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
      addListener: () => undefined,
      removeListener: () => undefined,
      dispatchEvent: () => false,
    }) as MediaQueryList;
}

// jsdom lacks these browser APIs used by motion and the layouts.
class NoopObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
  takeRecords() {
    return [];
  }
}
globalThis.IntersectionObserver ??= NoopObserver as unknown as typeof IntersectionObserver;
globalThis.ResizeObserver ??= NoopObserver as unknown as typeof ResizeObserver;
window.scrollTo = () => undefined;
