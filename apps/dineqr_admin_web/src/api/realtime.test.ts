import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { LiveUpdates, type RealtimeClient, type RealtimeEvent } from './realtime';

/** A stand-in for the SignalR client: tests push events into it. */
function fakeClient() {
  let listener: ((name: RealtimeEvent, payload?: unknown) => void) | null = null;
  const client = {
    isConnected: true,
    onEvent(l: (name: RealtimeEvent, payload?: unknown) => void) {
      listener = l;
      return () => (listener = null);
    },
  } as unknown as RealtimeClient;
  return { client, emit: (name: RealtimeEvent, payload?: unknown) => listener?.(name, payload) };
}

describe('live updates', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const setup = (patch: (payload: unknown) => Promise<boolean> = async () => true) => {
    const { client, emit } = fakeClient();
    const handlers = { orders: vi.fn(async () => {}), bills: vi.fn(async () => {}), menu: vi.fn(async () => {}) };
    const patchers = { orders: vi.fn(patch), bills: vi.fn(patch) };
    const live = new LiveUpdates(client, handlers, 30_000, patchers);
    return { emit, handlers, patchers, live };
  };

  it('re-reads only the order an event names, once per order', async () => {
    const { emit, handlers, patchers, live } = setup();
    emit('orders', { orderId: 'OD1' });
    emit('orders', { orderId: 'OD1' });
    emit('orders', { orderId: 'OD2' });
    await vi.advanceTimersByTimeAsync(400);
    expect(patchers.orders).toHaveBeenCalledTimes(2);
    expect(handlers.orders).not.toHaveBeenCalled();
    live.dispose();
  });

  it('re-reads the whole list when a record cannot be patched', async () => {
    const { emit, handlers, live } = setup(async () => false);
    emit('bills', { invoiceId: 'INV1' });
    await vi.advanceTimersByTimeAsync(400);
    expect(handlers.bills).toHaveBeenCalledTimes(1);
    live.dispose();
  });

  it('re-reads the whole list for a big burst, an error, or an event without a payload', async () => {
    const { emit, handlers, patchers, live } = setup(async () => {
      throw new Error('offline');
    });
    for (let i = 0; i < 20; i++) emit('orders', { orderId: `OD${i}` });
    emit('bills', { invoiceId: 'INV1' });
    emit('menu');
    await vi.advanceTimersByTimeAsync(400);
    expect(patchers.orders).not.toHaveBeenCalled();
    expect(handlers.orders).toHaveBeenCalledTimes(1);
    expect(handlers.bills).toHaveBeenCalledTimes(1);
    expect(handlers.menu).toHaveBeenCalledTimes(1);
    live.dispose();
  });

  it('re-reads everything after (re)connecting', async () => {
    const { emit, handlers, patchers, live } = setup();
    emit('orders', { orderId: 'OD1' });
    emit('connected');
    await vi.advanceTimersByTimeAsync(400);
    expect(patchers.orders).not.toHaveBeenCalled();
    expect(handlers.orders).toHaveBeenCalledTimes(1);
    expect(handlers.bills).toHaveBeenCalledTimes(1);
    expect(handlers.menu).toHaveBeenCalledTimes(1);
    live.dispose();
  });
});
