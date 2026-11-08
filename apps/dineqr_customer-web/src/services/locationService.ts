import { ApiException, type ApiClient } from './api';

/** A position as the browser reported it; never stored. */
export interface GuestPosition {
  latitude: number;
  longitude: number;
  /** The browser's own uncertainty, in metres. */
  accuracy: number;
  capturedAt: Date;
}

export type LocationFailure = 'permissionDenied' | 'serviceDisabled' | 'unavailable';

export type LocationReading = { position: GuestPosition } | { failure: LocationFailure };

/** The device's location. */
export interface LocationProvider {
  current(): Promise<LocationReading>;
}

/** The browser's Geolocation API (HTTPS only), asking for a fresh, precise fix. */
export class BrowserLocationProvider implements LocationProvider {
  constructor(private readonly timeoutMs = 15_000) {}

  current(): Promise<LocationReading> {
    const geolocation = typeof navigator === 'undefined' ? undefined : navigator.geolocation;
    if (!geolocation) return Promise.resolve({ failure: 'unavailable' });
    return new Promise((resolve) => {
      geolocation.getCurrentPosition(
        (fix) =>
          resolve({
            position: {
              latitude: fix.coords.latitude,
              longitude: fix.coords.longitude,
              accuracy: fix.coords.accuracy,
              capturedAt: new Date(fix.timestamp),
            },
          }),
        (error) =>
          resolve({
            failure:
              error.code === error.PERMISSION_DENIED
                ? 'permissionDenied'
                : error.code === error.POSITION_UNAVAILABLE
                  ? 'serviceDisabled'
                  : 'unavailable',
          }),
        { enableHighAccuracy: true, maximumAge: 0, timeout: this.timeoutMs },
      );
    });
  }
}

/** The server's error codes for a refused position. */
export const LOCATION_CODES = new Set([
  'outsideRestaurantArea',
  'locationRequired',
  'locationInvalid',
  'locationInaccurate',
  'locationStale',
  'mockLocation',
]);

export const OUTSIDE_MESSAGE =
  "You are outside the restaurant's permitted location. Please move closer to the restaurant to place your order.";

export interface LocationCheckResult {
  required: boolean;
  allowed: boolean;
  code?: string;
  message?: string;
}

/** The JSON the API takes, with the order and with the check. */
export const positionToJson = (p: GuestPosition) => ({
  latitude: p.latitude,
  longitude: p.longitude,
  accuracy: p.accuracy,
  // Browsers cannot tell a simulated position; the server checks the rest.
  mocked: false,
  capturedAt: p.capturedAt.toISOString(),
});

/** `POST /guest/location-check`: the server measures the distance. */
export class LocationService {
  constructor(private readonly api: ApiClient) {}

  async check(position: GuestPosition | null): Promise<LocationCheckResult> {
    try {
      const json = await this.api.post<Record<string, unknown>>(
        '/guest/location-check',
        position ? positionToJson(position) : {},
      );
      return { required: json.required === true, allowed: json.allowed !== false };
    } catch (error) {
      if (error instanceof ApiException) {
        if (LOCATION_CODES.has(error.code)) return { required: true, allowed: false, code: error.code, message: error.message };
        // A server from before the GPS area has no such check.
        if (error.isNotFound) return { required: false, allowed: true };
      }
      throw error;
    }
  }
}
