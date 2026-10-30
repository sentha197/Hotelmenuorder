import { render } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter } from 'react-router';
import { AppRoot } from '../App';
import { routes } from '../routes/routes';
import { MemoryStore } from '../services/storage';
import { createApp } from '../state/app';
import { FakeApi } from './fakeApi';

/** The whole app at [path], against an in-memory API. */
export function renderApp(path: string, options: { api?: FakeApi; storage?: MemoryStore } = {}) {
  const api = options.api ?? new FakeApi();
  const storage = options.storage ?? new MemoryStore();
  const app = createApp({ baseUrl: 'http://api.test', timeoutMs: 5000 }, { fetchImpl: api.fetch, storage });
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const view = render(<AppRoot app={app} router={router} />);
  return { api, app, router, storage, view, user: userEvent.setup() };
}

export const pathOf = (router: ReturnType<typeof createMemoryRouter>) => router.state.location.pathname;
