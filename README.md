# DineQR

**Scan • Order • Enjoy.** QR table ordering for restaurants: two separate
Flutter apps that share one business layer and one design system, and an
ASP.NET Core API on PostgreSQL that connects them.

```
apps/
  dineqr_customer/       DineQR (com.dineqr.customer): guests scan, order, track, pay, rate
  dineqr_admin/          DineQR Admin (com.dineqr.admin): staff sign-in and restaurant management
packages/
  dineqr_core/           models, pricing and billing rules, QR parsing, repositories
                         (HTTP and offline demo), API client, live updates, controllers
  dineqr_design_system/  logo (with the animated smile), colours, type, motion, widgets, branded PDFs
backend/                 DineQR API: ASP.NET Core (.NET 10), EF Core, PostgreSQL, SignalR
docs/
  BACKEND_INTEGRATION.md the contract between the apps and the API
branding/                logo and app-icon PNG exports
```

The apps are independent Flutter projects: each has its own `main.dart`,
navigation, theme, icons, launch screen, Android application id, iOS bundle
id, `pubspec.lock` and build. They depend on the two packages by path. The
customer app contains no staff screens, staff routes or staff sign-in.

## Running

Requires Flutter 3.44+ / Dart 3.12+, the .NET 10 SDK and PostgreSQL. Set up
and start the API first ([`backend/README.md`](backend/README.md): secrets,
migration, first owner account):

```bash
cd backend
dotnet run --project src/DineQR.Api      # http://0.0.0.0:5264, Swagger at /swagger
```

Then run each app. Debug builds find that local API on their own
(`http://localhost:5264` on Chrome, desktop and the iOS simulator,
`http://10.0.2.2:5264`, the host computer, on the Android emulator):

```bash
cd apps/dineqr_customer
flutter run -d chrome

cd apps/dineqr_admin
flutter run -d chrome
```

On a phone running a debug build, give the address explicitly:
`--dart-define=DINEQR_API_URL=http://<this computer's LAN IP>:5264`. VS Code
has ready-made launch configurations (`.vscode/launch.json`), including one
that starts both apps in Chrome.

Profile and release builds use the deployed API,
`https://hotelmenuorder.onrender.com`, unless `DINEQR_API_URL` names another
`https://` server (release builds refuse plain `http://`):

```bash
cd apps/dineqr_admin
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

Checks for everything (bash):

```bash
for p in packages/dineqr_core packages/dineqr_design_system \
         apps/dineqr_customer apps/dineqr_admin; do
  (cd "$p" && flutter pub get && flutter analyze && flutter test)
done
```

## Backend mode and the offline demo

Each app is built in one of two modes:

| Build flag | What the app does |
| --- | --- |
| `--dart-define=DINEQR_API_URL=<url>` | **Backend mode.** Menu, settings, tables, orders, bills, payments, staff, inventory and the activity log come from the DineQR API and PostgreSQL. |
| `--dart-define=DINEQR_MODE=demo` | **Offline demo**, only when asked for: data stays on the device, sample records are labelled `SAMPLE`, payments `SIMULATED`. |
| neither | Debug builds: backend mode against the local development API (above). Profile and release builds: backend mode against the deployed API (`https://hotelmenuorder.onrender.com`). No build silently shows invented data. |

In backend mode:

- Start-up never waits on the server: the splash appears at once. The
  customer app's splash waits only for the restaurant's settings and tables
  (it says "Connecting to the restaurant…" if that takes a while and offers
  a retry if the server cannot be reached); the admin app's splash waits
  only to restore a saved staff session (with the same messages, a retry and
  a way to the sign-in screen). Everything else loads in the background, and
  staff data loads after sign-in, side by side.
- A guest scans the table QR and the server issues a session scoped to that
  table. Guests see only their own orders and bills.
- **Takeaway**: while the restaurant takes takeaway orders (Tables & QR →
  "Take takeaway orders"), guests scan the counter's takeaway code
  (`DINEQR:TAKEAWAY`) or tap **Order takeaway** on the scanner, and order
  without a table; staff ring them up with **New order → Takeaway**. They
  go through the same kitchen, bill and payment flow, and read "Takeaway",
  "Ready for Pickup" and "Collected". Codes printed as `DINEQR:PARCEL` (its
  earlier name) keep working.
- Orders are sent as dishes and options; the server prices them (and refuses
  with "prices changed" if the total differs from what the guest saw).
- A guest's order appears in the admin app, and kitchen and payment changes
  reach both apps live (SignalR), without restarting. While the connection is
  down the apps refresh every 30 seconds and re-read everything after
  reconnecting.
- Payments count only when the server has verified them; the development
  server uses a clearly labelled simulator (no money moves).
- Staff sign in against the server (tokens kept in secure storage); what a
  role may open and do is checked by the server on every request.
- If the server cannot be reached, screens show their error, empty or retry
  states; nothing is invented.

The HTTP implementations live in `packages/dineqr_core/lib/src/api/`; the
contract is in [`docs/BACKEND_INTEGRATION.md`](docs/BACKEND_INTEGRATION.md)
and the API reference in [`backend/README.md`](backend/README.md).

## Customer app (`apps/dineqr_customer`)

| Screen | Folder |
| --- | --- |
| Splash with the smile-logo animation | `lib/features/splash/` |
| QR scanner (camera, torch, gallery, demo codes, Order takeaway) | `lib/features/qr_scanner/` |
| Table (or takeaway) confirmation | `lib/features/table_confirmation/` |
| Home: search, offers, categories, popular and recommended dishes | `lib/features/home/` |
| Menu: category, veg/non-veg, search, sorting | `lib/features/menu/` |
| Dish details: photo gallery, options, add-ons, live price | `lib/features/dish_details/` |
| Cart: remove with undo, instructions, coupons, charges | `lib/features/cart/` |
| Order summary, order placed, tracking, my orders | `lib/features/checkout/`, `order_success/`, `order_tracking/`, `order_history/` |
| Feedback | `lib/features/feedback/` |
| Bill, payment, payment history, receipt preview (PDF, share, print) | `lib/features/billing/` |

### Splash: the DineQR smile

The swoosh under the fork and spoon is the logo's smile. It is a separate
vector path in the real logo (`DineQrMark` in the design system), so it is
animated on its own without redrawing or distorting the logo:

1. The native Android/iOS launch screen shows the white logo on the ember
   background with the smile in a faint, flatter state. The first Flutter
   frame is identical, so there is no blank screen and no second splash.
2. A deep red-to-orange light blooms over the restaurant photo, a soft band
   of light crosses it once, and the edges fall into a gentle vignette.
3. The logo lifts and grows into place on a restrained spring (about 1.5%
   overshoot), sending two faint rings outwards as it lands.
4. The smile draws itself from left to right, deepens into its full curve,
   settles, glows once and catches a small sparkle at its tip. At the end it
   is identical to the static logo.
5. "DineQR" rises with its double-layer red-orange "QR", then
   SCAN • ORDER • ENJOY.
6. The QR emblem beneath them assembles (finder squares, then modules, on a
   frosted tile inside scanner brackets) and a scan line sweeps it while a
   soft glow breathes behind it, until the app moves on. It is decoration:
   a 7 × 7 glyph that cannot be scanned and is announced as "Preparing
   DineQR", never as a QR code.
7. The app fades to the scanner, or straight back to the menu when the
   guest reopens the app within 4 hours of scanning a table (or takeaway)
   that is still open. It moves on after about 2.2 seconds, once the
   restaurant's settings have arrived; if they take long it says so, and if
   the server cannot be reached it offers a retry.

With reduced motion the final composition shows at once and the app moves
on after 0.9 seconds.

### Trying it

- **Camera**: scan a code containing `DINEQR:TABLE:05` (print one from the
  admin app's **Tables & QR**). **No camera**: tap **Use a demo QR code**.
- **Takeaway**: tap **Order takeaway** on the scanner (shown while the
  restaurant takes takeaway orders; the offline demo does), or scan the
  takeaway code (`DINEQR:TAKEAWAY`, also in the demo codes).
- Offers: `WELCOME10` (10% off above ₹300, up to ₹100), `FEAST75` (₹75 off
  above ₹800).
- Payments offer UPI, card, net banking and wallet, all **SIMULATED**, with
  a demo picker for success, failure or cancellation.

## Admin app (`apps/dineqr_admin`)

Opens on an animated splash (`lib/auth/admin_splash_screen.dart`): from
the native launch frame the burgundy backdrop blooms over a faint grid, the
logo scales up inside a red-to-orange halo, "DineQR ADMIN", its accent bar
and "Restaurant management" rise in, and the smile catches a sparkle. The
halo keeps turning while a saved session is restored; then the splash
settles back into the launch frame, which is the sign-in screen's first
frame (two-pane on tablets), or cross-fades into the workspace when the
session was restored. After sign-in each role lands in its own workspace
with its own module order. The navigation is a bottom bar on phones and a
side navigation from 900 px wide.

| Role | Workspace | Lands on | Modules |
| --- | --- | --- | --- |
| Owner | Owner | Dashboard | every module |
| Manager | Operations | Dashboard | Orders, Kitchen, Service, Tables, Menu, Inventory, Bills, Payments, Reports, Activity |
| Cashier | Counter | Bills | Orders (counter POS), Payments, Tables, Dashboard |
| Kitchen staff | Kitchen | Kitchen | Orders, Menu |
| Service staff | Service | Service | Orders, Tables, Bills, Menu |
| Accountant | Finance | Dashboard | Reports, Bills, Payments, Orders, Activity |

| Module | What it does |
| --- | --- |
| Dashboard | Revenue, orders, pending/preparing/completed, average order value, paid/unpaid bills, outstanding, failed payments; today, yesterday, 7 or 30 days; 7-day chart, live orders, top dishes, payment summary, recent activity, alerts |
| Service | Waiters: ready-to-serve queue with "served" action (takeaway: "handed over at the counter", shown whatever the section), kitchen progress, table states, optional "my tables" section |
| Orders | Filters (status, dine-in or takeaway), search, details, status changes, cancel with reason, new order (POS, for a table or takeaway) |
| Kitchen | New / Preparing / Ready / Done lanes, order age, overdue flags, large buttons |
| Bills | Filters, bill detail, counter payments, refunds, reconciliation, receipts |
| Payments | Every payment attempt and refund, filters and search; totals match Reports |
| Menu | Dishes (price, options, add-ons, availability, archive) and categories |
| Tables & QR | Status, QR preview, print or share QR PDFs, add, edit, deactivate; the takeaway QR code and the switch that opens or closes takeaway |
| Reports | Sales, collections, outstanding, refunds, taxes, best sellers, categories, payment methods, tables; CSV and PDF |
| Inventory | Stock, units, reorder levels, adjustments with reasons, low-stock alerts |
| Staff | Accounts, roles, activation, password reset |
| Settings | Restaurant, taxes, service charge, payment methods, time zone, receipt note, offers, menu rules |
| Activity log | Who did what and when |

Permissions are checked in the controllers for every action, not only by
hiding navigation (`StaffRole.permissions` in `dineqr_core`). In production
the server must authorise every request again.

### Staff accounts

In backend mode the first owner is created by the API from its bootstrap
settings (`backend/README.md`), and the owner adds every other account in
**Staff**. There are no built-in accounts.

**Offline demo only** (`DINEQR_MODE=demo`): password `Demo@1234` for all of
these. They exist only on the device and are listed on the demo sign-in
screen.

| Role | Email |
| --- | --- |
| Owner | `owner@dineqr.demo` |
| Manager | `manager@dineqr.demo` |
| Cashier | `cashier@dineqr.demo` |
| Kitchen staff | `kitchen@dineqr.demo` |
| Service staff | `service@dineqr.demo` |
| Accountant | `accounts@dineqr.demo` |

Sessions end after 8 hours; repeated failures lock sign-in for a minute.
"Forgot password?" explains that an owner resets passwords from Staff;
emailed reset links need the server.

## Billing and payments

- Bills copy the order's pricing snapshot; later menu edits never change
  them. Status comes only from payment and refund records.
- Part payments, overpayment refusal, an in-progress lock, idempotency keys,
  and a re-check of interrupted payments when the app opens.
- `PaymentGateway` is the provider seam. The demo uses
  `SimulatedPaymentGateway`; without a provider, online payment shows as
  unavailable. The server-side flow (intent → checkout → signature and
  status verification → webhook) is in the backend document.
- Receipts: PDF (80 mm, A5, A4) with preview, share and the platform print
  dialog. ESC/POS bytes are built, but no thermal printer driver is
  included, so the apps say so instead of pretending to print.

## Design system and motion

`packages/dineqr_design_system`: the official palette (`#B5121B`, `#8E0F17`,
`#D62828`, `#FF6A00`, `#FF8A00`, `#202020`, `#F8F8F8`, `#FFF5F2`, `#248A45`,
`#FFC83D`), Poppins, spacing, radii, shadows, the logo and its double-layer
treatment, motion tokens (`Motion`, `SpringCurve`), loaders, and the shared
widgets and PDFs. Every animation respects the platform's reduce-motion
setting. The admin app adds a burgundy/charcoal operational frame
(`AdminColors`) on top.

## Tests and tools

Each project has its own `test/` folder (`flutter test`). Highlights:
pricing and rounding, offers, QR parsing, checkout and duplicate-submit
protection, billing and refunds, payment-ledger/report consistency, role
permissions and per-role navigation, full guest flow (splash → scan → order
→ track → rate), the takeaway flow (scanner → order → collected) and its
counter version, splash session resume, the splash waiting for (or failing
to reach) the server, the customer app having no staff entry, staff
sign-in, the admin splash's hand-over and retry, the waiter and cashier
workspaces, and a layout sweep of every admin module on a small phone and a
tablet at 1.3× text.

Tools (run with `flutter test <file>` inside an app):

| Tool | Output |
| --- | --- |
| `tool/generate_brand_assets_test.dart` | Launcher icons and native launch images (each app its own) |
| `apps/dineqr_customer/tool/screens_preview_test.dart` | PNG of every customer screen |
| `apps/dineqr_customer/tool/splash_frames_test.dart` | Splash animation frames and a contact sheet |
| `apps/dineqr_customer/tool/smile_sheet_test.dart` | The logo smile at evenly spaced progress values |
| `apps/dineqr_admin/tool/splash_frames_test.dart` | Admin splash frames through the hand-over to sign-in, and a contact sheet |
| `apps/dineqr_admin/tool/admin_preview_test.dart` | PNG of every admin module, phone and tablet |

## Assets and licences

- Food photos: Wikimedia Commons (CC0 / CC BY / CC BY-SA); credits in the
  customer app under **More → Photo Credits** and in
  `packages/dineqr_core/lib/src/demo/image_credits.dart`.
- Poppins: SIL Open Font License (`packages/dineqr_design_system/assets/fonts/OFL.txt`).
- QR codes: `qr` (BSD-3-Clause); PDFs: `pdf`, `printing` (Apache-2.0).
