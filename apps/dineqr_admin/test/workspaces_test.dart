import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/state/service_section_controller.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('service board (waiters)', () {
    testWidgets('a waiter lands on Service and serves a ready order', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies();
      final order = (await tester.runAsync(
        () => placeTestOrder(deps.orders, {'chicken_65': 1}, table: 5),
      ))!;
      // The demo kitchen simulator moves it to "ready" without a kitchen
      // login: placed → accepted → preparing → ready.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => deps.orders.advanceStatus(order.id));
      }
      expect(deps.orders.byId(order.id)!.status, OrderStatus.readyToServe);

      await deps.admin.signIn('service@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await settle(tester, 900);

      expect(find.text('Ready to serve'), findsOneWidget);
      expect(find.text('Service workspace'), findsOneWidget);
      final serve = find.text('Served at table 05');
      expect(serve, findsOneWidget);
      await tester.ensureVisible(serve);
      await tester.tap(serve);
      await settle(tester, 600);
      await settle(tester, 600);

      expect(deps.orders.byId(order.id)!.status, OrderStatus.served);
      expect(find.text('All served'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('a waiter section is saved per staff member', () async {
      final store = MemoryStore();
      final sections = ServiceSectionController(store);
      await sections.setTables('W1', {3, 5});
      await sections.setTables('W2', {9});
      final reopened = ServiceSectionController(store);
      expect(reopened.tablesFor('W1'), {3, 5});
      expect(reopened.tablesFor('W2'), {9});
      await reopened.setTables('W1', {});
      expect(ServiceSectionController(store).tablesFor('W1'), isEmpty);
    });
  });

  group('counter (cashiers)', () {
    testWidgets('a cashier lands on Bills and can start a counter order', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies(seedDemoData: true);
      await deps.admin.signIn('cashier@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await settle(tester, 900);

      expect(find.text('Counter workspace'), findsOneWidget);
      // Bills is the landing module and the first navigation item.
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 0);
      expect(find.text('Payments'), findsWidgets);

      await tester.tap(find.text('Orders').last);
      await settle(tester, 900);
      expect(find.text('New order'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('payment history totals match the reports', (tester) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies(seedDemoData: true);
      await deps.admin.signIn('cashier@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await tester.tap(find.text('Payments').last);
      await settle(tester, 900);
      await tester.ensureVisible(find.text('Last 30 days'));
      await settle(tester, 300);
      await tester.tap(find.text('Last 30 days'));
      await settle(tester, 600);

      final now = DateTime.now();
      final report = SalesReport.build(
        orders: deps.orders.orders,
        invoices: deps.billing.invoices,
        range: DateRange.preset(RangePreset.last30, now),
        now: now,
      );
      expect(
        find.text(CurrencyFormatter.format(report.collected)),
        findsWidgets,
      );
      expect(find.textContaining('SIMULATED'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
