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

  test(
    'a UPI payment to the restaurant is settled only by staff, live',
    () async {
      final config = ApiConfig(baseUrl: Uri.parse(_url));

      // ---- Admin app wiring: the owner sets up UPI to the restaurant's own
      // account. No payment provider is connected, so only manual
      // verification can be chosen.
      final staff = DineQrBackend.staff(config, MemoryTokenStorage());
      final signedIn = await staff.auth!.signIn(_ownerEmail, _ownerPassword);
      final owner = _SignedIn(signedIn.staff);
      final staffServices = await _services(staff, guard: owner);
      final paymentSettings = PaymentSettingsController(
        staff.paymentSettings!,
        owner,
      );
      await paymentSettings.load();
      expect(paymentSettings.automaticVerificationAvailable, isFalse);
      // The server itself refuses automatic verification without a provider.
      await expectLater(
        staff.paymentSettings!.save(
          const UpiSettings(
            enabled: true,
            upiId: 'e2e@okhdfcbank',
            payeeName: 'E2E Cafe',
            verificationMode: UpiVerificationMode.automatic,
          ),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('none is set up'),
          ),
        ),
      );
      await paymentSettings.save(
        const UpiSettings(
          enabled: true,
          upiId: ' E2E@OkHDFCBank ',
          payeeName: 'E2E Cafe',
        ),
      );
      expect(paymentSettings.upi.isReady, isTrue);
      expect(paymentSettings.upi.upiId, 'e2e@okhdfcbank');

      // ---- Customer app wiring: a table session, then the payee.
      final guestStore = MemoryStore();
      final guest = DineQrBackend.guest(config, guestStore);
      final guestServices = await _services(guest);
      await guestServices.catalog.load();
      expect(await guest.guestSession!.start('DINEQR:TABLE:06'), 6);
      expect(guestServices.billing.upiDirectAvailable, isFalse);
      await guestServices.billing.loadUpiSettings();
      expect(guestServices.billing.upiDirectAvailable, isTrue);
      expect(guestServices.billing.upiSettings.upiId, 'e2e@okhdfcbank');
      expect(guestServices.billing.upiSettings.payeeName, 'E2E Cafe');
      expect(guestServices.billing.guestMethods.first, PaymentMethodType.upi);

      final guestLive = LiveUpdates(
        guest.realtime,
        handlers: {'bills': guestServices.billing.load},
      );
      await guest.realtime.start();

      final cart = CartController(
        guestStore,
        pricingSource: () => guestServices.settings.pricing,
        offerLookup: (code) =>
            guestServices.settings.settings.offerByCode(code),
      )..add(guestServices.catalog.byId('paneer_tikka')!);
      final order = await guestServices.orders.placeOrder(
        cart: cart,
        tableNumber: 6,
      );
      final bill = await guestServices.billing.createForOrder(order);

      // ---- The guest starts the payment: held against the bill, not paid.
      final payment = await guestServices.billing.startUpiPayment(
        invoiceId: bill.id,
        amount: bill.payableNow,
      );
      expect(payment.status, PaymentStatus.pending);
      expect(payment.isUpiDirect, isTrue);
      expect(payment.isSimulated, isFalse);
      expect(payment.amount, bill.total);
      var guestBill = guestServices.billing.byId(bill.id)!;
      expect(guestBill.status, InvoiceStatus.pending);
      expect(guestBill.amountPaid, Money.zero);
      expect(guestBill.payableNow, Money.zero);

      // The link is built from the server's own record of the payment.
      final link = UpiPaymentLink.forPayment(
        settings: guestServices.billing.upiSettings,
        invoice: guestBill,
        payment: payment,
      );
      expect(link.uri.queryParameters['pa'], 'e2e@okhdfcbank');
      expect(link.uri.queryParameters['tr'], payment.id);
      expect(link.uri.queryParameters['am'], link.amountText);
      expect(link.uri.queryParameters['cu'], 'INR');

      // ---- Staff see the payment as it waits.
      await staffServices.billing.load();
      final staffLive = LiveUpdates(
        staff.realtime,
        handlers: {'bills': staffServices.billing.load},
      );
      await staff.realtime.start();
      expect(
        staffServices.billing.byId(bill.id)!.status,
        InvoiceStatus.pending,
      );

      // ---- The guest says they paid: staff are told, the bill is not paid.
      final claimed = await guestServices.billing.claimUpiPayment(
        payment.id,
        reference: 'e2eutr000001',
      );
      expect(claimed.isClaimed, isTrue);
      expect(claimed.status, PaymentStatus.pending);
      expect(claimed.reference, 'E2EUTR000001');
      await _eventually(
        () =>
            staffServices.billing
                .byId(bill.id)
                ?.payments
                .any((p) => p.id == payment.id && p.isClaimed) ??
            false,
        'staff to see the guest\'s claim',
      );
      expect(staffServices.billing.byId(bill.id)!.amountPaid, Money.zero);

      // A guest can neither confirm nor reject it.
      await expectLater(
        guestServices.billing.verifyUpiPayment(
          payment.id,
          reference: 'E2EUTR000009',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      // And once told, cannot cancel it either (the server refuses).
      await expectLater(
        guestServices.billing.cancelUpiPayment(payment.id),
        throwsA(isA<PaymentException>()),
      );

      // ---- Staff confirm that the money arrived: only now is it paid.
      final confirmed = await staffServices.billing.verifyUpiPayment(
        payment.id,
        reference: 'e2eutr000042',
      );
      expect(confirmed.status, PaymentStatus.succeeded);
      expect(confirmed.reference, 'E2EUTR000042');
      expect(confirmed.recordedBy, signedIn.staff.name);
      expect(staffServices.billing.byId(bill.id)!.status, InvoiceStatus.paid);
      await _eventually(
        () => guestServices.billing.byId(bill.id)?.status == InvoiceStatus.paid,
        'the guest to see the bill paid',
      );
      guestBill = guestServices.billing.byId(bill.id)!;
      expect(guestBill.amountPaid, bill.total);
      expect(guestBill.outstanding, Money.zero);
      expect(guestBill.payments.single.isUpiDirect, isTrue);

      // The same bank reference cannot confirm a second payment.
      cart.add(guestServices.catalog.byId('samosa')!);
      final second = await guestServices.orders.placeOrder(
        cart: cart,
        tableNumber: 6,
      );
      final secondBill = await guestServices.billing.createForOrder(second);
      final secondPayment = await guestServices.billing.startUpiPayment(
        invoiceId: secondBill.id,
        amount: secondBill.payableNow,
      );
      await staffServices.billing.load();
      await expectLater(
        staffServices.billing.verifyUpiPayment(
          secondPayment.id,
          reference: 'E2EUTR000042',
        ),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            contains('already recorded'),
          ),
        ),
      );
      // A cashier can turn a payment down; the balance is open again.
      final rejected = await staffServices.billing.rejectUpiPayment(
        secondPayment.id,
        reason: 'Not in the statement',
      );
      expect(rejected.status, PaymentStatus.failed);
      expect(
        staffServices.billing.byId(secondBill.id)!.payableNow,
        secondBill.total,
      );

      // ---- Switched off, guests are not offered it any more.
      await paymentSettings.save(paymentSettings.upi.copyWith(enabled: false));
      await guestServices.billing.loadUpiSettings();
      expect(guestServices.billing.upiDirectAvailable, isFalse);
      expect(guestServices.billing.upiSettings.upiId, isEmpty);

      await guestLive.dispose();
      await staffLive.dispose();
      await guest.realtime.dispose();
      await staff.realtime.dispose();
    },
    skip: _url.isEmpty ? 'Set DINEQR_E2E_API_URL to run against an API' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
