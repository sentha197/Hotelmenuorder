/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { defineConfig, loadEnv } from 'vite';

const loopback = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)(:\d+)?(\/|$)/i;

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), ['VITE_', 'DINEQR_']);
  // A production bundle that talks to "this computer" works for nobody else.
  if (mode === 'production' && loopback.test(env.VITE_API_URL ?? '')) {
    throw new Error(
      `VITE_API_URL is "${env.VITE_API_URL}", a development address. Set the ` +
        'deployed API (or leave it empty for same-origin) before building.',
    );
  }
  // DINEQR_API_PROXY (an environment variable, or `.env.render-preview`):
  // the dev and preview servers forward /api and /hubs to that API, so a
  // remote API works without listing localhost in its CORS origins.
  const proxyTarget = env.DINEQR_API_PROXY;
  const proxy = proxyTarget
    ? {
        '/api': { target: proxyTarget, changeOrigin: true },
        '/hubs': { target: proxyTarget, changeOrigin: true, ws: true },
      }
    : undefined;
  return {
    plugins: [react()],
    server: { port: 5173, host: true, proxy },
    preview: { port: 4173, host: true, proxy },
    build: {
      target: 'es2022',
      sourcemap: false,
      // The QR library (~480 kB) is its own chunk, loaded by the scanner only.
      chunkSizeWarningLimit: 520,
    },
    test: {
      environment: 'jsdom',
      globals: true,
      // Forked workers fail to start on some Windows setups; threads are fine.
      pool: 'threads',
      setupFiles: ['src/test/setup.ts'],
      include: ['src/**/*.test.{ts,tsx}'],
      css: false,
    },
  };
});
