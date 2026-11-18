import { webBaseFor } from '@/core/qr';

/**
 * Public, build-time settings (see `.env.*`). Nothing here is secret: it is
 * all readable in the browser.
 */
export interface ApiConfig {
  /** API host without `/api/v1`; empty for same-origin. */
  baseUrl: string;
  timeoutMs: number;
}

export interface ConfigIssue {
  title: string;
  detail: string;
}

/** The deployed API (Render), as in the Flutter apps' `ApiConfig.productionUrl`. */
export const PRODUCTION_API = 'https://hotelmenuorder.onrender.com';

export function resolveApiConfig(raw: string | undefined): { config: ApiConfig | null; issue: ConfigIssue | null } {
  const value = (raw ?? '').trim();
  if (value === '') return { config: { baseUrl: '', timeoutMs: 20_000 }, issue: null };
  let url: URL | null = null;
  try {
    url = new URL(value);
  } catch {
    url = null;
  }
  if (!url || !url.host || (url.protocol !== 'http:' && url.protocol !== 'https:')) {
    return {
      config: null,
      issue: {
        title: 'The server address is not valid',
        detail: `"${value}" is not a full http:// or https:// address. Set VITE_API_URL to the API host, for example ${PRODUCTION_API}.`,
      },
    };
  }
  return { config: { baseUrl: value.replace(/\/+$/, ''), timeoutMs: 20_000 }, issue: null };
}

const rawApi = import.meta.env.VITE_API_URL as string | undefined;
const resolved = resolveApiConfig(rawApi);

export const apiConfig = resolved.config;
export const apiConfigIssue = resolved.issue;

/** Where printed table QR codes point (see `.env.example`). */
export const webBase = webBaseFor((import.meta.env.VITE_DINEQR_WEB_URL as string | undefined) ?? '', rawApi ?? '', import.meta.env.PROD, PRODUCTION_API);

/** Optional Google Maps JavaScript API key (Settings › GPS ordering area). */
export const googleMapsKey = ((import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined) ?? '').trim();

/** Where the app is served below its origin (Vite `base`). */
export const basePath: string = import.meta.env.BASE_URL || '/';

/**
 * Dish, offer and QR pictures: `assets/images/<name>.jpg` for the bundled
 * photos (shipped in `public/assets/images`), full URLs for uploaded ones,
 * and possibly a server-relative path.
 */
export function imageUrl(path: string): string {
  if (!path) return '';
  if (/^(https?:|data:|blob:)/i.test(path)) return path;
  if (path.startsWith('/')) return `${apiConfig?.baseUrl ?? ''}${path}`;
  return `${basePath}${path}`;
}
