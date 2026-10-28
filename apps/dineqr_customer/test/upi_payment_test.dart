import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
import 'package:dineqr_customer/app/upi_launcher.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show settle, usePhoneScreen;
import 'support/brand_fonts.dart';

/// A bank's UPI ID: UPI apps may open a payment link to it.
const _ready = UpiSettings(
  enabled: true,
  upiId: 'cafe@hdfcbank',
  payeeName: 'Test Cafe',
);

const _link =
    'upi://pay?pa=cafe@hdfcbank&pn=Test%20Cafe&am=450.00&cu=INR'
    '&tn=Bill%20DQ-2026-00012%20PAY000001';

/// A Google Pay UPI ID: UPI apps refuse a payment link to it (NPCI OC/76A).
final _googlePay = _ready.copyWith(upiId: 'cafe@okhdfcbank');

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

PaymentTransaction _pending({DateTime? claimedAt, String reference = ''}) =>
    PaymentTransaction(
      id: 'PAY000001',
      invoiceId: 'INV00001',
      orderId: 'OD12345',
      amount: const Money(45000),
      method: PaymentMethodType.upi,
      status: PaymentStatus.pending,
      provider: PaymentTransaction.upiDirectProvider,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      idempotencyKey: 'key-1',
      reference: reference,
      claimedAt: claimedAt,
    );

/// A phone's UPI apps, as far as the app can tell.
class _FakeLauncher implements UpiLauncher {
  _FakeLauncher({
    this.canOpenApps = true,
    this.result = UpiLaunchResult.opened,
  });

  @override
  final bool canOpenApps;
  UpiLaunchResult result;
  final opened = <Uri>[];

  @override
  Future<UpiLaunchResult> open(Uri link) async {
    opened.add(link);
    return result;
  }
}

class _Rig {
  _Rig(this.deps, this.server, this.launcher);

  final CustomerDependencies deps;
  final FakeUpiBackend server;
  final _FakeLauncher launcher;

  Invoice get bill => deps.billing.byId('INV00001')!;
}

Finder _key(String key) => find.byKey(ValueKey(key));

/// The page's vertical scroll view.
final _page = find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

/// Scrolls the page until [finder] is on screen (a long page builds only what
/// is near the viewport), then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 250, scrollable: _page);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester, 700);
}

/// The app goes to the background (the guest is in their UPI app) and comes
/// back, through the states the system really reports.
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

/// Opens the bill of a guest whose restaurant [settings] describe.
Future<_Rig> _openBill(
  WidgetTester tester, {
  Invoice? invoice,
  UpiSettings settings = _ready,
  _FakeLauncher? launcher,
}) async {
  usePhoneScreen(tester);
  final bill = invoice ?? _bill();
  final server = FakeUpiBackend(bill, settings: settings);
  final phone = launcher ?? _FakeLauncher();
  final deps = await CustomerDependencies.create(
    store: MemoryStore(),
    config: const CustomerConfig(enableCamera: false),
    billingRepository: LocalBillingRepository(MemoryStore(), seed: [bill]),
    billingBackend: server,
    upiLauncher: phone,
    menuLatency: Duration.zero,
    orderLatency: const Duration(milliseconds: 300),
    paymentTime: const Duration(milliseconds: 300),
    seedDemoData: false,
  );
  await tester.runAsync(deps.billing.load);
  await tester.runAsync(deps.billing.loadUpiSettings);
  await tester.pumpWidget(DineQrApp(dependencies: deps));
  await tester.pump(const Duration(milliseconds: 2700)); // splash
  await settle(tester, 700);
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .pushNamed(Routes.bill, arguments: bill.id);
  await settle(tester, 800);
  return _Rig(deps, server, phone);
}

/// From the bill to the payment screen.
Future<void> _goToPayment(WidgetTester tester) async {
  await _tap(tester, find.text('Pay Now'));
}

/// Starts the full-balance UPI payment (UPI is the first option).
Future<void> _startUpi(WidgetTester tester) async {
  await _goToPayment(tester);
  await _tap(tester, find.text('Pay ₹450 with UPI'));
}

/// What the phone does when the guest goes to their UPI app and comes back:
/// opened with the payment link, or (for a UPI app's own ID) with the UPI
/// ID copied.
Future<void> _visitUpiApp(WidgetTester tester, {bool copy = false}) async {
  await _tap(tester, _key(copy ? 'upi-copy-to-pay' : 'upi-open-app'));
  await _backgroundAndBack(tester);
}

/// Records what the app copies.
List<String> _watchClipboard(WidgetTester tester) {
  final clipboard = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return clipboard;
}

void main() {
  setUpAll(loadBrandFonts);

  group('choosing UPI', () {
    testWidgets('UPI to the restaurant comes first and is not a simulation', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);

      expect(find.text('Choose how to pay'), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('Pay Test Cafe directly'), findsOneWidget);
      // The restaurant's UPI QR replaces the simulator's Scan & Pay.
      expect(find.text('Scan & Pay'), findsNothing);
      // The demo simulator still covers card, net banking and wallet, and
      // says so...
      expect(find.text('DEMO'), findsNWidgets(3));
      // ...but nothing about UPI to the restaurant is a demo.
      expect(find.textContaining('Demo payment'), findsNothing);
      expect(find.textContaining('Simulated result'), findsNothing);
      expect(find.text('Pay ₹450 with UPI'), findsOneWidget);
      // The note under the options says who is paid and when it counts.
      final note = find.textContaining('directly from your own UPI app');
      await tester.scrollUntilVisible(note, 250, scrollable: _page);
      expect(note, findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('AMOUNT TO PAY'),
        -250,
        scrollable: _page,
      );

      // Choosing a simulated method brings the demo wording back.
      await _tap(tester, find.text('Card'));
      final banner = find.textContaining('Demo payment');
      await tester.scrollUntilVisible(banner, -250, scrollable: _page);
      expect(banner, findsOneWidget);
      expect(find.text('Pay ₹450 with Card'), findsOneWidget);
      expect(find.text('Pay ₹450 with UPI'), findsNothing);

      expect(rig.server.calls.where((c) => c.startsWith('start')), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('without a UPI setup the usual options remain', (tester) async {
      await _openBill(tester, settings: _ready.copyWith(enabled: false));
      await _goToPayment(tester);
      expect(find.text('Pay Test Cafe directly'), findsNothing);
      // The demo's own (simulated) UPI and Scan & Pay are there, labelled as
      // such, under the demo banner; nothing is chosen for the guest.
      expect(find.text('Scan & Pay'), findsOneWidget);
      expect(find.text('DEMO'), findsNWidgets(6));
      expect(find.textContaining('with UPI'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('paying by UPI', () {
    testWidgets('starts a pending payment for the exact balance', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _startUpi(tester);

      expect(rig.server.calls, contains('start:45000'));
      expect(find.text('Pay with your UPI app'), findsOneWidget);
      expect(_key('upi-open-app'), findsOneWidget);

      // Reserved against the bill, but not paid.
      final bill = rig.bill;
      expect(bill.status, InvoiceStatus.pending);
      expect(bill.amountPaid, Money.zero);
      expect(bill.outstanding, const Money(45000));

      // The QR carries the payee, exact amount, INR and a unique reference.
      final qr = tester.widget<PlainQrCode>(find.byType(PlainQrCode));
      expect(qr.payload, _link);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a part payment is for exactly the chosen amount', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);
      await _tap(tester, find.text('Part payment'));
      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();
      await _tap(tester, find.text('Pay ₹150 with UPI'));

      expect(rig.server.calls, contains('start:15000'));
      expect(
        tester.widget<PlainQrCode>(find.byType(PlainQrCode)).payload,
        contains('&am=150.00&'),
      );
      expect(rig.bill.payableNow, const Money(30000));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an amount above the balance is refused before any request', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _goToPayment(tester);
      await _tap(tester, find.text('Part payment'));
      await tester.enterText(find.byType(TextField), '900');
      await tester.pump();
      await _tap(tester, find.textContaining('Pay ₹900'));
      expect(find.textContaining('You can pay at most'), findsOneWidget);
      expect(rig.server.calls.where((c) => c.startsWith('start')), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('lists the details to copy, and copies exact values', (
      tester,
    ) async {
      await _openBill(tester);
      final clipboard = _watchClipboard(tester);
      await _startUpi(tester);

      await tester.scrollUntilVisible(
        find.text('cafe@hdfcbank'),
        250,
        scrollable: _page,
      );
      expect(find.text('cafe@hdfcbank'), findsOneWidget);
      expect(find.text('₹450.00'), findsOneWidget);
      // The note names the bill and this payment, for the restaurant to match.
      expect(find.text('Bill DQ-2026-00012 PAY000001'), findsOneWidget);

      await _tap(tester, _key('copy-upi-id'));
      await _tap(tester, _key('copy-amount'));
      await _tap(tester, _key('copy-note'));
      expect(clipboard, [
        'cafe@hdfcbank',
        '450.00',
        'Bill DQ-2026-00012 PAY000001',
      ]);
      expect(find.text('Note copied'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the restaurant\'s own QR is a backup with a warning', (
      tester,
    ) async {
      await _openBill(
        tester,
        settings: _ready.copyWith(
          qrImageUrl: 'https://x.test/uploads/upi/a.png',
        ),
      );
      await _startUpi(tester);
      expect(_key('upi-own-qr'), findsNothing);
      await _tap(tester, _key('upi-own-qr-toggle'));
      expect(_key('upi-own-qr'), findsOneWidget);
      expect(find.textContaining('does not carry the amount'), findsOneWidget);
      expect(find.textContaining('₹450.00 yourself'), findsOneWidget);
      // The generated QR with the amount is still the first choice.
      expect(find.byType(PlainQrCode), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed start explains why and offers a way back', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      rig.server.failStart = 'A payment for this bill is in progress.';
      await _startUpi(tester);
      expect(find.text('Payment failed'), findsWidgets);
      expect(
        find.text('A payment for this bill is in progress.'),
        findsOneWidget,
      );
      expect(rig.bill.payments, isEmpty);
      await _tap(tester, find.text('Try again'));
      expect(find.text('Choose how to pay'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('tapping pay twice starts one payment', (tester) async {
      final rig = await _openBill(tester);
      rig.server.holdStart = Completer<void>();
      await _goToPayment(tester);
      final pay = find.text('Pay ₹450 with UPI');
      await tester.tap(pay);
      await tester.pump();
      await tester.tap(pay, warnIfMissed: false);
      await tester.pump();
      rig.server.holdStart!.complete();
      await settle(tester, 700);
      expect(
        rig.server.calls.where((c) => c.startsWith('start')),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the UPI app', () {
    testWidgets('is opened with the exact payment link', (tester) async {
      final rig = await _openBill(tester);
      await _startUpi(tester);
      await _tap(tester, _key('upi-open-app'));
      expect(rig.launcher.opened.single.toString(), _link);
      // Opening it proves nothing: the bill is as it was.
      expect(rig.bill.status, InvoiceStatus.pending);
      expect(rig.bill.amountPaid, Money.zero);
      expect(rig.server.calls.where((c) => c.startsWith('claim')), isEmpty);
      expect(find.text('Pay with UPI again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('coming back asks what happened, and "not sure" waits', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _startUpi(tester);
      expect(_key('upi-outcome'), findsNothing);
      await _visitUpiApp(tester);
      expect(find.text('Did your payment go through?'), findsOneWidget);

      await _tap(tester, _key('upi-outcome-unsure'));
      expect(_key('upi-outcome'), findsNothing);
      expect(
        rig.server.calls.where(
          (c) => c.startsWith('claim') || c.startsWith('cancel'),
        ),
        isEmpty,
      );
      expect(rig.bill.status, InvoiceStatus.pending);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('leaving the app without a UPI app opened asks nothing', (
      tester,
    ) async {
      await _openBill(tester);
      await _startUpi(tester);
      await _backgroundAndBack(tester);
      expect(_key('upi-outcome'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('"it failed or I cancelled" cancels the attempt, no charge', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _startUpi(tester);
      await _visitUpiApp(tester);
      await _tap(tester, _key('upi-outcome-failed'));

      expect(rig.server.calls, contains('cancel:PAY000001'));
      expect(find.text('Payment cancelled'), findsOneWidget);
      expect(
        find.textContaining('Nothing was recorded on your bill'),
        findsOneWidget,
      );
      final bill = rig.bill;
      expect(bill.amountPaid, Money.zero);
      expect(bill.status, InvoiceStatus.unpaid);
      expect(bill.payableNow, const Money(45000));

      // And the guest can simply try again.
      await _tap(tester, find.text('Try again'));
      expect(find.text('Choose how to pay'), findsOneWidget);
      await _tap(tester, find.text('Pay ₹450 with UPI'));
      expect(
        rig.server.calls.where((c) => c.startsWith('start')),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a phone with no UPI app is told, and can still pay', (
      tester,
    ) async {
      final rig = await _openBill(
        tester,
        launcher: _FakeLauncher(result: UpiLaunchResult.noApp),
      );
      await _startUpi(tester);
      await _tap(tester, _key('upi-open-app'));
      expect(rig.launcher.opened, hasLength(1));
      expect(find.textContaining('No UPI app was found'), findsOneWidget);
      // The other ways are right there.
      expect(find.byType(PlainQrCode), findsOneWidget);
      expect(_key('copy-upi-id'), findsOneWidget);
      // Nothing was claimed or asked.
      expect(_key('upi-outcome'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed launch is reported without claiming anything', (
      tester,
    ) async {
      await _openBill(
        tester,
        launcher: _FakeLauncher(result: UpiLaunchResult.failed),
      );
      await _startUpi(tester);
      await _tap(tester, _key('upi-open-app'));
      expect(
        find.textContaining('could not open your UPI app'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('desktop and web show the QR and details instead', (
      tester,
    ) async {
      await _openBill(tester, launcher: _FakeLauncher(canOpenApps: false));
      await _startUpi(tester);
      expect(_key('upi-open-app'), findsNothing);
      expect(
        find.textContaining('Open this page on your phone'),
        findsOneWidget,
      );
      expect(find.byType(PlainQrCode), findsOneWidget);
      expect(_key('copy-amount'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('a UPI app\'s own UPI ID (Google Pay, PhonePe, ...)', () {
    testWidgets('is never handed to a UPI app as a link', (tester) async {
      final rig = await _openBill(tester, settings: _googlePay);
      await _startUpi(tester);

      // UPI apps refuse a link to such an ID ("limit reached"), so none is
      // offered: the guest copies the ID into their app.
      expect(_key('upi-open-app'), findsNothing);
      expect(_key('upi-copy-steps'), findsOneWidget);
      expect(find.textContaining('choose “Pay UPI ID”'), findsOneWidget);
      expect(find.textContaining('Pay exactly ₹450.00'), findsOneWidget);
      expect(find.textContaining('an NPCI rule'), findsOneWidget);
      // The QR code still carries the exact payment.
      expect(
        tester.widget<PlainQrCode>(find.byType(PlainQrCode)).payload,
        'upi://pay?pa=cafe@okhdfcbank&pn=Test%20Cafe&am=450.00&cu=INR'
        '&tn=Bill%20DQ-2026-00012%20PAY000001',
      );
      expect(find.textContaining('Scan from gallery'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Payment details'),
        250,
        scrollable: _page,
      );
      expect(find.text('cafe@okhdfcbank'), findsOneWidget);
      expect(rig.launcher.opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('copying the ID to pay asks what happened on return', (
      tester,
    ) async {
      final rig = await _openBill(tester, settings: _googlePay);
      final clipboard = _watchClipboard(tester);
      await _startUpi(tester);
      expect(_key('upi-outcome'), findsNothing);

      await _visitUpiApp(tester, copy: true);
      expect(clipboard, ['cafe@okhdfcbank']);
      expect(find.text('Did your payment go through?'), findsOneWidget);
      // Copying proves nothing either.
      expect(rig.bill.amountPaid, Money.zero);
      expect(rig.server.calls.where((c) => c.startsWith('claim')), isEmpty);

      await _tap(tester, _key('upi-outcome-paid'));
      await _tap(tester, _key('upi-claim'));
      expect(rig.server.calls, contains('claim:PAY000001:'));
      expect(find.text('Waiting for the restaurant'), findsOneWidget);
      expect(rig.bill.status, InvoiceStatus.pending);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('above ₹2,000 no screenshot is suggested', (tester) async {
      // UPI caps paying a QR picture from the gallery at ₹2,000.
      final big = Invoice(
        id: 'INV00001',
        billNumber: 'DQ-2026-00012',
        orderId: 'OD12345',
        tableNumber: 5,
        createdAt: DateTime.now(),
        lines: const [],
        amounts: const BillBreakdown(
          subtotal: Money(250000),
          tax: Money.zero,
          total: Money(250000),
          taxRateBasisPoints: 0,
        ),
        restaurant: const RestaurantSnapshot(name: 'Test Cafe'),
      );
      await _openBill(tester, invoice: big, settings: _googlePay);
      await _goToPayment(tester);
      await _tap(tester, find.text('Pay ₹2,500 with UPI'));
      expect(find.byType(PlainQrCode), findsOneWidget);
      expect(find.textContaining('Scan from gallery'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('telling the restaurant', () {
    testWidgets(
      '"I\'ve paid" waits for the restaurant; the bill stays unpaid',
      (tester) async {
        final rig = await _openBill(tester);
        await _startUpi(tester);
        await _visitUpiApp(tester);
        await _tap(tester, _key('upi-outcome-paid'));
        expect(find.text('Tell the restaurant you paid'), findsOneWidget);

        await tester.enterText(_key('upi-ref-field'), 'utr 9876 5432 10');
        await tester.pump();
        await _tap(tester, _key('upi-claim'));

        expect(rig.server.calls, contains('claim:PAY000001:UTR9876543210'));
        expect(find.text('Waiting for the restaurant'), findsOneWidget);
        expect(find.text('UTR9876543210'), findsOneWidget);
        // No claim makes the bill paid.
        final bill = rig.bill;
        expect(bill.status, InvoiceStatus.pending);
        expect(bill.amountPaid, Money.zero);
        expect(bill.outstanding, const Money(45000));
        expect(_key('upi-open-app'), findsNothing);
        expect(find.text('Payment confirmed'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('the transaction ID is optional but must look right', (
      tester,
    ) async {
      final rig = await _openBill(tester);
      await _startUpi(tester);
      await _tap(tester, _key('upi-paid'));
      await tester.enterText(_key('upi-ref-field'), '12');
      await tester.pump();
      await _tap(tester, _key('upi-claim'));
      expect(find.text(UpiReference.rule), findsOneWidget);
      expect(rig.server.calls.where((c) => c.startsWith('claim')), isEmpty);

      await tester.enterText(_key('upi-ref-field'), '');
      await tester.pump();
      await _tap(tester, _key('upi-claim'));
      expect(rig.server.calls, contains('claim:PAY000001:'));
      expect(find.text('Waiting for the restaurant'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed request is shown and can be retried', (tester) async {
      final rig = await _openBill(tester);
      await _startUpi(tester);
      await _tap(tester, _key('upi-paid'));
      rig.server.failClaim = 'Cannot reach the restaurant server.';
      await _tap(tester, _key('upi-claim'));

      // Still on the form, with the reason, and nothing was recorded.
      expect(find.text('Cannot reach the restaurant server.'), findsOneWidget);
      expect(find.text('Waiting for the restaurant'), findsNothing);
      expect(rig.server.latest.isClaimed, isFalse);

      rig.server.failClaim = null;
      await _tap(tester, _key('upi-claim'));
      expect(find.text('Cannot reach the restaurant server.'), findsNothing);
      expect(find.text('Waiting for the restaurant'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('once claimed the guest cannot cancel it themselves', (
      tester,
    ) async {
      await _openBill(
        tester,
        invoice: _bill(
          payments: [
            _pending(claimedAt: DateTime.now(), reference: 'UTR9876543210'),
          ],
        ),
      );
      await _goToPaymentFromBill(tester);
      expect(find.text('Waiting for the restaurant'), findsOneWidget);
      expect(_key('upi-cancel'), findsNothing);
      expect(find.textContaining('Ask the staff'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the restaurant decides', () {
    Future<_Rig> waiting(WidgetTester tester) async {
      final rig = await _openBill(tester);
      await _startUpi(tester);
      await _tap(tester, _key('upi-paid'));
      await _tap(tester, _key('upi-claim'));
      expect(find.text('Waiting for the restaurant'), findsOneWidget);
      return rig;
    }

    testWidgets('confirmation arrives and settles the bill', (tester) async {
      final rig = await waiting(tester);
      await rig.server.verifyUpiPayment(
        'PAY000001',
        reference: 'UTR9876543210',
      );
      await _tap(tester, _key('upi-check'));

      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(
        find.text('The restaurant confirmed your UPI payment.'),
        findsOneWidget,
      );
      expect(find.text('₹450 paid by UPI'), findsOneWidget);
      expect(find.text('UTR9876543210'), findsOneWidget);
      final bill = rig.bill;
      expect(bill.status, InvoiceStatus.paid);
      expect(bill.outstanding, Money.zero);
      expect(find.text('View receipt'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the screen checks by itself while it waits', (tester) async {
      final rig = await waiting(tester);
      rig.server.calls.clear();
      await tester.pump(const Duration(seconds: 11));
      expect(rig.server.calls, contains('refresh:PAY000001'));
      expect(find.text('Waiting for the restaurant'), findsOneWidget);

      await rig.server.verifyUpiPayment(
        'PAY000001',
        reference: 'UTR9876543210',
      );
      await tester.pump(const Duration(seconds: 11));
      await settle(tester, 700);
      expect(find.text('Payment confirmed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a rejection says the money was not received', (tester) async {
      final rig = await waiting(tester);
      await rig.server.rejectUpiPayment(
        'PAY000001',
        reason: 'Not in the bank statement',
      );
      await _tap(tester, _key('upi-check'));

      expect(find.text('Payment not received'), findsOneWidget);
      expect(find.textContaining('Not in the bank statement'), findsOneWidget);
      expect(
        find.textContaining('show your UPI receipt to the staff'),
        findsOneWidget,
      );
      final bill = rig.bill;
      expect(bill.amountPaid, Money.zero);
      expect(bill.status, InvoiceStatus.failed);
      expect(bill.payableNow, const Money(45000));

      await _tap(tester, find.text('Try again'));
      expect(find.text('Choose how to pay'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('coming back to a payment', () {
    testWidgets('an unfinished payment is resumed, not started again', (
      tester,
    ) async {
      final rig = await _openBill(
        tester,
        invoice: _bill(payments: [_pending()]),
      );
      expect(
        find.text('You started a UPI payment of ₹450. It is not finished yet.'),
        findsOneWidget,
      );
      expect(find.text('Continue UPI payment'), findsOneWidget);
      // Nothing can be paid twice: the amount is already held.
      expect(find.text('Pay Now'), findsNothing);

      await _tap(tester, _key('upi-resume'));
      expect(find.text('Pay with your UPI app'), findsOneWidget);
      expect(rig.server.calls.where((c) => c.startsWith('start')), isEmpty);
      expect(
        tester.widget<PlainQrCode>(find.byType(PlainQrCode)).payload,
        _link,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a claimed payment shows as waiting on the bill', (
      tester,
    ) async {
      await _openBill(
        tester,
        invoice: _bill(payments: [_pending(claimedAt: DateTime.now())]),
      );
      expect(
        find.text(
          'Waiting for the restaurant to confirm your UPI payment of ₹450.',
        ),
        findsOneWidget,
      );
      expect(find.text('View payment'), findsOneWidget);
      expect(find.text('Pending verification'), findsWidgets);
      await _tap(tester, _key('upi-resume'));
      expect(find.text('Waiting for the restaurant'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an unfinished payment can be cancelled to pay another way', (
      tester,
    ) async {
      final rig = await _openBill(
        tester,
        invoice: _bill(payments: [_pending()]),
      );
      await _tap(tester, _key('upi-resume'));
      await _tap(tester, _key('upi-cancel'));
      expect(rig.server.calls, contains('cancel:PAY000001'));
      expect(find.text('Payment cancelled'), findsOneWidget);
      expect(rig.bill.payableNow, const Money(45000));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('missing payee details stop an unclaimed payment cleanly', (
      tester,
    ) async {
      final rig = await _openBill(
        tester,
        invoice: _bill(payments: [_pending()]),
        settings: _ready.copyWith(enabled: false),
      );
      await _tap(tester, _key('upi-resume'));
      expect(_key('upi-unavailable'), findsOneWidget);
      expect(_key('upi-open-app'), findsNothing);
      expect(find.byType(PlainQrCode), findsNothing);
      await _tap(tester, _key('upi-cancel'));
      expect(rig.server.calls, contains('cancel:PAY000001'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('layout', () {
    const sizes = {'small phone': Size(360, 760), 'tablet': Size(1280, 800)};
    for (final (copy, id) in [(false, 'a bank ID'), (true, 'a UPI app ID')]) {
      for (final MapEntry(key: name, value: size) in sizes.entries) {
        testWidgets(
          'every UPI screen for $id fits a $name at the largest text',
          (tester) async {
            tester.view.physicalSize = size * 2;
            tester.view.devicePixelRatio = 2;
            tester.platformDispatcher.textScaleFactorTestValue = 1.3;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final errors = <String>[];
            final original = FlutterError.onError;
            FlutterError.onError = (d) => errors.add(d.exceptionAsString());
            try {
              final bill = _bill();
              final server = FakeUpiBackend(
                bill,
                settings: (copy ? _googlePay : _ready).copyWith(
                  qrImageUrl: 'https://x.test/uploads/upi/a.png',
                ),
              );
              final deps = await CustomerDependencies.create(
                store: MemoryStore(),
                config: const CustomerConfig(enableCamera: false),
                billingRepository: LocalBillingRepository(
                  MemoryStore(),
                  seed: [bill],
                ),
                billingBackend: server,
                upiLauncher: _FakeLauncher(),
                menuLatency: Duration.zero,
                seedDemoData: false,
              );
              await tester.runAsync(deps.billing.load);
              await tester.runAsync(deps.billing.loadUpiSettings);
              await tester.pumpWidget(DineQrApp(dependencies: deps));
              await tester.pump(const Duration(milliseconds: 2700));
              await settle(tester, 700);
              tester
                  .state<NavigatorState>(find.byType(Navigator).first)
                  .pushNamed(Routes.bill, arguments: bill.id);
              await settle(tester, 800);

              await _tap(tester, find.text('Pay Now'));
              await _tap(tester, find.text('Pay ₹450 with UPI'));
              // The outcome question is up.
              await _visitUpiApp(tester, copy: copy);
              await _tap(tester, _key('upi-own-qr-toggle'));
              await _tap(tester, _key('upi-paid')); // the claim sheet
              await tester.enterText(_key('upi-ref-field'), '12');
              await _tap(tester, _key('upi-claim')); // with its error showing
              await tester.enterText(_key('upi-ref-field'), 'UTR9876543210');
              await _tap(tester, _key('upi-claim')); // now waiting
              await tester.drag(
                find.byType(ListView).last,
                const Offset(0, -600),
              );
              await settle(tester, 500);
            } finally {
              FlutterError.onError = original;
            }
            expect(errors, isEmpty, reason: errors.join('\n'));
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  });
}

/// Opens the payment screen from a bill that has a UPI payment in progress.
Future<void> _goToPaymentFromBill(WidgetTester tester) async {
  await _tap(tester, _key('upi-resume'));
}
