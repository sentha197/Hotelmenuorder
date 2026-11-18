import { TAKEAWAY_TABLE } from './orders';

/**
 * What printed table codes hold (TableQrParser.codeFor): `DINEQR:TABLE:05`
 * and `DINEQR:TAKEAWAY`, or, with a web base, links to the DineQR customer
 * web app (`<base>/t/05`, `<base>/takeaway`) that a phone camera opens.
 */
export const TABLE_PREFIX = 'DINEQR:TABLE:';
export const TAKEAWAY_PAYLOAD = 'DINEQR:TAKEAWAY';

export const payloadFor = (table: number) => (table === TAKEAWAY_TABLE ? TAKEAWAY_PAYLOAD : `${TABLE_PREFIX}${String(table).padStart(2, '0')}`);

/** [value] as a web app address (scheme, host, port and path only), or null. */
export function webBaseFrom(value: string): string | null {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return null;
  }
  if (!url.host || (url.protocol !== 'http:' && url.protocol !== 'https:')) return null;
  return `${url.protocol}//${url.host}${url.pathname.replace(/\/+$/, '')}`;
}

/**
 * The web base for these settings (TableQrParser.webBaseFor): the given
 * address; else, in a production build on the deployed API, that host (it
 * serves the web app); otherwise none (plain payloads).
 */
export function webBaseFor(webDefine: string, apiUrl: string, production: boolean, productionApi: string): string | null {
  const given = webBaseFrom(webDefine);
  if (given) return given;
  if (!production) return null;
  const api = webBaseFrom(apiUrl);
  const deployed = webBaseFrom(productionApi);
  return api != null && api === deployed ? deployed : null;
}

/** The web app link for [table] (or takeaway), e.g. `https://site/t/05`. */
export const linkFor = (table: number, base: string) =>
  table === TAKEAWAY_TABLE ? `${base.replace(/\/+$/, '')}/takeaway` : `${base.replace(/\/+$/, '')}/t/${String(table).padStart(2, '0')}`;

export const codeFor = (table: number, base: string | null) => (base == null ? payloadFor(table) : linkFor(table, base));
