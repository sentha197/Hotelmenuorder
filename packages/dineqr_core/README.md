# dineqr_core

The shared business layer of DineQR, used by both the customer app and the
admin app. No widgets and no navigation live here.

| Folder | Contents |
| --- | --- |
| `lib/src/models/` | Typed models with JSON: menu, cart, orders, bills, payments, refunds, settings, staff and permissions, inventory |
| `lib/src/utils/` | `Money` (integer paise), currency and date formatting, restaurant time zone and date ranges, ids |
| `lib/src/qr/` | `TableQrParser`: the `DINEQR:TABLE:NN` payload, validated against configured tables |
| `lib/src/repositories/` | Repository interfaces (the backend seams) with local demo implementations |
| `lib/src/services/` | Auth, payment gateway, `SalesReport`, `PaymentLedger`, CSV export, ESC/POS receipt bytes |
| `lib/src/state/` | `ChangeNotifier` controllers both apps use (catalog, cart, orders, billing, settings) and the `AccessGuard` / `AuditLog` contract |
| `lib/src/runtime/` | `DineQrServices`: wires settings, menu, orders and bills to one set of repositories |
| `lib/src/demo/` | Demo menu, sample orders and bills, photo credits, `DineQrAssets` |
| `assets/images/` | Demo menu photos (credits in `lib/src/demo/image_credits.dart`) |
| `lib/testing.dart` | Test helpers (`FakeGuard`, `placeTestOrder`, …) shared by the apps' tests |

Import everything through `package:dineqr_core/dineqr_core.dart`.

## Rules that live here

- **Money** is integer paise. Every bill uses one formula: discount (never
  above the subtotal), then service charge, then tax, each rounded half-up.
- **Bills copy the order's pricing snapshot**, so later menu or price edits
  never change a placed order or its bill.
- **Bill status comes only from payment and refund records.** Pending,
  failed and cancelled payments never count as collected.
- **Reports and the payment ledger share definitions** (`SalesReport`,
  `PaymentLedger`), so the dashboard, reports, exports and payment history
  always agree. `test/payment_ledger_test.dart` checks this.
- **Privileged actions call `AccessGuard.require`** in the controller, not
  only in the UI. The customer app uses `GuestAccess`, which refuses them
  all. A real backend must authorise every request again on the server.

## Tests

```bash
flutter test
```
