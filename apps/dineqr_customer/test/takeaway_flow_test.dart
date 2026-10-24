import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show createDependencies, settle, usePhoneScreen;

final _orderTakeaway = find.textContaining(
  'Order takeaway',
  findRichText: true,
);

Future<void> passSplash(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2700));
  await settle(tester, 700);
}

void main() {
  testWidgets('a guest orders takeaway and collects it at the counter', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final semantics = tester.ensureSemantics();
    final deps = await createDependencies();
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await passSplash(tester);

    // 1. The scanner offers takeaway while the restaurant takes it.
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(_orderTakeaway, findsOneWidget);
    await tester.tap(_orderTakeaway);
    await tester.pump();
    expect(find.text('Takeaway selected'), findsOneWidget);
    await settle(tester, 1000);
    await settle(tester, 1000);

    // 2. Welcome: no table, collect at the counter.
    expect(find.text('Takeaway order'), findsOneWidget);
    expect(find.text('Collect'), findsOneWidget);
    expect(find.textContaining('collect it at the counter'), findsOneWidget);
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);
    expect(deps.session.isTakeaway, isTrue);
    expect(deps.session.tableNumber, OrderTables.takeaway);
    expect(find.text('Takeaway'), findsWidgets); // the session chip

    // 3. Add a dish from the menu.
    await tester.tap(find.text('Starters'));
    await settle(tester, 800);
    await tester.tap(find.bySemanticsLabel('Add Chicken 65 to cart'));
    await settle(tester, 400);
    expect(deps.cart.quantityOfItem('chicken_65'), 1);

    // 4. Cart (via the snackbar action) and summary say takeaway, never
    // "Table 00".
    await tester.tap(find.text('VIEW CART'));
    await settle(tester, 700);
    expect(find.text('Takeaway · collect at the counter'), findsOneWidget);
    await tester.tap(find.text('Proceed to Place Order'));
    await settle(tester, 700);
    expect(find.text('Collect at the counter'), findsOneWidget);
    expect(find.text('Serving to table'), findsNothing);
    expect(find.text('00'), findsNothing);

    // 5. Place it: the order is a takeaway order with its own bill.
    final total = deps.cart.bill.total;
    await tester.tap(find.textContaining('Place Order ·'));
    await tester.pump();
    await settle(tester, 400);
    await settle(tester, 1200);
    expect(find.text('Order Placed\nSuccessfully!'), findsOneWidget);
    expect(find.text('At the counter'), findsOneWidget);
    final order = deps.orders.orders.first;
    expect(order.isTakeaway, isTrue);
    expect(order.bill.total, total);
    expect(deps.billing.forOrder(order.id)!.isTakeaway, isTrue);

    // 6. Tracking reads "Ready for Pickup" and "Collected".
    await settle(tester, 800);
    await tester.tap(find.text('Track Order'));
    await settle(tester, 700);
    expect(find.text('Ready for Pickup'), findsOneWidget);
    expect(find.text('Ready to Serve'), findsNothing);
    for (var i = 0; i < 3; i++) {
      final advance = find.textContaining('Mark as');
      await tester.scrollUntilVisible(
        advance,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(advance);
      await settle(tester, 800);
    }
    expect(deps.orders.byId(order.id)!.status, OrderStatus.readyToServe);
    expect(find.text('Ready to collect!'), findsOneWidget);
    final advance = find.textContaining('Mark as');
    await tester.scrollUntilVisible(
      advance,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(advance);
    await settle(tester, 800);
    expect(deps.orders.byId(order.id)!.status, OrderStatus.served);
    expect(find.text('Collected'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('takeaway is not offered while the restaurant is closed to it', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final store = MemoryStore();
    await store.write(
      StorageKeys.settings,
      jsonEncode(
        LocalSettingsRepository.defaults
            .copyWith(takeawayOrdersEnabled: false)
            .toJson(),
      ),
    );
    final deps = await createDependencies(store: store);
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await passSplash(tester);

    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(_orderTakeaway, findsNothing);

    // The counter's printed code says so instead of opening the menu.
    await tester.tap(find.text('Use a demo QR code'));
    await settle(tester, 500);
    await tester.tap(find.text('Takeaway order'));
    await settle(tester, 400);
    expect(find.text(TableQrError.takeawayUnavailable.message), findsOneWidget);
    expect(deps.session.tableNumber, isNull);
    await settle(tester, 4500); // the error hides itself
  });
}
