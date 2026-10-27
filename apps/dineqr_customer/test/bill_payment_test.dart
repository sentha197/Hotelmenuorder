import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
import 'package:dineqr_customer/features/billing/demo_checkout_sheet.dart'
    show demoUpiId;
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart'
    show createDependencies, scanDemoTable, settle, usePhoneScreen;

void main() {
  group('guest bill and payment', () {
    Future<(CustomerDependencies, Invoice)> placeAndOpenBill(
      WidgetTester tester,
      Map<String, int> items,
    ) async {
      final deps = await createDependencies();
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

    /// Taps the pay button, which opens the demo checkout sheet.
    Future<void> payWith(WidgetTester tester, String label) async {
      await tester.tap(find.textContaining('with $label'));
      await settle(tester, 700);
      expect(find.text('Confirm demo payment'), findsOneWidget);
    }

    Future<void> finishCheckout(WidgetTester tester, String action) async {
      await tester.ensureVisible(find.text(action));
      await tester.tap(find.text(action));
      await settle(tester, 700); // sheet closes, processing starts
      await settle(tester, 800); // simulated processing time
    }

    testWidgets('UPI: the demo checkout settles the bill with a demo '
        'reference', (tester) async {
      usePhoneScreen(tester);
      final (deps, invoice) = await placeAndOpenBill(tester, {'chicken_65': 2});
      expect(find.text(invoice.billNumber), findsWidgets);
      expect(find.text('Unpaid'), findsWidgets);
      await openPayment(tester);

      // Every option, labelled as a demo.
      for (final option in PaymentOption.values) {
        await choose(tester, option.label);
      }
      expect(find.text('Split payment'), findsOneWidget);
      expect(find.text('DEMO'), findsWidgets);

      await choose(tester, 'UPI');
      await payWith(tester, 'UPI');
      expect(find.text(demoUpiId), findsOneWidget);
      expect(find.text('DEMO PAYMENT'), findsWidgets);
      // Nothing is recorded before the guest confirms.
      expect(deps.billing.byId(invoice.id)!.payments, isEmpty);

      await tester.tap(find.text('Confirm demo payment'));
      await settle(tester, 700);
      expect(find.text('Confirming your demo payment…'), findsOneWidget);
      // While it is processing there is nothing to tap twice.
      expect(find.textContaining('with UPI'), findsNothing);
      await settle(tester, 800);

      expect(find.text('Demo payment successful'), findsOneWidget);
      expect(find.text('Demo transaction ref'), findsOneWidget);
      final paid = deps.billing.byId(invoice.id)!;
      expect(paid.status, InvoiceStatus.paid);
      final payment = paid.payments.single;
      expect(payment.isSimulated, isTrue);
      expect(payment.reference, startsWith('DEMO-'));
      expect(payment.methodLabel, 'UPI · UPI ID');
      expect(find.text(payment.reference), findsOneWidget);

      // Back on the bill: refreshed, paid, marked as a demo receipt.
      await tester.tap(find.text('Done'));
      await settle(tester, 800);
      expect(find.text('Pay Now'), findsNothing);
      expect(find.text('DEMO RECEIPT'), findsOneWidget);
      expect(find.text('DEMO PAYMENT'), findsOneWidget);
    });

    testWidgets('Scan & Pay shows a QR code; a declined payment charges '
        'nothing and can be retried by card', (tester) async {
      usePhoneScreen(tester);
      final (deps, invoice) = await placeAndOpenBill(tester, {
        'masala_dosa': 1,
      });
      await openPayment(tester);
      await choose(tester, 'Scan & Pay');
      await payWith(tester, 'Scan & Pay');
      expect(find.byType(TableQrCode), findsOneWidget);
      expect(find.text('Scan with any UPI app'), findsOneWidget);

      await finishCheckout(tester, 'Simulate failure');
      expect(find.text('Payment failed'), findsWidgets);
      var bill = deps.billing.byId(invoice.id)!;
      expect(bill.amountPaid, Money.zero);
      expect(bill.status, InvoiceStatus.failed);
      expect(bill.payments.single.methodDetail, 'Scan & Pay');

      await tester.tap(find.text('Try again'));
      await settle(tester, 600);
      await choose(tester, 'Card');
      await payWith(tester, 'Card');
      // A test card is shown; nothing asks for a real card number.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Debit card'));
      await tester.pump();
      await finishCheckout(tester, 'Confirm demo payment');

      expect(find.text('Demo payment successful'), findsOneWidget);
      bill = deps.billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.paid);
      expect(bill.amountPaid, invoice.total);
      expect(
        bill.payments
            .where((p) => p.status == PaymentStatus.succeeded)
            .single
            .methodLabel,
        'Card · Debit',
      );
    });

    testWidgets('a cancelled or closed checkout never counts as paid', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final (deps, invoice) = await placeAndOpenBill(tester, {
        'paneer_tikka': 1,
      });
      await openPayment(tester);

      // Closing the sheet records nothing.
      await choose(tester, 'Wallet');
      await payWith(tester, 'Wallet');
      await tester.tapAt(const Offset(20, 20));
      await settle(tester, 700);
      expect(find.text('Confirm demo payment'), findsNothing);
      expect(deps.billing.byId(invoice.id)!.payments, isEmpty);

      await choose(tester, 'Net Banking');
      await payWith(tester, 'Net Banking');
      await tester.tap(find.text('Axis Bank'));
      await tester.pump();
      await finishCheckout(tester, 'Cancel payment');
      expect(find.text('Payment cancelled'), findsOneWidget);
      final bill = deps.billing.byId(invoice.id)!;
      expect(bill.amountPaid, Money.zero);
      expect(bill.outstanding, invoice.total);
      expect(bill.payments.single.status, PaymentStatus.cancelled);
      expect(bill.payments.single.methodDetail, 'Axis Bank');
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
      });
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
      await settle(tester, 700);
      await finishCheckout(tester, 'Confirm demo payment');
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
      await placeAndOpenBill(tester, {'masala_dosa': 1});
      expect(tester.takeException(), isNull);
      // The bill is centred at a readable width.
      expect(tester.getSize(find.byType(InvoiceView)).width, lessThan(641));
      await openPayment(tester);
      expect(tester.takeException(), isNull);
      // Three options per row on wide screens.
      final upi = tester.getTopLeft(find.text('UPI')).dy;
      expect(tester.getTopLeft(find.text('Scan & Pay')).dy, upi);
      expect(tester.getTopLeft(find.text('Card')).dy, upi);
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
