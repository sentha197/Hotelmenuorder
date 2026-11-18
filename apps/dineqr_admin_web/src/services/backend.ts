import { AuthService } from '@/api/auth';
import { createApiClient } from '@/api/client';
import { DineQrApi } from '@/api/dineqr';
import { RealtimeClient } from '@/api/realtime';
import { apiConfig } from '@/config/env';

/**
 * Everything the admin app needs to run against the DineQR API: the staff
 * sign-in, an API client that sends the access token (and renews it after a
 * 401), the typed endpoints and the live-update connection. Created once.
 */
function create() {
  if (!apiConfig) return null;
  // Sign-in and refresh calls go through a client without a token, so a
  // refresh never waits on itself.
  const auth = new AuthService(createApiClient(apiConfig));
  const http = createApiClient(apiConfig, { token: auth.accessToken, renewSession: auth.renew });
  return {
    auth,
    api: new DineQrApi(http),
    realtime: new RealtimeClient(`${apiConfig.baseUrl}/hubs/events`, auth.accessToken),
  };
}

export const backend = create();

/** The backend, for code that only runs once the app is configured. */
export function requireBackend() {
  if (!backend) throw new Error('The DineQR server address is not configured.');
  return backend;
}
