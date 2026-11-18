import { parseOptionalInstant } from './time';

type Json = Record<string, unknown>;

// ---------------------------------------------------------- Wi-Fi restriction

/** One network the restaurant authorised: an address, a range, or a dynamic-DNS hostname. */
export interface AuthorizedNetwork {
  value: string;
  label: string;
  /** For a hostname: its current addresses. */
  resolved: string[];
}

/**
 * What the server sees for this device's own request. [consistent] is false
 * when an edge header names another client address (a proxy's address is
 * being reported and the restriction would not work).
 */
export interface NetworkCheck {
  address: string | null;
  source: string;
  matches: boolean;
  matchedBy: string | null;
  isPrivate: boolean;
  sharedCarrier: boolean;
  consistent: boolean;
  headers: Record<string, string>;
  suggestedEntry: string | null;
}

export interface NetworkAccessSettings {
  enabled: boolean;
  ssid: string;
  restrictTakeaway: boolean;
  networks: AuthorizedNetwork[];
  you: NetworkCheck | null;
}

export function networkSettingsFromJson(json: Json): NetworkAccessSettings {
  const you = json.you as Json | undefined | null;
  return {
    enabled: (json.enabled as boolean | undefined) ?? false,
    ssid: (json.ssid as string | undefined) ?? '',
    restrictTakeaway: (json.restrictTakeaway as boolean | undefined) ?? false,
    networks: ((json.networks as Json[] | undefined) ?? []).map((n) => ({
      value: String(n.value),
      label: (n.label as string | undefined) ?? '',
      resolved: ((n.resolved as unknown[] | undefined) ?? []).map(String),
    })),
    you: you
      ? {
          address: (you.address as string | null | undefined) ?? null,
          source: (you.source as string | undefined) ?? '',
          matches: (you.matches as boolean | undefined) ?? false,
          matchedBy: (you.matchedBy as string | null | undefined) ?? null,
          isPrivate: (you.private as boolean | undefined) ?? false,
          sharedCarrier: (you.sharedCarrier as boolean | undefined) ?? false,
          consistent: (you.consistent as boolean | undefined) ?? true,
          headers: Object.fromEntries(Object.entries((you.headers as Json | undefined) ?? {}).map(([k, v]) => [k, String(v)])),
          suggestedEntry: (you.suggestedEntry as string | null | undefined) ?? null,
        }
      : null,
  };
}

export const networkSettingsToJson = (s: Pick<NetworkAccessSettings, 'enabled' | 'ssid' | 'restrictTakeaway' | 'networks'>): Json => ({
  enabled: s.enabled,
  ssid: s.ssid,
  restrictTakeaway: s.restrictTakeaway,
  networks: s.networks.map((n) => ({ value: n.value, ...(n.label ? { label: n.label } : {}) })),
});

export const MAX_NETWORKS = 20;

/** NetworkAccessSettingsController.save's checks; returns the cleaned settings or a message. */
type NetworkDraft = Pick<NetworkAccessSettings, 'enabled' | 'ssid' | 'restrictTakeaway' | 'networks'>;

export function cleanNetworkSettings(next: NetworkDraft): { error: string; value?: undefined } | { error?: undefined; value: NetworkDraft } {
  const ssid = next.ssid.trim();
  if (ssid.length > 32) return { error: 'A Wi-Fi name is at most 32 characters.' };
  const networks = next.networks
    .filter((n) => n.value.trim())
    .map((n) => ({ value: n.value.trim(), label: n.label.trim(), resolved: [] as string[] }));
  if (networks.length > MAX_NETWORKS) return { error: 'List at most 20 networks.' };
  if (next.enabled && networks.length === 0) {
    return { error: "Add the restaurant's network before switching the restriction on, or no guest could order." };
  }
  return { value: { enabled: next.enabled, ssid, restrictTakeaway: next.restrictTakeaway, networks } };
}

// ------------------------------------------------------------- GPS ordering area

export interface GeofenceSettings {
  restaurantId: number;
  restaurantName: string;
  /** A location has been saved. */
  configured: boolean;
  enabled: boolean;
  latitude: number | null;
  longitude: number | null;
  radius: number;
  takeaway: boolean;
  createdAt: Date | null;
  updatedAt: Date | null;
  updatedBy: string;
}

export const geofenceFromJson = (json: Json): GeofenceSettings => ({
  restaurantId: (json.restaurantId as number | undefined) ?? 1,
  restaurantName: (json.restaurantName as string | undefined) ?? '',
  configured: (json.configured as boolean | undefined) ?? false,
  enabled: (json.enabled as boolean | undefined) ?? false,
  latitude: typeof json.latitude === 'number' ? json.latitude : null,
  longitude: typeof json.longitude === 'number' ? json.longitude : null,
  radius: (json.radius as number | undefined) ?? 50,
  takeaway: (json.takeaway as boolean | undefined) ?? false,
  createdAt: parseOptionalInstant(json.createdAt),
  updatedAt: parseOptionalInstant(json.updatedAt),
  updatedBy: (json.updatedBy as string | undefined) ?? '',
});

export const geofenceToJson = (g: Pick<GeofenceSettings, 'enabled' | 'latitude' | 'longitude' | 'radius' | 'takeaway'>): Json => ({
  enabled: g.enabled,
  latitude: g.latitude,
  longitude: g.longitude,
  radius: g.radius,
  takeaway: g.takeaway,
});

export const Geofence = {
  presets: [20, 30, 50, 100] as const,
  minRadius: 10,
  maxRadius: 1000,
  isValidPoint: (lat: number | null, lng: number | null) =>
    lat != null && lng != null && Number.isFinite(lat) && Number.isFinite(lng) && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !(lat === 0 && lng === 0),
  /** GeofenceSettingsController.save's checks. */
  validate(g: Pick<GeofenceSettings, 'enabled' | 'latitude' | 'longitude' | 'radius'>): string | null {
    if (g.radius < Geofence.minRadius || g.radius > Geofence.maxRadius) return 'Choose a radius from 10 to 1000 metres.';
    if (g.latitude != null || g.longitude != null) {
      if (!Geofence.isValidPoint(g.latitude, g.longitude)) {
        return 'Enter a latitude from -90 to 90 and a longitude from -180 to 180, or pick the restaurant on the map.';
      }
      return null;
    }
    return g.enabled ? "Set the restaurant's location before switching the GPS restriction on." : "Set the restaurant's location.";
  },
};
