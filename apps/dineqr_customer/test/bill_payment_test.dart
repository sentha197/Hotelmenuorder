import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart'
    show createDependencies, scanDemoTable, settle, usePhoneScreen;

/// Long enough to see the processing screen.
const _processing = Duration(milliseconds: 300);

void main() {
  group('guest bill and payment', () {
    /// Opens the bill for [items]. [gateway] is the payment gateway (none:
    /// only the counter); [options] the online options switched on.
    Future<(CustomerDependencies, Invoice)> placeAndOpenBill(
      WidgetTester tester,
      Map<String, int> items, {
      PaymentGateway? gateway,
      Set<PaymentOption>? options,
    }) async {
      final store = MemoryStore();
      if (options != null) {
        await tester.runAsync(
          () => LocalSettingsRepository(store).saveSettings(
            LocalSettingsRepository.defaults.copyWith(onlineOptions: options),
          ),
        );
      }
      final deps = await createDependencies(
        store: store,
        paymentGateway: gateway,
      );
      final order = (await tester.runAsync(
        () => placeTestOrder(deps.orders, items),
      ))!;
      final invoice = deps.billing.forOrder(order.id)!;
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      await tester.pump(const Duration(milliseconds: 2700)); // splash
      await settle(tester, 700);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(Routes.bill, arguments: invoice.id);
      await settle(tester, 800);
      return (deps, invoice);
    }

    Future<void> openPayment(WidgetTester tester) async {
      await tester.tap(find.text('Pay Now'));
      await settle(tester, 800);
      expect(find.text('Choose how to pay'), findsOneWidget);
    }

    /// Brings an option card fully into view (not under the pay bar) and
    /// selects it.
    Future<void> choose(WidgetTester tester, String option) async {
      // The list builds lazily: scroll the card into existence first.
      await tester.scrollUntilVisible(
        find.text(option),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('form')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text(option));
      await settle(tester, 300);
      await tester.tap(find.text(option));
      await tester.pump();
    }

    /// Taps the pay button and waits for the gateway's answer.
    Future<void> pay(WidgetTester tester, String label) async {
      await tester.tap(find.textContaining(label));
      await settle(tester, 100);
      await settle(tester, 800); // the gateway's processing time
    }

    testWidgets('UPI through the payment gateway settles the bill, with no '
        'demo wording anywhere', (tester) async {
      usePhoneScreen(tester);
      final (deps, invoice) = await placeAndOpenBill(tester, {
        'chicken_65': 2,
      }, gateway: FakePaymentGateway(processingTime: _processing));
      expect(find.text(invoice.billNumber), findsWidgets);
      expect(find.text('Unpaid'), findsWidgets);
      await openPayment(tester);

      // Every option the restaurant switched on, none labelled as a demo.
      for (final option in PaymentOption.values) {
        await choose(tester, option.label);
      }
      expect(find.text('Split payment'), findsOneWidget);
      expect(find.text('DEMO'), findsNothing);
      expect(find.textContaining('Demo'), findsNothing);
      expect(find.textContaining('simulated'), findsNothing);

      await choose(tester, 'UPI');
      await tester.tap(find.textContaining('with UPI'));
      await settle(tester, 100);
      expect(find.text('Confirming your payment…'), findsOneWidget);
      // While it is processing there is nothing to tap twice.
      expect(find.textContaining('with UPI'), findsNothing);
      await settle(tester, 800);

      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('Reference'), findsOneWidget);
      final paid = deps.billing.byId(invoice.id)!;
      expect(paid.status, InvoiceStatus.paid);
      final payment = paid.payments.single;
      expect(payment.isSimulated, isFalse);
      expect(payment.reference, 'TEST-1');
      expect(payment.methodLabel, 'UPI · UPI ID');
      expect(find.text(payment.reference), findsOneWidget);

      // Back on the bill: refreshed, paid, a plain receipt.
      await tester.tap(find.text('Done'));
      await settle(tester, 800);
      expect(find.text('Pay Now'), findsNothing);
      expect(find.text('RECEIPT'), findsOneWidget);
      expect(find.text('DEMO RECEIPT'), findsNothing);
      expect(find.text('TEST PAYMENT'), findsNothing);
    });

    testWidgets('UPI and QR Code show only when switched on; a declined '
        'payment charges nothing and can be retried by card', (tester) async {
      usePhoneScreen(tester);
      final gateway = FakePaymentGateway(processingTime: _processing);
      final (deps, invoice) = await placeAndOpenBill(
        tester,
        {'masala_dosa': 1},
        gateway: gateway,
        options: {PaymentOption.scanAndPay, PaymentOption.card},
      );
      await openPayment(tester);
      // QR Code without UPI from an app.
      expect(find.byKey(const ValueKey('option-scanAndPay')), findsOneWidget);
      expect(find.byKey(const ValueKey('option-upi')), findsNothing);
      expect(find.byKey(const ValueKey('option-wallet')), findsNothing);

      gateway.next = FakePaymentOutcome.failure;
      await choose(tester, 'QR Payment');
      await pay(tester, 'by QR code');
      expect(find.text('Payment failed'), findsWidgets);
      var bill = deps.billing.byId(invoice.id)!;
      expect(bill.amountPaid, Money.zero);
      expect(bill.status, InvoiceStatus.failed);
      expect(bill.payments.single.methodDetail, 'QR code');

      gateway.next = FakePaymentOutcome.success;
      await tester.tap(find.text('Try again'));
      await settle(tester, 600);
      await choose(tester, 'Card');
      // Nothing here asks for a card number.
      expect(find.byType(TextField), findsNothing);
      await pay(tester, 'with Card');
      expect(find.text('Payment successful'), findsOneWidget);
      bill = deps.billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.paid);
      expect(bill.amountPaid, invoice.total);
    });

    testWidgets('UPI from an app without QR Code', (tester) async {
      usePhoneScreen(tester);
      await placeAndOpenBill(
        tester,
        {'masala_dosa': 1},
        gateway: FakePaymentGateway(),
        options: {PaymentOption.upi},
      );
      await openPayment(tester);
      expect(find.byKey(const ValueKey('option-upi')), findsOneWidget);
      expect(find.byKey(const ValueKey('option-scanAndPay')), findsNothing);
      expect(find.byKey(const ValueKey('option-card')), findsNothing);
    });

    testWidgets('without a payment gateway only cash and the counter are '
        'offered', (tester) async {
      usePhoneScreen(tester);
      final (deps, invoice) = await placeAndOpenBill(tester, {
        'paneer_tikka': 1,
      });
      await openPayment(tester);
      expect(
        find.textContaining('Online payment is not available right now'),
        findsOneWidget,
      );
      for (final option in PaymentOption.online) {
        expect(
          find.byKey(ValueKey('option-${option.name}')),
          findsNothing,
          reason: option.label,
        );
      }
      expect(find.byKey(const ValueKey('option-cash')), findsOneWidget);
      expect(find.byKey(const ValueKey('option-payAtCounter')), findsOneWidget);
      expect(find.textContaining('Demo'), findsNothing);
      expect(deps.billing.byId(invoice.id)!.payments, isEmpty);
    });

    testWidgets('cash at the counter waits for staff and moves no money', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final (deps, invoice) = await placeAndOpenBill(tester, {
        'butter_chicken': 1,
      });
      await openPayment(tester);
      await choose(tester, 'Cash');
      final amount = CurrencyFormatter.format(invoice.total);
      await tester.tap(find.text('Pay $amount in cash'));
      await settle(tester, 800);

      expect(find.text('Pay $amount in cash'), findsOneWidget); // title
      expect(find.textContaining('Nothing has been paid yet'), findsOneWidget);
      var bill = deps.billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.unpaid);
      expect(bill.payments, isEmpty);
      expect(bill.openCounterRequest!.kind, CounterRequestKind.cash);

      await tester.tap(find.text('Back to bill'));
      await settle(tester, 800);
      expect(find.text('Pay another way'), findsOneWidget);
      expect(find.textContaining('Cash at the counter'), findsOneWidget);

      // The guest changes their mind.
      await tester.tap(find.text('Cancel'));
      await settle(tester, 400);
      bill = deps.billing.byId(invoice.id)!;
      expect(bill.counterRequest, isNull);
      expect(find.text('Pay Now'), findsOneWidget);
    });

    testWidgets('a split bill: UPI online, the rest in cash at the counter', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final (deps, invoice) = await placeAndOpenBill(tester, {
        'chicken_65': 2,
        'butter_naan': 2,
      }, gateway: FakePaymentGateway(processingTime: _processing));
      final due = invoice.payableNow;
      final online = Money((due.paise ~/ 200) * 100);
      final rest = due - online;
      await openPayment(tester);
      await choose(tester, 'Split payment');
      await settle(tester, 800);

      expect(find.text('Part 1'), findsOneWidget);
      expect(find.text('Part 2'), findsOneWidget);
      await tester.tap(find.text('Start split payment'));
      await settle(tester, 400);

      await tester.tap(
        find.text('Pay part 1: ${CurrencyFormatter.format(online)} by UPI'),
      );
      await settle(tester, 100);
      await settle(tester, 800);
      var bill = deps.billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.partiallyPaid);
      expect(bill.amountPaid, online);

      await tester.tap(
        find.text(
          'Pay ${CurrencyFormatter.format(rest)} in cash at the counter',
        ),
      );
      await settle(tester, 800);
      expect(find.text('Online parts paid'), findsOneWidget);
      bill = deps.billing.byId(invoice.id)!;
      expect(bill.payments, hasLength(1));
      expect(bill.amountPaid, online);
      expect(bill.openCounterRequest!.amount, rest);
      expect(bill.status, InvoiceStatus.partiallyPaid);
    });

    testWidgets('bill and payment screens fit a desktop window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await placeAndOpenBill(tester, {
        'masala_dosa': 1,
      }, gateway: FakePaymentGateway());
      expect(tester.takeException(), isNull);
      // The bill is centred at a readable width.
      expect(tester.getSize(find.byType(InvoiceView)).width, lessThan(641));
      await openPayment(tester);
      expect(tester.takeException(), isNull);
      // The options one below another, in a column of readable width.
      final upi = tester.getTopLeft(find.text('UPI'));
      final qr = tester.getTopLeft(find.text('QR Payment'));
      final card = tester.getTopLeft(find.text('Card'));
      // The chosen row (UPI) has a thicker border: within a pixel.
      expect(qr.dx, closeTo(upi.dx, 1));
      expect(card.dx, closeTo(qr.dx, 1));
      expect(qr.dy, greaterThan(upi.dy));
      expect(card.dy, greaterThan(qr.dy));
      expect(
        tester.getSize(find.byKey(const ValueKey('option-upi'))).width,
        lessThan(641),
      );
    });
  });

  group('the customer app has no staff area', () {
    // Guest screens must not mention admin or staff access anywhere.
    final adminWording = find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .toLowerCase();
      return text.contains('admin') ||
          text.contains('staff sign') ||
          text.contains('sign in');
    });

    testWidgets('no screen, gesture or URL opens staff sign-in', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createDependencies();
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      await scanDemoTable(tester, 'Table 05');

      await tester.tap(find.text('Start Ordering'));
      await settle(tester, 800);
      expect(adminWording, findsNothing, reason: 'Home');
      await tester.tap(find.text('More'));
      await settle(tester, 700);
      expect(adminWording, findsNothing, reason: 'More');
      await tester.scrollUntilVisible(
        find.textContaining('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // To the end of the list, clear of the bottom navigation bar.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await settle(tester, 300);
      await tester.tap(find.textContaining('About'));
      await settle(tester, 700);
      expect(adminWording, findsNothing, reason: 'About sheet');

      // The version line used to hide a staff entry; now it is plain text.
      await tester.longPress(find.textContaining('Version'));
      await settle(tester, 900);
      expect(find.text('Staff sign in'), findsNothing);
      await tester.tap(find.text('Got it'));
      await settle(tester, 700);

      // An old /admin link lands in the guest app, not on a staff screen.
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed('/admin');
      await settle(tester, 900);
      expect(find.text('Staff sign in'), findsNothing);
      expect(adminWording, findsNothing, reason: '/admin route');
    });
  });
}
