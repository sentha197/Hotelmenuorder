import { defineConfig } from 'vitest/config';

// Live checks against a running DineQR API (see e2e/README section in the
// app README). Skipped unless DINEQR_E2E_API_URL is set.
export default defineConfig({
  test: {
    environment: 'node',
    pool: 'threads',
    include: ['e2e/**/*.e2e.test.ts'],
    testTimeout: 60_000,
    hookTimeout: 60_000,
  },
});
