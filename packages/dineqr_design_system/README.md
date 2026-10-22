# dineqr_design_system

The DineQR look and feel, shared by the customer app and the admin app.

| Folder | Contents |
| --- | --- |
| `lib/src/theme/` | `AppColors` (the official palette and gradients), `AppTypography`, `AppSpacing`, `AppRadii`, `AppShadows`, `AppTheme` |
| `lib/src/brand/` | The DineQR logo as vector paths (`DineQrMark`, with the animatable smile), wordmark, tagline, lockup, app icon, brand surfaces |
| `lib/src/motion/` | Motion tokens (`Motion`, `SpringCurve`), entrance and press helpers, loaders (`QrScanLoader`, `QrPulseLoader`, `BrandShimmer`, …) and one-shot effects |
| `lib/src/widgets/` | Buttons, dialogs, state views, food and order widgets, the invoice view, table QR codes |
| `lib/src/documents/` | Branded PDFs (receipts, reports, QR sheets), the receipt preview, print and share helpers |
| `assets/fonts/` | Poppins (SIL Open Font License, `assets/fonts/OFL.txt`) |

Import everything through
`package:dineqr_design_system/dineqr_design_system.dart`. The font family is
`AppTypography.fontFamily` (`packages/dineqr_design_system/Poppins`).

## The logo smile

The red-to-orange swoosh under the fork and spoon is the logo's smile. It is
its own vector path, so `DineQrMark(smile: t)` can animate it without
touching the rest of the logo: at 0 it is a faint, flatter curve (the
customer app's launch screen shows this state), it then draws itself from
left to right, deepens into its full curve on a soft spring and settles; at
1 it is identical to the static logo. `smileGlow` adds a warm glow beneath
it.

## Motion rules

- Use `Motion` durations and curves; `Motion.of(context, …)` returns zero
  when the platform asks for reduced motion.
- `Motion.spring` (about 1.5% overshoot) for brand moments, never a bounce.
- One effect at a time; nothing animates forever without a purpose.

## Tests

```bash
flutter test
```
