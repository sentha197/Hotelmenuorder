# DineQR API

The server both DineQR apps run on: ASP.NET Core (.NET 10) Web API, Entity
Framework Core 10 with Npgsql, and PostgreSQL. It owns every business rule
that matters for money and access:

- prices every order from its own menu, offers and tax settings;
- creates the bill with each order and records every payment and refund;
- authorises every staff request by the account's role, checked against the
  database on each request;
- pushes live change notifications (SignalR) to both apps.

```
backend/
  DineQR.sln
  src/DineQR.Api/
    Domain/          entities, enums, the role → permission matrix
    Data/            DbContext, migrations, seed import, owner bootstrap
    Contracts/       request/response shapes (match the Flutter models' JSON)
    Services/        auth, orders, billing and payments, menu, settings,
                     tables, staff, inventory, reports, live updates
    Endpoints/       the HTTP API (/api/v1/…)
    Infrastructure/  errors, JSON, JWT, start-up tasks
  tests/DineQR.Api.Tests/   unit tests + HTTP integration tests (throwaway DB)
```

## First-time setup

Requirements: .NET 10 SDK, PostgreSQL 17 (the `dineqr` database exists),
Flutter 3.44+ for the apps.

### 1. Secrets (never in the repository)

Local development uses .NET user secrets, stored in your Windows profile:

```powershell
cd backend/src/DineQR.Api
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Host=localhost;Port=5432;Database=dineqr;Username=postgres;Password=<password>"
dotnet user-secrets set "Jwt:SigningKey" "<at least 32 random bytes>"
dotnet user-secrets set "Bootstrap:OwnerEmail" "owner@dineqr.local"
dotnet user-secrets set "Bootstrap:OwnerPassword" "<strong password>"
dotnet user-secrets list
```

Production uses environment variables instead (`ConnectionStrings__DefaultConnection`,
`Jwt__SigningKey`, …); [`.env.example`](.env.example) lists them with
placeholders. The Flutter apps never see database credentials and never talk
to PostgreSQL: only the API does.

### 2. Back up, then migrate the database

The migrations are additive. The existing `users` table is adopted, not
recreated: it gains three nullable/defaulted sign-in columns (`last_login_at`,
`failed_login_count`, `locked_until`) and its rows are untouched. Take a
backup first anyway:

```powershell
$env:PGPASSWORD = "<password>"
& "C:\Program Files\PostgreSQL\17\bin\pg_dump.exe" -h localhost -U postgres -d dineqr -Fc -f "$env:USERPROFILE\dineqr-backups\dineqr-$(Get-Date -Format yyyyMMdd-HHmmss).dump"

cd backend
dotnet tool restore                       # dotnet-ef (local tool)
dotnet ef migrations script --idempotent --project src/DineQR.Api   # review the SQL
dotnet ef database update --project src/DineQR.Api -- --environment Development
```

Restore if ever needed: `pg_restore -h localhost -U postgres -d dineqr --clean <file>.dump`
(this replaces the current contents, so only do it deliberately).

**Without the .NET SDK** (for example on the machine that only has PostgreSQL,
or in the Neon SQL editor), run the generated SQL instead. It is idempotent:
each step checks `__EFMigrationsHistory`, so running it twice changes nothing,
and EF treats the migration as applied afterwards.

```powershell
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -h localhost -U postgres -d dineqr -v ON_ERROR_STOP=1 -f backend\migration-scripts\AddUpiPayments.sql
```

`migration-scripts/AddUpiPayments.sql` covers the `AddUpiPayments` migration
(UPI payment settings and payment verification), for a database already at
`ParcelOrders`. Regenerate it, or script every migration, with
`dotnet ef migrations script --idempotent --project src/DineQR.Api`.

### 3. Run the API

```powershell
cd backend
dotnet run --project src/DineQR.Api        # http://0.0.0.0:5264 (all network interfaces)
```

On the first start in Development the API:

1. imports the initial catalogue (`Data/Seed/initial-catalog.json`: 4
   categories, 21 dishes with portions and add-ons, restaurant settings, 2
   offers, tables 1–30), **only into empty tables**, so restarts never
   duplicate or overwrite anything;
2. creates the first owner account from `Bootstrap:*` if no active owner
   exists. Every other staff account is created by the owner in the admin
   app (Staff module).

The catalogue file is exported from the data the offline demo used to
hard-code (`packages/dineqr_core/tool/export_seed_test.dart`). No orders,
bills, payments, inventory or other staff are seeded: those only come from
real use.

- Swagger UI: http://localhost:5264/swagger (Development only, or
  `OpenApi__Enabled=true`). Use **Authorize** with a token from
  `POST /api/v1/auth/login` or `POST /api/v1/guest/sessions`.
- Health: http://localhost:5264/health returns only `{"status":"Healthy"}`
  or `Unhealthy`, including a database check, never connection details.

## Running the apps against the API

Both apps choose their mode at build time:

| Build flag | Mode |
| --- | --- |
| `--dart-define=DINEQR_API_URL=<url>` | Backend mode (normal) |
| `--dart-define=DINEQR_MODE=demo` | Explicit offline demo (device-only sample data, labelled) |
| neither | Debug builds: the local API (below). Profile and release builds: the deployed API, `https://hotelmenuorder.onrender.com` |

The API address depends on where the app runs (`localhost` on a phone is
the phone itself):

| Where the app runs | `DINEQR_API_URL` |
| --- | --- |
| Android emulator | `http://10.0.2.2:5264` |
| Chrome / Windows on this computer | `http://localhost:5264` |
| Phone or tablet on the same Wi-Fi | `http://<this computer's LAN IP>:5264` (`ipconfig`) |
| iOS simulator (macOS) | `http://localhost:5264` |
| Production (Render) | `https://hotelmenuorder.onrender.com` (the release-build default) |

```powershell
cd apps/dineqr_customer
flutter run --dart-define=DINEQR_API_URL=http://10.0.2.2:5264

cd apps/dineqr_admin
flutter run --dart-define=DINEQR_API_URL=http://10.0.2.2:5264
```

VS Code: `.vscode/launch.json` has ready-made configurations (emulator,
Chrome, offline demo) for both apps.

Physical devices: the API listens on all interfaces (port 5264). Windows
Firewall must allow it once, on private networks only:

```powershell
New-NetFirewallRule -DisplayName "DineQR API (dev)" -Direction Inbound -Protocol TCP -LocalPort 5264 -Profile Private -Action Allow
```

Plain `http://` is allowed in **debug and profile** Android builds only
(`android/app/src/debug|profile/AndroidManifest.xml`). Release builds require
HTTPS, so test against a local HTTP API with `flutter run` (debug) or
`flutter build apk --debug`, and deploy the API behind HTTPS for release
builds. PostgreSQL is never exposed to the network.

Flutter web needs CORS. In Development any `localhost` origin is allowed;
in production list the web origins in `Cors:AllowedOrigins`.

## API reference

All paths are under `/api/v1`. Money is integer **paise** (`₹1 = 100`),
times are UTC ISO-8601, and errors are RFC 7807 problems with a stable
`code` (e.g. `tableUnavailable`, `takeawayUnavailable`, `priceChanged`,
`paymentInProgress`) and a `title` that is safe to show. Response shapes
match the Flutter models' `fromJson` in `packages/dineqr_core`; orders and
bills also carry `type` (`dineIn` or `takeaway`).

**Takeaway** orders are ordinary orders without a table: table number `0`
(real tables are 1–999), the same pricing, bill, kitchen workflow and
payments. The restaurant opens or closes takeaway in settings; while it is
closed, takeaway sessions and orders (guest or staff) are refused.

| Method and path | Who | Notes |
| --- | --- | --- |
| `POST /auth/login` | anyone | `{email, password}` → access token (15 min), refresh token, session end (8 h), staff profile and permissions. Generic errors; 5 failures lock the account for a minute; per-IP rate limit |
| `POST /auth/refresh` | anyone | Rotates the refresh token; reusing an old one ends the whole session |
| `POST /auth/logout` | anyone | Ends the session of the given refresh token |
| `GET /auth/me`, `POST /auth/password` | staff | Profile; change own password |
| `GET /settings`, `GET /menu`, `GET /tables`, `GET /tables/{n}` | public | Restaurant settings and the coupons usable today (`offers`), the guest menu with the special offers and combos live today (`promotions`, see Offers), table numbers and whether they take orders. Usage limits and counts are never sent to guests |
| `GET /payments/config` | public | No secrets: `mode` (`demo` or `live`), the provider taking online payments now (`provider`, `available`, `simulated`, kept for older apps) and its online `methods`, `currency`, and whether live mode can be chosen (`liveProvider`, `liveAvailable`, `liveMethods`: `["upi"]` for Cashfree) |
| `POST /guest/sessions` | public | `{qrPayload: "DINEQR:TABLE:05"}` → a guest token scoped to that table (4 h), `{guestToken, tableNumber, expiresAt, orderType}`; refused for unknown or inactive tables. `DINEQR:TAKEAWAY` (or `DINEQR:PARCEL`, its earlier name) starts a takeaway session (`tableNumber: 0`, `orderType: "takeaway"`) while takeaway is open, else `takeawayUnavailable` |
| `POST /orders` | guest | `{lines: [{itemId, quantity, options} or {comboId, quantity}], instructions, offerCode, idempotencyKey, expectedTotal, orderType}`. Priced by the server with its live special offers, combos and the coupon (see Offers); refused with `priceChanged` if the total differs from what the guest saw, and with `offerUnavailable` when a combo or coupon ended or ran out; replays return the original order. Each line returns its `discount`, `discountLabel` and `promotionId`, a combo line its `comboId` and `comboItems`, and the order its `discounts` breakdown. `orderType` (`dineIn` or `takeaway`, optional) must match the session (`orderTypeMismatch`); a takeaway order is refused with `takeawayUnavailable` once takeaway closes |
| `GET /orders`, `GET /bills` | guest | The session's own orders and bills |
| `GET /orders/{id}`, `GET /orders/{id}/bill`, `GET /bills/{id}` | own guest session, or staff with viewOrders / viewBills | |
| `POST /orders/{id}/feedback` | guest | Once, after the order is served |
| `POST /payments/intents` | own guest session or staff | `{invoiceId, amount, method, idempotencyKey, methodDetail}`. Records a **pending** payment through the provider of the restaurant's payment mode (the demo simulator in demo mode) before the provider is involved; refuses overpayment, part payments when not allowed, a method the provider does not take (`methodUnavailable`: Cashfree takes `upi` only), and a second attempt while one is pending. `methodDetail` is display text (`QR code`, `Google Pay`, `Credit`, a bank or wallet name) and is refused if it could hold a card or account number. UPI needs the currency to be INR. With Cashfree it also opens a Cashfree order for exactly the amount (`503 gatewayUnavailable` if Cashfree cannot be reached; nothing is recorded then). The answer includes the bill (`invoice`) |
| `POST /payments/{id}/checkout` | own guest session or collectPayments | `{channel: "apps" \| "qr"}` for a pending Cashfree payment → `{payment, links, qrImage, qrText, expiresAt}`: UPI links by app (`default`, `gpay`, `phonepe`, `paytm`, `bhim`) or a QR code, as a picture (`qrImage`, `data:image/png;base64,…`) or as the `upi://pay` link it holds (`qrText`, drawn by the app), all checked to ask for the exact amount. Asking again (another app, or the QR) pays the **same** Cashfree order, so it can be paid once at most. `paymentEnded` once the order can no longer be paid |
| `POST /payments/{id}/confirm` | own guest session or staff | Sends the provider's checkout result; the **server verifies it** with the provider that took the payment before it counts (demo: `simulatedOutcome` `success`, `failure` or `cancel`). For Cashfree the app's result is ignored: only Cashfree's API is asked |
| `POST /bills/{id}/counter-request`, `DELETE /bills/{id}/counter-request` | own guest session | `{kind: "cash" \| "counter", amount}` (amount defaults to everything payable now): the guest will pay at the counter. Moves no money and never changes the bill's status; staff see it on the bill, and recording a counter payment (or the bill being settled) ends it |
| `GET /payments/{id}` | own guest session or staff | Current status; pending payments are re-checked (a Cashfree payment with Cashfree's API; while Cashfree cannot be reached it stays pending) |
| `GET /payments/upi` | any guest session or staff | The restaurant's UPI payee for paying a bill: `{enabled, upiId, payeeName, qrImage, verificationMode}` (the mode in effect). Reveals nothing while UPI is switched off or incomplete |
| `POST /payments/upi` | own guest session or collectPayments | `{invoiceId, amount, idempotencyKey}`. Starts a UPI payment **to the restaurant's own account**: records a *pending* payment (`provider: "UPI direct"`, never simulated) that holds the amount against the bill. Same amount rules as an online payment; refused with `upiUnavailable` when UPI is off |
| `POST /payments/{id}/upi/claim` | own guest session or collectPayments | `{reference?}`. The guest says they paid (the optional UPI transaction ID is stored as unverified). Sets `claimed`; the payment stays *pending* |
| `POST /payments/{id}/cancel` | own guest session or collectPayments | Cancels a pending UPI payment. A guest cannot cancel a payment to the restaurant's UPI ID they have claimed (`alreadyClaimed`). A Cashfree payment's order is terminated at Cashfree first; if the guest had already paid, the payment is recorded as **paid** instead |
| `POST /webhooks/payments/cashfree` | Cashfree | Anonymous, but every call must carry Cashfree's `x-webhook-signature` (base64 HMAC-SHA256 of `x-webhook-timestamp` + raw body, keyed with the client secret; `401` otherwise). The body only names the order: the server then asks Cashfree's API for the payment and checks the amount and currency before anything counts. Repeats are harmless; unknown orders are acknowledged and ignored |
| `GET /admin/menu` | staff | Every dish (archived too) and category, and every special offer and combo with its `limit` and `used` count |
| `PUT /admin/promotions/{id}`, `PATCH /admin/promotions/{id}`, `DELETE /admin/promotions/{id}` | manageOffers | Create/replace a special offer or combo (validated like the app; the usage count is kept), `{active}`, delete (orders keep their copy). Audited; guests' menus refresh at once |
| `PUT /admin/offers/{code}`, `PATCH /admin/offers/{code}`, `DELETE /admin/offers/{code}` | manageOffers | Create or update a coupon (the body's `code` may rename it; the usage count is kept), `{active}`, delete. Audited |
| `POST /admin/uploads/offer-images` | manageOffers | Multipart `file` → `{url}` for a special offer's or combo's picture, stored like dish photos |
| `PUT /admin/menu/items/{id}`, `PATCH /admin/menu/items/{id}` | manageMenu | Create/replace a dish (validated like the app); `{available}` / `{archived}` |
| `PUT /admin/menu/categories` | manageCategories | The category list; a category still used by any dish cannot be removed |
| `GET /admin/settings`, `PUT /admin/settings` | staff / manageSettings | Settings and every coupon (with `limit` and `used`). A save without `offers` (current apps) leaves the coupons alone; apps from before the Offers section save the whole list, and their saves keep each coupon's dates, limit and count. `takeaway` opens or closes takeaway; it is also served as `parcel` for apps from before the rename, `parcel` is accepted when `takeaway` is missing, and a save with neither keeps the current value. `paymentMode` (`demo`/`live`): switching to live is refused with `liveUnavailable` until a verified gateway is configured. `currency` (INR, USD, EUR, GBP, AED, SGD) is refused with `currencyLocked` once any bill exists. A save without either keeps the current value |
| `GET /admin/tables`, `PUT /admin/tables` | staff / manageTables | The table list. Removing a table with open orders or unpaid bills is refused. `server`: omitted keeps the assignment, `""` clears it |
| `GET /admin/servers` | viewTables | Staff who can serve tables |
| `GET /admin/orders?from=&to=&status=` | viewOrders | Orders in the range plus every open order |
| `POST /admin/orders` | createOrders | Staff/counter order for `tableNumber`, or `orderType: "takeaway"` with no table (table `0` from older apps means the same) |
| `POST /admin/orders/{id}/status` | manageKitchen / serveOrders / cancelOrders (by target) | Only the next stage, or `cancelled` with a reason (voids the bill; money already paid shows as a refund due) |
| `GET /admin/bills?from=&to=`, `GET /admin/bills/{id}` | viewBills | Bills in the range plus every unsettled one |
| `POST /admin/bills/{id}/payments` | collectPayments | Counter payment (cash, card terminal, UPI at the counter), idempotent. In demo mode it is recorded as a demo payment (`simulated`, `mode: "demo"`). Ends the guest's counter request |
| `POST /admin/payments/{id}/verify` | collectPayments | `{reference}` (required, the bank's UPI transaction ID, 6–40 letters or digits). A cashier confirms that a UPI payment reached the restaurant's account: the **only** way it becomes `succeeded` (besides a connected verifier). Idempotent; the same reference cannot confirm two payments (`duplicateReference`); audited |
| `POST /admin/payments/{id}/reject` | collectPayments | `{reason?}`. The money did not arrive: the payment fails and the balance is open again; audited |
| `GET /admin/payments/settings` | staff | The UPI payment settings and whether automatic verification can run (`automaticVerificationAvailable`) |
| `PUT /admin/payments/settings` | manageSettings (owner) | `{enabled, upiId, payeeName, qrImage, verificationMode}`. The UPI ID is `name@bank` (stored lower case); `automatic` is refused unless a verifier is connected; `qrImage` must be `""`, the saved value, or an image uploaded below (any other address is refused). Audited |
| `POST /admin/uploads/upi-qr` | manageSettings | Multipart `file` (JPEG, PNG or WebP, same size limit as dish photos) → `{url}`. Takes effect when saved with the settings; the replaced image is deleted |
| `POST /admin/bills/{id}/reconcile` | reconcilePayments | Re-checks pending online payments with the provider |
| `POST /admin/payments/{id}/refunds` | issueRefunds | Up to what is refundable on that payment, idempotent |
| `GET/POST /admin/staff`, `PATCH /admin/staff/{id}`, `POST /admin/staff/{id}/password` | manageStaff | Never returns hashes. You cannot change your own role or deactivate yourself; one active owner always remains; deactivation and password resets end that person's sessions. Only an owner can create or change an owner account, or reset an owner's password. `role` may be `custom` with a `roleTitle` of 2 to 30 characters (e.g. "Officer"): a custom role starts with no permissions and the owner grants them with `PUT …/access`. Sending the same `custom` role with a new `roleTitle` renames it and keeps its access |
| `PUT /admin/staff/{id}/access` | manageStaff, owner only | Body `{ "permissions": ["viewOrders", …] }` replaces what that person's role allows (`null` goes back to the role's defaults). Applies on their next request; a role change clears it. Not for yourself or another owner. The staff list shows `permissions` (what they can really do) and `customAccess` |
| `GET /admin/audit?from=&to=&action=&limit=` | viewAuditLog | Every privileged action, recorded in the same transaction as the change |
| `GET /admin/inventory`, `POST /admin/inventory`, `PUT /admin/inventory/{id}`, `POST /admin/inventory/{id}/adjustments` | manageInventory | Stock changes only through adjustments; running out marks linked dishes sold out (and restocking makes them available) when that setting is on |
| `GET /admin/reports/summary?from=YYYY-MM-DD&to=YYYY-MM-DD` | viewReports (money fields need viewFinancials) | Restaurant days, inclusive: orders, gross and net sales, discounts, service, taxes, billed, collected (successful payments only), refunds, outstanding, bill counts, failed payments, by method, daily, items |

The permission matrix (owner, manager, cashier, kitchen, waiter, accountant)
is in `Domain/Enums.cs` (`RolePermissions`) and mirrors the apps'
`StaffRole.permissions`. The apps only use it to shape their screens; the
server checks it on every request, against the account's **current** role
and active flag in the database.

## Offers

Three kinds, managed in the admin app's **Offers** section (permission
`manageOffers`: owners and managers by default):

- **Special offers**: a percentage (1–100%) or flat amount off each unit of
  chosen dishes, applied with no code. Percentages apply to the dish as
  ordered (add-ons included); a flat amount never exceeds the dish.
- **Combos**: 2 or more dishes (1–10 different ones, up to 10 of each) sold
  as one cart line for a fixed price that must be below what the dishes
  cost separately (their default portion, no add-ons). The kitchen sees the
  dishes; a combo can be ordered only while every dish can.
- **Coupons**: codes guests enter (percent with an optional cap, or flat;
  optional minimum order).

All three have an active switch, optional first and last days (restaurant
days, both included) and an optional usage limit (orders). Code:
`Services/Pricing.cs` (`OfferRules`, `Pricing.Apply`),
`Services/PromotionService.cs`, `Services/OrderService.cs`; the apps mirror
it in dineqr_core `OfferPricing`.

How an order is priced (the server decides; the apps only preview it and
send `expectedTotal`):

1. Every dish line at its full price makes the subtotal; a combo line's
   price is what its dishes cost separately.
2. Each dish line gets the best special offer live today that covers it
   (one per line; the first of equally good offers, by sort order then id,
   wins). Each combo line gets its combo's saving. Combo lines never get a
   special offer as well.
3. The coupon applies to what is left, and its minimum order is checked
   against that. One coupon per order.
4. Service charge and tax follow on the discounted amount, as before.

The order stores each line's saving (`order_lines.discount`,
`discount_label`, `promotion_id`), a combo's dishes
(`order_lines.combo_items`) and the breakdown (`orders.discounts`); the bill
copies the totals, and `DiscountPaise`/`DiscountLabel` stay the sum and a
single label for older apps and reports. Payments are checked against the
bill's discounted total, so paying the undiscounted amount is refused as an
overpayment.

Usage limits: placing an order takes one use of each promotion and coupon
it saved with, inside the order's transaction, with a guarded
`UPDATE … SET used_count = used_count + 1 WHERE used_count < usage_limit`.
That row lock makes concurrent orders take turns, so a limit is never
exceeded: an order that loses the race is refused with `offerUnavailable`
(or, priced after it, simply gets no saving). A replayed order uses
nothing again; a cancelled order gives its uses back. An offer that reaches
its limit disappears from every guest's menu at once (a `menu` or
`settings` live update).

One restaurant per deployment (see Known limitations), so there is no
tenant column: guests read only live offers, and every change needs a
signed-in staff member with `manageOffers`.

## Live updates

SignalR hub `/hubs/events` (token in the `access_token` query parameter).
Connections join `staff` (signed-in staff), `guest:{session}` (one guest's
table session) and `all`. Events only say what changed (`orders`, `bills`,
`menu`, `settings`, `tables`, `inventory`, `staff`); the apps then re-read
the data through the REST API, so every permission check still applies and
nothing private is broadcast. After a reconnect the apps re-read everything,
and while the connection is down they refresh every 30 seconds.

This works while an app is open. Notifications for closed apps would need
push notifications (FCM/APNs), which are not set up.

## Payments

`IPaymentProvider` (`Services/Payments.cs`) is the provider seam. The server,
never the app, decides whether a payment succeeded.

The restaurant's **payment mode** (a setting, `restaurant_settings.payment_mode`)
picks the provider for new online payments (`PaymentProviders`):

- **Demo (the default)**: the built-in simulator, wherever the API runs. It
  never contacts a bank. Every payment taken in demo mode (counter ones
  recorded by staff too) is stored with `is_simulated = true` and served as
  `mode: "demo"`; bills, receipts, the payment history and the activity log
  label them as demo payments, never as verified money. References start
  with `DEMO-`. A demo payment still pending when the owner switches to live
  is resolved as failed.
- **Live**: the live gateway (`Payments:Provider`): `Cashfree` with its keys
  (below). Without one (`None`, the default; `Simulated`, an old development
  value, means the same) switching to live is refused and the restaurant
  stays in demo mode. Counter payments always work.

Every payment change takes the bill's row lock (`select … for update`)
inside a transaction, so concurrent requests on one bill run one after
another: a repeated request (same idempotency key) returns the first result,
and no mix of payments can overpay the bill. Failed and cancelled payments
never count as paid. No card number, CVV, UPI PIN or banking password is
accepted or stored: the API has no field for them.

### UPI through Cashfree (automatic confirmation)

In live mode guests pay by UPI from an app on their phone (Google Pay,
PhonePe, Paytm or any other) or by scanning a QR code, and the bill is
marked **Paid** (or **Partially paid**) on its own, with nobody checking a
bank statement. Cashfree collects the payment and settles it to the
restaurant's bank account under the restaurant's Cashfree merchant account
(Cashfree's fees and KYC apply). Code: `Services/Cashfree.cs`,
`Services/BillingService.Gateway.cs`, `Services/GatewaySweeper.cs`.

How a payment settles:

1. `POST /payments/intents` (`method: "upi"`) records a pending payment
   (holding the amount against the bill) and creates a Cashfree order for
   exactly that amount, valid for `OrderMinutes`.
2. `POST /payments/{id}/checkout` returns Cashfree's UPI app links or QR
   code for that order (Cashfree's order-pay API, UPI channel `link` or
   `qrcode`). Every link (and a QR sent as a `upi://pay` link) must ask for
   exactly the payment's amount (`am`) and currency (`cu`), or it is dropped
   and logged; a QR picture is passed on as it is. On Android the app sends
   the plain `upi://pay` link to the chosen app by its package; on iOS it
   opens the app's own link.
3. The payment counts only when **Cashfree's API** lists a `SUCCESS` payment
   on the order for exactly the amount and currency asked for. The server
   asks it when Cashfree's signed webhook arrives, when the app asks for the
   status (every few seconds, and when the guest returns from the UPI app),
   and every `ReconcileSeconds` in the background. A webhook body, the UPI
   app returning, or the guest saying they paid is never evidence on its
   own. Another amount is recorded as `failed` with the reason (nothing
   counted; audited as `payment.gateway.mismatch` for staff to check in
   Cashfree).
4. A failed or abandoned attempt, a guest's cancel, or an expired order
   ends the Cashfree order first (terminated), and only then is the payment
   recorded as not paid, so it can never succeed afterwards. If the guest
   paid just before, it is recorded as paid instead. While Cashfree says
   `TERMINATION_REQUESTED` the payment stays pending (a payment under way may
   still succeed) and is checked again.
5. Should Cashfree ever report money on an order whose payment was already
   recorded as not paid, nothing is counted (the bill may have been paid
   another way since); the audit trail gets one `payment.gateway.late` entry
   for staff to refund or record it.

Each Cashfree payment id settles at most one record (unique index), every
change runs under the bill's row lock, and duplicate webhooks change
nothing. Refunds of Cashfree payments go through Cashfree's refund API.

**Setup** (server configuration only; the apps never see a key):

| Setting | Value |
| --- | --- |
| `Payments__Provider` | `Cashfree` |
| `Payments__Cashfree__ClientId`, `Payments__Cashfree__ClientSecret` | From the Cashfree dashboard (Developers → API keys). The secret also verifies webhooks |
| `Payments__Cashfree__Environment` | `sandbox` (test keys) or `production` |
| `Payments__Cashfree__NotifyUrl` | `https://<your API host>/api/v1/webhooks/payments/cashfree`, also added as the webhook URL in the Cashfree dashboard (payment success, failed and user-dropped events) |
| `Payments__Cashfree__CustomerPhone` | The restaurant's 10-digit mobile number (Cashfree requires a phone on every order; guests give none) |
| `Payments__Cashfree__OrderMinutes`, `…__ReconcileSeconds` | Optional: 16 and 60 by default |

Then apply the `GatewayPayments` migration (`migration-scripts/GatewayPayments.sql`
on Neon, idempotent), deploy, and switch the payment mode to **Live** in the
admin app (Settings → Payments). Live mode offers UPI and QR Payment online
(plus cash and paying at the counter); UPI to the restaurant's own UPI ID
(below) is not offered while Cashfree takes UPI.

**Sandbox**: payments made with sandbox keys are Cashfree's test payments.
No money moves, so they are recorded as demo payments (`is_simulated`,
`mode: "demo"`) and bills and receipts say so, even in live mode. Real UPI
apps cannot pay sandbox orders; complete test payments with the tools in
Cashfree's sandbox (see Cashfree's sandbox documentation), then watch the
webhook settle the bill. Use production keys only for real money.

### UPI straight to the restaurant's account (no gateway)

The restaurant can take UPI payments into its own account with no payment
gateway and no provider credentials: the owner saves the UPI ID, the name
guests see and, optionally, the merchant QR picture
(`PUT /admin/payments/settings`). Only those public payee details are stored;
the server never holds a UPI PIN, card number or bank credential. The server
checks the UPI ID's form and refuses one a typo away from a Google Pay handle
(`@okabi` for `@oksbi`, `UpiRules.IdProblem`), which no one can pay. A saved ID
that breaks the rules stops UPI being offered to guests until it is fixed.

The guest pays in their own UPI app, so the server **cannot see the money**.
That shapes the whole flow (`Services/BillingService.Upi.cs`):

1. `POST /payments/upi` records a *pending* payment (provider `UPI direct`) so
   the amount is held against the bill. The app builds the `upi://pay` link
   (payee, exact amount, `INR`, note `Bill <number> <payment id>`; no `tr` or
   `mc`, which mark merchant payments). It opens the guest's chosen UPI app
   with that link (on Android sent to the app's package; "Other UPI apps" is
   Android's chooser) and keeps it as a QR code and copyable details below.
   Some UPI apps refuse a filled-in payment to a personal UPI-app ID
   (`@okaxis`, `@ybl`, `@paytm`, ...); the guest is told so, and pays by the
   QR or the copied ID instead.
2. The guest says they paid (`/upi/claim`). That only flags the payment for
   staff (`claimed`); the bill is **not** paid.
3. A cashier checks the credit in the restaurant's bank or UPI app and
   confirms it with the bank's transaction ID (`/admin/payments/{id}/verify`),
   or rejects it. Only then is it `succeeded`, so the bill, reports and
   receipts count it.

What can never settle one: returning from the UPI app, the app's own report,
a screenshot, or the development simulator (`/payments/{id}/confirm` refuses
these payments). A UPI transaction ID confirms one payment only, enforced in
the database (`ix_payments_upi_reference`). A UPI attempt the guest started
but never claimed is dropped after 15 minutes (`UpiRules.AttemptWindow`) so it
cannot block the bill; a claimed one waits for a cashier. Refunds of these
payments are recorded here and returned by the restaurant from its own UPI
app.

**Verification mode.** `manual` (default) is the cashier flow above.
`automatic` needs a bank or payment-provider integration, and **none ships with
the app**: `IUpiPaymentVerifier` (`Services/Payments.cs`) is the seam. The
registered `UnavailableUpiPaymentVerifier` reports it unavailable, so
`automatic` cannot be saved (the owner sees why) and a saved `automatic` falls
back to `manual` for guests. To add one, implement `IUpiPaymentVerifier` for
your provider (status lookup by payment; a success must carry the bank's
reference, or it is ignored) and register it in `Program.cs`; pending payments
are then resolved when a bill or payment is refreshed or reconciled. A webhook
endpoint would call the same rules; it is not built because its signature
scheme depends on the provider.

Uploaded QR pictures are served from the same upload folder as dish photos
(`/uploads/upi/…`), so they share its caveat: on a host with an ephemeral disk
they disappear on redeploy. Payments do not depend on the picture: the QR guests
scan is generated from the UPI ID and amount.

## Receipts and printing

Receipts are built in the apps (`dineqr_design_system`: PDF for 80 mm, A5
and A4, share and the platform print dialog) from bills read from the API,
so printing never creates a second bill or payment. ESC/POS bytes for
thermal printers are generated (`EscPosReceipt`); no printer driver plugin
is included.

## Database

Tables (snake_case): `users` (adopted), `refresh_tokens`,
`restaurant_settings` (one row), `discount_offers` (coupons), `promotions`
and `promotion_items` (special offers and combos), `menu_categories`,
`menu_items`, `menu_item_portions`, `menu_item_add_ons`,
`restaurant_tables`, `orders`, `order_lines`, `order_status_history`,
`invoices`, `payments`, `refunds`, `audit_logs`, `inventory_items`,
`stock_movements`, plus sequences for order (`OD12345`), bill, payment,
refund and stock ids.

- Money columns are `numeric(14,2)` rupees (exact); the code works in integer
  paise.
- UPI to the restaurant (migration `AddUpiPayments`): `restaurant_settings`
  gains `upi_enabled`, `upi_id`, `upi_payee_name`, `upi_qr_image` and
  `upi_verification_mode` (all defaulted, so existing rows stay valid and a
  running older API keeps working), and `payments` gains `claimed_at` plus a
  partial unique index on `reference` for confirmed UPI payments. Payments,
  amounts, statuses and timestamps use the existing `payments` table.
- Takeaway orders and their bills have `table_number = 0` (no table; there
  is no foreign key from orders to tables, so past orders keep their table
  number). The takeaway switch is `restaurant_settings.parcel_orders_enabled`
  (`TakeawayOrdersEnabled` in the code): the column keeps its name from
  before the rename, so the rename needed no migration and a deploy never
  runs an API version against a column it does not know.
- Orders and bills store their own pricing snapshot, so menu changes never
  alter history. Order lines keep the chosen portion, spice and add-ons.
- Offers (migration `Promotions`): `promotions` (id, kind `special`/`combo`,
  title, description, image, `starts_on`/`ends_on` dates, `is_active`,
  `usage_limit`, `used_count`, `discount_type`/`discount_value` for special
  offers, `combo_price` for combos) and `promotion_items` (dish and quantity;
  a foreign key to `menu_items`, which are archived, never deleted).
  `discount_offers` gains `starts_on`, `ends_on`, `usage_limit` and
  `used_count`. `order_lines` gains `combo_id`, `combo_items` (jsonb),
  `discount`, `discount_label` and `promotion_id`; `orders` gains
  `discounts` (jsonb). Every new column is nullable or defaulted, so
  existing orders read as before and the previous API keeps working.
- Unique idempotency keys on orders, payments and refunds; optimistic
  concurrency (`xmin`) on orders and bills; check constraints on amounts,
  quantities, seats and table numbers.
- Timestamps are `timestamptz` (UTC). Reports use the restaurant's UTC
  offset from settings for business days.

New migration: `dotnet ef migrations add <Name> --project src/DineQR.Api --output-dir Data/Migrations -- --environment Development`.
Review it (and back up) before `dotnet ef database update`.

## Tests

```powershell
cd backend
# once: a connection string for a THROWAWAY database (name must contain "test")
dotnet user-secrets set "ConnectionStrings:Tests" "Host=localhost;Port=5432;Database=dineqr_tests;Username=postgres;Password=<password>" --project tests/DineQR.Api.Tests
dotnet test
```

The fixture creates `dineqr_tests`, migrates and seeds it, runs the API in a
`Testing` environment (which never loads the API's user secrets, so it
cannot reach the real database) and drops the database afterwards. The tests
cover pricing and rounding, offers, server-side order pricing, idempotent
replays, price-change refusal, sold-out dishes and inactive tables, guest
isolation, the status workflow per role, cancellation voiding the bill,
online payment verification (declined, in progress, paid), counter payments,
refunds and their limits, report figures (failed payments are not
collected), sign-in, refresh rotation and reuse detection, lockout,
immediate effect of deactivation, the last-owner rule, table assignments,
stock-driven sold-out dishes, takeaway (the switch and its legacy
`parcel` key, takeaway and legacy codes, the whole workflow from order to
payment, the order type check, idempotent replays, counter takeaway orders,
and dine-in alongside it), and payment modes (`PaymentModeTests`: demo by
default and live refused without a gateway, demo labels, method detail and
currency on payments, card numbers refused, failed and cancelled payments
never counted, counter requests and who may make them, a split bill settled
once, concurrent attempts on one bill never overpaying it, and the currency
lock).

Flutter side (`packages/dineqr_core/test/api_test.dart`): the HTTP client,
token renewal, request shapes (dishes and options, never prices), error
mapping, payments and the idempotent retry of a checkout.
`test/live_api_e2e_test.dart` runs the customer and staff wiring against a
running API (an order reaching staff, and a status change and a payment
reaching both apps live); start the API against a throwaway database first:

```powershell
# terminal 1: API on port 5265 with a throwaway database (create it first)
$env:ASPNETCORE_ENVIRONMENT="Testing"; $env:ASPNETCORE_URLS="http://localhost:5265"
$env:ConnectionStrings__DefaultConnection="Host=localhost;Database=dineqr_e2e_test;Username=postgres;Password=<password>"
$env:Jwt__SigningKey="<32+ bytes>"; $env:Database__MigrateOnStartup="true"; $env:Seed__InitialCatalog="true"
$env:Bootstrap__OwnerEmail="owner@e2e.local"; $env:Bootstrap__OwnerPassword="<password>"; $env:Payments__Provider="Simulated"
dotnet run --project src/DineQR.Api --no-launch-profile

# terminal 2
cd packages/dineqr_core
flutter test test/live_api_e2e_test.dart --dart-define=DINEQR_E2E_API_URL=http://localhost:5265 --dart-define=DINEQR_E2E_OWNER_EMAIL=owner@e2e.local --dart-define=DINEQR_E2E_OWNER_PASSWORD=<password>
```

## Deploying on Render with Neon

The API runs on Render as a Docker web service built from the root
`Dockerfile`, at `https://hotelmenuorder.onrender.com`, on a Neon PostgreSQL
database. The image listens on port 10000 and trusts Render's
`X-Forwarded-Proto`/`X-Forwarded-For`, so the API sees `https` and each
caller's own address. Set these in the Render service's **Environment**
(never in the repository):

| Variable | Value |
| --- | --- |
| `ConnectionStrings__DefaultConnection` | Neon's connection details in Npgsql form: `Host=<endpoint>.<region>.aws.neon.tech;Port=5432;Database=<db>;Username=<role>;Password=<password>;SSL Mode=VerifyFull` |
| `Jwt__SigningKey` | At least 32 random bytes, e.g. base64 of 48 random bytes |
| `ImageStorage__PublicBaseUrl` | `https://hotelmenuorder.onrender.com` |
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `Bootstrap__OwnerEmail`, `Bootstrap__OwnerPassword` | Only until the first owner exists, then remove |

Everything else defaults correctly from `appsettings.json` (JWT issuer,
audience and lifetimes, `Database:MigrateOnStartup=false`,
`Seed:InitialCatalog=false`, `Payments:Provider=None`,
`OpenApi:Enabled=false`). Do not set `ASPNETCORE_URLS` on Render. Set the
service's **Health Check Path** to `/health`.

Apply migrations from your computer after reviewing them, with the Neon
connection string in this terminal only:

```powershell
cd backend
dotnet tool restore
$env:ConnectionStrings__DefaultConnection = "<Neon connection string>"
dotnet ef migrations list --project src/DineQR.Api     # pending ones are marked
dotnet ef migrations script --idempotent --project src/DineQR.Api
dotnet ef database update --project src/DineQR.Api
Remove-Item Env:ConnectionStrings__DefaultConnection
```

The `PaymentModes` migration (payment mode and currency on the settings,
currency and method detail on payments, the counter request on bills) must
be applied **before** deploying the API that uses it. The previous API
works with it applied: every new column has a default (`demo`, `INR`).
After the deploy, guests see the demo payment options at once, since demo
is the default mode.

The `GatewayPayments` migration (`expires_at` and `provider_payment_id` on
payments, two indexes) must be applied **before** deploying the API with
Cashfree; `migration-scripts/GatewayPayments.sql` does it (idempotent). The
previous API works with it applied: both columns are nullable. Then add the
`Payments__Cashfree__*` settings (see Payments) and switch to live mode.

The `Promotions` migration (offers, combos, coupon dates and limits, and
the discount breakdown on orders) must be applied **before** deploying the
API that uses it; `migration-scripts/Promotions.sql` does it (idempotent,
from `StaffRoleTitle`, so `StaffCustomAccess.sql` goes first). The previous
API works with it applied. Apps from before it keep working against the new
API (they ignore the new fields, and their settings saves keep each
coupon's dates and limit) with one exception: they do not know special
offers, so the total they expect for a dish on offer is too high and the
server refuses the order with `priceChanged`. Update the customer and admin
apps before creating the first special offer.

Renaming "parcel" to "takeaway" needed no migration, and either side can be
updated first: the API still accepts and serves the old `parcel` setting
and `DINEQR:PARCEL` code, and the apps send both setting keys and fall back
to the old code when an older API does not know `DINEQR:TAKEAWAY`. Printed
`DINEQR:PARCEL` codes keep working; reprint from **Tables & QR** whenever
convenient.

### Dish photos

Render's disk is ephemeral, so photos are **not** kept on disk: every upload
is converted and stored in PostgreSQL (table `stored_images`), and served
from `GET /api/v1/images/{id}.webp` with a one-year `immutable` cache. They
survive redeploys and restarts, and cost the database roughly 50-500 KB each.
The `StoredImages` migration must be applied **before** deploying an API that
uses it; the previous API keeps working with it applied.

What an upload goes through:

1. The format is decided by the file's leading bytes, never its name or
   declared type: JPEG, PNG, GIF, WebP, BMP, TIFF, ICO, AVIF and HEIC/HEIF.
2. The whole file is decoded (Magick.NET, with the format named explicitly,
   and pixel/memory limits). A file that merely starts like a photo is
   refused as damaged, and anything else (PDF, SVG, executables) as
   unsupported.
3. It is turned upright (EXIF orientation), converted to sRGB, stripped of
   metadata such as GPS, scaled to fit `MaxDimension` and stored as WebP,
   which every app can draw. Animated images keep their first frame.

Settings (`ImageStorage__*` environment variables):

| Setting | Default | |
| --- | --- | --- |
| `MaxBytes` | 10485760 | Largest upload. Keep in step with `DishImageUploader.maxBytes` in the apps |
| `AllowedFormats` | all nine | Comma-separated, e.g. `jpeg,png,webp` to restrict. The apps keep no list of their own |
| `MaxDimension` / `Quality` | 1600 / 82 | Size and WebP quality of the stored photo |
| `MaxSourcePixels` / `MaxDecodeMemoryMb` | 30000000 / 320 | Decoding limits; raise them only with the host's memory |
| `PublicBaseUrl` | | Absolute base for returned URLs |

At start-up the API logs which formats it accepts and warns if the host's
image library cannot read one of them. Older photos uploaded to
`wwwroot/uploads` are still served if the file survived (on Render it does
not; re-upload those dishes' photos). Replaced or abandoned photos are not
deleted automatically.

## Production checklist

- [ ] HTTPS in front of the API (reverse proxy or Kestrel certificate);
      release app builds use the `https://` URL.
- [ ] `ConnectionStrings__DefaultConnection`, a long random `Jwt__SigningKey`,
      and `ASPNETCORE_ENVIRONMENT=Production` as environment variables.
- [ ] A database user with only the rights the API needs; regular `pg_dump`
      backups and a tested restore.
- [ ] Migrations applied with `dotnet ef database update` (or a migration
      bundle) after review; `Database__MigrateOnStartup=false`. **Apply
      `AddUpiPayments` before (or with) deploying an API that includes it**:
      with `MigrateOnStartup=false` the new API does not apply it, and without
      its columns the settings queries fail.
- [ ] First owner created, then the `Bootstrap__*` values removed.
- [ ] `Seed__InitialCatalog` only on the first run, then false (it never
      overwrites, but the real menu should replace the sample one).
- [ ] Cashfree **production** keys, `NotifyUrl` and the webhook set up in
      the Cashfree dashboard (see Payments), and `GatewayPayments` applied,
      before taking real money online; until then the restaurant runs in
      demo mode, where online payments are simulated and labelled as demo
      payments.
- [ ] `Cors__AllowedOrigins` for web builds; Swagger off (`OpenApi__Enabled=false`).
- [ ] Release signing for both Android apps and Apple provisioning for iOS.
- [ ] Push notifications if staff need alerts while the app is closed.

## Known limitations

- Cashfree is the only gateway, and it takes UPI only (UPI apps and QR
  codes): live mode has no card, net banking or wallet checkout. It has been
  tested against a faithful fake of Cashfree's API and webhooks, not yet
  against Cashfree's own sandbox; do that with your keys before going live.
  Cashfree's 2023-08-01 API reference documents the order-pay request but
  not the UPI `payload` keys of its answer; the app links follow Cashfree's
  published UPI-intent example (`default`, `gpay`, `phonepe`, `paytm`,
  `bhim`, `web`), and the QR is accepted either as a picture or as a link.
  In sandbox those "links" are Cashfree's simulator web page, which the app
  opens in the browser.
- A Cashfree payment cannot be one part of a split payment (each part must
  finish before the next, and a UPI payment finishes when Cashfree reports
  it).
- One restaurant per deployment: settings are a single row. Guests reach
  only their own session's bills and staff are checked per role, but there
  is no multi-restaurant (tenant) separation inside one database.
- Reports count demo payments as collected, like any other recorded payment.
- UPI to the restaurant's own UPI ID (without Cashfree) is confirmed by a
  cashier. Automatic verification has its seam (`IUpiPaymentVerifier`) but
  no bank adapter, so it stays unavailable; use Cashfree for automatic
  confirmation. It is offered to guests only while the restaurant bills in
  INR and Cashfree does not take UPI.
- A personal (non-merchant) UPI ID may be refused or limited by some UPI apps
  when paid through a link or QR; use the restaurant's merchant UPI ID.
- Staff screens load the last 90 days of orders and bills (plus everything
  still open); reports for older ranges should use
  `GET /admin/reports/summary`, which the admin app does not call yet.
- Waiters' "my tables" sections are still saved per device; the server's
  table assignments (`server` field) are not yet used by the admin app.
- Live updates need the app to be open; there are no push notifications.
