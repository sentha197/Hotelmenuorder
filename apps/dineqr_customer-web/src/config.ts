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
        detail: `"${value}" is not a full http:// or https:// address. Set VITE_API_URL to the API host, for example https://hotelmenuorder.onrender.com.`,
      },
    };
  }
  return { config: { baseUrl: value.replace(/\/+$/, ''), timeoutMs: 20_000 }, issue: null };
}

const resolved = resolveApiConfig(import.meta.env.VITE_API_URL as string | undefined);

export const apiConfig = resolved.config;
export const apiConfigIssue = resolved.issue;

/** Where the app is served below its origin (Vite `base`). */
export const basePath: string = import.meta.env.BASE_URL || '/';

/** Origins whose table links count as DineQR links when scanned in-app. */
export function allowedQrOrigins(): string[] {
  const extra = ((import.meta.env.VITE_QR_ORIGINS as string | undefined) ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  const own = typeof window === 'undefined' ? [] : [window.location.origin];
  return [...new Set([...own, ...extra])];
}

/**
 * Dish and category photos: the server sends `assets/images/<name>.jpg` for
 * the bundled photos (shipped in `public/assets/images`), full URLs for
 * uploaded ones, and possibly a server-relative path.
 */
export function imageUrl(path: string): string {
  if (!path) return '';
  if (/^(https?:|data:|blob:)/i.test(path)) return path;
  if (path.startsWith('/')) return `${apiConfig?.baseUrl ?? ''}${path}`;
  return `${basePath}${path}`;
}
