import 'dart:async';
import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
import 'package:dineqr_customer/app/upi_launcher.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show settle, usePhoneScreen;
import 'support/brand_fonts.dart';

/// UPI through the live gateway (Cashfree) on the guest's payment screen:
/// UPI apps and QR Payment, full and part payments, and a bill that is paid
/// only once the gateway has reported the payment to the server, never
/// because the guest came back from their UPI app.

Invoice _bill({List<PaymentTransaction> payments = const []}) => Invoice(
  id: 'INV00001',
  billNumber: 'DQ-2026-00012',
  orderId: 'OD12345',
  tableNumber: 5,
  createdAt: DateTime.now(),
  lines: const [],
  amounts: const BillBreakdown(
    subtotal: Money(45000),
    tax: Money.zero,
    total: Money(45000),
    taxRateBasisPoints: 0,
  ),
  restaurant: const RestaurantSnapshot(name: 'Test Cafe'),
  payments: payments,
);

/// A phone and its UPI apps, as far as the app can tell.
class _Phone implements UpiLauncher {
  _Phone({this.canOpenApps = true});

  @override
  final bool canOpenApps;
  List<InstalledUpiApp> installed = [
    InstalledUpiApp.of(UpiApp.googlePay),
    InstalledUpiApp.of(UpiApp.phonePe),
  ];
  UpiLaunchResult result = UpiLaunchResult.opened;
  final opened = <({Uri link, InstalledUpiApp? app})>[];

  /// What the UPI apps say when the guest comes back (Android's result).
  final appReplies = StreamController<UpiAppReply>.broadcast();

  @override
  Stream<UpiAppReply> get replies => appReplies.stream;

  @override
  Future<List<InstalledUpiApp>> installedApps() async =>
      canOpenApps ? installed : const [];

  @override
  Future<UpiLaunchResult> open(
    Uri link, {
    InstalledUpiApp? app,
    Map<String, String> appLinks = const {},
  }) async {
    opened.add((link: link, app: app));
    return result;
  }
}

class _Rig {
  _Rig(this.deps, this.server, this.phone);

  final CustomerDependencies deps;
  final FakeUpiBackend server;
  final _Phone phone;

  Invoice get bill => deps.billing.byId('INV00001')!;

  Iterable<String> callsStarting(String prefix) =>
      server.calls.where((c) => c.startsWith(prefix));
}

Finder _key(String key) => find.byKey(ValueKey(key));

final _page = find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 250, scrollable: _page);
  }
  await tester.ensureVisible(finder);
  // Let the list's entrance animation finish so the target stays put.
  await settle(tester, 700);
  await tester.tap(finder);
  await settle(tester, 700);
}

/// The app goes to the background (the guest is in their UPI app) and
/// comes back.
Future<void> _backgroundAndBack(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await settle(tester, 700);
}

/// Time passes on the payment page: its status checks run.
Future<void> _wait(WidgetTester tester, [int seconds = 4]) async {
  await tester.pump(Duration(seconds: seconds));
  await settle(tester, 700);
}

/// The gateway's own description, as the server reports it in live mode.
ServerPaymentGateway _cashfree() => ServerPaymentGateway()
  ..update(
    providerName: 'Cashfree',
    available: true,
    isSimulated: false,
    methods: {PaymentMethodType.upi},
  );

/// Opens the bill of a restaurant in live mode with Cashfree. The
/// restaurant's own UPI ID is set up too ([upi]): the gateway is used
/// instead, since it needs no one to confirm the money.
Future<_Rig> _openBill(
  WidgetTester tester, {
  Invoice? invoice,
  _Phone? phone,
  UpiSettings upi = const UpiSettings(
    enabled: true,
    upiId: 'cafe@hdfcbank',
    payeeName: 'Test Cafe',
  ),
}) async {
  usePhoneScreen(tester);
  final bill = invoice ?? _bill();
  final server = FakeUpiBackend(bill, settings: upi);
  final device = phone ?? _Phone();
  final store = MemoryStore();
  await tester.runAsync(
    () => LocalSettingsRepository(store).saveSettings(
      LocalSettingsRepository.defaults.copyWith(paymentMode: PaymentMode.live),
    ),
  );
  final deps = await CustomerDependencies.create(
    store: store,
    config: const CustomerConfig(enableCamera: false),
    billingRepository: LocalBillingRepository(MemoryStore(), seed: [bill]),
    billingBackend: server,
    paymentGateway: _cashfree(),
    upiLauncher: device,
    menuLatency: Duration.zero,
    orderLatency: const Duration(milliseconds: 300),
    paymentTime: const Duration(milliseconds: 300),
    seedDemoData: false,
  );
  await tester.runAsync(deps.settings.load);
  await tester.runAsync(deps.billing.load);
  await tester.runAsync(deps.billing.loadUpiSettings);
  await tester.pumpWidget(DineQrApp(dependencies: deps));
  await tester.pump(const Duration(milliseconds: 2700)); // splash
  await settle(tester, 700);
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .pushNamed(Routes.bill, arguments: bill.id);
  await settle(tester, 800);
  return _Rig(deps, server, device);
}

Future<void> _goToPayment(WidgetTester tester) =>
    _tap(tester, find.text('Pay Now'));

void main() {
  setUpAll(loadBrandFonts);

  group('choosing', () {
    testWidgets('UPI apps and QR Payment, one below another, all real', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);

      expect(find.text('Choose how to pay'), findsOneWidget);
      for (final option in ['UPI', 'QR Payment', 'Cash', 'Pay at Counter']) {
        expect(find.text(option), findsOneWidget, reason: option);
      }
      // One below another.
      expect(
        tester.getTopLeft(find.text('QR Payment')).dy,
        greaterThan(tester.getTopLeft(find.text('UPI')).dy),
      );
      // Live mode takes UPI only online, and nothing is a demo.
      expect(find.text('Card'), findsNothing);
      expect(find.text('DEMO'), findsNothing);
      expect(find.textContaining('Demo payment'), findsNothing);
      // The restaurant's own UPI ID (confirmed by staff) is not offered.
      expect(find.text('Pay Test Cafe directly'), findsNothing);
      // A gateway payment cannot be one part of several.
      expect(find.text('Split payment'), findsNothing);

      // UPI is chosen and lists the phone's UPI apps.
      expect(
        find.text('Google Pay, PhonePe, Paytm or any UPI app'),
        findsOneWidget,
      );
      expect(_key('upi-app-googlePay'), findsOneWidget);
      expect(_key('upi-app-phonePe'), findsOneWidget);
      expect(_key('upi-app-paytm'), findsNothing);
      expect(_key('upi-app-other'), findsOneWidget);
      expect(find.text('Pay ₹450 with Google Pay'), findsOneWidget);

      final note = find.textContaining('Secured by Cashfree');
      await tester.scrollUntilVisible(note, 250, scrollable: _page);
      expect(note, findsOneWidget);
      expect(rig.server.calls.where((c) => c.startsWith('gateway')), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a device that cannot open UPI apps pays by QR code', (
      tester,
    ) async {
      final rig = await _openBill(tester, phone: _Phone(canOpenApps: false));
      await _goToPayment(tester);
      expect(find.textContaining('cannot open a UPI app'), findsOneWidget);
      expect(_key('upi-app-other'), findsNothing);
      await _tap(tester, find.text('Pay ₹450 with UPI'));
      expect(rig.callsStarting('checkout'), ['checkout:PAY000001:qr']);
      expect(_key('gateway-qr'), findsOneWidget);
      expect(rig.phone.opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('paying with a UPI app', () {
    testWidgets('the app tapped opens with the exact amount; the bill is paid '
        'only when the gateway reports it', (tester) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);
      await _tap(tester, _key('upi-app-phonePe'));

      expect(rig.server.calls, [
        'upiSettings',
        'upiSettings',
        'gateway:45000:PhonePe',
        'checkout:PAY000001:apps',
      ]);
      // The gateway's plain UPI link, sent to PhonePe itself.
      final opened = rig.phone.opened.single;
      expect(opened.app?.known, UpiApp.phonePe);
      expect(opened.app?.id, 'com.phonepe.app');
      final link = opened.link.toString();
      expect(link, startsWith('upi://pay?pa=cashfree.test@axis'));
      expect(link, contains('am=450.00'));
      expect(link, contains('cu=INR'));
      expect(link, contains('tr=PAY000001'));
      expect(_key('gateway-waiting'), findsOneWidget);
      expect(find.text('Open PhonePe again'), findsOneWidget);
      // Held against the bill, not paid.
      expect(rig.bill.status, InvoiceStatus.pending);
      expect(rig.bill.amountPaid, Money.zero);

      // Back from PhonePe: the server is asked at once; nothing is assumed.
      final asked = rig.callsStarting('refresh').length;
      await _backgroundAndBack(tester);
      expect(rig.callsStarting('refresh').length, greaterThan(asked));
      expect(rig.bill.amountPaid, Money.zero);
      expect(find.text('Did your payment go through?'), findsNothing);
      expect(_key('gateway-waiting'), findsOneWidget);

      // The gateway reports the payment to the server.
      rig.server.settleGateway('PAY000001');
      await _wait(tester);
      expect(find.text('Payment successful'), findsOneWidget);
      expect(
        find.textContaining('Cashfree confirmed your UPI payment'),
        findsOneWidget,
      );
      expect(find.text('₹450 paid by UPI · PhonePe'), findsOneWidget);
      expect(find.text('412345678901'), findsOneWidget);
      expect(rig.bill.status, InvoiceStatus.paid);
      // One payment, one gateway order.
      expect(rig.callsStarting('gateway'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('switching to the QR code pays the same payment', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);
      await _tap(tester, find.text('Pay ₹450 with Google Pay'));
      expect(rig.phone.opened.single.app?.known, UpiApp.googlePay);

      await _tap(tester, _key('gateway-show-qr'));
      expect(_key('gateway-qr'), findsOneWidget);
      await _tap(tester, _key('gateway-switch-phonePe'));
      expect(rig.phone.opened.last.app?.known, UpiApp.phonePe);
      expect(rig.phone.opened.last.link, rig.phone.opened.first.link);
      expect(rig.callsStarting('gateway'), hasLength(1));
      expect(rig.callsStarting('checkout'), [
        'checkout:PAY000001:apps',
        'checkout:PAY000001:qr',
        'checkout:PAY000001:apps',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an app that is not there is reported, nothing is assumed', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      rig.phone.result = UpiLaunchResult.noApp;
      await _goToPayment(tester);
      await _tap(tester, _key('upi-app-googlePay'));
      expect(_key('gateway-launch-problem'), findsOneWidget);
      expect(find.textContaining('Google Pay was not found'), findsOneWidget);
      expect(rig.bill.amountPaid, Money.zero);
      expect(_key('gateway-show-qr'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('every UPI app on the phone is listed with its own icon and '
        'opens by itself', (tester) async {
      final phone = _Phone()
        ..installed = InstalledUpiApp.sorted([
          InstalledUpiApp(
            id: 'in.org.npci.upiapp',
            label: 'BHIM',
            icon: base64Decode(FakeUpiBackend.qrImage.split(',').last),
          ),
          InstalledUpiApp.of(UpiApp.phonePe),
          InstalledUpiApp.of(UpiApp.googlePay),
        ]);
      final rig = await _openBill(tester, phone: phone);
      await _goToPayment(tester);

      // Google Pay, PhonePe, then the rest, then the phone's own list.
      final order = [
        'upi-app-googlePay',
        'upi-app-phonePe',
        'upi-app-in.org.npci.upiapp',
        'upi-app-other',
      ].map((key) => tester.getTopLeft(_key(key)).dy).toList();
      expect(order, List.of(order)..sort());
      expect(
        find.descendant(
          of: _key('upi-app-in.org.npci.upiapp'),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      await _tap(tester, _key('upi-app-in.org.npci.upiapp'));
      expect(rig.server.calls, contains('gateway:45000:BHIM'));
      final opened = rig.phone.opened.single;
      expect(opened.app?.id, 'in.org.npci.upiapp');
      expect(opened.link.toString(), contains('am=450.00'));
      expect(find.text('Open BHIM again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with no UPI app found, the phone\'s own list and the QR code '
        'are still offered', (tester) async {
      final rig = await _openBill(tester, phone: _Phone()..installed = []);
      await _goToPayment(tester);
      expect(_key('upi-apps-none'), findsOneWidget);
      expect(_key('upi-app-other'), findsOneWidget);
      expect(find.text('Pay ₹450 with UPI'), findsOneWidget);

      await _tap(tester, _key('upi-app-other'));
      expect(rig.server.calls, contains('gateway:45000:'));
      expect(rig.phone.opened.single.app?.isChooser, isTrue);
      expect(find.text('Open my UPI app again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('paying by QR code', () {
    testWidgets('a part payment shows the gateway QR and leaves the bill '
        'partly paid', (tester) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);
      await _tap(tester, find.text('Part payment'));
      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();
      await _tap(tester, find.text('QR Payment'));
      await _tap(tester, find.text('Pay ₹150 by QR code'));

      expect(rig.server.calls, contains('gateway:15000:QR code'));
      expect(rig.callsStarting('checkout'), ['checkout:PAY000001:qr']);
      expect(_key('gateway-qr'), findsOneWidget);
      expect(find.text('Scan to pay'), findsOneWidget);
      expect(_key('gateway-time-left'), findsOneWidget);
      // Nothing opens: the guest scans.
      expect(rig.phone.opened, isEmpty);
      expect(rig.bill.payableNow, const Money(30000));

      rig.server.settleGateway('PAY000001');
      await _wait(tester);
      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('Partially paid'), findsWidgets);
      expect(rig.bill.status, InvoiceStatus.partiallyPaid);
      expect(rig.bill.outstanding, const Money(30000));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a QR code sent as its payment link is drawn here', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      rig.server.qrAsText = true;
      await _goToPayment(tester);
      await _tap(tester, find.text('QR Payment'));
      await _tap(tester, find.text('Pay ₹450 by QR code'));
      final qr = tester.widget<PlainQrCode>(
        find.descendant(
          of: _key('gateway-qr'),
          matching: find.byType(PlainQrCode),
        ),
      );
      expect(qr.payload, startsWith('upi://pay?pa=cashfree.test@axis'));
      expect(qr.payload, contains('am=450.00'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('not paid', () {
    testWidgets('a failed payment never counts and can be tried again', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);
      await _tap(tester, _key('upi-app-googlePay'));
      rig.server.settleGateway(
        'PAY000001',
        status: PaymentStatus.failed,
        reference: '',
        reason: 'The payment failed: Insufficient balance. No money was taken.',
      );
      await _wait(tester);
      expect(find.text('Payment failed'), findsWidgets);
      expect(find.textContaining('Insufficient balance'), findsOneWidget);
      expect(rig.bill.amountPaid, Money.zero);
      expect(rig.bill.payableNow, const Money(45000));

      await _tap(tester, find.text('Try again'));
      expect(find.text('Choose how to pay'), findsOneWidget);
      await _tap(tester, _key('upi-app-googlePay'));
      // A new payment, not the failed one again.
      expect(rig.callsStarting('gateway'), hasLength(2));
      expect(_key('gateway-waiting'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelling ends the payment and frees the bill', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);
      await _tap(tester, _key('upi-app-googlePay'));
      await _tap(tester, _key('gateway-cancel'));
      expect(rig.server.calls, contains('cancel:PAY000001'));
      expect(find.text('Payment not completed'), findsOneWidget);
      expect(rig.bill.payableNow, const Money(45000));
      expect(rig.bill.amountPaid, Money.zero);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('network trouble keeps waiting and never marks it paid', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      rig.server.failCheckout = 'The payment service did not respond.';
      await _goToPayment(tester);
      await _tap(tester, _key('upi-app-googlePay'));
      expect(_key('gateway-error'), findsOneWidget);
      expect(rig.phone.opened, isEmpty);
      rig.server.failCheckout = null;
      await _tap(tester, _key('gateway-retry'));
      expect(rig.phone.opened, hasLength(1));

      rig.server.failRefresh = 'Cannot reach the restaurant server.';
      await _wait(tester);
      expect(_key('gateway-offline'), findsOneWidget);
      expect(rig.bill.status, InvoiceStatus.pending);
      expect(_key('gateway-waiting'), findsOneWidget);

      // Back online; the payment had gone through meanwhile.
      rig.server.failRefresh = null;
      rig.server.settleGateway('PAY000001');
      await _wait(tester);
      expect(find.text('Payment successful'), findsOneWidget);
      expect(rig.bill.status, InvoiceStatus.paid);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('coming back', () {
    testWidgets('a payment being confirmed shows on the bill and reopens', (
      tester,
    ) async {
      final pending = PaymentTransaction(
        id: 'PAY000001',
        invoiceId: 'INV00001',
        orderId: 'OD12345',
        amount: const Money(45000),
        method: PaymentMethodType.upi,
        methodDetail: 'Google Pay',
        status: PaymentStatus.pending,
        provider: 'Cashfree',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        idempotencyKey: 'key-1',
      );
      final rig = await _openBill(tester, invoice: _bill(payments: [pending]));
      expect(_key('gateway-pending-note'), findsOneWidget);
      expect(find.text('Pay Now'), findsNothing);

      await _tap(tester, _key('gateway-resume'));
      expect(_key('gateway-waiting'), findsOneWidget);
      // The same payment, by QR until the guest picks an app.
      expect(rig.callsStarting('gateway'), isEmpty);
      expect(rig.callsStarting('checkout'), ['checkout:PAY000001:qr']);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('layout', () {
    for (final MapEntry(key: name, value: size) in {
      'small phone': const Size(360, 760),
      'tablet': const Size(1280, 800),
    }.entries) {
      testWidgets('the options and the payment page fit a $name at the '
          'largest text', (tester) async {
        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.exceptionAsString());
        try {
          final rig = await _openBill(tester);
          tester.view.physicalSize = size * 2;
          tester.view.devicePixelRatio = 2;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          await settle(tester, 700);
          await _goToPayment(tester);
          await _tap(tester, find.text('QR Payment'));
          await _tap(tester, find.text('Pay ₹450 by QR code'));
          await tester.scrollUntilVisible(
            _key('gateway-cancel'),
            250,
            scrollable: _page,
          );
          rig.server.settleGateway('PAY000001');
          await _wait(tester);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = original;
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        }
        expect(errors.where((e) => e.contains('overflowed')), isEmpty);
      });
    }
  });
}
