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
| `POST /admin/payments/{id}/reconcile` | `POST /admin/bills/{id}/reconcile` (all pending payments of the bill) |
| `GET /admin/payments` | Not separate: `GET /admin/bills` returns every payment and refund with its bill |
| `POST /admin/staff/{id}/password-reset` | `POST /admin/staff/{id}/password` (sets a new password; ends that person's sessions) |
| `GET /admin/reports` | `GET /admin/reports/summary?from=&to=`; the admin screens still compute reports from the orders and bills they load (90 days plus open ones) |
| `GET /admin/service-sections` | Not built: waiter sections are still per device. Tables carry an optional server assignment instead |
| (not in the original contract) | Takeaway: `DINEQR:TAKEAWAY` sessions, `orderType` on orders, the `takeaway` setting (see "Takeaway" below) |
| (not in the original contract) | Payment modes, counter requests and currency (see "Payment modes" below) |
| `POST /webhooks/payments` | Built for Cashfree as `POST /webhooks/payments/cashfree`, with `POST /payments/{id}/checkout` for its UPI app links and QR code (see "UPI through Cashfree" below). Without Cashfree keys restaurants run in demo mode (a labelled simulator) |
| (not in the original contract) | UPI straight to the restaurant's own account, with no gateway: `GET/POST /payments/upi`, `POST /payments/{id}/upi/claim`, `POST /payments/{id}/cancel`, `POST /admin/payments/{id}/verify` and `/reject`, `GET/PUT /admin/payments/settings`, `POST /admin/uploads/upi-qr` (see "UPI to the restaurant's own account" below) |

Payments go through `/payments/intents` and `/payments/{id}/confirm` as
described below. Money is integer minor units ("paise") in JSON (stored as
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
7. Dashboard, reports, payment history and exports derive from the same
   payment and refund records (`SalesReport` and `PaymentLedger` define
   them).
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
| `PaymentGateway` (`services/payment_gateway.dart`) | both | `SimulatedPaymentGateway` (demo), `UnavailablePaymentGateway` | `/payments/*` plus the provider's checkout SDK |
| `StaffRepository` (`repositories/staff_repository.dart`) | admin | `LocalStaffRepository` (accounts and audit log) | `/admin/staff/*`, `/admin/audit` |
| `InventoryRepository` (`repositories/inventory_repository.dart`) | admin | `LocalInventoryRepository` | `/admin/inventory/*` |
| `ThermalPrinter` (`services/thermal_printer.dart`) | both | `UnavailableThermalPrinter` | Platform plugin for the chosen printer (Bluetooth/USB/LAN); `EscPosReceipt.encode` already builds the bytes |
| Reports (`services/report_service.dart`, `services/payment_ledger.dart`) | admin | `SalesReport.build`, `PaymentLedger.build` over local data | `/admin/reports`, `/admin/payments` with the same definitions |
| Waiter sections (`apps/dineqr_admin/lib/state/service_section_controller.dart`) | admin | Saved on the device per staff member | Optional `/admin/service-sections` (below) |

A production build passes `AppConfig(demoMode: false)` (customer:
`CustomerConfig(demoMode: false)`) and the HTTP implementations. With
`demoMode: false` the apps hide demo tools, use `UnavailablePaymentGateway`
unless a real gateway is supplied, and seed no sample data or demo accounts.

Menu photos: `MenuItem.image` and the optional `MenuItem.gallery` may be
`https://` URLs; the apps load them over the network (bundled demo photos
use `assets/images/…` paths).

### Required app changes for production billing

The billing controller (`state/billing_controller.dart`) was written for
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

### Guest sessions (customer app, missing contract)

The customer app has no account or login. Today a "guest session" is the
table stored on the device after a valid scan (resumed for 4 hours). The
server needs an explicit, table-scoped guest session so a guest can only
read and pay their own table's orders:

| Method and path | Body | Returns |
| --- | --- | --- |
| `POST /guest/sessions` | `{qrPayload}` (e.g. `DINEQR:TABLE:05`, ideally with an opaque per-table token) | `{guestToken, tableNumber, expiresAt}`; an error when the table is unknown or inactive |

The `guestToken` is sent with the `/orders`, `/bills` and `/payments` calls
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
| collectPayments | ✓ | ✓ | ✓ | | | |
| viewPayments (payment history) | ✓ | ✓ | ✓ | | | ✓ |
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

### Takeaway

The restaurant's single takeaway code, `DINEQR:TAKEAWAY`, starts a session
with no table (`tableNumber: 0`, `orderType: "takeaway"`) while the setting
`takeaway` is on.
`DINEQR:PARCEL`, the code's name before the rename, is still accepted.
Takeaway orders use the same pricing, bill, kitchen workflow and payments;
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
| `GET /admin/payments?from=&to=&status=&method=&q=` | viewPayments | Payment history (missing contract): every payment attempt and refund with its bill, order and table. Totals as defined by `PaymentLedger` |

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

### Payment modes (implemented)

| Field or call | Meaning |
| --- | --- |
| Setting `paymentMode` (`demo` / `live`) | Demo (default): online payments go to the server's simulator and every payment, counter ones too, is stored as a demo payment. Live: the configured gateway (Cashfree); refused (`liveUnavailable`) while none is configured |
| Setting `currency` | ISO code (INR, USD, EUR, GBP, AED, SGD); refused (`currencyLocked`) once any bill exists. UPI needs INR. Apps format every amount with it |
| `GET /payments/config` | `mode`, `currency`, `liveProvider`, `liveAvailable`, `liveMethods`, plus `provider`/`available`/`simulated`/`methods` for the provider in use now (older apps read those three) |
| Payment `detail` | Display-only method detail: `QR code` or an app name (UPI), `Credit`/`Debit` (card), a bank or wallet name. Never card numbers, CVVs, PINs |
| Payment `currency`, `mode` | Recorded with every payment |
| `POST /bills/{id}/counter-request {kind, amount}`, `DELETE …` | Guest: "I will pay in `cash` / at the `counter`". Moves no money, never changes the status; ends when staff record a payment or the bill is settled |

The guest options map onto the methods: UPI (from an app) and QR Payment are
`upi`; Card, Net Banking and Wallet are online methods (demo mode only);
Cash and Pay at Counter are counter requests that staff settle with
`POST /admin/bills/{id}/payments`. A split payment is several of these on
one bill: each online part is its own payment with its own idempotency key,
at most one counter part, and the server's checks
(`amount <= outstanding − pending`, one pending attempt at a time, a row lock
per bill) keep the parts from exceeding the balance. UPI that settles later
(through Cashfree, or to the restaurant's own UPI ID) is not offered as a
part.

### UPI through Cashfree (implemented)

Live mode with `Payments:Provider=Cashfree`. The guest pays by UPI from an
app or a QR code and the bill settles without anyone confirming it:

1. `POST /payments/intents {invoiceId, amount, method: "upi", methodDetail,
   idempotencyKey}` records the pending payment and creates a Cashfree order
   for exactly `amount`. The answer carries the payment and the bill.
2. `POST /payments/{id}/checkout {channel: "apps" | "qr"}` returns
   `{links: {default, gpay, phonepe, paytm, bhim}, qrImage, qrText,
   expiresAt}` for that order; the server drops any link that does not ask
   for exactly the amount (`am`) in rupees (`cu=INR`). The QR is a picture
   (`qrImage`) or the link it holds (`qrText`, drawn by the app). The app
   opens the guest's chosen app with the payee and amount filled in: on
   Android the plain `upi://pay` link sent to the app's package (the app
   lists every installed UPI app, with its icon, through MainActivity.kt's
   `dineqr/upi` channel); on iOS the app's own scheme (`tez`, `phonepe`,
   `paytmmp`). Asking again pays the same order.
3. Cashfree calls `POST /webhooks/payments/cashfree` (signature:
   `base64(HMAC_SHA256(timestamp + rawBody, clientSecret))`). The server
   ignores what the body claims and asks Cashfree's API for the order's
   payments; only a `SUCCESS` for exactly the amount and currency counts.
   `GET /payments/{id}` (the app polls it, and asks again when the guest
   comes back from the UPI app) and a background sweep do the same check,
   so a lost webhook only delays the update.
4. Failures, cancellations and expired orders terminate the Cashfree order
   before the payment is recorded as not paid, so it cannot succeed later;
   if the guest had paid first, the payment is recorded as paid.

The UPI app returning to DineQR, or the guest saying they paid, never
changes anything. Sandbox payments are recorded as demo payments.

### UPI to the restaurant's own account

A way to pay online that needs no provider account, offered when Cashfree is
not taking UPI: the guest pays the restaurant's UPI ID from their own UPI
app. The server cannot see that money, so it is held to the same rule as
everything else here, **only the side that can verify a payment may mark it
paid**, and that side is a cashier (or a connected bank integration), never
the guest's app.

| Method and path | Who | Notes |
| --- | --- | --- |
| `GET /payments/upi` | guest session or staff | The payee: `{enabled, upiId, payeeName, qrImage, verificationMode}`; empty while UPI is off |
| `POST /payments/upi` `{invoiceId, amount, idempotencyKey}` | guest session or collectPayments | Records a **pending** payment (`provider: "UPI direct"`). The server checks the amount against the balance exactly as for `/payments/intents` |
| `POST /payments/{id}/upi/claim` `{reference?}` | guest session or collectPayments | "I paid": sets `claimed`; still pending |
| `POST /payments/{id}/cancel` | guest session (unclaimed only) or collectPayments | |
| `POST /admin/payments/{id}/verify` `{reference}` | collectPayments | The cashier saw the credit; records the bank's transaction ID; `succeeded` |
| `POST /admin/payments/{id}/reject` `{reason?}` | collectPayments | The money did not arrive; `failed` |
| `GET/PUT /admin/payments/settings` | staff / manageSettings | `{enabled, upiId, payeeName, qrImage, verificationMode}` |
| `POST /admin/uploads/upi-qr` | manageSettings | The merchant QR picture; saved with the settings |

The app builds the `upi://pay?pa=<UPI ID>&pn=<name>&am=<amount>&cu=INR&tn=Bill <number> <payment id>`
link from the payee and the payment (`UpiPaymentLink` in `dineqr_core`) and
shows it as a QR code and as details to copy. There is no `tr` or `mc`: those
mark a merchant payment, and the restaurant's UPI ID may be a personal one.

The link is never handed to a UPI app: Google Pay and PhonePe refuse a
payment that another app fills in for a restaurant's own UPI ID, under their
anti-fraud rules (Google Pay says "Your money has not been debited. You've
exceeded the bank limit", though no limit was reached), and no link
parameter changes that. Only a payment gateway's verified merchant ID is
accepted, which is how large apps do it. So the app copies the UPI ID and
opens the app the guest picks on its own (Android: `launch` on
MainActivity.kt's `dineqr/upi` channel; iOS: the app's scheme), where the
guest pays it, or the guest scans the QR (from
another phone, or a screenshot with "Scan from gallery", which UPI caps at
₹2,000). Filled-in UPI payments that the apps accept, confirmed
automatically, need a payment gateway: Cashfree (above). Opening an app
proves nothing: the guest is asked what happened, and the payment stays
pending until staff confirm it. `PaymentTransaction.statusLabel` and
`InvoiceStatus.pending` ("Pending verification") describe it everywhere.

The server checks UPI IDs for form, and refuses one a typo away from a Google
Pay handle (`@okabi` for `@oksbi`): Google Pay finds no account for it
("Could not load banking name", "No payment account registered on Google
Pay"). Whether an ID really exists only a UPI app can tell, so the admin
settings show a QR of the ID alone for the owner to scan.

Automatic verification is part of the settings but needs a bank or provider
integration (`IUpiPaymentVerifier`); none is built, so it cannot be selected.

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
| `GET /settings` | public | Name, contact, tax and service labels and rates, coupons usable today, time zone (special offers and combos come with `GET /menu`) |
| `PUT /admin/settings` | manageSettings | Tax registration and address are printed only when set |
| `GET/POST/PATCH /admin/inventory`, `POST /admin/inventory/{id}/adjustments` | manageInventory | Stock changes only through recorded adjustments |
| `GET /admin/service-sections`, `PUT /admin/service-sections/{staffId}` `{tables[]}` | serveOrders (own), manageStaff (anyone's) | Optional (missing contract). Today each waiter's "my tables" is a filter saved on their device; a server version would let managers assign sections for the whole team |

## Before going live

- [x] HTTP implementations of the interfaces above
      (`packages/dineqr_core/lib/src/api/`), passed to
      `CustomerDependencies.create` and `AdminDependencies.create`; demo mode
      only when explicitly requested.
- [x] Guest sessions (`POST /guest/sessions`) for the customer app.
- [x] Billing controller changes described in "Required app changes"
      (`BillingBackend`: the server creates bills and records every payment
      and refund).
- [ ] Payment provider account, server-side keys, webhook endpoint and
      signature verification; a test-mode run of every outcome.
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
