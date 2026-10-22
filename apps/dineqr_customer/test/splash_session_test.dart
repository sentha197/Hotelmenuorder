import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
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
}
