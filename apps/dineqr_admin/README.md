# DineQR Admin

The restaurant staff and management app (`com.dineqr.admin`). A separate
Flutter project from the customer app, with its own entry point, sign-in,
navigation, theme, icons and launch screen. It shares only
[`dineqr_core`](../../packages/dineqr_core) and
[`dineqr_design_system`](../../packages/dineqr_design_system) with the
customer app.

```bash
flutter pub get
flutter run                 # Android / iOS
flutter run -d chrome       # web
flutter test
```

See the [workspace README](../../README.md) for demo accounts, roles,
modules and the backend status.

| Folder | Contents |
| --- | --- |
| `lib/main.dart` | Entry point |
| `lib/app/` | App widget, dependency wiring (`AdminDependencies`), admin theme |
| `lib/auth/` | Sign-in screen and the gate (sign-in until a valid session, then the workspace) |
| `lib/shell/` | Workspace frame, modules and per-role navigation (`AdminModule.forRole`) |
| `lib/modules/` | One folder per module: dashboard, service, orders, kitchen, bills, payments, menu, tables, reports, inventory, staff, settings, activity |
| `lib/state/` | Staff session (the `AccessGuard`), staff, inventory, waiter sections |
| `lib/brand/` | Admin app icon and lockup |
| `tool/` | Icon and launch-image generator, screenshot walkthrough |
