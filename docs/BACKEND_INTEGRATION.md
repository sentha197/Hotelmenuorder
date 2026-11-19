# DineQR backend integration

DineQR is two Flutter apps, **DineQR** (customer, `apps/dineqr_customer`)
and **DineQR Admin** (staff, `apps/dineqr_admin`), sharing one business
layer (`packages/dineqr_core`), and the **DineQR API** (`backend/`,
ASP.NET Core + PostgreSQL) that connects them.

## Implementation status

The API implements this contract under `/api/v1`, and both apps use it in
backend mode (`--dart-define=DINEQR_API_URL=…`); the offline demo runs only
when built with `--dart-define=DINEQR_MODE=demo`. The authoritative API
reference, with setup, is [`backend/README.md`](../backend/README.md).
Where the implementation differs from the original contract below:

| Contract below | Implemented as |
| --- | --- |
| `POST`/`PUT /admin/menu/items` | `PUT /admin/menu/items/{id}` creates or replaces; `PATCH` for availability and archiving |
| Category `POST`/`PUT`/`PATCH`/`DELETE`, `PUT …/order` | `PUT /admin/menu/categories` with the whole ordered list (same rules) |
| Table `POST`/`PATCH`/`DELETE` | `PUT /admin/tables` with the whole list (removal refused while a table has open orders or unpaid bills); public `GET /tables` |
| Online payments (`/payments/intents`, `/payments/{id}/confirm`, `GET /payments/{id}`, reconcile, `GET /admin/payments`, webhooks) | **Retired.** DineQR takes no payment online: guests pay at the billing counter and staff record it with `POST /admin/bills/{id}/payments` (see "Bills, counter payments and refunds" below) |
| `POST /admin/staff/{id}/password-reset` | `POST /admin/staff/{id}/password` (sets a new password; ends that person's sessions) |
| `GET /admin/reports` | `GET /admin/reports/summary?from=&to=`; the admin screens still compute reports from the orders and bills they load (90 days plus open ones) |
| `GET /admin/service-sections` | Not built: waiter sections are still per device. Tables carry an optional server assignment instead |
| (not in the original contract) | Takeaway: `DINEQR:TAKEAWAY` sessions, `orderType` on orders, the `takeaway` setting (see "Takeaway" below) |
| (not in the original contract) | The restaurant's currency, fixed once bills exist |

Payments are taken at the billing counter only (no online payment, gateway
or UPI flow; these were built and then retired, and their history is kept).
Money is integer minor units ("paise") in JSON (stored as
`numeric(14,2)`), in the restaurant's currency; times are UTC.

The rest of this document is the original contract and the reasoning behind
it.

## Two apps, one backend

The apps are separate processes, usually on separate devices. They never
share memory or local storage, so in the offline demo **a guest's order does
not reach the admin app**, and staff status changes do not reach the guest.
Only a shared backend connects them. With one, these rules must hold:

1. Orders placed by guests are visible to authorised staff in real time.
2. Staff status changes update the guest's tracking screen in real time.
3. Menu, availability and settings changes reach the customer app.
4. Placed orders keep their own line prices; menu edits never change them.
5. Every bill is priced by the server with one formula (the one in
   `dineqr_core`: discount, then service charge, then tax, half-up).
6. Every payment and refund references its bill and order.
7. Dashboard, reports and exports derive from the same payment and refund
   records (`SalesReport` defines them).
8. Every privileged operation is authorised by the server.

## Ground rules

1. **The server is the source of truth.** The app displays what the server
   returns. Client-side checks (permissions, validation, totals) are for user
   experience only.
2. **Every privileged request is authorised on the server**: a valid staff
   session *and* the role permission for that action (table below). Hiding a
   button in the app is not security.
3. **Prices are computed on the server.** Orders are submitted as item ids,
   quantities and options; the server prices them from its own menu, tax,
   service-charge and offer configuration and returns the bill snapshot.
4. **No secrets in the app.** Admin credentials live only on the server.
5. **No payment in the app.** Guests never pay through DineQR; a bill is
   paid only when staff record the payment taken at the billing counter.
6. **A table QR identifies an ordering context only** (`DINEQR:TABLE:05`). It
   grants no staff access. The server re-checks that the table exists and is
   active when an order is submitted.
7. **Idempotency.** Order submission, counter payments and refunds carry an
   idempotency key; replays return the original result.
8. **Money** is integer paise (`₹1 = 100`), currency `INR`. **Time** is UTC
   ISO-8601 on the wire; the restaurant's UTC offset comes from settings and
   is used for "today" and report ranges.

## Where the apps plug in

Both apps build the shared services with `DineQrServices.create`
(`packages/dineqr_core/lib/src/runtime/dineqr_services.dart`), through their
own composition roots:

- customer: `CustomerDependencies.create`
  (`apps/dineqr_customer/lib/app/dependencies.dart`), with `GuestAccess` as
  the access guard (every privileged action is refused);
- admin: `AdminDependencies.create`
  (`apps/dineqr_admin/lib/app/dependencies.dart`), with the signed-in staff
  session (`AdminSessionController`) as the access guard.

Paths below are relative to `packages/dineqr_core/lib/src/`.

| Interface (file) | Used by | Demo implementation | Production work |
| --- | --- | --- | --- |
| `AuthService` (`services/auth_service.dart`) | admin | `DemoAuthService`: local accounts, salted SHA-256, lockout | HTTP client for `/auth/*`; tokens in secure storage |
| `MenuRepository` (`repositories/menu_repository.dart`) | both | `DemoMenuRepository` | `/menu`, `/admin/menu/*` |
| `OrderRepository` (`repositories/order_repository.dart`) | both | `LocalOrderRepository` | `/orders`, `/admin/orders/*`, live updates |
| `SettingsRepository` (`repositories/settings_repository.dart`) | both | `LocalSettingsRepository` (settings and tables) | `/settings`, `/admin/settings`, `/admin/tables` |
| `BillingRepository` (`repositories/billing_repository.dart`) | both | `LocalBillingRepository` | `/bills/*`, `/admin/bills/*` (read-mostly, see below) |
| `StaffRepository` (`repositories/staff_repository.dart`) | admin | `LocalStaffRepository` (accounts and audit log) | `/admin/staff/*`, `/admin/audit` |
| `InventoryRepository` (`repositories/inventory_repository.dart`) | admin | `LocalInventoryRepository` | `/admin/inventory/*` |
| `ThermalPrinter` (`services/thermal_printer.dart`) | both | `UnavailableThermalPrinter` | Platform plugin for the chosen printer (Bluetooth/USB/LAN); `EscPosReceipt.encode` already builds the bytes |
| Reports (`services/report_service.dart`) | admin | `SalesReport.build` over local data | `/admin/reports` with the same definitions |
| Waiter sections (`apps/dineqr_admin/lib/state/service_section_controller.dart`) | admin | Saved on the device per staff member | Optional `/admin/service-sections` (below) |

A production build passes `AppConfig(demoMode: false)` (customer:
`CustomerConfig(demoMode: false)`) and the HTTP implementations. With
`demoMode: false` the apps hide demo tools and seed no sample data or demo
accounts.

Menu photos: `MenuItem.image` and the optional `MenuItem.gallery` may be
`https://` URLs; the apps load them over the network (bundled demo photos
use `assets/images/…` paths).

## Authentication

| Method and path | Body | Returns |
| --- | --- | --- |
| `POST /auth/login` | `{email, password}` | `{accessToken, refreshToken, expiresAt, staff: {id, name, email, role, permissions[]}}` |
| `POST /auth/refresh` | `{refreshToken}` | new token pair |
| `POST /auth/logout` | | revokes the refresh token |
| `GET /auth/me` | | the staff profile and permissions |

- Passwords are hashed server-side with Argon2id or bcrypt. The demo's
  iterated SHA-256 is for the offline demo only.
- Rate limiting and lockout are enforced server-side. Errors are generic
  ("incorrect email or password") so they do not reveal which emails exist.
- Access tokens are short-lived (for example 15 minutes). Sessions end after
  inactivity or 8 hours; the app already signs out on expiry.
- Store tokens with platform secure storage, not `shared_preferences`.

### Guest sessions (customer app, missing contract)

The customer app has no account or login. Today a "guest session" is the
table stored on the device after a valid scan (resumed for 4 hours). The
server needs an explicit, table-scoped guest session so a guest can only
read and pay their own table's orders:

| Method and path | Body | Returns |
| --- | --- | --- |
| `POST /guest/sessions` | `{qrPayload}` (e.g. `DINEQR:TABLE:05`, ideally with an opaque per-table token) | `{guestToken, tableNumber, expiresAt}`; an error when the table is unknown or inactive |

The `guestToken` is sent with the `/orders` calls
below. It grants no staff permission of any kind.

## Roles and permissions

The server holds the authoritative matrix. The app mirrors it in
`StaffRole` / `Permission` (`packages/dineqr_core/lib/src/models/staff.dart`)
to shape the UI and to check every action in the controllers. Which modules
a role sees, in which order, and where it lands after sign-in is
presentation only (`AdminModule.forRole`, `StaffRoleWorkspace` in the admin
app).

| Permission | Owner | Manager | Cashier | Kitchen | Waiter | Accountant |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| viewDashboard | ✓ | ✓ | ✓ | | | ✓ |
| viewFinancials | ✓ | | | | | ✓ |
| viewOrders | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| createOrders (incl. the cashier's counter POS) | ✓ | ✓ | ✓ | | ✓ | |
| manageKitchen (accept, preparing, ready) | ✓ | ✓ | | ✓ | | |
| serveOrders | ✓ | ✓ | | | ✓ | |
| cancelOrders | ✓ | ✓ | | | | |
| viewMenu | ✓ | ✓ | | ✓ | ✓ | |
| manageMenu / manageCategories | ✓ | ✓ | | | | |
| manageOffers (special offers, combos, coupons) | ✓ | ✓ | | | | |
| viewTables | ✓ | ✓ | ✓ | | ✓ | |
| manageTables | ✓ | ✓ | | | | |
| viewBills | ✓ | ✓ | ✓ | | ✓ | ✓ |
| collectPayments (record counter payments) | ✓ | ✓ | ✓ | | | |
| issueRefunds | ✓ | | | | | ✓ |
| viewReports | ✓ | ✓ | | | | ✓ |
| exportReports | ✓ | | | | | ✓ |
| manageInventory | ✓ | ✓ | | | | |
| manageStaff / manageSettings | ✓ | | | | | |
| viewAuditLog | ✓ | ✓ | | | | ✓ |

## Menu and categories

| Method and path | Permission | Notes |
| --- | --- | --- |
| `GET /menu` | public | Active categories and non-archived dishes, with `isAvailable` |
| `POST /admin/menu/items`, `PUT /admin/menu/items/{id}` | manageMenu | Same validation as `CatalogController.validateItem` |
| `PATCH /admin/menu/items/{id}` `{isAvailable}` / `{isArchived}` | manageMenu | Sold out or archived |
| `POST /admin/menu/categories`, `PUT …/{id}`, `PATCH …/{id}` `{isActive}` | manageCategories | |
| `PUT /admin/menu/categories/order` `{ids[]}` | manageCategories | Display order |
| `DELETE /admin/menu/categories/{id}` | manageCategories | Refused while any dish (archived included) uses it |

Editing a dish never changes placed orders or bills: each order stores its
own line prices and bill snapshot.

## Tables

| Method and path | Permission | Notes |
| --- | --- | --- |
| `GET /tables/{number}` | public | `{number, isActive}`, used to validate a scanned QR |
| `GET /admin/tables` | viewTables | With live status (occupied, bill due) |
| `POST /admin/tables`, `PATCH /admin/tables/{number}`, `DELETE …` | manageTables | Removal refused while the table has open orders |

For production, consider per-table opaque tokens in the QR (for example
`DINEQR:TABLE:05:<random>`), checked by the server, so table numbers cannot be
guessed.

### Takeaway

The restaurant's single takeaway code, `DINEQR:TAKEAWAY`, starts a session
with no table (`tableNumber: 0`, `orderType: "takeaway"`) while the setting
`takeaway` is on.
`DINEQR:PARCEL`, the code's name before the rename, is still accepted.
Takeaway orders use the same pricing, bill, kitchen workflow and counter payment;
the apps label them "Takeaway", "Ready for Pickup" and "Collected". Staff
place them with `POST /admin/orders {orderType: "takeaway"}` (no table).
The server refuses takeaway sessions and orders with `takeawayUnavailable`
while takeaway is closed, and a guest order whose `orderType` does not match
its session with `orderTypeMismatch`.

## Orders

`POST /orders`

```json
{
  "tableNumber": 5,
  "lines": [
    {"itemId": "chicken_65", "quantity": 2,
     "options": {"portionId": "half", "spice": "spicy", "addOnIds": []}}
  ],
  "instructions": "Less oil",
  "offerCode": "WELCOME10",
  "idempotencyKey": "…",
  "orderType": "dineIn"
}
```

(As implemented, guests do not send `tableNumber`: the session decides it.
`orderType` is `dineIn` or `takeaway` and must match the session. A combo
is one line, `{"comboId": "combo_family_feast", "quantity": 1}`. Special
offers need nothing in the request: the server applies the live ones, then
the coupon; see "Offers" in backend/README.md.)

The server checks the table is active and every dish is orderable, prices the
order and returns it with `bill` (`subtotal`, `discount`, `service`, `tax`,
`total`, rates and labels) and the created bill. Errors map to
`CheckoutError` (`tableUnavailable`, `itemsUnavailable`, …).

| Method and path | Permission | Notes |
| --- | --- | --- |
| `GET /orders/{id}` | guest session for that table, or viewOrders | Tracking |
| `POST /orders/{id}/feedback` `{rating, comment}` | guest session | Only after served; once |
| `GET /admin/orders?status=&from=&to=` | viewOrders | |
| `POST /admin/orders` | createOrders | Staff-entered order, source `staff` |
| `POST /admin/orders/{id}/status` `{target, reason}` | by target: manageKitchen / serveOrders / cancelOrders | Only the next stage, or cancel (with a reason) before ready |

Status updates reach guests and other staff in real time (WebSocket or
server-sent events, or polling every few seconds as a fallback). The demo's
"simulate kitchen" control does not exist in production.

## Bills, counter payments and refunds

DineQR takes no payment online. The server creates each order's bill with
the order; the kitchen works the order whatever the bill's state; the guest
pays at the billing counter and staff record it.

| Method and path | Permission | Notes |
| --- | --- | --- |
| `GET /orders/{id}/bill`, `GET /bills/{id}` | own guest session or viewBills | Amounts are the order's snapshot; payments and refunds as recorded. The guest apps show the order total from the order itself |
| `GET /admin/bills?from=&to=` | viewBills | Bills in the range plus every unsettled one |
| `POST /admin/bills/{id}/payments` `{amount, method, reference?, idempotencyKey, methodDetail?}` | collectPayments | Cash, card or UPI taken on the counter's own terminal/scanner; never above what is due; idempotent |
| `POST /admin/payments/{id}/refunds` `{amount, reason, idempotencyKey}` | issueRefunds | Recorded as returned at the counter. Payments from the retired online gateway are refused (`409 refundAtProvider`) |

Payments made before online payment was retired (`Cashfree`, `UPI direct`,
`Simulator` providers) stay on their bills and still count. Older servers'
`counterRequest`, `partial` and `methods` fields are no longer sent and are
ignored if present.

## Reports

`GET /admin/reports?from=&to=&includeSamples=` (viewReports; money fields
need viewFinancials; exports need exportReports). Use the definitions in
`SalesReport` so the dashboard, report screen and CSV/PDF exports agree:

- **Orders**: orders placed in the range, excluding cancelled ones.
- **Gross sales**: sum of order subtotals (before discounts).
- **Billed**: sum of order totals (after discounts, plus service charge and
  tax).
- **Collected**: payments recorded at the billing counter (and older
  successful online payments) whose confirmation falls in the range.
- **Refunds**: refunds processed in the range.
- **Net collected** = collected − refunds.
- **Net sales** = gross sales − discounts − refunds.
- **Outstanding**: unpaid balances of non-void bills created in the range.
- **Average order value** = billed ÷ orders.
- Days are restaurant days (the configured UTC offset), half-open
  `[start, end)`.

## Staff, audit and settings

| Method and path | Permission | Notes |
| --- | --- | --- |
| `GET /admin/staff`, `POST /admin/staff`, `PATCH /admin/staff/{id}` | manageStaff | Never returns password hashes. Owners cannot demote or deactivate themselves; at least one active owner remains |
| `POST /admin/staff/{id}/password-reset` | manageStaff | Prefer an emailed reset link to a temporary password |
| `GET /admin/audit?from=&to=&action=` | viewAuditLog | The server writes an audit event for every privileged action |
| `GET /settings` | public | Name, contact, tax and service labels and rates, coupons usable today, time zone (special offers and combos come with `GET /menu`) |
| `PUT /admin/settings` | manageSettings | Tax registration and address are printed only when set |
| `POST /guest/network-access` | guest | The dine-in Wi-Fi check: `403 networkNotAllowed` unless the request comes from one of the restaurant's authorised public networks (orders are checked the same way). See "Dine-in Wi-Fi restriction" in backend/README.md |
| `GET /admin/network-access`, `PUT /admin/network-access` | manageSettings | The restriction, its authorised networks (never sent to guests), and what the server sees for the calling device |
| `POST /guest/location-check` | guest | The GPS ordering area check: the device's position → allowed, or `403` (`outsideRestaurantArea`, `locationRequired`, ...). Guest `POST /orders` carries the same `location` and is checked again; independent of, and in addition to, the Wi-Fi check |
| `GET /admin/geofence`, `PUT /admin/geofence` | manageSettings | The restaurant's location, radius (10–1000 m), switch and takeaway option. See "GPS ordering area" in backend/README.md |
| `GET /legal/documents`, `GET /legal/documents/{kind}` | public | The published Terms & Conditions and Privacy Policy (the apps hold no copy of the text) |
| `GET /guest/legal`, `POST /guest/legal/acceptances` | guest | What the guest session must still accept, and recording the acceptance of each published version. Every guest `POST /orders` is refused with `409 legalAcceptanceRequired` until the published versions are accepted |
| `GET/POST/PUT/DELETE /admin/legal/documents`, `POST /admin/legal/documents/{id}/publish\|unpublish`, `GET /admin/legal/acceptances` | manageSettings (viewAuditLog may read) | Versions (drafts editable, published text locked), publishing, and the acceptance history. See "Terms & Conditions and Privacy Policy" in backend/README.md |
| `GET/POST/PATCH /admin/inventory`, `POST /admin/inventory/{id}/adjustments` | manageInventory | Stock changes only through recorded adjustments |
| `GET /admin/service-sections`, `PUT /admin/service-sections/{staffId}` `{tables[]}` | serveOrders (own), manageStaff (anyone's) | Optional (missing contract). Today each waiter's "my tables" is a filter saved on their device; a server version would let managers assign sections for the whole team |

## Before going live

- [x] HTTP implementations of the interfaces above
      (`packages/dineqr_core/lib/src/api/`), passed to
      `CustomerDependencies.create` and `AdminDependencies.create`; demo mode
      only when explicitly requested.
- [x] Guest sessions (`POST /guest/sessions`) for the customer app.
- [x] Billing on the server (`BillingBackend`: the server creates bills and
      records every counter payment and refund).
- [x] No online payment: guests pay at the billing counter.
- [x] Staff tokens in secure storage in the admin app
      (`flutter_secure_storage`). Certificate pinning not set up.
- [x] Real-time order updates to both apps (SignalR, with REST re-reads
      and a polling fallback).
- [ ] Printer plugin for the chosen thermal printer, if any.
- [x] HTTPS for the deployed API (release builds refuse plain HTTP):
      `https://hotelmenuorder.onrender.com`, the release-build default.
- [ ] Release signing configs for both Android apps (they currently sign
      release builds with the debug key) and Apple team/provisioning for
      both iOS bundle ids (`com.dineqr.customer`, `com.dineqr.admin`).
