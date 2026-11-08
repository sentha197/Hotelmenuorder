import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
import 'package:dineqr_customer/features/network/location_lock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show scanDemoTable, settle, usePhoneScreen;

GuestPosition _at(double metres) => GuestPosition(
  latitude: 13.0827 + metres / 111195,
  longitude: 80.2707,
  accuracy: 5,
  capturedAt: DateTime.now(),
);

/// The phone's GPS: what it reports next.
class _Device implements LocationProvider {
  LocationReading next = LocationReading.position(_at(5));
  final opened = <LocationFailure>[];

  @override
  Future<LocationReading> current() async => next;

  @override
  Future<bool> openSettings(LocationFailure failure) async {
    opened.add(failure);
    return true;
  }
}

/// The server: inside within 20 m, like the API's measurement.
class _Server implements GuestLocationChecker {
  final seen = <GuestPosition?>[];

  @override
  Future<LocationCheckResult> check(GuestPosition? position) async {
    seen.add(position);
    if (position == null) {
      return const LocationCheckResult(
        required: true,
        allowed: false,
        code: 'locationRequired',
      );
    }
    return (position.latitude - 13.0827) * 111195 <= 20
        ? const LocationCheckResult(required: true, allowed: true)
        : const LocationCheckResult(
            required: true,
            allowed: false,
            code: DineInLocation.outsideCode,
            message: DineInLocation.outsideMessage,
          );
  }
}

void main() {
  testWidgets('ordering locks outside the area, or without location, and '
      'opens again inside', (tester) async {
    usePhoneScreen(tester);
    final device = _Device();
    final server = _Server();
    // The restaurant switched the 20 m area on.
    final store = MemoryStore();
    await store.write(
      StorageKeys.settings,
      jsonEncode(
        const RestaurantSettings(
          location: DineInLocation(enabled: true, radius: 20),
        ).toJson(),
      ),
    );
    final deps = await CustomerDependencies.create(
      store: store,
      config: const CustomerConfig(enableCamera: false),
      menuLatency: Duration.zero,
      orderLatency: const Duration(milliseconds: 300),
      seedDemoData: false,
      locationChecker: server,
      locationProvider: device,
    );
    await tester.pumpWidget(DineQrApp(dependencies: deps));

    // 1. Inside: the guest orders as usual.
    await scanDemoTable(tester, 'Table 12');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);
    expect(find.text('Popular Dishes'), findsOneWidget);
    expect(find.byType(LocationLockPanel), findsNothing);
    expect(server.seen, isNotEmpty);

    // 2. The guest walks away; the app resumes and checks again.
    device.next = LocationReading.position(_at(80));
    await deps.locationAccess.verify();
    await settle(tester);
    expect(find.text('You are too far from the restaurant'), findsOneWidget);
    expect(find.text(DineInLocation.outsideMessage), findsOneWidget);
    expect(find.text('Ordering within 20 m of the restaurant'), findsOneWidget);
    // Nothing underneath can be used.
    await tester.tap(find.text('Popular Dishes'), warnIfMissed: false);
    expect(deps.cart.isEmpty, isTrue);

    // 3. Location permission refused.
    device.next = const LocationReading.failed(
      LocationFailure.permissionDenied,
    );
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Allow location to order'), findsOneWidget);
    expect(find.text('Allow location'), findsOneWidget);

    // 4. GPS switched off on the phone: the button opens its settings.
    device.next = const LocationReading.failed(LocationFailure.serviceDisabled);
    await tester.tap(find.text('Allow location'));
    await settle(tester);
    expect(find.text('Turn on location'), findsOneWidget);
    await tester.tap(find.text('Open location settings'));
    await settle(tester);
    expect(device.opened, [LocationFailure.serviceDisabled]);

    // 5. Back at the restaurant with GPS on: ordering opens again.
    device.next = LocationReading.position(_at(3));
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.byType(LocationLockPanel), findsNothing);
    expect(deps.access.isLocked, isFalse, reason: 'Wi-Fi lock untouched');

    // 6. Checkout measures again right before the order.
    deps.cart.quickAdd(deps.catalog.allItems.first);
    deps.navigatorKey.currentState!.pushNamed(Routes.summary);
    await settle(tester, 800);
    final before = server.seen.length;
    device.next = LocationReading.position(_at(70));
    await tester.tap(find.textContaining('Place Order ·'));
    await settle(tester);
    expect(server.seen.length, before + 1);
    expect(deps.orders.orders, isEmpty);
    expect(find.text(DineInLocation.outsideMessage), findsWidgets);
  });

  testWidgets('nothing is asked while the area is off', (tester) async {
    usePhoneScreen(tester);
    final device = _Device()
      ..next = const LocationReading.failed(LocationFailure.permissionDenied);
    final server = _Server();
    final deps = await CustomerDependencies.create(
      store: MemoryStore(),
      config: const CustomerConfig(enableCamera: false),
      menuLatency: Duration.zero,
      seedDemoData: false,
      locationChecker: server,
      locationProvider: device,
    );
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await scanDemoTable(tester, 'Table 12');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);
    expect(find.byType(LocationLockPanel), findsNothing);
    expect(server.seen, isEmpty);
  });
}
