# DineQR backend integration

DineQR ships with **no backend**. Everything runs in an explicit offline demo
(`AppConfig.demoMode = true`): menu, orders, bills, simulated payments, staff
accounts and reports are stored on the device with `shared_preferences`.

This document lists the service seams in the Flutter app and the HTTP
contracts a production backend must provide. None of these endpoints exist
yet; they are the contract to build against.

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
4. **No secrets in the app.** Payment-provider secret keys, webhook secrets
   and admin credentials live only on the server. The app may hold a
   provider's *public* key id.
5. **A payment is paid only when the server has verified it** with the
   provider (signature check plus a status fetch, or a verified webhook).
   Returning to the app is never proof of payment.
6. **A table QR identifies an ordering context only** (`DINEQR:TABLE:05`). It
   grants no staff access. The server re-checks that the table exists and is
   active when an order is submitted.
7. **Idempotency.** Order submission, payment creation and refunds carry an
   idempotency key; replays return the original result.
8. **Money** is integer paise (`₹1 = 100`), currency `INR`. **Time** is UTC
   ISO-8601 on the wire; the restaurant's UTC offset comes from settings and
   is used for "today" and report ranges.

## Where the app plugs in

`AppDependencies.create` (`lib/app/dependencies.dart`) accepts every service:

| App interface (file) | Demo implementation | Production work |
| --- | --- | --- |
| `AuthService` (`lib/data/services/auth_service.dart`) | `DemoAuthService`: local accounts, salted SHA-256, lockout | HTTP client for `/auth/*`; tokens in secure storage |
| `MenuRepository` (`lib/data/repositories/menu_repository.dart`) | `DemoMenuRepository` | `/menu`, `/admin/menu/*` |
| `OrderRepository` (`lib/data/repositories/order_repository.dart`) | `LocalOrderRepository` | `/orders`, `/admin/orders/*`, live updates |
| `SettingsRepository` (`lib/data/repositories/settings_repository.dart`) | `LocalSettingsRepository` (settings and tables) | `/settings`, `/admin/settings`, `/admin/tables` |
| `BillingRepository` (`lib/data/repositories/billing_repository.dart`) | `LocalBillingRepository` | `/bills/*`, `/admin/bills/*` (read-mostly, see below) |
| `PaymentGateway` (`lib/data/services/payment_gateway.dart`) | `SimulatedPaymentGateway` (demo), `UnavailablePaymentGateway` | `/payments/*` plus the provider's checkout SDK |
| `StaffRepository` (`lib/data/repositories/staff_repository.dart`) | `LocalStaffRepository` (accounts and audit log) | `/admin/staff/*`, `/admin/audit` |
| `InventoryRepository` (`lib/data/repositories/inventory_repository.dart`) | `LocalInventoryRepository` | `/admin/inventory/*` |
| `ThermalPrinter` (`lib/data/services/thermal_printer.dart`) | `UnavailableThermalPrinter` | Platform plugin for the chosen printer (Bluetooth/USB/LAN); `EscPosReceipt.encode` already builds the bytes |
| Reports (`lib/data/services/report_service.dart`) | `SalesReport.build` over local data | `/admin/reports` with the same definitions |

A production build passes `AppConfig(demoMode: false)` and the HTTP
implementations. With `demoMode: false` the app hides demo tools, uses
`UnavailablePaymentGateway` unless a real gateway is supplied, and does not
seed sample data or demo accounts.

### Required app changes for production billing

The billing controller (`lib/state/billing_controller.dart`) was written for
the single-device demo. It records a pending transaction, calls the gateway,
and saves the result itself. With a backend:

- Bills are created by the server when an order is accepted;
  `createForOrder` should fetch rather than build them.
- `payOnline` should create a payment intent on the server, open the
  provider checkout, send the result to the server for verification, then
  **re-fetch the bill**. It must not write payment status itself.
- `recordCounterPayment`, `refund` and `reconcile` become server calls;
  `saveInvoice` is not used for payment state.

The UI, models and status rules (`Invoice.status`, `outstanding`,
`payableNow`) stay as they are; they read whatever the server returns.

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

## Roles and permissions

The server holds the authoritative matrix. The app mirrors it in
`StaffRole` / `Permission` (`lib/data/models/staff.dart`) to shape the UI.

| Permission | Owner | Manager | Cashier | Kitchen | Waiter | Accountant |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| viewDashboard | ✓ | ✓ | ✓ | | | ✓ |
| viewFinancials | ✓ | | | | | ✓ |
| viewOrders | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| createOrders | ✓ | ✓ | | | ✓ | |
| manageKitchen (accept, preparing, ready) | ✓ | ✓ | | ✓ | | |
| serveOrders | ✓ | ✓ | | | ✓ | |
| cancelOrders | ✓ | ✓ | | | | |
| viewMenu | ✓ | ✓ | | ✓ | ✓ | |
| manageMenu / manageCategories | ✓ | ✓ | | | | |
| viewTables | ✓ | ✓ | ✓ | | ✓ | |
| manageTables | ✓ | ✓ | | | | |
| viewBills | ✓ | ✓ | ✓ | | ✓ | ✓ |
| collectPayments | ✓ | ✓ | ✓ | | | |
| reconcilePayments | ✓ | | ✓ | | | ✓ |
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
  "idempotencyKey": "…"
}
```

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

## Bills, payments and refunds

| Method and path | Permission | Notes |
| --- | --- | --- |
| `GET /bills/{id}`, `GET /orders/{id}/bill` | guest session or viewBills | Amounts are the order's snapshot; payments and refunds as recorded |
| `GET /admin/bills?from=&to=&status=&method=&q=` | viewBills | |
| `POST /payments/intents` | guest session | See below |
| `POST /payments/{id}/confirm` | guest session | Provider callback data for verification |
| `GET /payments/{id}` | guest session or viewBills | Current status (maps to `PaymentGateway.checkStatus`) |
| `POST /admin/bills/{id}/payments` `{amount, method, reference}` | collectPayments | Cash or card terminal at the counter |
| `POST /admin/payments/{id}/reconcile` | reconcilePayments | Re-queries the provider |
| `POST /admin/payments/{id}/refunds` `{amount, reason, idempotencyKey}` | issueRefunds | Provider refund API; pending until confirmed |
| `POST /webhooks/payments` | provider signature | `payment.captured`, `payment.failed`, `refund.processed`, … |

### Online payment flow (Razorpay as an example)

1. `POST /payments/intents {invoiceId, amount, method, idempotencyKey}`. The
   server checks `0 < amount <= outstanding − pending` and the restaurant's
   part-payment policy, creates a provider order for `amount` paise, stores a
   **pending** transaction and returns
   `{paymentId, providerOrderId, keyId, amount, currency}`.
2. The app opens the provider checkout with `providerOrderId` and the public
   `keyId`.
3. On completion the SDK returns `razorpay_payment_id`, `razorpay_order_id`
   and `razorpay_signature`. The app sends them to
   `POST /payments/{paymentId}/confirm`.
4. The server verifies
   `HMAC_SHA256(order_id + "|" + payment_id, key_secret) == signature`,
   fetches the payment from the provider, checks it is captured for the same
   amount and order, then marks the transaction **succeeded** and updates the
   bill.
5. Webhooks (signature checked with the webhook secret, processed once per
   event id) settle payments whose confirmation never arrived (app closed,
   network lost).
6. The app re-fetches the bill. Interrupted payments show as "waiting for
   confirmation" and are re-checked when the app opens (already implemented
   with `BillingController.checkPending`).

Cancelled or failed attempts never change the balance. Refunds never reopen a
balance; a cancelled order's paid amount shows as "refund due".

## Reports

`GET /admin/reports?from=&to=&includeSamples=` (viewReports; money fields
need viewFinancials; exports need exportReports). Use the definitions in
`SalesReport` so the dashboard, report screen and CSV/PDF exports agree:

- **Orders**: orders placed in the range, excluding cancelled ones.
- **Gross sales**: sum of order subtotals (before discounts).
- **Billed**: sum of order totals (after discounts, plus service charge and
  tax).
- **Collected**: successful payments whose confirmation falls in the range.
  Pending, failed and cancelled payments are excluded.
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
| `GET /settings` | public | Name, contact, tax and service labels and rates, active offers, time zone |
| `PUT /admin/settings` | manageSettings | Tax registration and address are printed only when set |
| `GET/POST/PATCH /admin/inventory`, `POST /admin/inventory/{id}/adjustments` | manageInventory | Stock changes only through recorded adjustments |

## Before going live

- [ ] HTTP implementations of the interfaces above, injected through
      `AppDependencies.create`, with `AppConfig(demoMode: false)`.
- [ ] Billing controller changes described in "Required app changes".
- [ ] Payment provider account, server-side keys, webhook endpoint and
      signature verification; a test-mode run of every outcome.
- [ ] Tokens in secure storage; certificate pinning if required by policy.
- [ ] Real-time order updates.
- [ ] Printer plugin for the chosen thermal printer, if any.
- [ ] Remove or disable the demo staff entry (long press in About) for
      production builds. It is already inactive when `demoMode` is false.
