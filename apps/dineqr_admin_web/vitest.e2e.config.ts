/// <reference types="vitest/config" />
import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vite';

/**
 * Live end-to-end tests against a running DineQR API (never the deployed
 * one: they create orders, staff and payments). Start a throwaway API, then:
 *
 *     DINEQR_E2E_API=http://localhost:5265 DINEQR_E2E_OWNER_EMAIL=... DINEQR_E2E_OWNER_PASSWORD=... npm run test:e2e
 */
const api = process.env.DINEQR_E2E_API ?? '';

export default defineConfig({
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  test: {
    environment: 'jsdom',
    environmentOptions: { jsdom: { url: 'http://localhost:5180/' } },
    globals: true,
    pool: 'threads',
    include: ['e2e/**/*.e2e.test.ts'],
    testTimeout: 60_000,
    hookTimeout: 60_000,
    fileParallelism: false,
    env: { VITE_API_URL: api },
  },
});
