import 'dart:async';
import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/features/splash/splash_screen.dart';
import 'package:dineqr_customer/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show settle, usePhoneScreen;

void main() {
  final start = DateTime(2026, 10, 22, 19, 30);

  Future<CustomerDependencies> reopen(MemoryStore store, DateTime now) =>
      CustomerDependencies.create(
        store: store,
        config: const CustomerConfig(enableCamera: false),
        menuLatency: Duration.zero,
        seedDemoData: false,
        clock: () => now,
      );

  Future<void> passSplash(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 2700));
    await settle(tester, 900);
  }

  test('a table session resumes only within the dining window', () async {
    final store = MemoryStore();
    var now = start;
    final session = SessionController(store, clock: () => now);
    await session.startSession(7);
    expect(session.resumableTable, 7);

    now = start.add(const Duration(hours: 3, minutes: 59));
    expect(SessionController(store, clock: () => now).resumableTable, 7);

    now = start.add(const Duration(hours: 4, minutes: 1));
    final later = SessionController(store, clock: () => now);
    expect(later.resumableTable, isNull);
    // The table is still remembered for the scanner's "continue" option.
    expect(later.tableNumber, 7);
  });

  testWidgets('reopening mid-meal goes straight back to the menu', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final store = MemoryStore();
    await SessionController(store, clock: () => start).startSession(7);

    final deps = await reopen(store, start.add(const Duration(minutes: 40)));
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await passSplash(tester);

    expect(find.text('Scan QR Code'), findsNothing);
    expect(find.text('Popular Dishes'), findsOneWidget);
  });

  testWidgets('an expired session opens the scanner', (tester) async {
    usePhoneScreen(tester);
    final store = MemoryStore();
    await SessionController(store, clock: () => start).startSession(7);

    final deps = await reopen(store, start.add(const Duration(hours: 6)));
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await passSplash(tester);
    expect(find.text('Scan QR Code'), findsOneWidget);
  });

  testWidgets('a takeaway session resumes while takeaway is open', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final store = MemoryStore();
    await SessionController(
      store,
      clock: () => start,
    ).startSession(OrderTables.takeaway);

    final deps = await reopen(store, start.add(const Duration(minutes: 20)));
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await passSplash(tester);
    expect(find.text('Popular Dishes'), findsOneWidget);
    expect(deps.session.isTakeaway, isTrue);
  });

  testWidgets('a takeaway session is not resumed once takeaway closes', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final store = MemoryStore();
    await SessionController(
      store,
      clock: () => start,
    ).startSession(OrderTables.takeaway);
    await store.write(
      StorageKeys.settings,
      jsonEncode(
        LocalSettingsRepository.defaults
            .copyWith(takeawayOrdersEnabled: false)
            .toJson(),
      ),
    );

    final deps = await reopen(store, start.add(const Duration(minutes: 20)));
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await passSplash(tester);
    expect(find.text('Scan QR Code'), findsOneWidget);
  });

  group('waiting for the server', () {
    Future<CustomerDependencies> withServer(SettingsRepository settings) {
      final store = MemoryStore();
      return CustomerDependencies.create(
        store: store,
        config: CustomerConfig(
          enableCamera: false,
          demoMode: false,
          api: ApiConfig(baseUrl: Uri.parse('http://api.test')),
        ),
        settingsRepository: settings,
        menuRepository: DemoMenuRepository(
          latency: Duration.zero,
          store: store,
        ),
        orderRepository: LocalOrderRepository(
          store,
          latency: Duration.zero,
          seedDemoOrders: false,
        ),
        billingRepository: LocalBillingRepository(store),
        paymentGateway: const UnavailablePaymentGateway(),
      );
    }

    testWidgets('the splash shows at once and says it is connecting', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final settings = _ServerSettings()..gate = Completer<void>();
      final deps = await withServer(settings);
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2700));
      expect(find.text('Connecting to the restaurant…'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsNothing);

      await tester.pump(SplashScreen.slowAfter);
      expect(find.textContaining('can take up to a minute'), findsOneWidget);

      settings.gate!.complete();
      await settle(tester, 900);
      expect(find.text('Scan QR Code'), findsOneWidget);
      // Stops the polling timer; awaiting the stream cancel would never
      // finish under the test clock.
      deps.liveUpdates!.dispose().ignore();
    });

    testWidgets('an unreachable server gets a retry, not an endless spinner', (
      tester,
    ) async {
      usePhoneScreen(tester);
      // The attempt started with the app and the splash's own one both fail.
      final settings = _ServerSettings()..failures = 2;
      final deps = await withServer(settings);
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      await tester.pump(const Duration(milliseconds: 2700));

      expect(find.text("Can't reach the restaurant"), findsOneWidget);
      expect(find.text(const ApiException.network().message), findsOneWidget);
      expect(find.text('Scan QR Code'), findsNothing);

      await tester.tap(find.text('Try again'));
      await settle(tester, 900);
      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(settings.calls, 3);
      // Stops the polling timer; awaiting the stream cancel would never
      // finish under the test clock.
      deps.liveUpdates!.dispose().ignore();
    });
  });
}

/// Restaurant settings from a server that can be slow ([gate]) or fail
/// ([failures] times).
class _ServerSettings implements SettingsRepository {
  Completer<void>? gate;
  int failures = 0;
  int calls = 0;

  @override
  Future<RestaurantSettings> fetchSettings() async {
    calls++;
    await gate?.future;
    if (failures > 0) {
      failures--;
      throw const ApiException.network();
    }
    return const RestaurantSettings(takeawayOrdersEnabled: true);
  }

  @override
  Future<List<RestaurantTable>> fetchTables() async => [
    for (var n = 1; n <= 30; n++) RestaurantTable(number: n),
  ];

  @override
  Future<void> saveSettings(RestaurantSettings settings) async {}

  @override
  Future<void> saveTables(List<RestaurantTable> tables) async {}

  @override
  Future<void> reset() async {}
}
