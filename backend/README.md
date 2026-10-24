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
| `GET /settings`, `GET /menu`, `GET /tables`, `GET /tables/{n}` | public | Restaurant settings and active offers, the guest menu, table numbers and whether they take orders |
| `GET /payments/config` | public | Which payment provider is configured (no secrets) |
| `POST /guest/sessions` | public | `{qrPayload: "DINEQR:TABLE:05"}` → a guest token scoped to that table (4 h), `{guestToken, tableNumber, expiresAt, orderType}`; refused for unknown or inactive tables. `DINEQR:TAKEAWAY` (or `DINEQR:PARCEL`, its earlier name) starts a takeaway session (`tableNumber: 0`, `orderType: "takeaway"`) while takeaway is open, else `takeawayUnavailable` |
| `POST /orders` | guest | `{lines: [{itemId, quantity, options}], instructions, offerCode, idempotencyKey, expectedTotal, orderType}`. Priced by the server; refused with `priceChanged` if the total differs from what the guest saw; replays return the original order. `orderType` (`dineIn` or `takeaway`, optional) must match the session (`orderTypeMismatch`); a takeaway order is refused with `takeawayUnavailable` once takeaway closes |
| `GET /orders`, `GET /bills` | guest | The session's own orders and bills |
| `GET /orders/{id}`, `GET /orders/{id}/bill`, `GET /bills/{id}` | own guest session, or staff with viewOrders / viewBills | |
| `POST /orders/{id}/feedback` | guest | Once, after the order is served |
| `POST /payments/intents` | own guest session or staff | Records a **pending** payment before the provider is involved; refuses overpayment, part payments when not allowed, and a second attempt while one is pending |
| `POST /payments/{id}/confirm` | own guest session or staff | Sends the provider's checkout result; the **server verifies it** with the provider before the payment counts |
| `GET /payments/{id}` | own guest session or staff | Current status; pending payments are re-checked |
| `GET /admin/menu` | staff | Every dish (archived too) and category |
| `PUT /admin/menu/items/{id}`, `PATCH /admin/menu/items/{id}` | manageMenu | Create/replace a dish (validated like the app); `{available}` / `{archived}` |
| `PUT /admin/menu/categories` | manageCategories | The category list; a category still used by any dish cannot be removed |
| `GET /admin/settings`, `PUT /admin/settings` | staff / manageSettings | Settings and every offer. `takeaway` opens or closes takeaway; it is also served as `parcel` for apps from before the rename, `parcel` is accepted when `takeaway` is missing, and a save with neither keeps the current value |
| `GET /admin/tables`, `PUT /admin/tables` | staff / manageTables | The table list. Removing a table with open orders or unpaid bills is refused. `server`: omitted keeps the assignment, `""` clears it |
| `GET /admin/servers` | viewTables | Staff who can serve tables |
| `GET /admin/orders?from=&to=&status=` | viewOrders | Orders in the range plus every open order |
| `POST /admin/orders` | createOrders | Staff/counter order for `tableNumber`, or `orderType: "takeaway"` with no table (table `0` from older apps means the same) |
| `POST /admin/orders/{id}/status` | manageKitchen / serveOrders / cancelOrders (by target) | Only the next stage, or `cancelled` with a reason (voids the bill; money already paid shows as a refund due) |
| `GET /admin/bills?from=&to=`, `GET /admin/bills/{id}` | viewBills | Bills in the range plus every unsettled one |
| `POST /admin/bills/{id}/payments` | collectPayments | Counter payment (cash, card terminal, UPI at the counter), idempotent |
| `POST /admin/bills/{id}/reconcile` | reconcilePayments | Re-checks pending online payments with the provider |
| `POST /admin/payments/{id}/refunds` | issueRefunds | Up to what is refundable on that payment, idempotent |
| `GET/POST /admin/staff`, `PATCH /admin/staff/{id}`, `POST /admin/staff/{id}/password` | manageStaff | Never returns hashes. You cannot change your own role or deactivate yourself; one active owner always remains; deactivation and password resets end that person's sessions |
| `GET /admin/audit?from=&to=&action=&limit=` | viewAuditLog | Every privileged action, recorded in the same transaction as the change |
| `GET /admin/inventory`, `POST /admin/inventory`, `PUT /admin/inventory/{id}`, `POST /admin/inventory/{id}/adjustments` | manageInventory | Stock changes only through adjustments; running out marks linked dishes sold out (and restocking makes them available) when that setting is on |
| `GET /admin/reports/summary?from=YYYY-MM-DD&to=YYYY-MM-DD` | viewReports (money fields need viewFinancials) | Restaurant days, inclusive: orders, gross and net sales, discounts, service, taxes, billed, collected (successful payments only), refunds, outstanding, bill counts, failed payments, by method, daily, items |

The permission matrix (owner, manager, cashier, kitchen, waiter, accountant)
is in `Domain/Enums.cs` (`RolePermissions`) and mirrors the apps'
`StaffRole.permissions`. The apps only use it to shape their screens; the
server checks it on every request, against the account's **current** role
and active flag in the database.

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

- **Production default (`Payments:Provider = None`)**: online payment is
  unavailable (the apps show that); counter payments recorded by staff work.
- **Development (`Simulated`)**: a simulator that only runs in Development.
  Every payment it handles is stored with `is_simulated = true`, and bills and
  receipts say no money moved.
- **A real provider (for example Razorpay)** needs: the key id and secret and
  the webhook secret in server configuration (never in the apps);
  `CreateOrderAsync` creating the provider order for the pending payment;
  `VerifyAsync` checking `HMAC_SHA256(order_id|payment_id, secret)` and
  fetching the payment to confirm amount and status; a signed, idempotent
  webhook endpoint for payments whose confirmation never arrived; refunds
  through the provider API; and the provider's checkout SDK in the customer
  app (it then calls `/payments/{id}/confirm` with the signed result).

## Receipts and printing

Receipts are built in the apps (`dineqr_design_system`: PDF for 80 mm, A5
and A4, share and the platform print dialog) from bills read from the API,
so printing never creates a second bill or payment. ESC/POS bytes for
thermal printers are generated (`EscPosReceipt`); no printer driver plugin
is included.

## Database

Tables (snake_case): `users` (adopted), `refresh_tokens`,
`restaurant_settings` (one row), `discount_offers`, `menu_categories`,
`menu_items`, `menu_item_portions`, `menu_item_add_ons`,
`restaurant_tables`, `orders`, `order_lines`, `order_status_history`,
`invoices`, `payments`, `refunds`, `audit_logs`, `inventory_items`,
`stock_movements`, plus sequences for order (`OD12345`), bill, payment,
refund and stock ids.

- Money columns are `numeric(14,2)` rupees (exact); the code works in integer
  paise.
- Takeaway orders and their bills have `table_number = 0` (no table; there
  is no foreign key from orders to tables, so past orders keep their table
  number). The takeaway switch is `restaurant_settings.parcel_orders_enabled`
  (`TakeawayOrdersEnabled` in the code): the column keeps its name from
  before the rename, so the rename needed no migration and a deploy never
  runs an API version against a column it does not know.
- Orders and bills store their own pricing snapshot, so menu changes never
  alter history. Order lines keep the chosen portion, spice and add-ons.
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
stock-driven sold-out dishes, and takeaway (the switch and its legacy
`parcel` key, takeaway and legacy codes, the whole workflow from order to
payment, the order type check, idempotent replays, counter takeaway orders,
and dine-in alongside it).

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

Renaming "parcel" to "takeaway" needed no migration, and either side can be
updated first: the API still accepts and serves the old `parcel` setting
and `DINEQR:PARCEL` code, and the apps send both setting keys and fall back
to the old code when an older API does not know `DINEQR:TAKEAWAY`. Printed
`DINEQR:PARCEL` codes keep working; reprint from **Tables & QR** whenever
convenient.

Render's disk is ephemeral: dish photos uploaded through the admin app
(`wwwroot/uploads`) are lost on every redeploy or restart, while the menu
keeps pointing at them. Until photos move to object storage, use the
bundled photos or `https://` image URLs hosted elsewhere.

## Production checklist

- [ ] HTTPS in front of the API (reverse proxy or Kestrel certificate);
      release app builds use the `https://` URL.
- [ ] `ConnectionStrings__DefaultConnection`, a long random `Jwt__SigningKey`,
      and `ASPNETCORE_ENVIRONMENT=Production` as environment variables.
- [ ] A database user with only the rights the API needs; regular `pg_dump`
      backups and a tested restore.
- [ ] Migrations applied with `dotnet ef database update` (or a migration
      bundle) after review; `Database__MigrateOnStartup=false`.
- [ ] First owner created, then the `Bootstrap__*` values removed.
- [ ] `Seed__InitialCatalog` only on the first run, then false (it never
      overwrites, but the real menu should replace the sample one).
- [ ] A real payment provider (see Payments) or online payment left off.
- [ ] `Cors__AllowedOrigins` for web builds; Swagger off (`OpenApi__Enabled=false`).
- [ ] Release signing for both Android apps and Apple provisioning for iOS.
- [ ] Push notifications if staff need alerts while the app is closed.

## Known limitations

- No real payment provider is integrated (provider seam, simulator and the
  required steps are in place; see Payments).
- Staff screens load the last 90 days of orders and bills (plus everything
  still open); reports for older ranges should use
  `GET /admin/reports/summary`, which the admin app does not call yet.
- Waiters' "my tables" sections are still saved per device; the server's
  table assignments (`server` field) are not yet used by the admin app.
- Live updates need the app to be open; there are no push notifications.
