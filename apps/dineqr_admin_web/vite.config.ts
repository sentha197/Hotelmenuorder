/// <reference types="vitest/config" />
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';
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
  // DINEQR_API_PROXY: the dev and preview servers forward /api and /hubs to
  // that API, so a remote API works without listing localhost in its CORS
  // origins (the deployed API's list is configured on the server).
  const proxyTarget = env.DINEQR_API_PROXY;
  const proxy = proxyTarget
    ? {
        '/api': { target: proxyTarget, changeOrigin: true },
        '/hubs': { target: proxyTarget, changeOrigin: true, ws: true },
      }
    : undefined;
  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
    },
    server: { port: 5180, host: true, proxy },
    preview: { port: 4180, host: true, proxy },
    build: {
      target: ['es2022', 'safari15', 'chrome100', 'firefox100', 'edge100'],
      sourcemap: false,
      // Every module page is its own lazily loaded chunk; the chart library
      // only loads with the pages that draw charts.
      chunkSizeWarningLimit: 600,
    },
    test: {
      environment: 'jsdom',
      globals: true,
      // Forked workers fail to start on some Windows setups; threads are fine.
      pool: 'threads',
      setupFiles: ['src/test/setup.ts'],
      testTimeout: 20_000,
      include: ['src/**/*.test.{ts,tsx}'],
      css: false,
    },
  };
});
