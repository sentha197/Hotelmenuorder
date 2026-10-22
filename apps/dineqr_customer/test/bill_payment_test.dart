import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
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
      usePhoneScreen(tester);
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

    testWidgets('a simulated payment settles the bill', (tester) async {
      final (deps, invoice) = await placeAndOpenBill(tester, {'chicken_65': 2});
      expect(find.text(invoice.billNumber), findsWidgets);
      final payLabel = 'Pay ${CurrencyFormatter.format(invoice.payableNow)}';
      await tester.ensureVisible(find.text(payLabel));
      await tester.tap(find.text(payLabel));
      await settle(tester, 800);

      expect(find.text('Pay with'), findsOneWidget);
      expect(find.text('SIMULATED'), findsWidgets);
      await tester.tap(find.text(payLabel).last);
      await tester.pump();
      expect(find.text('Confirming your payment…'), findsOneWidget);
      await settle(tester, 400); // simulated processing time
      await settle(tester, 800);

      expect(find.text('Payment successful'), findsOneWidget);
      final paid = deps.billing.byId(invoice.id)!;
      expect(paid.status, InvoiceStatus.paid);
      expect(paid.payments.single.isSimulated, isTrue);
    });

    testWidgets('a declined payment can be retried and charges nothing', (
      tester,
    ) async {
      final (deps, invoice) = await placeAndOpenBill(tester, {
        'masala_dosa': 1,
      });
      final payLabel = 'Pay ${CurrencyFormatter.format(invoice.payableNow)}';
      await tester.ensureVisible(find.text(payLabel));
      await tester.tap(find.text(payLabel));
      await settle(tester, 800);

      await tester.scrollUntilVisible(
        find.text('Failure'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('form')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Failure'));
      await tester.pump();
      await tester.tap(find.text(payLabel).last);
      await settle(tester, 400);
      await settle(tester, 800);

      // The result title and the bill's status badge.
      expect(find.text('Payment failed'), findsWidgets);
      expect(find.text('Try again'), findsOneWidget);
      final bill = deps.billing.byId(invoice.id)!;
      expect(bill.amountPaid, Money.zero);
      expect(bill.status, InvoiceStatus.failed);

      await tester.tap(find.text('Try again'));
      await settle(tester, 600);
      expect(find.text('Pay with'), findsOneWidget);
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
