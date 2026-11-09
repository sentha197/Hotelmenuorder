import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/modules/dashboard/dashboard_screen.dart';
import 'package:dineqr_admin/modules/settings/gps_restriction_card.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// Stands in for the server: stores what is saved, like PUT /admin/geofence.
class _Server implements GeofenceSettingsRepository {
  GeofenceSettings stored = const GeofenceSettings(
    restaurantName: 'DineQR Restaurant',
  );
  final saves = <GeofenceSettings>[];

  @override
  bool get isAvailable => true;

  @override
  Future<GeofenceSettings> fetch() async => stored;

  @override
  Future<GeofenceSettings> save(GeofenceSettings settings) async {
    saves.add(settings);
    stored = GeofenceSettings(
      restaurantName: stored.restaurantName,
      configured: true,
      enabled: settings.enabled,
      latitude: settings.latitude,
      longitude: settings.longitude,
      radius: settings.radius,
      takeaway: settings.takeaway,
      createdAt: DateTime(2026, 11, 8, 10),
      updatedAt: DateTime(2026, 11, 8, 10, 5),
      updatedBy: 'Owner',
    );
    return stored;
  }
}

/// The admin's phone, standing at the restaurant.
class _Device implements LocationProvider {
  LocationReading next = LocationReading.position(
    GuestPosition(
      latitude: 13.0827,
      longitude: 80.2707,
      accuracy: 8,
      capturedAt: DateTime(2026, 11, 8),
    ),
  );

  @override
  Future<LocationReading> current() async => next;

  @override
  Future<bool> openSettings(LocationFailure failure) async => true;
}

Future<void> _open(WidgetTester tester, _Server server, _Device device) async {
  tester.view.physicalSize = const Size(400, 900) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final deps = await createAdminDependencies(
    geofenceRepository: server,
    locationProvider: device,
  );
  await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
  await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
  await settle(tester, 800);
  Provider.of<AdminShellController>(
    tester.element(find.byType(DashboardScreen)),
    listen: false,
  ).open(AdminModule.settings);
  await settle(tester);
  await Scrollable.ensureVisible(
    tester.element(find.byType(GpsRestrictionCard)),
  );
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  testWidgets('the owner sets the location and radius and switches it on', (
    tester,
  ) async {
    final server = _Server();
    final device = _Device();
    await _open(tester, server, device);

    expect(find.text('GPS Location & Ordering Restrictions'), findsOneWidget);
    expect(find.text('DineQR Restaurant'), findsOneWidget);

    // Switching on with no location yet is refused before any request.
    await _tap(tester, find.text('Enable GPS restriction'));
    await _tap(tester, find.text('Save GPS configuration'));
    await tester.tap(find.text('Switch on'));
    await settle(tester);
    expect(server.saves, isEmpty);
    expect(
      find.text(
        "Set the restaurant's location before switching the GPS restriction "
        'on.',
      ),
      findsOneWidget,
    );

    // This device's location fills in the coordinates.
    await _tap(tester, find.text("Use this device's location"));
    expect(find.text('13.082700'), findsOneWidget);
    expect(find.text('80.270700'), findsOneWidget);
    expect(find.text('Open in Google Maps'), findsOneWidget);

    await _tap(tester, find.text('30 m'));
    await _tap(tester, find.text('Save GPS configuration'));
    await tester.tap(find.text('Switch on'));
    await settle(tester);

    final saved = server.saves.single;
    expect(saved.enabled, isTrue);
    expect(saved.latitude, 13.0827);
    expect(saved.longitude, 80.2707);
    expect(saved.radius, 30);
    expect(saved.takeaway, isFalse);
    expect(find.textContaining('Last saved'), findsOneWidget);
  });

  testWidgets('a custom radius and typed coordinates are checked', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server, _Device());

    // The Wi-Fi card above has a switch with the same label.
    await _tap(
      tester,
      find.descendant(
        of: find.byType(GpsRestrictionCard),
        matching: find.text('Include takeaway orders'),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Latitude'),
      '12.9716',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Longitude'),
      '77.5946',
    );
    await _tap(tester, find.text('Custom'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Radius in metres (10 to 1000)'),
      '5000',
    );
    await _tap(tester, find.text('Save GPS configuration'));
    expect(server.saves, isEmpty);
    expect(
      find.text('Choose a radius from 10 to 1000 metres.'),
      findsOneWidget,
    );
    // Let the message close before tapping what it covered.
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Radius in metres (10 to 1000)'),
      '75',
    );
    await _tap(tester, find.text('Save GPS configuration'));
    final saved = server.saves.single;
    expect(saved.enabled, isFalse);
    expect(saved.radius, 75);
    expect(saved.takeaway, isTrue);
    expect(saved.latitude, 12.9716);
  });

  testWidgets('a refused location permission says what to do', (tester) async {
    final device = _Device()
      ..next = const LocationReading.failed(LocationFailure.permissionDenied);
    await _open(tester, _Server(), device);
    await _tap(tester, find.text("Use this device's location"));
    expect(
      find.textContaining("Allow DineQR Admin to use this device's location"),
      findsOneWidget,
    );
  });
}
