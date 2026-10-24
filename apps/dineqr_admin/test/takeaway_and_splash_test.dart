import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/app/dependencies.dart';
import 'package:dineqr_admin/auth/admin_login_screen.dart';
import 'package:dineqr_admin/auth/admin_splash_screen.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Demo sign-in whose restores (after the first, made while the app is
/// created) fail [failures] times as if the server were unreachable.
class _UnreachableAtFirst implements AuthService {
  _UnreachableAtFirst(this._inner, {required this.failures});

  final AuthService _inner;
  int failures;
  int restores = 0;

  @override
  bool get isDemo => _inner.isDemo;

  @override
  Future<({StaffAccount staff, AdminSession session})> signIn(
    String email,
    String password,
  ) => _inner.signIn(email, password);

  @override
  Future<({StaffAccount staff, AdminSession session})?> restore() async {
    restores++;
    if (restores > 1 && failures > 0) {
      failures--;
      throw const ApiException.network();
    }
    return _inner.restore();
  }

  @override
  Future<void> signOut() => _inner.signOut();
}

double _markWidth(WidgetTester tester) =>
    tester.widget<DineQrMark>(find.byType(DineQrMark).first).size;

void main() {
  group('splash', () {
    testWidgets('opens on the launch frame and hands over to sign-in', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies();
      await tester.pumpWidget(
        DineQrAdminApp(dependencies: deps, showSplash: true),
      );

      // The first frame is the native launch screen.
      expect(find.byType(AdminSplashScreen), findsOneWidget);
      expect(_markWidth(tester), AdminLoginScreen.launchMarkWidth);

      await tester.pump(const Duration(milliseconds: 700));
      expect(_markWidth(tester), greaterThan(AdminLoginScreen.launchMarkWidth));
      expect(find.text('Restaurant management'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      await settle(tester, 500);
      await settle(tester, 1000);
      expect(find.byType(AdminSplashScreen), findsNothing);
      expect(find.text('Staff sign in'), findsOneWidget);
    });

    testWidgets('a saved session goes straight to the workspace', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final store = MemoryStore();
      final first = await createAdminDependencies(store: store);
      await first.admin.signIn('manager@dineqr.demo', DemoCredentials.password);

      final deps = await createAdminDependencies(store: store);
      await tester.pumpWidget(
        DineQrAdminApp(dependencies: deps, showSplash: true),
      );
      await tester.pump(const Duration(milliseconds: 1400));
      await settle(tester, 600);
      await settle(tester, 900);

      expect(find.byType(AdminSplashScreen), findsNothing);
      expect(find.text('Staff sign in'), findsNothing);
      expect(deps.admin.isSignedIn, isTrue);
      expect(find.text('Operations workspace'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an unreachable server gets a retry, not an endless wait', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final store = MemoryStore();
      final auth = _UnreachableAtFirst(
        DemoAuthService(LocalStaffRepository(store, seed: () => []), store),
        // The splash's attempt and its one automatic retry.
        failures: 2,
      );
      final deps = await AdminDependencies.create(
        store: store,
        authService: auth,
        menuLatency: Duration.zero,
        orderLatency: Duration.zero,
        seedDemoData: false,
      );
      await tester.pumpWidget(
        DineQrAdminApp(dependencies: deps, showSplash: true),
      );
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(seconds: 1)); // the automatic retry
      await settle(tester, 400);

      expect(find.text("Can't reach the DineQR server"), findsOneWidget);
      expect(find.text('Staff sign in'), findsNothing);
      expect(auth.restores, 3);

      await tester.tap(find.text('Try again'));
      await settle(tester, 600);
      await settle(tester, 900);
      expect(auth.restores, 4);
      expect(find.text('Staff sign in'), findsOneWidget);
    });
  });

  group('takeaway', () {
    testWidgets('a cashier rings up a takeaway order at the counter', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies();
      await deps.admin.signIn('cashier@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await settle(tester, 900);

      await tester.tap(find.text('Orders').last);
      await settle(tester, 900);
      await tester.tap(find.text('New order'));
      await settle(tester, 900);

      await tester.tap(find.text('Takeaway'));
      await settle(tester, 300);
      expect(find.text('Choose a table'), findsNothing);
      expect(find.textContaining('Collected at the counter'), findsOneWidget);

      final add = find.byTooltip('Add Chicken 65');
      await tester.scrollUntilVisible(
        add,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(add);
      await settle(tester, 300);
      await tester.tap(find.textContaining('Place order ·'));
      await settle(tester, 900);
      await settle(tester, 900);

      final order = deps.orders.orders.first;
      expect(order.isTakeaway, isTrue);
      expect(order.source, OrderSource.staff);
      expect(deps.billing.forOrder(order.id)!.isTakeaway, isTrue);
      // The order detail opens, labelled as takeaway.
      expect(find.text('Takeaway'), findsWidgets);
      expect(find.text('Table 00'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('waiters hand a ready takeaway order over at the counter', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies();
      final order = (await tester.runAsync(
        () => placeTestOrder(deps.orders, {
          'samosa': 2,
        }, table: OrderTables.takeaway),
      ))!;
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => deps.orders.advanceStatus(order.id));
      }
      expect(deps.orders.byId(order.id)!.status, OrderStatus.readyToServe);

      await deps.admin.signIn('service@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await settle(tester, 900);

      expect(find.text('Served at table 00'), findsNothing);
      final handOver = find.text('Handed over at the counter');
      expect(handOver, findsOneWidget);
      await tester.ensureVisible(handOver);
      await tester.tap(handOver);
      await settle(tester, 600);
      await settle(tester, 600);
      expect(deps.orders.byId(order.id)!.status, OrderStatus.served);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
