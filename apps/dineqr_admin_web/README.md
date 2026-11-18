# DineQR Admin — web

The DineQR staff and management app for the browser: a React port of the
Flutter app in `apps/dineqr_admin`, talking to the same DineQR API (and so
the same database) with the same endpoints, request bodies, permission rules
and wording. The Flutter app is unchanged.

Stack: React 19 + TypeScript, Vite, React Router, Tailwind CSS 4, Motion
(the current package name of Framer Motion), Lucide icons, Axios, TanStack
Query, React Hook Form + Zod, Recharts, `@microsoft/signalr` for live
updates and `qrcode` for QR codes drawn locally.

## Run it

```bash
npm install
npm run dev          # http://localhost:5180, API at VITE_API_URL (.env.development: http://localhost:5264)
npm run build        # type-check + production build into dist/
npm test             # unit tests of the business rules
```

Settings (see `.env.example`; everything in `VITE_*` is public):

| Variable | Meaning |
|---|---|
| `VITE_API_URL` | API host without `/api/v1`. Empty = same origin. A production build refuses a localhost address. |
| `VITE_DINEQR_WEB_URL` | Customer web app address; printed table QR codes become links to it (same rule as the Flutter `DINEQR_WEB_URL`). |
| `VITE_GOOGLE_MAPS_API_KEY` | Optional map in Settings › GPS ordering area. Without it, coordinates are typed or taken from this device, as in Flutter. |
| `DINEQR_API_PROXY` | Dev/preview server only: forward `/api` and `/hubs` to this API (avoids CORS while developing against a remote API). |

### Deploying

* **CORS:** the deployed API answers browsers only from origins listed in
  `Cors__AllowedOrigins__0`, `__1`, … on the server (Render). Add the admin
  site's origin there, or serve the site and the API from one origin.
* Any static host works; route every path to `index.html` (`public/_redirects`
  covers Netlify and Cloudflare Pages).

### Live end-to-end tests

`e2e/live.e2e.test.ts` drives the app's real API client, sign-in and actions
against a running API: sign-in/refresh/sign-out, settings, tables, dishes,
categories, photo upload, coupons, special offers, combos, UPI settings,
Wi-Fi and GPS restrictions, staff and custom access, inventory, a staff order
through the kitchen, a counter payment, a refund, a cancellation, and Terms &
Conditions publishing. It creates real records, so point it at a throwaway
API, never the deployed one:

```bash
DINEQR_E2E_API=http://localhost:5265 DINEQR_E2E_OWNER_EMAIL=owner@example.test DINEQR_E2E_OWNER_PASSWORD=... npm run test:e2e
```

## Feature inventory (Flutter → web)

Every Flutter screen, dialog and action has a web counterpart. Paths are the
web routes; each one checks the same permission as the Flutter module.

| Flutter | Web | Covered |
|---|---|---|
| Splash + session restore (retry / go to sign-in) | `/` | ✓ |
| Staff sign-in, errors, lock-out wording, forgot password | `/` | ✓ |
| Role workspaces, module order, badges, sign-out, session expiry | shell | ✓ (+ Ctrl/⌘ K quick switch, collapsible sidebar, phone bottom bar with More) |
| Dashboard: period chips, 10 metrics with change, alerts, 7-day chart, live orders, top dishes, payment summary, recent activity | `/dashboard` | ✓ |
| Service: my tables (saved on this device), ready to serve, in the kitchen, table tiles and table sheet | `/service` | ✓ |
| Orders: search, period/type/status filters with counts, advance, cancel with reason | `/orders` | ✓ |
| Order detail: overview, items, status history, bill, feedback | `/orders/:id` | ✓ |
| New order (POS): dine-in/takeaway, table, dishes, combos, special offers, instructions, summary | `/orders/new` | ✓ (priced like the server; verified against it) |
| Kitchen display: lanes, overdue tickets, 30 s ages, completed | `/kitchen` | ✓ |
| Bills: metrics, search, period/status/method filters | `/bills` | ✓ |
| Bill detail: counter request, record payment, reconcile, refund, UPI confirm / not received / cancel | `/bills/:id` | ✓ |
| Receipt preview / share PDF / thermal print | `/bills/:id/receipt` | ✓ print or "Save as PDF" from the browser; thermal printing is unavailable (as in the Flutter app, which has no printer either) |
| Payments ledger: period, status, method, search, metrics | `/payments` | ✓ |
| Menu: dishes (filters, availability, restore), categories (add, edit, hide, reorder, delete) | `/menu` | ✓ (drag or arrow buttons to reorder) |
| Dish editor: basics, description, photo upload/sample, visibility, spice, portions, add-ons, archive | `/menu/dishes/:id` | ✓ |
| Offers: special offers, combos, coupons (create, edit, pause, delete) | `/offers`, `/offers/new/:kind`, `/offers/edit/:id` | ✓ |
| Tables & QR: states, add/edit/(de)activate/remove, QR per table, takeaway switch and code, print all | `/tables`, `/tables/print` | ✓ |
| Reports: presets and custom range, metrics, daily chart, breakdown and definitions, best sellers, categories, payment collection, taxes, outstanding bills, refunds, tables, CSV and PDF export | `/reports`, `/reports/print` | ✓ (PDF via the browser's print dialog; collection shown as a segmented bar instead of a donut) |
| Inventory: filters, add/edit, adjust with reasons, history | `/inventory` | ✓ |
| Staff: add (any role name), change role, custom access editor, activate, reset password, role guide | `/staff` | ✓ |
| Settings: restaurant, taxes, currency, payment options, part payments, time zone, receipt note, menu & stock rules | `/settings` | ✓ |
| UPI payment settings: enable, UPI ID with typo check, payee, check-QR, merchant QR upload, verification mode | `/settings` | ✓ |
| Dine-in Wi-Fi restriction and "this device" check | `/settings` | ✓ |
| GPS ordering area: location, this device, Google Maps, radius | `/settings` | ✓ (map only with an API key, as in Flutter) |
| Terms & Privacy: published, drafts, earlier versions, editor with preview, publish/unpublish/delete, acceptance history with filters | `/legal` | ✓ |
| Activity log: search, area filters | `/activity` | ✓ |
| Offline demo mode (`DINEQR_MODE=demo`) and "Reset all demo data" | — | Not ported: the web app works only against the server, so there is no offline demo data to reset |

## How it is built

```
src/
  api/          client.ts (Axios, RFC 7807 errors, GET retry, 401 renew), auth.ts, dineqr.ts (every endpoint), realtime.ts (SignalR + 30 s fallback poll)
  core/         business rules ported from dineqr_core: money, time, pricing, offers, billing, reports, settings, access, …
  state/        session.ts (staff session), data.ts (TanStack Query hooks + live updates), actions.ts (every change, with the Flutter controllers' checks), run.ts
  components/   ui/ (design system), domain/ (invoice, badges, QR), charts/, brand/
  layouts/      AppShell.tsx
  pages/        one folder per module, each lazily loaded
  routes/       modules.ts (role workspaces), router.tsx (guards)
  styles/       index.css (theme tokens for dark and light)
```

* **Server is the judge.** The app checks permissions and inputs only to save
  a round trip; the API authorises and validates every request. Payments are
  settled only by the server (counter payments by staff, UPI-direct by a
  cashier's confirmation).
* **Sessions.** The access token lives in memory (and this tab's session
  storage, so a reload does not rotate tokens); the refresh token in this
  browser's local storage, like the Flutter app's secure storage. Refreshes
  are serialised across tabs (Web Locks), because the server ends the whole
  session when a rotated refresh token is reused. Only a 401 ends the
  session; a rate limit or server error keeps it for a retry. Local storage is
  readable by scripts on this origin, so keep the site free of third-party
  scripts.
* **Live updates.** Server events re-read the matching data (bursts merged);
  while the connection is down everything refreshes every 30 s.
* **Themes.** Dark and light tokens in `styles/index.css`; the choice (or the
  device setting) is remembered per browser and applied before first paint.
* **Motion.** Follows the device's reduced-motion setting: fades stay, movement
  goes.
