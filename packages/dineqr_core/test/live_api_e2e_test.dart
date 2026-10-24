// End-to-end check of the customer and staff wiring against a running
// DineQR API (never the production database):
//
//     flutter test test/live_api_e2e_test.dart \
//       --dart-define=DINEQR_E2E_API_URL=http://localhost:5265 \
//       --dart-define=DINEQR_E2E_OWNER_EMAIL=owner@e2e.local \
//       --dart-define=DINEQR_E2E_OWNER_PASSWORD=...
//
// Skipped when no URL is given. See backend/README.md for starting the API
// against a throwaway database.
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = String.fromEnvironment('DINEQR_E2E_API_URL');
const _ownerEmail = String.fromEnvironment('DINEQR_E2E_OWNER_EMAIL');
const _ownerPassword = String.fromEnvironment('DINEQR_E2E_OWNER_PASSWORD');

/// Waits until [condition] holds (live updates arrive asynchronously).
Future<void> _eventually(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

class _SignedIn implements AccessGuard {
  const _SignedIn(this.actor);

  @override
  final StaffAccount actor;

  @override
  bool can(Permission permission) => actor.can(permission);

  @override
  void require(Permission permission) {
    if (!can(permission)) throw PermissionDeniedException(permission);
  }
}

/// The shared services as the apps wire them. Creating them reads nothing
/// from the server; like the apps, this then loads the restaurant settings
/// (prices and taxes depend on them).
Future<DineQrServices> _services(
  DineQrBackend backend, {
  AccessGuard guard = const GuestAccess(),
}) async {
  final services = await DineQrServices.create(
    store: MemoryStore(),
    config: const AppConfig(demoMode: false),
    guard: guard,
    menuRepository: backend.menu,
    orderRepository: backend.orders,
    billingRepository: backend.billing,
    settingsRepository: backend.settings,
    paymentGateway: await backend.paymentGateway(),
    billingBackend: backend.billingBackend,
  );
  await services.settings.load();
  return services;
}

void main() {
  test(
    'a guest order reaches staff, and status and payment reach both, live',
    () async {
      final config = ApiConfig(baseUrl: Uri.parse(_url));

      // ---- Customer app wiring: menu, settings and table from the API.
      final guestStore = MemoryStore();
      final guest = DineQrBackend.guest(config, guestStore);
      final guestServices = await _services(guest);
      await guestServices.catalog.load();
      expect(guestServices.catalog.state, LoadState.ready);
      expect(guestServices.catalog.allItems, isNotEmpty);
      expect(await guest.guestSession!.start('DINEQR:TABLE:05'), 5);
      final guestLive = LiveUpdates(
        guest.realtime,
        handlers: {
          'orders': guestServices.orders.load,
          'bills': guestServices.billing.load,
        },
      );
      await guest.realtime.start();
      expect(guest.realtime.isConnected, isTrue);

      final cart = CartController(
        guestStore,
        pricingSource: () => guestServices.settings.pricing,
        offerLookup: (code) =>
            guestServices.settings.settings.offerByCode(code),
      );
      cart.add(guestServices.catalog.byId('chicken_65')!, quantity: 2);
      final shownTotal = cart.bill.total;
      final order = await guestServices.orders.placeOrder(
        cart: cart,
        tableNumber: 5,
      );
      // The server priced it exactly as the app showed it.
      expect(order.id, startsWith('OD'));
      expect(order.bill.total, shownTotal);
      final bill = await guestServices.billing.createForOrder(order);
      expect(bill.total, shownTotal);

      // ---- Admin app wiring: staff sign-in and the same order.
      final staff = DineQrBackend.staff(config, MemoryTokenStorage());
      final signedIn = await staff.auth!.signIn(_ownerEmail, _ownerPassword);
      final staffServices = await _services(
        staff,
        guard: _SignedIn(signedIn.staff),
      );
      // The admin app loads staff data once someone has signed in.
      await staffServices.orders.load();
      await staffServices.billing.load();
      expect(staffServices.orders.byId(order.id), isNotNull);
      final staffLive = LiveUpdates(
        staff.realtime,
        handlers: {
          'orders': staffServices.orders.load,
          'bills': staffServices.billing.load,
        },
      );
      await staff.realtime.start();

      // The kitchen accepts it; the guest's tracking updates by itself.
      await staffServices.orders.updateStatus(order.id, OrderStatus.accepted);
      await _eventually(
        () =>
            guestServices.orders.byId(order.id)?.status == OrderStatus.accepted,
        'the guest to see the accepted order',
      );

      // The guest pays through the server's (development) simulator; staff
      // see the bill paid without reloading.
      final payment = await guestServices.billing.payOnline(
        invoiceId: bill.id,
        amount: bill.payableNow,
        method: PaymentMethodType.upi,
      );
      expect(payment.status, PaymentStatus.succeeded);
      expect(payment.isSimulated, isTrue);
      expect(guestServices.billing.byId(bill.id)!.status, InvoiceStatus.paid);
      await _eventually(
        () => staffServices.billing.byId(bill.id)?.status == InvoiceStatus.paid,
        'staff to see the bill paid',
      );

      await guestLive.dispose();
      await staffLive.dispose();
      await guest.realtime.dispose();
      await staff.realtime.dispose();
    },
    skip: _url.isEmpty ? 'Set DINEQR_E2E_API_URL to run against an API' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a takeaway order goes from the guest to staff and back, live',
    () async {
      final config = ApiConfig(baseUrl: Uri.parse(_url));

      // ---- Admin app wiring: an owner opens takeaway.
      final staff = DineQrBackend.staff(config, MemoryTokenStorage());
      final signedIn = await staff.auth!.signIn(_ownerEmail, _ownerPassword);
      final staffServices = await _services(
        staff,
        guard: _SignedIn(signedIn.staff),
      );
      await staffServices.settings.updateSettings(
        staffServices.settings.settings.copyWith(takeawayOrdersEnabled: true),
      );

      // ---- Customer app wiring: the restaurant now takes takeaway.
      final guestStore = MemoryStore();
      final guest = DineQrBackend.guest(config, guestStore);
      final guestServices = await _services(guest);
      expect(guestServices.settings.settings.takeawayOrdersEnabled, isTrue);
      expect(guestServices.settings.isOrderable(OrderTables.takeaway), isTrue);
      await guestServices.catalog.load();
      // Codes printed under the old name still start a takeaway session.
      expect(
        await guest.guestSession!.start('DINEQR:PARCEL'),
        OrderTables.takeaway,
      );
      expect(
        await guest.guestSession!.start(TableQrParser.takeawayPayload),
        OrderTables.takeaway,
      );
      final guestLive = LiveUpdates(
        guest.realtime,
        handlers: {
          'orders': guestServices.orders.load,
          'bills': guestServices.billing.load,
          'settings': guestServices.settings.load,
        },
      );
      await guest.realtime.start();

      final cart = CartController(
        guestStore,
        pricingSource: () => guestServices.settings.pricing,
        offerLookup: (code) =>
            guestServices.settings.settings.offerByCode(code),
      );
      cart.add(guestServices.catalog.byId('paneer_tikka')!, quantity: 2);
      final shownTotal = cart.bill.total;
      final order = await guestServices.orders.placeOrder(
        cart: cart,
        tableNumber: OrderTables.takeaway,
      );
      expect(order.isTakeaway, isTrue);
      expect(order.tableLabel, 'Takeaway');
      expect(order.bill.total, shownTotal);
      final bill = await guestServices.billing.createForOrder(order);
      expect(bill.isTakeaway, isTrue);
      expect(bill.total, shownTotal);

      // ---- Staff see it as takeaway and take it through the workflow.
      await staffServices.orders.load();
      await staffServices.billing.load();
      expect(staffServices.orders.byId(order.id)!.isTakeaway, isTrue);
      final staffLive = LiveUpdates(
        staff.realtime,
        handlers: {
          'orders': staffServices.orders.load,
          'bills': staffServices.billing.load,
        },
      );
      await staff.realtime.start();
      for (final target in [
        OrderStatus.accepted,
        OrderStatus.preparing,
        OrderStatus.readyToServe,
        OrderStatus.served,
      ]) {
        await staffServices.orders.updateStatus(order.id, target);
      }
      await _eventually(
        () => guestServices.orders.byId(order.id)?.status == OrderStatus.served,
        'the guest to see the order collected',
      );
      expect(guestServices.orders.byId(order.id)!.statusLabel, 'Collected');

      // A counter takeaway order rung up by staff.
      await staffServices.catalog.load();
      final counterCart = CartController(
        MemoryStore(),
        pricingSource: () => staffServices.settings.pricing,
      )..add(staffServices.catalog.byId('samosa')!);
      final counter = await staffServices.orders.placeOrder(
        cart: counterCart,
        tableNumber: OrderTables.takeaway,
        source: OrderSource.staff,
      );
      expect(counter.isTakeaway, isTrue);
      expect(counter.source, OrderSource.staff);

      // The guest pays through the server's development simulator; the
      // staff list shows the bill paid without reloading.
      final payment = await guestServices.billing.payOnline(
        invoiceId: bill.id,
        amount: bill.payableNow,
        method: PaymentMethodType.upi,
      );
      expect(payment.status, PaymentStatus.succeeded);
      await _eventually(
        () => staffServices.billing.byId(bill.id)?.status == InvoiceStatus.paid,
        'staff to see the takeaway bill paid',
      );

      // Closing takeaway stops new takeaway orders, even on an open session.
      await staffServices.settings.updateSettings(
        staffServices.settings.settings.copyWith(takeawayOrdersEnabled: false),
      );
      cart.add(guestServices.catalog.byId('paneer_tikka')!);
      await expectLater(
        guestServices.orders.placeOrder(
          cart: cart,
          tableNumber: OrderTables.takeaway,
        ),
        throwsA(
          isA<CheckoutException>().having(
            (e) => e.error,
            'error',
            CheckoutError.takeawayUnavailable,
          ),
        ),
      );

      await guestLive.dispose();
      await staffLive.dispose();
      await guest.realtime.dispose();
      await staff.realtime.dispose();
    },
    skip: _url.isEmpty ? 'Set DINEQR_E2E_API_URL to run against an API' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
