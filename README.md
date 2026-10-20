# DineQR

**Scan • Order • Enjoy.** A QR-based restaurant ordering app built with Flutter. A guest scans the QR code on their table, browses the menu, customizes dishes, places an order, tracks it, and rates it.

The app runs fully offline with static demo data. No backend is needed: orders, kitchen updates, and ratings are simulated and saved on the device.

## Running the app

```bash
flutter pub get
flutter run            # Android or iOS device/emulator
flutter run -d chrome  # quick preview in the browser
```

Requires Flutter 3.44+ / Dart 3.12+. The Dart package is still named `menu_order`; the app is labelled **DineQR** on Android, iOS and the web.

### Trying the QR flow

- **Real camera** (Android, iOS, web): scan a code whose content is `DINEQR:TABLE:05` (tables 1–30 are valid). Codes printed before the rename (`BITEANDDINE:TABLE:05`) are still accepted. To get scannable codes, open **More → Demo QR Codes** on another device; they are generated live and carry the DineQR symbol.
- **No camera / no code**: tap **Use a demo QR code** on the scanner, or tap the table card shown in the frame. Demo payloads go through the same validation as camera scans, and the list includes an invalid code and an unknown table so you can see the error handling.
- **Flashlight** and **Scan from photos** work on Android and iOS.

### Demo behaviour

- Placing an order takes a short simulated delay and creates IDs `#OD12345`, `#OD12346`, …
- On **Order Tracking**, the *Simulate kitchen updates* card moves the order through Placed → Preparing → Ready → Served. When it reaches Served, the rating sheet opens.
- **Past Orders** includes two sample orders, labelled `SAMPLE`.
- **More → Reset Demo Data** clears the cart, favorites, ratings, and orders.

## Screens

| # | Screen | Location |
|---|---|---|
| 1 | Splash | `lib/features/splash/` |
| 2 | Scan QR code | `lib/features/qr_scanner/` |
| 3 | Table confirmation | `lib/features/table_confirmation/` |
| 4 | Home / categories | `lib/features/home/` |
| 5 | Category items / menu | `lib/features/menu/` |
| 6 | Dish details | `lib/features/dish_details/` |
| 7 | Cart | `lib/features/cart/` |
| 8 | Order summary | `lib/features/checkout/` |
| 9 | Order placed | `lib/features/order_success/` |
| 10 | Order tracking | `lib/features/order_tracking/` |
| 11 | My orders (+ details) | `lib/features/order_history/` |
| 12 | Rate your experience | `lib/features/feedback/` |

The **More** tab (`lib/features/more/`) contains the table switcher, favorites, demo tools, and photo credits.

## Brand system

All colours, the logo and the motion language live in shared code; screens never define their own.

- **Colours** (`lib/app/theme/app_colors.dart`): Primary Red `#B5121B`, Deep Red `#8E0F17`, Accent Red `#D62828`, Vibrant Orange `#FF6A00`, Warm Orange `#FF8A00`, Charcoal `#202020`, Soft White `#F8F8F8`, Pale Warm `#FFF5F2`, Success `#248A45`, Rating Gold `#FFC83D`, plus the shared gradients.
- **Logo** (`lib/core/brand/dineqr_logo.dart`): the chef-hat / fork / spoon / QR symbol is drawn as vector paths (`DineQrMark`) in colour, inverted (white) and mono tones, with an animated reveal for the splash. Also `DineQrWordmark` (layered red-orange "QR"), `DineQrTagline`, `DineQrLockup` and `DineQrAppIcon`. The symbol is a vector redraw of the supplied brand sheet; if you have the original vector artwork, compare and adjust the paths in `_MarkGeometry`.
- **Double-layer treatment**: a deep red base offset under a red-to-orange gradient face. Used on the logo, the "QR" of the wordmark, primary buttons, hero numbers and success emblems, not on every card.
- **Motion** (`lib/core/animations/`): shared durations and curves (`Motion`), entrance and press helpers, contextual loaders (`QrAssembleLoader` on the splash, `QrPulseLoader` in buttons, `BrandShimmer` skeletons, `BrandProgressBar`) and one-shot effects (`SuccessEmblem`, `FavoriteBurst`, `AnimatedStarRating`, `WipeReveal`). Every animation respects the platform's reduce-motion setting, and repeating ones only run while their state is on screen.

### Icons and brand exports

Launcher icons (Android legacy + adaptive with a themed-icon layer, iOS, web) and the PNG exports in `branding/` are generated from the vector logo:

```bash
flutter test tool/generate_brand_assets_test.dart
```

`tool/screens_preview_test.dart` walks the whole app at phone size and saves a screenshot of every screen (`--dart-define=OUT=<dir>`).

## Architecture

```
lib/
  app/        app widget, routes + navigation helpers, dependency wiring, theme
  core/       brand (logo, surfaces), animations (motion tokens, loaders,
              effects), currency and date formatting, shared widgets
  data/       models, demo menu, repositories, key-value storage
  state/      ChangeNotifier controllers (session, catalog, cart, orders, shell)
  features/   one folder per screen
tool/         asset generation and screenshot harnesses (run with flutter test)
branding/     generated logo and app-icon PNGs (transparent)
```

- **State management:** `provider` with one controller per concern. Each one is the single source of truth for its state: table session, menu and favorites, cart, order history (including status and ratings), and the selected tab.
- **Money:** amounts are integer paise (`Money`). Tax is half-up rounded. Every screen uses the same `BillBreakdown` and `CurrencyFormatter`, so totals always match (₹, Indian digit grouping).
- **Orders:** at checkout, each order snapshots its lines, prices, tax, instructions, and table. Later menu or cart changes never alter order history.
- **Persistence:** the table, cart, favorites, and orders are saved with `shared_preferences` and survive restarts.
- **Swapping in a real backend:** implement `MenuRepository` and `OrderRepository` against your API and pass them to `AppDependencies.create`. The UI doesn't need to change.

## Tests

```bash
flutter analyze
flutter test
```

- **Unit tests** cover: QR parsing and validation (including legacy codes); cart add, merge, split, quantity, remove, undo, and clear; pricing and rounding; checkout validation; order ID generation; snapshot immutability; duplicate-submit protection; status transitions; feedback validation; and persistence.
- **Widget tests** drive the full flow on a phone-sized screen: splash → demo scan → welcome → home → dish details → cart → summary → order placed → tracking → feedback → order history. They also cover invalid QR codes, menu filters, clearing the cart, the brand widgets in every tone, QR generation for every table, loaders replacing spinners, reduced motion on the splash, and that Home settles with no animation left running.

## Assets and licenses

- **Food photos:** from Wikimedia Commons (CC0 / CC BY / CC BY-SA). Authors and licenses are listed in the app under **More → Photo Credits** and in `lib/data/demo/image_credits.dart`.
- **Typeface:** Poppins, bundled under the SIL Open Font License (`assets/fonts/OFL.txt`).
- **QR codes:** generated with the `qr` package (BSD-3-Clause).
