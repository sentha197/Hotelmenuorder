import 'package:dineqr_admin/app/dependencies.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Admin dependencies on in-memory storage with no artificial latency.
Future<AdminDependencies> createAdminDependencies({
  MemoryStore? store,
  bool seedDemoData = false,
  bool demoMode = true,
  DateTime Function()? clock,
  NetworkAccessSettingsRepository? networkSettingsRepository,
  LegalAdminRepository? legalRepository,
  GeofenceSettingsRepository? geofenceRepository,
  PaymentGateway? paymentGateway,
  LocationProvider locationProvider = const GeolocatorLocationProvider(),
}) => AdminDependencies.create(
  store: store ?? MemoryStore(),
  geofenceRepository: geofenceRepository,
  locationProvider: locationProvider,
  networkSettingsRepository: networkSettingsRepository,
  legalRepository: legalRepository,
  config: AppConfig(demoMode: demoMode),
  menuLatency: Duration.zero,
  orderLatency: Duration.zero,
  paymentGateway: paymentGateway,
  seedDemoData: seedDemoData,
  clock: clock,
);

/// Phone-sized surface (iPhone 13/14 logical size).
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}
