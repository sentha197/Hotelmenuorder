# DineQR

**Scan • Order • Enjoy.** A QR-based restaurant ordering app built with Flutter, in three connected parts:

1. **Guest app**: scan the table QR, browse the menu, customise dishes, apply offers, order, track, view the bill, pay and rate.
2. **Staff dashboard**: a separate, signed-in area for owners, managers, cashiers, kitchen, service staff and accountants.
3. **Billing and payments**: bills for every order, part or full payments, refunds, PDF receipts and payment history.

Everything runs in an **offline demo**: no backend is needed. Orders, bills, payments and staff accounts are stored on the device, payments are **simulated** (no money moves), and sample data is labelled as such. The contracts a real backend must implement are in [`docs/BACKEND_INTEGRATION.md`](docs/BACKEND_INTEGRATION.md).

## Running the app

```bash
flutter pub get
flutter run                          # guest app on Android or iOS
flutter run -d chrome                # guest app in the browser
flutter run -t lib/main_admin.dart   # staff dashboard as its own app
```

Requires Flutter 3.44+ / Dart 3.12+. The Dart package is still named `menu_order`; the app is labelled **DineQR** on Android, iOS and the web.

### Opening the staff dashboard

The guest app has no visible admin button or menu item. Staff use one of:

- the separate entry point `lib/main_admin.dart` (opens straight to staff sign-in, with no guest screens underneath);
- the `/admin` route on the web build (for example `http://localhost:<port>/#/admin`);
- in the **demo build only**, a long press on the version line in **More → About this demo**.

Every route still requires signing in, and every staff action checks the role's permission in the controller, not just in the UI. With a real backend the server must authorise each request too.

### Demo staff accounts (offline demo only)

All demo accounts use the password `Demo@1234`. They exist only in demo mode and are created on the device; the sign-in screen lists them.

| Role | Email |
| --- | --- |
| Owner | `owner@dineqr.demo` |
| Manager | `manager@dineqr.demo` |
| Cashier | `cashier@dineqr.demo` |
| Kitchen staff | `kitchen@dineqr.demo` |
| Service staff | `service@dineqr.demo` |
| Accountant | `accounts@dineqr.demo` |

Sessions end after 8 hours, and repeated failures lock sign-in for a minute.

### Trying the QR flow

- **Real camera** (Android, iOS, web): scan a code whose content is `DINEQR:TABLE:05`. Scans are checked against the restaurant's configured tables (30 by default; staff can add, edit or deactivate tables). Codes printed before the rename (`BITEANDDINE:TABLE:05`) still work. To get scannable codes, open **More → Demo QR Codes** on another device, or print them from **Tables & QR** in the staff dashboard.
- **No camera / no code**: tap **Use a demo QR code** on the scanner. Demo payloads go through the same validation, including an invalid code and an unknown table.
- **Flashlight** and **Scan from photos** work on Android and iOS.

### Demo behaviour

- Placing an order takes a short simulated delay and creates IDs `#OD12345`, `#OD12346`, … The confirmation says the order was **not sent to a real kitchen**.
- Orders move through Placed → Accepted → Preparing → Ready → Served. Staff move them from **Orders** or **Kitchen**; on the guest's **Order Tracking** screen, a clearly labelled *Simulate kitchen updates* card does the same. When an order is served the rating sheet opens.
- Offers: `WELCOME10` (10% off above ₹300, up to ₹100) and `FEAST75` (₹75 off above ₹800). Apply them from **Home → Offers for You** or the cart. Staff can edit offers in **Settings**.
- Payments: the **Pay** screen offers UPI, card, net banking and wallet, all marked **SIMULATED**, and a *Simulated result* picker (success, failure, cancelled) to try every outcome.
- Sample orders and bills from the last two weeks fill the dashboard and reports. They are flagged `SAMPLE`, and reports can exclude them.
- **More → Reset Demo Data** clears the cart, favourites and ratings and restores the sample orders and bills. Owners can reset everything (menu, settings, staff, stock) from **Settings**.

## Guest screens

| # | Screen | Location |
|---|---|---|
| 1 | Splash | `lib/features/splash/` |
| 2 | Scan QR code | `lib/features/qr_scanner/` |
| 3 | Table confirmation | `lib/features/table_confirmation/` |
| 4 | Home: categories, offers, popular and recommended dishes | `lib/features/home/` |
| 5 | Menu: categories, veg filter, search, sorting, sold-out dishes | `lib/features/menu/` |
| 6 | Dish details | `lib/features/dish_details/` |
| 7 | Cart: coupons, charges, sold-out handling | `lib/features/cart/` |
| 8 | Order summary | `lib/features/checkout/` |
| 9 | Order placed | `lib/features/order_success/` |
| 10 | Order tracking | `lib/features/order_tracking/` |
| 11 | My orders (+ details) | `lib/features/order_history/` |
| 12 | Rate your experience | `lib/features/feedback/` |
| | Bill, payment, receipt preview, bills and payments history | `lib/features/billing/` |

The **More** tab (`lib/features/more/`) contains the table switcher, favourites, bills and payments, demo tools and photo credits.

## Billing and payments

- **Bills** (`Invoice`) are created for every order and copy its pricing snapshot, so later menu or price changes never alter them. Bill numbers look like `DQ-2026-00012`.
- **Status comes only from payment and refund records**, never from the order status: Unpaid, Payment pending, Partially paid, Paid, Payment failed, Partly refunded, Refunded, Void.
- **Part payments** (if the restaurant allows them) leave a balance; paying more than the balance is refused. A payment is recorded as pending *before* the provider is called, has an idempotency key, and a second payment cannot start while one is in progress. Interrupted payments are re-checked when the app opens.
- **Payment providers** sit behind `PaymentGateway`. The demo uses `SimulatedPaymentGateway`; without a configured provider, online payment is shown as unavailable. The secure server-side flow for a real provider (Razorpay as an example) is in the backend document.
- **Receipts**: PDF receipts (80 mm roll, A5 or A4) with a preview, sharing and printing through the platform's print service. Thermal printers sit behind `ThermalPrinter`; ESC/POS bytes are already built (`EscPosReceipt`), but no printer driver is included, so the app says "No thermal printer connected" instead of pretending to print.
- Demo bills carry a notice that payments are simulated or that the bill is a sample. Tax registration numbers and addresses appear only when the restaurant sets them.

## Staff dashboard

`lib/admin/`, with its own navigation: a bottom bar plus **More** on phones, and a side rail on tablets and desktop.

| Module | What it does | Needs |
| --- | --- | --- |
| Dashboard | Revenue, order and bill metrics with trends, 7-day chart, live orders, low-stock alerts | view dashboard |
| Orders | Filters, search, details, status changes, cancel with reason, staff-entered orders | view orders |
| Kitchen | Large New / Preparing / Ready lanes with order age and overdue flags | kitchen |
| Bills | Filters (date, status, method, search), bill detail, counter payments, refunds, reconciliation, receipts | view bills |
| Menu | Dishes (add, edit, price, options, availability, archive) and categories (order, enable, delete when empty) | view / manage menu |
| Tables & QR | Status, QR preview, print or share QR PDFs, add, edit, deactivate | view / manage tables |
| Reports | Today, yesterday, 7 days, 30 days or a custom range; sales breakdown with definitions, best sellers, categories, payment methods, taxes, outstanding bills, refunds, table use; CSV and PDF export with the same figures | view reports (+ financials, export) |
| Inventory | Stock, units, reorder levels, adjustments with reasons, optional auto sold-out for linked dishes | manage inventory |
| Staff | Accounts, roles, activation, password reset | manage staff |
| Settings | Restaurant details, taxes, service charge, payment methods, time zone, receipt note, offers, menu rules | manage settings |
| Activity log | Who did what and when, for sensitive actions | view audit log |

Roles and their permissions are defined in `lib/data/models/staff.dart` and listed in the backend document.

## Launch and splash

The native launch screens (Android, Android 12+ and iOS) show the white DineQR symbol, 120 points wide, centred on the dark ember background. The Flutter splash's first frame is identical, then the symbol lifts and grows while the photo, glow, wordmark, tagline and QR loader appear, and the app moves to the scanner after about 2.2 seconds. If start-up fails, a retry screen is shown instead of a stuck splash.

## Brand system

All colours, the logo and the motion language live in shared code; screens never define their own.

- **Colours** (`lib/app/theme/app_colors.dart`): Primary Red `#B5121B`, Deep Red `#8E0F17`, Accent Red `#D62828`, Vibrant Orange `#FF6A00`, Warm Orange `#FF8A00`, Charcoal `#202020`, Soft White `#F8F8F8`, Pale Warm `#FFF5F2`, Success `#248A45`, Rating Gold `#FFC83D`, plus the shared gradients.
- **Logo** (`lib/core/brand/dineqr_logo.dart`): the chef-hat / fork / spoon / QR symbol drawn as vector paths (`DineQrMark`) in colour, inverted (white) and mono tones. Also `DineQrWordmark` (layered red-orange "QR"), `DineQrTagline`, `DineQrLockup` and `DineQrAppIcon`. The symbol is a vector redraw of the supplied brand sheet; if you have the original vector artwork, compare and adjust the paths in `_MarkGeometry`.
- **Double-layer treatment**: a deep red base offset under a red-to-orange gradient face, used on the logo, the "QR" of the wordmark, primary buttons, hero numbers and success emblems.
- **Motion** (`lib/core/animations/`): shared durations and curves (`Motion`), entrance and press helpers, contextual loaders (`QrAssembleLoader`, `QrPulseLoader`, `BrandShimmer`, `BrandProgressBar`) and one-shot effects. Every animation respects the platform's reduce-motion setting.

### Icons, launch images and screenshots

Launcher icons, native launch images and the PNG exports in `branding/` are generated from the vector logo:

```bash
flutter test tool/generate_brand_assets_test.dart
```

Screenshot walkthroughs for visual review (`--dart-define=OUT=<dir>` to choose the folder):

```bash
flutter test tool/screens_preview_test.dart   # guest app, phone size
flutter test tool/admin_preview_test.dart     # staff dashboard, phone and tablet
```

## Architecture

```
lib/
  app/        app widget, routes + navigation, dependency wiring, theme
  admin/      staff dashboard: sign-in, shell, one folder per module
  core/       brand, animations, formatting (money, restaurant time), widgets
  data/       models, demo data, repositories, services (auth, payments,
              reports, receipts, exports, printing), key-value storage
  state/      ChangeNotifier controllers
  features/   guest screens, one folder per screen
docs/         backend integration contracts
tool/         asset generation and screenshot walkthroughs (flutter test)
branding/     generated logo and app-icon PNGs
```

- **State:** `provider` with one controller per concern: session, catalog, cart, orders, billing, settings, admin session, staff, inventory.
- **One source of truth on the device:** guest and staff screens share the same controllers, so a staff status change appears in the guest's tracking at once, and menu edits reach the guest menu. Separate devices would need the backend.
- **Money:** integer paise (`Money`). One formula for every bill: discount (never above the subtotal), then service charge, then tax, each rounded half-up to the paisa.
- **Time:** the restaurant's time zone (a UTC offset in Settings) is used for "today", report ranges, bill numbers and every displayed date.
- **Reports:** `SalesReport.build` computes every figure once; the dashboard, the report screen and the CSV/PDF exports all read the same object.
- **Backend:** every repository and service is an interface passed to `AppDependencies.create`. See [`docs/BACKEND_INTEGRATION.md`](docs/BACKEND_INTEGRATION.md) for the endpoints, the payment flow and the changes the billing controller needs.

## Tests

```bash
flutter analyze
flutter test
```

- **Guest app:** QR parsing and table validation, cart and customisation, pricing and rounding, offers, sold-out dishes, checkout validation, duplicate-submit protection, order status flow, feedback, persistence, and full widget walkthroughs (splash → scan → order → track → rate, menu filters, invalid codes).
- **Billing:** bill snapshots and numbering, invoice statuses, full and part payments, overpayment, in-progress lock, failed and cancelled payments, interrupted payments, idempotency, counter payments, refunds and their limits, audit entries, ESC/POS receipt text, and widget tests of a successful and a declined simulated payment.
- **Staff:** sign-in, wrong passwords, lockout, inactive accounts, session restore and expiry, role permissions, navigation per role, order status permissions, menu and category rules, staff rules, date ranges, report figures (collections exclude pending and failed payments) and CSV export consistency.
- **Layout:** every staff module is opened and scrolled on a small phone and a tablet, with the real font at the largest text size the app allows, and any overflow fails the test.

## Limitations

- No backend: data lives on one device. Multi-device sync, real-time updates and server-side authorisation need the backend described in `docs/BACKEND_INTEGRATION.md`.
- No real payment provider is connected; payments in the demo are simulated.
- No thermal printer driver; PDF receipts print through the platform's print service.
- Demo staff sign-in is checked on the device; production sign-in must be done by a server.

## Assets and licenses

- **Food photos:** from Wikimedia Commons (CC0 / CC BY / CC BY-SA). Authors and licenses are listed in the app under **More → Photo Credits** and in `lib/data/demo/image_credits.dart`.
- **Typeface:** Poppins, bundled under the SIL Open Font License (`assets/fonts/OFL.txt`).
- **QR codes:** generated with the `qr` package (BSD-3-Clause); PDFs with `pdf` and `printing` (Apache-2.0).
