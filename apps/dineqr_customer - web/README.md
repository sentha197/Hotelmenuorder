# DineQR (customer app)

The guest app (`com.dineqr.customer`): scan the table QR code, browse the
menu, order, track, pay and rate. A separate Flutter project from the admin
app; it shares only
[`dineqr_core`](../../packages/dineqr_core) and
[`dineqr_design_system`](../../packages/dineqr_design_system). It has no
staff screens, routes or sign-in of any kind.

```bash
flutter pub get
flutter run                 # Android / iOS
flutter run -d chrome       # web
flutter test
```

See the [workspace README](../../README.md) for the splash animation, demo
behaviour and the backend status.

| Folder | Contents |
| --- | --- |
| `lib/main.dart` | Entry point (portrait) |
| `lib/app/` | App widget, routes, dependency wiring (`CustomerDependencies`) |
| `lib/features/` | One folder per screen: splash, scanner, table confirmation, home, menu, dish details, cart, checkout, order placed, tracking, orders, feedback, billing, more |
| `lib/state/` | Guest table session (resumes within 4 hours) and tab state |
| `assets/images/splash_bg.jpg` | Splash and scanner backdrop (menu photos live in `dineqr_core`) |
| `tool/` | Icon and launch-image generator, screenshot and splash-frame tools |
