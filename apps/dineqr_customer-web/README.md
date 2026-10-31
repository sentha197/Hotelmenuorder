# DineQR customer web app

The DineQR guest app for the browser: React 19, TypeScript and Vite. It talks to the same ASP.NET Core API as the Flutter apps (`backend/`) and keeps their rules: the server prices every order, decides every payment and checks every table.

- A **direct visit** (`https://<site>/`) opens the **QR scanner** first.
- A **table QR code scanned with Google Lens or the phone camera** opens `https://<site>/t/05` (or `/takeaway`). The table is checked and the guest confirms it; there is no second scan.
- `https://<site>/about` is the DineQR story page (how it works, the features, what the app promises), linked from the scanner and from More. It is public and opens no table session.

## Run it

```bash
npm install
npm run dev        # http://localhost:5173, against the local API on :5264
npm test           # unit and UI tests (Vitest, jsdom)
npm run build      # type check + production bundle in dist/
npm run preview    # serve dist/ on :4173
npm run preview:render  # build and serve on :4173 against the deployed Render API (proxied)
```

Node 20.19 or newer. `npm run dev` expects the API started with `dotnet run` (port 5264), as Flutter debug builds do. To develop against a remote API instead, let the dev server proxy it:

```bash
DINEQR_API_PROXY=https://hotelmenuorder.onrender.com VITE_API_URL= npm run dev
```

That creates real orders in that API's database, and so does ordering from `npm run preview:render`.

## Configuration

Build-time, public values only (`.env.*`). Everything here ends up in the browser bundle, so never put secrets, keys or credentials in `VITE_` variables.

| Variable | Default | Meaning |
|---|---|---|
| `VITE_API_URL` | dev: `http://localhost:5264`, build: `https://hotelmenuorder.onrender.com` | API host without `/api/v1`. Empty = same origin, with the host proxying `/api` and `/hubs` to the API. A production build that points at `localhost` fails. |
| `VITE_QR_ORIGINS` | empty | Extra origins whose table links the in-app scanner accepts (comma separated). The site's own origin is always accepted. |
| `VITE_DEMO_QR_CODES` | `true` in dev only | Shows "Use a demo QR code" on the scanner (simulated scans of tables 05 and 12, takeaway and two invalid codes). Leave it off in production. |

### API side (Render)

The deployed API sends CORS headers only for origins listed in `Cors:AllowedOrigins`, and today that list is empty. Before the site goes live, add the site's origin as a Render environment variable:

```
Cors__AllowedOrigins__0=https://<your web host>
```

The alternative is to serve the site and the API from one origin: the host proxies `/api/*` and `/hubs/*` to the API, and the site is built with `VITE_API_URL=` (empty). No database change is needed for the web app.

## QR codes

| Printed code | Opens / means |
|---|---|
| `https://<site>/t/05` | Table 05. A phone camera or Google Lens opens it in the browser; the in-app scanners read the table from it. |
| `https://<site>/takeaway` | Takeaway, accepted only while the restaurant takes takeaway orders. |
| `DINEQR:TABLE:05`, `DINEQR:TAKEAWAY` | The original codes, plus the legacy `BITEANDDINE:TABLE:NN`, `DINEQR:PARCEL` and `BITEANDDINE:PARCEL`. The apps' own scanners read them; a phone camera only shows the text. |

Whatever was scanned, the app sends the canonical payload (`DINEQR:TABLE:05`) to `POST /api/v1/guest/sessions`, which checks the table again, so the backend is unchanged. Links from any other website are refused rather than opened, as are site links that are not table links.

**Printing link codes.** Build the admin app with the web address:

```bash
flutter build apk --dart-define=DINEQR_WEB_URL=https://<your web host>
```

Its Tables screen, the printable QR sheet and the takeaway code then hold `https://<host>/t/NN` links. Build the Flutter customer app with the same define so its scanner accepts the reprinted codes. Without the define, both apps keep the plain payloads, so nothing changes until you opt in. Customer APKs built before this change don't read link codes. Codes printed earlier keep working in every app, but only link codes open from Google Lens.

## Hosting

The output is a static single-page app (`dist/`). Serve `index.html` for every path that is not a real file, so `/t/05`, `/menu` and `/bills/…` survive a page refresh:

- Netlify / Cloudflare Pages: `public/_redirects` is included.
- Render static site: add a rewrite rule `/*` → `/index.html`.
- nginx: `try_files $uri /index.html;`
- Vercel: a rewrite of `/(.*)` to `/index.html`.

The camera needs HTTPS: browsers only offer `getUserMedia` on secure pages (`localhost` is the only exception). On plain HTTP the scanner says so and points to the phone camera / Google Lens instead.

## The story page (`/about`)

A dark, cinematic page: the hero draws the DineQR logo from its vector paths (`components/DineQrMark.tsx`, a port of the Flutter splash geometry) and scans a table code on a phone; then a scroll-lit manifesto, five product chapters (scan, menu, cart, payment, the admin board), a feature gallery, the app's promises and a closing call to scan. Files: `pages/AboutPage.tsx`, `styles/landing.css`, `hooks/useCinematics.ts`. It is a lazy route (about 9 kB of script and 8 kB of CSS, gzipped), loaded only when opened, and it is always dark, whatever the app's theme. In the dark theme the whole app uses the same look. The scanner (`/`, `/scan`) has a glass header with the drawn logo and a "How it works" link to `/about`, and with the camera on the live picture replaces the backdrop. Every other page takes the look from the design tokens in `styles/tokens.css`: the ink background with crimson and orange light behind each page, graphite glass cards, glass app bars and navigation, pill buttons with the gradient and light band, and heavier headings. Red or orange text uses `--accent-text`, which keeps its contrast on dark surfaces; `--primary` stays the brand red for fills. Receipts, QR codes and the white mockups on `/about` are light surfaces (the `.light-surface` group in `tokens.css`), and printing switches the whole page back to light.

- **Motion** uses CSS keyframes, one IntersectionObserver and one `requestAnimationFrame` scroll handler. No animation library was added for it. Scrolling is never hijacked, looping animations pause off screen, parallax drift is capped at 32 px, and the 3D tilt only follows fine pointers (mouse, trackpad).
- **Reduced motion** (`prefers-reduced-motion: reduce`): everything is shown at once, the logo appears finished, and nothing moves.
- **Content.** The phone and tablet mockups are illustrations (hidden from screen readers) made from the bundled food photos. Their dishes, prices and order numbers are samples, not the restaurant's data. The page shows no testimonials or statistics.
- **Layout.** It is recomposed at 1080 px (one column: chapters stack, the gallery uses four columns) and at 760 px (phone: the mockups are rearranged, and the gallery uses one column).

## The app's design (Ember)

Every page except `/about` uses one design system, `styles/system.css`, on top of the tokens in `styles/tokens.css`:

- **Light and dark.** The app follows the device's appearance and switches live when it changes (no reload). Guests can override it in More › Appearance (Device / Light / Dark); the choice is kept in `localStorage` on that device only. `src/theme.ts` resolves the theme to `data-theme` on `<html>`, and every colour is a token in `tokens.css` keyed on it: the dark stage in the first `:root` block, daylight in `:root[data-theme='light']` (warm paper, white cards on hairline edges, soft shadows; the glow surfaces stay crimson). An inline script in `index.html` sets the theme before the first paint, so the wrong theme never flashes. With the camera on, the scanner stays a dark viewfinder in either theme, and `/about` is always dark (pinned in `routes.tsx`, browser bar in its original red). Receipts and QR codes stay light surfaces in both themes.
- **Signature pieces.** The glow button (a near-black body with ember light pooled at its foot, clipped by its own corners), the icon-tile eyebrow, glass pills, headings that rise out of a mask (`MaskedText`), and ember panels.
- **Sizes.** One responsive scale in `tokens.css` (the second `:root` block): type (`--fs-*`: on phones and tablets a 13 px body, 15–16 px section headings and 20–24 px page titles; from 1025 px a 14 px body, 13 px labels, 15 px card titles, 18 px section headings and 24–28 px page titles; the home and scanner headlines up to 32 px and the amount to pay 28–36 px, fluid with `clamp()`), weights, line heights, tracking, icons (`--icon-*`), control heights (`--h-*`), radii (`--r-*`), media (`--img-*`) and the page gutter (`--page`). Media queries retune them at 375, 600, 1024 and 1440 px; touch screens keep 40 px targets, and iOS gets 16 px inputs so it does not zoom. Components use the tokens rather than pixel values; `components/sizes.ts` mirrors the icon, logo and emblem sizes for props that take pixels.
- **Navigation.** A floating glass dock on phones and portrait tablets, and a glass pill across the top from 769 px, with the active tab's capsule sliding between tabs. Each page has its title under a floating back bar, both aligned to the page's column; once the title scrolls away, the bar frosts over and shows it (`AppBar`).
- **Home.** A centred hero, then the restaurant's own dishes on a slowly turning 3D ring (`components/DishRing.tsx`, which a sideways drag also spins) with the featured carousel in front of its lower third, photo cards for categories, and glass dish cards with hover depth.
- **Featured carousel** (`components/FeaturedCarousel.tsx`): the dishes marked "Home banner" in admin, one at a time. A new banner cross-fades in while its plate swings in from the side of travel and the copy rises line by line. It advances every 6 s; the active dot's fill is the timer, so hovering, keyboard focus, a finger on it, scrolling it away or the pause button all hold it. Swipe, arrows (on mouse devices), dots and the arrow keys change slides by hand.
- **Categories** (`components/CategoryCards.tsx`): the menu's categories as photo cards. Large on Home (a card opens that part of the menu); compact on the menu, where the row is the category tabs and the selected card's ring slides to the new choice without shifting the row.
- **States.** Empty states sit in a scan window with a sweeping beam. Confirmations draw an orbit ring and throw sparks. A faint spark field (`components/Ambient.tsx`) sits behind every page in the dark theme.
- **Motion.** One easing language (`--ease-out` for entrances, `--ease-io` for moves) and fixed durations (`--m-*`). Pages fade and lift in on every navigation (back and forward included); lists and cards (`FadeIn`) arrive as they scroll into view, once. The ring and the carousel run only while on screen.
- **Reduced motion** (the device's setting; on Windows, Settings › Accessibility › Visual effects › Animation effects off): less motion, not none. Entrances still fade and every control still answers, but nothing travels, zooms, spins or loops: movement keyframes are redefined as fades at the end of `system.css`, motion's components use fade-only variants, the carousel does not advance on its own and only cross-fades, and the ring holds still unless dragged. `/about` keeps its original rule (everything there finishes at once).

`/about` keeps its own stylesheet (`landing.css`) and is not affected: `base.css` pins `.landing` to the original 14 px base, and the shared icon rule skips it.

## How it maps to the Flutter app

| Feature | Flutter source | API | Web |
|---|---|---|---|
| Scanner, QR rules | `features/qr_scanner`, `core/qr/table_qr_parser.dart` | `/settings`, `/tables` | `pages/ScannerPage.tsx`, `hooks/useQrScanner.ts`, `core/qr.ts` |
| Table confirmation | `features/table_confirmation` | `POST /guest/sessions` | `pages/TableEntryPage.tsx` |
| Session, resume (4 h) | `state/session_controller.dart`, `api/api_auth.dart` | guest token | `state/sessionStore.ts`, `services/guestSession.ts` |
| Home, menu, dish | `features/home`, `menu`, `dish_details`, `catalog_controller.dart` | `GET /menu` | `pages/HomePage.tsx`, `MenuPage.tsx`, `DishPage.tsx`, `state/catalogStore.ts` |
| Cart, offers, pricing | `features/cart`, `cart_controller.dart`, `pricing.dart`, `discount_offer.dart` | (server re-prices) | `pages/CartPage.tsx`, `state/cartStore.ts`, `core/pricing.ts` |
| Checkout | `features/checkout`, `order_controller.dart` | `POST /orders` (idempotency key, expected total) | `pages/CheckoutPage.tsx`, `state/orderStore.ts` |
| Placed, tracking, orders, rating | `order_success`, `order_tracking`, `order_history`, `feedback` | `GET /orders`, `POST /orders/{id}/feedback`, SignalR `/hubs/events` | `pages/OrderPages.tsx`, `components/orders.tsx`, `services/realtime.ts` |
| Bill, receipt, history | `features/billing/bill_screen.dart`, `payment_history_screen.dart` | `GET /bills`, `GET /orders/{id}/bill` | `pages/BillPages.tsx`, `components/invoice.tsx` |
| Payment (demo simulator, counter, UPI to the restaurant, gateway UPI, split) | `payment_screen.dart`, `upi_payment_panel.dart`, `gateway_payment_panel.dart`, `split_payment_screen.dart`, `demo_checkout_sheet.dart`, `billing_controller.dart` | `/payments/intents`, `/payments/{id}/confirm`, `/payments/{id}`, `/payments/upi`, `/payments/{id}/upi/claim`, `/payments/{id}/cancel`, `/payments/{id}/checkout`, `/bills/{id}/counter-request` | `pages/PaymentPage.tsx`, `SplitPaymentPage.tsx`, `components/paymentPanels.tsx`, `DemoCheckout.tsx`, `state/billingStore.ts` |
| More, credits | `features/more` | — | `pages/MiscPages.tsx` |
| About (story page) | `more_screen.dart` about sheet, splash logo | — | `pages/AboutPage.tsx` |

Where the browser differs from the Flutter app:

- **UPI apps.** A web page can't list or launch installed apps. For UPI to the restaurant's own account, a phone copies the UPI ID and the guest pays in their own app; desktop shows the QR code. Either way the bill is paid only once the restaurant confirms. For gateway UPI, a phone opens the gateway's `upi://` link and the phone offers its UPI apps; desktop shows the gateway's QR code.
- **Receipt.** The Flutter PDF export becomes a print-ready page ("Print or save as PDF") plus a share/copy of a text summary.
- **Storage.** The guest token is kept in `localStorage` until it expires, as the Flutter app keeps it in SharedPreferences, so a closed tab doesn't lose the guest's orders and bills. It grants no staff access. No payment data is stored.

## Tests

- `npm test`: core rules (QR parsing, pricing, offers, bills, split plans, UPI link) and the theme (following the device live, the guest's choice, `/about` pinned dark), plus the whole app rendered against an in-memory API. Covers the scanner as the first screen, `/t/NN` entry without a second scan, invalid, inactive and takeaway codes, guards, refresh, camera errors, a duplicate scan opening one table, the order, and demo, failed and cash payments.
- `npm run test:e2e`: the app's services against a running API. **Use a throwaway database**: the test places orders and payments.

  ```bash
  DINEQR_E2E_API_URL=http://localhost:5265 DINEQR_E2E_OWNER_EMAIL=… DINEQR_E2E_OWNER_PASSWORD=… npm run test:e2e
  ```

- `npm run test:browser -- <site url> <qr.y4m> <screenshot dir>`: Chromium (`npx playwright install chromium`) with a fake camera playing a QR video made by `npm run qr-video -- "<site>/t/05" qr.y4m`. Runs the full journey and saves screenshots. It also places a real order on the configured API.

### Trying it with a phone

1. Host the build over HTTPS and add its origin to the API's CORS list (above).
2. Make a code for `https://<site>/t/05`: the admin app built with `DINEQR_WEB_URL`, or any QR generator.
3. Scan it with Google Lens or the phone camera. It should open straight on the Table 05 welcome screen.
4. Open `https://<site>/` directly. The scanner should ask for the camera and open the table when it sees the code.
