import { act, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MemoryStore } from '../services/storage';
import { FakeApi } from '../test/fakeApi';
import { pathOf, renderApp } from '../test/render';

// The camera: each test says what the "camera" sees.
const camera = vi.hoisted(() => ({
  start: (_cb: (result: { getText(): string } | undefined) => void): Promise<void> => Promise.resolve(),
  stops: 0,
}));

vi.mock('@zxing/browser', () => ({
  BrowserQRCodeReader: class {
    async decodeFromConstraints(_constraints: unknown, _video: unknown, cb: (r: unknown, e: unknown, c: unknown) => void) {
      const controls = { stop: () => void camera.stops++ };
      await camera.start((result) => cb(result, undefined, controls));
      return controls;
    }
  },
}));

const code = (text: string) => ({ getText: () => text });

function withCamera() {
  Object.defineProperty(window, 'isSecureContext', { value: true, configurable: true });
  Object.defineProperty(navigator, 'mediaDevices', { value: { getUserMedia: vi.fn() }, configurable: true });
}

beforeEach(() => {
  camera.stops = 0;
  camera.start = () => Promise.resolve();
});

afterEach(() => {
  Object.defineProperty(navigator, 'mediaDevices', { value: undefined, configurable: true });
});

describe('direct visit (no table in the URL)', () => {
  it('shows the QR scanner first, and starts no session', async () => {
    const { api } = renderApp('/');
    expect(await screen.findByTestId('scanner')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Scan QR Code' })).toBeInTheDocument();
    expect(screen.getByText('Scan the restaurant QR code on your table to continue.')).toBeInTheDocument();
    expect(api.requests.some((r) => r.path === '/guest/sessions')).toBe(false);
  });

  it('says what to do when the browser cannot use the camera', async () => {
    Object.defineProperty(window, 'isSecureContext', { value: true, configurable: true });
    renderApp('/');
    expect(await screen.findByText(/This browser cannot use the camera here/)).toBeInTheDocument();
  });

  it('explains that the camera needs HTTPS', async () => {
    Object.defineProperty(window, 'isSecureContext', { value: false, configurable: true });
    Object.defineProperty(navigator, 'mediaDevices', { value: { getUserMedia: vi.fn() }, configurable: true });
    renderApp('/');
    expect(await screen.findByText(/The camera only works on a secure \(https:\/\/\) page/)).toBeInTheDocument();
  });

  it('sends ordering pages without a session to the scanner', async () => {
    const { router } = renderApp('/menu');
    await waitFor(() => expect(pathOf(router)).toBe('/'));
    expect(await screen.findByTestId('scanner')).toBeInTheDocument();
  });
});

describe('the about page', () => {
  it('is public, starts no session, and leads to the scanner', async () => {
    const { api, router, user } = renderApp('/about');
    expect(await screen.findByRole('heading', { level: 1, name: 'Scan. Order. Enjoy.' })).toBeInTheDocument();
    expect(api.requests.some((r) => r.path === '/guest/sessions')).toBe(false);
    await user.click(screen.getByRole('link', { name: /Scan your table/ }));
    await waitFor(() => expect(pathOf(router)).toBe('/scan'));
    expect(await screen.findByTestId('scanner')).toBeInTheDocument();
  });

  it('is linked from the scanner', async () => {
    const { router, user } = renderApp('/');
    await user.click(await screen.findByRole('link', { name: /How it works/ }));
    await waitFor(() => expect(pathOf(router)).toBe('/about'));
  });
});

describe('external QR entry (/t/NN: Google Lens or the phone camera)', () => {
  it('opens the table directly, without scanning again', async () => {
    const { api, router, user } = renderApp('/t/05');
    expect(await screen.findByText('Welcome to')).toBeInTheDocument();
    expect(screen.getByLabelText('Table 05')).toBeInTheDocument();
    expect(screen.queryByTestId('scanner')).not.toBeInTheDocument();
    await user.click(screen.getByTestId('start-ordering'));
    await waitFor(() => expect(pathOf(router)).toBe('/home'));
    const session = api.requests.find((r) => r.path === '/guest/sessions');
    // The server validates the same canonical payload the apps use.
    expect(session?.body).toEqual({ qrPayload: 'DINEQR:TABLE:05' });
    expect(await screen.findByRole('heading', { name: 'What are you craving today?' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Ordering at Table 05/ })).toBeInTheDocument();
  });

  it('refuses tables that do not exist or are not taking orders', async () => {
    renderApp('/t/99');
    expect(await screen.findByText('This QR code points to a table that does not exist.')).toBeInTheDocument();
  });

  it('refuses an inactive table', async () => {
    renderApp('/t/09');
    expect(await screen.findByText('This table is not taking orders right now. Please ask a staff member.')).toBeInTheDocument();
  });

  it('refuses takeaway while it is closed, and opens it when it is open', async () => {
    renderApp('/takeaway');
    expect(await screen.findByText(/Takeaway orders are not being taken right now/)).toBeInTheDocument();
  });

  it('opens takeaway when the restaurant takes it', async () => {
    const api = new FakeApi();
    api.takeaway = true;
    renderApp('/takeaway', { api });
    expect(await screen.findByText('Takeaway order')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Eating in\? Scan your table QR/ })).toBeInTheDocument();
  });

  it('refuses a malformed table link', async () => {
    renderApp('/t/abc');
    expect(await screen.findByTestId('entry-error')).toHaveTextContent('This code doesn’t work');
  });

  it('keeps the session through a refresh, and a rescan of the same table skips the welcome', async () => {
    const storage = new MemoryStore();
    const first = renderApp('/t/05', { storage });
    await first.user.click(await screen.findByTestId('start-ordering'));
    await waitFor(() => expect(pathOf(first.router)).toBe('/home'));
    first.view.unmount();

    // A new page load on a nested URL (what a browser refresh does).
    renderApp('/cart', { storage });
    expect(await screen.findByRole('heading', { name: 'My Cart' })).toBeInTheDocument();
  });

  it('resumes a recent session from the root URL', async () => {
    const storage = new MemoryStore();
    const first = renderApp('/t/05', { storage });
    await first.user.click(await screen.findByTestId('start-ordering'));
    await waitFor(() => expect(pathOf(first.router)).toBe('/home'));
    first.view.unmount();
    const second = renderApp('/', { storage });
    await waitFor(() => expect(pathOf(second.router)).toBe('/home'));
    const third = renderApp('/t/05', { storage });
    await waitFor(() => expect(pathOf(third.router)).toBe('/home'));
  });
});

describe('the in-app scanner', () => {
  it('opens the scanned table once, however often the camera reports it', async () => {
    withCamera();
    camera.start = async (report) => {
      report(code(`${window.location.origin}/t/05`));
      report(code(`${window.location.origin}/t/05`));
      report(code('DINEQR:TABLE:07'));
    };
    const { router } = renderApp('/');
    const visited: string[] = [];
    router.subscribe((state) => visited.push(state.location.pathname));
    expect(await screen.findByText('Table 05 detected')).toBeInTheDocument();
    await waitFor(() => expect(pathOf(router)).toBe('/t/05'), { timeout: 3000 });
    expect(visited.filter((p) => p.startsWith('/t/'))).toEqual(['/t/05']);
    expect(camera.stops).toBeGreaterThan(0);
  });

  it('accepts the original DINEQR payloads', async () => {
    withCamera();
    camera.start = async (report) => report(code('DINEQR:TABLE:12'));
    const { router } = renderApp('/');
    await waitFor(() => expect(pathOf(router)).toBe('/t/12'), { timeout: 3000 });
  });

  it('refuses links to other websites and keeps scanning', async () => {
    withCamera();
    let report: (r: { getText(): string }) => void = () => undefined;
    camera.start = async (cb) => {
      report = cb as typeof report;
    };
    const { router } = renderApp('/');
    await screen.findByTestId('scanner');
    await waitFor(() => expect(report).not.toBeNull());
    await act(async () => report(code('https://evil.example/t/05')));
    expect(await screen.findByRole('alert')).toHaveTextContent('This QR code opens another website');
    expect(pathOf(router)).toBe('/');
    await act(async () => report(code('DINEQR:TABLE:99')));
    expect(await screen.findByText('This QR code points to a table that does not exist.')).toBeInTheDocument();
    await act(async () => report(code('DINEQR:TABLE:03')));
    await waitFor(() => expect(pathOf(router)).toBe('/t/03'), { timeout: 3000 });
  });

  it('explains a denied camera and offers a retry, without crashing', async () => {
    withCamera();
    camera.start = () => Promise.reject(Object.assign(new Error('denied'), { name: 'NotAllowedError' }));
    renderApp('/');
    expect(await screen.findByText(/Camera access is off/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Retry/ })).toBeInTheDocument();
  });

  it('takes a pasted link or code from the manual entry', async () => {
    const { router, user } = renderApp('/');
    await user.click(await screen.findByRole('button', { name: /Enter code or link/ }));
    const dialog = await screen.findByRole('dialog');
    await user.type(within(dialog).getByLabelText('Link or code'), 'https://evil.example/t/05');
    await user.click(within(dialog).getByRole('button', { name: 'Continue' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('This QR code opens another website');
    await user.click(screen.getByRole('button', { name: /Enter code or link/ }));
    const again = await screen.findByRole('dialog');
    await user.type(within(again).getByLabelText('Link or code'), `${window.location.origin}/t/04`);
    await user.click(within(again).getByRole('button', { name: 'Continue' }));
    await waitFor(() => expect(pathOf(router)).toBe('/t/04'), { timeout: 3000 });
  });
});
