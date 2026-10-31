import 'dart:async';
import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/features/network/dine_in_lock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show scanDemoTable, settle, usePhoneScreen;

/// The server's answers to the guest's network check.
class _Server implements NetworkAccessChecker {
  NetworkAccessResult answer = NetworkAccessResult.allowed;

  @override
  Future<NetworkAccessResult> check() async => answer;
}

const _message =
    "Please connect to the restaurant's Wi-Fi to access the DineQR menu and "
    'place your order.';

void main() {
  testWidgets('dine-in locks off the restaurant Wi-Fi and opens again on it', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final server = _Server();
    final network = StreamController<bool>();
    addTearDown(network.close);
    // The restaurant switched the restriction on.
    final store = MemoryStore();
    await store.write(
      StorageKeys.settings,
      jsonEncode(
        const RestaurantSettings(
          takeawayOrdersEnabled: true,
          wifi: DineInWifi(enabled: true, ssid: 'DineQR Guest'),
        ).toJson(),
      ),
    );
    final deps = await CustomerDependencies.create(
      store: store,
      config: const CustomerConfig(enableCamera: false),
      menuLatency: Duration.zero,
      orderLatency: const Duration(milliseconds: 300),
      paymentTime: const Duration(milliseconds: 300),
      seedDemoData: false,
      networkAccessChecker: server,
      connectivity: network.stream,
      accessPollEvery: null,
    );
    await tester.pumpWidget(DineQrApp(dependencies: deps));

    // 1. On the restaurant Wi-Fi: the guest orders as usual.
    await scanDemoTable(tester, 'Table 12');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);
    expect(find.text('Popular Dishes'), findsOneWidget);
    expect(find.byType(DineInLockPanel), findsNothing);
    expect(deps.access.isLocked, isFalse);

    // 2. The phone switches to mobile data: the server sees another network.
    server.answer = NetworkAccessResult.blocked;
    network.add(true);
    await settle(tester);
    expect(find.text(_message), findsOneWidget);
    expect(find.text('Wi-Fi: DineQR Guest'), findsOneWidget);
    // The menu, cart and checkout underneath cannot be used.
    await tester.tap(find.text('Popular Dishes'), warnIfMissed: false);
    expect(deps.cart.isEmpty, isTrue);

    // 3. No connection at all.
    network.add(false);
    await settle(tester);
    expect(
      find.text('Your phone is not connected to any network.'),
      findsOneWidget,
    );

    // 4. Back on the restaurant Wi-Fi: verified, and open again.
    server.answer = NetworkAccessResult.allowed;
    network.add(true);
    await settle(tester);
    expect(find.byType(DineInLockPanel), findsNothing);
    expect(find.text('Popular Dishes'), findsOneWidget);

    // 5. A failed order elsewhere locks it too; "Try again" asks again.
    deps.access.reportBlocked();
    await settle(tester);
    expect(find.text(_message), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.byType(DineInLockPanel), findsNothing);
  });

  testWidgets('takeaway stays open when the restaurant left it out', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final server = _Server()..answer = NetworkAccessResult.blocked;
    final store = MemoryStore();
    await store.write(
      StorageKeys.settings,
      jsonEncode(
        const RestaurantSettings(
          takeawayOrdersEnabled: true,
          wifi: DineInWifi(enabled: true, ssid: 'DineQR Guest'),
        ).toJson(),
      ),
    );
    final deps = await CustomerDependencies.create(
      store: store,
      config: const CustomerConfig(enableCamera: false),
      menuLatency: Duration.zero,
      seedDemoData: false,
      networkAccessChecker: server,
      accessPollEvery: null,
    );
    await tester.pumpWidget(DineQrApp(dependencies: deps));

    await scanDemoTable(tester, 'Takeaway order');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);

    expect(deps.session.isTakeaway, isTrue);
    expect(deps.access.isLocked, isFalse);
    expect(find.byType(DineInLockPanel), findsNothing);
  });
}
