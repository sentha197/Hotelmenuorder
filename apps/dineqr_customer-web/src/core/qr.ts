import { TAKEAWAY_TABLE } from './orders';

/**
 * DineQR table codes.
 *
 * Printed codes hold one of two forms:
 * - the original payloads, `DINEQR:TABLE:05` (dine-in) and `DINEQR:TAKEAWAY`
 *   (plus the legacy `BITEANDDINE:TABLE:05`, `DINEQR:PARCEL`,
 *   `BITEANDDINE:PARCEL`), which only the apps' own scanners understand;
 * - a link to this web app, `https://<site>/t/05` or `https://<site>/takeaway`,
 *   which a phone camera or Google Lens opens straight in the browser.
 *
 * Either way the code only says where an order is placed. The server checks
 * the table (and that takeaway is open) again when the guest session starts
 * and on every order; a link is never followed to another website.
 */

export type QrError =
  | 'empty'
  | 'unrecognized'
  | 'foreignLink'
  | 'invalidTable'
  | 'tableInactive'
  | 'takeawayUnavailable';

export const qrErrorMessage: Record<QrError, string> = {
  empty: 'No QR code content was found.',
  unrecognized: 'This is not a DineQR code.',
  foreignLink: 'This QR code opens another website, not this restaurant. Scan the DineQR code on your table.',
  invalidTable: 'This QR code points to a table that does not exist.',
  tableInactive: 'This table is not taking orders right now. Please ask a staff member.',
  takeawayUnavailable: 'Takeaway orders are not being taken right now. Please ask a staff member.',
};

export type QrResult =
  | { kind: 'table'; table: number }
  | { kind: 'takeaway' }
  | { kind: 'invalid'; error: QrError };

export const PAYLOAD_PREFIX = 'DINEQR:TABLE:';
export const TAKEAWAY_PAYLOAD = 'DINEQR:TAKEAWAY';
const legacyPrefixes = ['BITEANDDINE:TABLE:'];
const legacyTakeaway = ['DINEQR:PARCEL', 'BITEANDDINE:PARCEL'];

/** Without restaurant configuration, tables are numbered 1 to 30. */
export const MAX_TABLE_WITHOUT_CONFIG = 30;

/** Paths of the web form, relative to where the app is served. */
const tablePath = /^\/t\/(\d{1,3})\/?$/i;
const takeawayPath = /^\/takeaway\/?$/i;

export interface QrContext {
  /** Origins whose links count as DineQR links (the site's own, at least). */
  allowedOrigins: readonly string[];
  /** Where the app is served below the origin, e.g. `/` or `/order/`. */
  basePath?: string;
  tableExists?: (table: number) => boolean;
  tableActive?: (table: number) => boolean;
  /** Defaults to false: a takeaway code is refused unless the setting says so. */
  takeawayEnabled?: boolean;
}

/** The canonical payload the server's `/guest/sessions` accepts. */
export function payloadFor(table: number): string {
  return table === TAKEAWAY_TABLE ? TAKEAWAY_PAYLOAD : `${PAYLOAD_PREFIX}${table.toString().padStart(2, '0')}`;
}

/** The web link printed on a table's code, e.g. `https://site/t/05`. */
export function linkFor(table: number, origin: string, basePath = '/'): string {
  const base = `${origin.replace(/\/+$/, '')}${normalizeBase(basePath)}`;
  return table === TAKEAWAY_TABLE ? `${base}takeaway` : `${base}t/${table.toString().padStart(2, '0')}`;
}

const normalizeBase = (basePath: string) => `/${basePath.replace(/^\/+|\/+$/g, '')}/`.replace('//', '/');

/** A path inside the app (`/t/05`), after removing [basePath]. */
export function routeFromPath(pathname: string, basePath = '/'): { kind: 'table'; table: number } | { kind: 'takeaway' } | null {
  const base = normalizeBase(basePath);
  let path = pathname;
  if (base !== '/' && path.toLowerCase().startsWith(base.toLowerCase())) path = path.slice(base.length - 1);
  const table = tablePath.exec(path);
  if (table) return { kind: 'table', table: Number(table[1]) };
  if (takeawayPath.test(path)) return { kind: 'takeaway' };
  return null;
}

/**
 * Turns whatever was scanned into the canonical payload, or an error. A
 * link is accepted only from [allowedOrigins] and only in its table or
 * takeaway form; anything else is refused rather than opened.
 */
export function toPayload(raw: string | null | undefined, ctx: Pick<QrContext, 'allowedOrigins' | 'basePath'>): { payload: string } | { error: QrError } {
  const value = (raw ?? '').trim();
  if (!value) return { error: 'empty' };
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) return { payload: value };
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return { error: 'unrecognized' };
  }
  const origin = url.origin.toLowerCase();
  const allowed = ctx.allowedOrigins.some((o) => o.replace(/\/+$/, '').toLowerCase() === origin);
  if (!allowed) return { error: url.protocol === 'https:' || url.protocol === 'http:' ? 'foreignLink' : 'unrecognized' };
  // Plain http only for origins explicitly allowed (local development).
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return { error: 'unrecognized' };
  const route = routeFromPath(url.pathname, ctx.basePath);
  if (!route) return { error: 'unrecognized' };
  return { payload: route.kind === 'takeaway' ? TAKEAWAY_PAYLOAD : `${PAYLOAD_PREFIX}${route.table}` };
}

/** Validates a scanned value against the restaurant's tables. */
export function parseTableQr(raw: string | null | undefined, ctx: QrContext): QrResult {
  const converted = toPayload(raw, ctx);
  if ('error' in converted) return { kind: 'invalid', error: converted.error };
  const value = converted.payload;
  const upper = value.toUpperCase();

  if (upper === TAKEAWAY_PAYLOAD || legacyTakeaway.includes(upper)) {
    return ctx.takeawayEnabled ? { kind: 'takeaway' } : { kind: 'invalid', error: 'takeawayUnavailable' };
  }
  const prefix = [PAYLOAD_PREFIX, ...legacyPrefixes].find((p) => upper.startsWith(p));
  if (!prefix) return { kind: 'invalid', error: 'unrecognized' };
  const tablePart = value.slice(prefix.length).trim();
  if (!/^\d{1,3}$/.test(tablePart)) return { kind: 'invalid', error: 'unrecognized' };
  const table = Number(tablePart);
  // Table zero is the takeaway sentinel, never a real table.
  if (table === TAKEAWAY_TABLE) return { kind: 'invalid', error: 'invalidTable' };
  const exists = ctx.tableExists ? table >= 1 && ctx.tableExists(table) : table >= 1 && table <= MAX_TABLE_WITHOUT_CONFIG;
  if (!exists) return { kind: 'invalid', error: 'invalidTable' };
  if (ctx.tableActive && !ctx.tableActive(table)) return { kind: 'invalid', error: 'tableInactive' };
  return { kind: 'table', table };
}

export const tableOf = (result: QrResult): number | null =>
  result.kind === 'table' ? result.table : result.kind === 'takeaway' ? TAKEAWAY_TABLE : null;
