import { describe, expect, it } from 'vitest';
import { linkFor, parseTableQr, payloadFor, routeFromPath, toPayload, type QrContext } from './qr';

const site = 'https://order.example.com';
const ctx: QrContext = { allowedOrigins: [site] };
const tableOf = (raw: string, extra: Partial<QrContext> = {}) => {
  const result = parseTableQr(raw, { ...ctx, ...extra });
  return result.kind === 'table' ? result.table : null;
};
const errorOf = (raw: string, extra: Partial<QrContext> = {}) => {
  const result = parseTableQr(raw, { ...ctx, ...extra });
  return result.kind === 'invalid' ? result.error : null;
};

describe('existing payloads (same rules as TableQrParser)', () => {
  it('reads table codes, case and spaces aside', () => {
    expect(tableOf('DINEQR:TABLE:05')).toBe(5);
    expect(tableOf('  dineqr:table:12 ')).toBe(12);
    expect(tableOf('BITEANDDINE:TABLE:07')).toBe(7);
  });

  it('refuses anything else', () => {
    for (const raw of ['DINEQR:MENU:05', 'DINEQR:TABLE:', 'DINEQR:TABLE:5a', 'DINEQR:TABLE:-3', 'DINEQR:TABLE:1234', 'hello']) {
      expect(errorOf(raw)).toBe('unrecognized');
    }
    expect(errorOf('')).toBe('empty');
    expect(errorOf('   ')).toBe('empty');
  });

  it('checks the table against the restaurant', () => {
    expect(errorOf('DINEQR:TABLE:00')).toBe('invalidTable');
    expect(errorOf('DINEQR:TABLE:31')).toBe('invalidTable');
    const tables = { tableExists: (t: number) => t === 4 || t === 40, tableActive: (t: number) => t !== 40 };
    expect(tableOf('DINEQR:TABLE:40', { tableExists: tables.tableExists })).toBe(40);
    expect(errorOf('DINEQR:TABLE:05', tables)).toBe('invalidTable');
    expect(errorOf('DINEQR:TABLE:40', tables)).toBe('tableInactive');
  });

  it('accepts takeaway only while it is open, old names included', () => {
    for (const raw of ['DINEQR:TAKEAWAY', 'DINEQR:PARCEL', 'BITEANDDINE:PARCEL']) {
      expect(parseTableQr(raw, { ...ctx, takeawayEnabled: true }).kind).toBe('takeaway');
      expect(errorOf(raw)).toBe('takeawayUnavailable');
    }
  });

  it('builds the canonical payloads the server accepts', () => {
    expect(payloadFor(5)).toBe('DINEQR:TABLE:05');
    expect(payloadFor(0)).toBe('DINEQR:TAKEAWAY');
  });
});

describe('web links (what Google Lens and phone cameras open)', () => {
  it('reads /t/NN and /takeaway on the site', () => {
    expect(tableOf(`${site}/t/05`)).toBe(5);
    expect(tableOf(`${site}/t/5/`)).toBe(5);
    expect(tableOf(`${site}/T/12?utm=x#top`)).toBe(12);
    expect(parseTableQr(`${site}/takeaway`, { ...ctx, takeawayEnabled: true }).kind).toBe('takeaway');
  });

  it('applies the same table checks to links', () => {
    expect(errorOf(`${site}/t/99`)).toBe('invalidTable');
    expect(errorOf(`${site}/t/00`)).toBe('invalidTable');
    expect(errorOf(`${site}/takeaway`)).toBe('takeawayUnavailable');
  });

  it('never trusts another website', () => {
    expect(errorOf('https://evil.example/t/05')).toBe('foreignLink');
    expect(errorOf('http://order.example.com/t/05')).toBe('foreignLink');
    expect(errorOf('https://order.example.com.evil.example/t/05')).toBe('foreignLink');
    expect(errorOf('https://example.com/menu')).toBe('foreignLink');
  });

  it('refuses links on the site that are not table links', () => {
    expect(errorOf(`${site}/`)).toBe('unrecognized');
    expect(errorOf(`${site}/menu`)).toBe('unrecognized');
    expect(errorOf(`${site}/t/abc`)).toBe('unrecognized');
    expect(errorOf('javascript://alert(1)')).toBe('unrecognized');
    expect(errorOf('upi://pay?pa=x@y')).toBe('unrecognized');
  });

  it('accepts extra configured origins', () => {
    expect(tableOf('https://print.example.org/t/03', { allowedOrigins: [site, 'https://print.example.org/'] })).toBe(3);
  });

  it('handles an app served below a path', () => {
    const below = { allowedOrigins: [site], basePath: '/order/' };
    expect(tableOf(`${site}/order/t/08`, below)).toBe(8);
    expect(linkFor(8, site, '/order/')).toBe(`${site}/order/t/08`);
    expect(routeFromPath('/order/takeaway', '/order/')).toEqual({ kind: 'takeaway' });
  });

  it('round-trips the printed link', () => {
    for (const table of [1, 5, 12, 30]) expect(tableOf(linkFor(table, site))).toBe(table);
    expect(linkFor(0, site)).toBe(`${site}/takeaway`);
    expect(toPayload(linkFor(7, site), ctx)).toEqual({ payload: 'DINEQR:TABLE:7' });
  });
});
