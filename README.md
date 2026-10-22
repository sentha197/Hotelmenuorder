# DineQR

**Scan • Order • Enjoy.** QR table ordering for restaurants, as two separate
Flutter apps that share one business layer and one design system.

```
apps/
  dineqr_customer/       DineQR (com.dineqr.customer): guests scan, order, track, pay, rate
  dineqr_admin/          DineQR Admin (com.dineqr.admin): staff sign-in and restaurant management
packages/
  dineqr_core/           models, pricing and billing rules, QR parsing, repositories, services, controllers
  dineqr_design_system/  logo (with the animated smile), colours, type, motion, widgets, branded PDFs
docs/
  BACKEND_INTEGRATION.md backend contracts both apps plug into
branding/                logo and app-icon PNG exports
```

The apps are independent Flutter projects: each has its own `main.dart`,
navigation, theme, icons, launch screen, Android application id, iOS bundle
id, `pubspec.lock` and build. They depend on the two packages by path. The
customer app contains no staff screens, staff routes or staff sign-in.

## Running

Requires Flutter 3.44+ / Dart 3.12+.

```bash
cd apps/dineqr_customer
flutter pub get
flutter run                  # Android / iOS
flutter run -d chrome        # web

cd apps/dineqr_admin
flutter pub get
flutter run                  # Android / iOS (phones and tablets)
flutter run -d chrome        # web
```

Checks for everything (bash):

```bash
for p in packages/dineqr_core packages/dineqr_design_system \
         apps/dineqr_customer apps/dineqr_admin; do
  (cd "$p" && flutter pub get && flutter analyze && flutter test)
done
```

## No backend yet: what the demo does

There is **no backend** in this repository. Both apps run in an explicit
offline demo (`AppConfig.demoMode`): data is stored on each device, sample
orders and bills are labelled `SAMPLE`, payments are labelled `SIMULATED`
and no money moves.

Because the apps are separate processes on separate devices, **an order
placed in the customer app does not appear in the admin app** (and staff
status changes do not reach the guest) until a shared backend exists. Each
app has its own demo data; the customer app's tracking screen has a
labelled "Simulate kitchen updates" control instead. Every repository and
service is an interface, so connecting both apps to one server is a matter
of passing HTTP implementations to `CustomerDependencies.create` and
`AdminDependencies.create`. The contracts, including the endpoints that do
not exist yet, are in [`docs/BACKEND_INTEGRATION.md`](docs/BACKEND_INTEGRATION.md).

## Customer app (`apps/dineqr_customer`)

| Screen | Folder |
| --- | --- |
| Splash with the smile-logo animation | `lib/features/splash/` |
| QR scanner (camera, torch, gallery, demo codes) | `lib/features/qr_scanner/` |
| Table confirmation | `lib/features/table_confirmation/` |
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
2. A deep red-to-orange light blooms over the restaurant photo.
3. The logo lifts and grows into place on a restrained spring (about 1.5%
   overshoot).
4. The smile draws itself from left to right, deepens into its full curve,
   settles and glows once. At the end it is identical to the static logo.
5. "DineQR" rises with its double-layer red-orange "QR", then
   SCAN • ORDER • ENJOY.
6. A QR-scanner loader (corner brackets, one scan line) runs until the app
   moves on, about 2.2 seconds in total.
7. The app fades to the scanner, or straight back to the menu when the
   guest reopens the app within 4 hours of scanning a table that is still
   active.

With reduced motion the final composition shows at once and the app moves
on after 0.9 seconds. Start-up errors show a retry screen.

### Trying it

- **Camera**: scan a code containing `DINEQR:TABLE:05` (print one from the
  admin app's **Tables & QR**). **No camera**: tap **Use a demo QR code**.
- Offers: `WELCOME10` (10% off above ₹300, up to ₹100), `FEAST75` (₹75 off
  above ₹800).
- Payments offer UPI, card, net banking and wallet, all **SIMULATED**, with
  a demo picker for success, failure or cancellation.

## Admin app (`apps/dineqr_admin`)

Opens on staff sign-in (with a launch-screen hand-off and a two-pane layout
on tablets). After sign-in each role lands in its own workspace with its
own module order. The navigation is a bottom bar on phones and a side
navigation from 900 px wide.

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
| Service | Waiters: ready-to-serve queue with "served" action, kitchen progress, table states, optional "my tables" section |
| Orders | Filters, search, details, status changes, cancel with reason, new order (POS) |
| Kitchen | New / Preparing / Ready / Done lanes, order age, overdue flags, large buttons |
| Bills | Filters, bill detail, counter payments, refunds, reconciliation, receipts |
| Payments | Every payment attempt and refund, filters and search; totals match Reports |
| Menu | Dishes (price, options, add-ons, availability, archive) and categories |
| Tables & QR | Status, QR preview, print or share QR PDFs, add, edit, deactivate |
| Reports | Sales, collections, outstanding, refunds, taxes, best sellers, categories, payment methods, tables; CSV and PDF |
| Inventory | Stock, units, reorder levels, adjustments with reasons, low-stock alerts |
| Staff | Accounts, roles, activation, password reset |
| Settings | Restaurant, taxes, service charge, payment methods, time zone, receipt note, offers, menu rules |
| Activity log | Who did what and when |

Permissions are checked in the controllers for every action, not only by
hiding navigation (`StaffRole.permissions` in `dineqr_core`). In production
the server must authorise every request again.

### Demo staff accounts (offline demo only)

Password `Demo@1234` for all. They exist only in demo mode and are listed on
the sign-in screen.

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
→ track → rate), splash session resume, the customer app having no staff
entry, staff sign-in, the waiter and cashier workspaces, and a layout sweep
of every admin module on a small phone and a tablet at 1.3× text.

Tools (run with `flutter test <file>` inside an app):

| Tool | Output |
| --- | --- |
| `tool/generate_brand_assets_test.dart` | Launcher icons and native launch images (each app its own) |
| `apps/dineqr_customer/tool/screens_preview_test.dart` | PNG of every customer screen |
| `apps/dineqr_customer/tool/splash_frames_test.dart` | Splash animation frames and a contact sheet |
| `apps/dineqr_customer/tool/smile_sheet_test.dart` | The logo smile at evenly spaced progress values |
| `apps/dineqr_admin/tool/admin_preview_test.dart` | PNG of every admin module, phone and tablet |

## Assets and licences

- Food photos: Wikimedia Commons (CC0 / CC BY / CC BY-SA); credits in the
  customer app under **More → Photo Credits** and in
  `packages/dineqr_core/lib/src/demo/image_credits.dart`.
- Poppins: SIL Open Font License (`packages/dineqr_design_system/assets/fonts/OFL.txt`).
- QR codes: `qr` (BSD-3-Clause); PDFs: `pdf`, `printing` (Apache-2.0).
