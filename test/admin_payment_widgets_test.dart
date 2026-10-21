import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/app/app.dart';
import 'package:menu_order/app/dependencies.dart';
import 'package:menu_order/app/routes.dart';
import 'package:menu_order/core/utils/currency.dart';
import 'package:menu_order/data/models/billing.dart';
import 'package:menu_order/data/services/auth_service.dart';
import 'package:menu_order/data/storage/key_value_store.dart';

import 'app_flow_test.dart'
    show createDependencies, scanDemoTable, settle, usePhoneScreen;
import 'support/fakes.dart';

void main() {
  group('staff sign-in screen', () {
    testWidgets(
      'validates input, rejects bad passwords and opens the dashboard',
      (tester) async {
        usePhoneScreen(tester);
        final deps = await createDependencies();
        await tester.pumpWidget(
          DineQrApp(dependencies: deps, initialRoute: Routes.admin),
        );
        await settle(tester, 800);

        expect(find.text('Staff sign in'), findsOneWidget);
        // The guest splash is not underneath the admin entry.
        expect(find.text('Scan QR Code'), findsNothing);
        expect(find.text('Demo accounts (offline demo only)'), findsOneWidget);

        await tester.ensureVisible(find.text('Sign in'));
        await tester.tap(find.text('Sign in'));
        await settle(tester, 300);
        expect(find.text('Enter your email.'), findsOneWidget);
        expect(find.text('Enter your password.'), findsOneWidget);

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'owner@dineqr.demo');
        await tester.enterText(fields.at(1), 'not-the-password1');
        await tester.tap(find.text('Sign in'));
        await settle(tester, 600);
        expect(find.text(AuthError.invalidCredentials.message), findsOneWidget);
        expect(deps.admin.isSignedIn, isFalse);

        await tester.enterText(fields.at(1), DemoCredentials.password);
        await tester.tap(find.text('Sign in'));
        await settle(tester, 800);
        await settle(tester, 800);
        expect(deps.admin.isSignedIn, isTrue);
        expect(deps.admin.actor!.name, 'Demo Owner');
        expect(find.text('Staff sign in'), findsNothing);
        expect(find.text('Dashboard'), findsWidgets);

        // Dispose the shell so its periodic session check stops.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('a kitchen account only sees its own modules', (tester) async {
      usePhoneScreen(tester);
      final deps = await createDependencies();
      await deps.admin.signIn('kitchen@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(
        DineQrApp(dependencies: deps, initialRoute: Routes.admin),
      );
      await settle(tester, 800);
      await settle(tester, 800);

      expect(find.text('Kitchen'), findsWidgets);
      expect(find.text('Bills'), findsNothing);
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Settings'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('signing out returns to the sign-in screen', (tester) async {
      usePhoneScreen(tester);
      final deps = await createDependencies();
      await deps.admin.signIn('manager@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(
        DineQrApp(dependencies: deps, initialRoute: Routes.admin),
      );
      await settle(tester, 800);
      await settle(tester, 800);
      expect(find.text('Staff sign in'), findsNothing);

      await deps.admin.signOut(reason: 'Signed out for the test.');
      await settle(tester, 800);
      expect(find.text('Staff sign in'), findsOneWidget);
      expect(find.text('Signed out for the test.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('guest bill and payment', () {
    Future<(AppDependencies, Invoice)> placeAndOpenBill(
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

  group('reaching staff sign-in from the guest app', () {
    // Guest screens must not mention admin or staff access anywhere.
    final adminWording = find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .toLowerCase();
      return text.contains('admin') ||
          text.contains('staff') ||
          text.contains('sign in');
    });

    Future<void> openAbout(WidgetTester tester) async {
      await tester.tap(find.text('Start Ordering'));
      await settle(tester, 800);
      expect(adminWording, findsNothing, reason: 'Home');
      await tester.tap(find.text('More'));
      await settle(tester, 700);
      expect(adminWording, findsNothing, reason: 'More');
      // The About tile is at the bottom of a long list, so scroll to it.
      await tester.scrollUntilVisible(
        find.textContaining('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.textContaining('About'));
      await settle(tester, 700);
      expect(adminWording, findsNothing, reason: 'About sheet');
    }

    testWidgets('a long press on the version line opens it (demo build)', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createDependencies();
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      await scanDemoTable(tester, 'Table 05');
      await openAbout(tester);

      final version = find.text('Version 1.0.0 · Demo build');
      // A quick tap does nothing.
      await tester.tap(version);
      await settle(tester, 600);
      expect(find.text('Staff sign in'), findsNothing);
      // The touch area is larger than the text, so a slightly-off press works.
      await tester.longPressAt(tester.getCenter(version) + const Offset(0, 14));
      await settle(tester, 900);
      await settle(tester, 800);

      expect(find.text('Staff sign in'), findsOneWidget);
      expect(deps.admin.isSignedIn, isFalse);
      // The guest app is still underneath, so Back returns to it.
      expect(find.text('Back'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await settle(tester, 800);
      expect(find.text('Staff sign in'), findsNothing);
      expect(find.text('More'), findsWidgets);
    });

    testWidgets('the demo accounts panel fills in the sign-in', (tester) async {
      usePhoneScreen(tester);
      final deps = await createDependencies();
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      await scanDemoTable(tester, 'Table 05');
      await openAbout(tester);
      await tester.longPress(find.text('Version 1.0.0 · Demo build'));
      await settle(tester, 900);
      await settle(tester, 800);

      await tester.ensureVisible(find.text('Owner'));
      await tester.tap(find.text('Owner'));
      await settle(tester, 400);
      await tester.tap(find.text('Sign in'));
      await settle(tester, 900);
      await settle(tester, 900);

      expect(deps.admin.isSignedIn, isTrue);
      expect(deps.admin.actor!.email, 'owner@dineqr.demo');

      // Dispose the shell so its periodic session check stops.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('does nothing when demo mode is off', (tester) async {
      usePhoneScreen(tester);
      final deps = await AppDependencies.create(
        store: MemoryStore(),
        config: const AppConfig(enableCamera: false, demoMode: false),
        menuLatency: Duration.zero,
        orderLatency: Duration.zero,
      );
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      await scanDemoTable(tester, 'Table 05');
      await openAbout(tester);

      await tester.longPress(find.text('Version 1.0.0'));
      await settle(tester, 900);
      expect(find.text('Staff sign in'), findsNothing);
      expect(deps.admin.isDemo, isFalse);
      // Without a configured service, staff sign-in is refused outright.
      await expectLater(
        deps.admin.signIn('owner@dineqr.demo', 'Demo@1234'),
        throwsA(isA<AuthException>()),
      );
      expect(deps.admin.isSignedIn, isFalse);
    });
  });
}
