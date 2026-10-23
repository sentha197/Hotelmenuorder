import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

import '../state/admin_session_controller.dart';
import '../state/inventory_controller.dart';
import '../state/service_section_controller.dart';
import '../state/staff_controller.dart';

/// Creates and wires the admin app's state: the staff session (which is the
/// [AccessGuard] for every privileged action), staff accounts, inventory and
/// the shared business services.
class AdminDependencies {
  AdminDependencies._({
    required this.config,
    required this.services,
    required this.admin,
    required this.staff,
    required this.inventory,
    required this.sections,
    required this.audit,
    required this.printer,
    this.backend,
    this.liveUpdates,
  });

  /// Which mode the build runs in:
  /// - `--dart-define=DINEQR_API_URL=<url>`: the DineQR API (production);
  /// - `--dart-define=DINEQR_MODE=demo`: the explicit offline demo;
  /// - neither, in a debug build: the local development API.
  static const _mode = String.fromEnvironment('DINEQR_MODE');

  static bool get demoRequested => _mode == 'demo';

  static ApiConfig? get apiFromEnvironment => ApiConfig.fromEnvironment();

  static Future<AdminDependencies> create({
    KeyValueStore? store,
    MenuRepository? menuRepository,
    OrderRepository? orderRepository,
    BillingRepository? billingRepository,
    SettingsRepository? settingsRepository,
    StaffRepository? staffRepository,
    InventoryRepository? inventoryRepository,
    PaymentGateway? paymentGateway,
    AuthService? authService,
    ThermalPrinter printer = const UnavailableThermalPrinter(),
    AppConfig config = const AppConfig(),
    ApiConfig? api,
    TokenStorage? tokens,
    Duration menuLatency = const Duration(milliseconds: 450),
    Duration orderLatency = const Duration(milliseconds: 900),
    Duration paymentTime = const Duration(milliseconds: 1400),
    bool? seedDemoData,
    DateTime Function()? clock,
  }) async {
    final storage = store ?? await DineQrServices.openStorage();
    final now = (clock ?? DateTime.now)();
    final demo = config.demoMode;
    // With the API, staff stay signed in (up to the 8-hour session) through
    // a refresh token kept in secure storage.
    final backend = demo || api == null
        ? null
        : DineQrBackend.staff(api, tokens ?? MemoryTokenStorage());
    backend?.auth?.keepSignedIn = true;

    final staffRepo =
        staffRepository ??
        backend?.staff ??
        LocalStaffRepository(
          storage,
          // Demo accounts exist only in demo mode, on a fresh install.
          seed: () => demo ? DemoCredentials.seedAccounts(now) : [],
        );
    final audit = AuditLog(staffRepo, clock: clock);
    final admin = AdminSessionController(
      authService ??
          backend?.auth ??
          (demo
              ? DemoAuthService(staffRepo, storage, clock: clock)
              : const UnavailableAuthService()),
      audit,
      clock: clock,
    );

    final services = await DineQrServices.create(
      store: storage,
      config: config,
      guard: admin,
      audit: audit,
      menuRepository: menuRepository ?? backend?.menu,
      orderRepository: orderRepository ?? backend?.orders,
      billingRepository: billingRepository ?? backend?.billing,
      settingsRepository: settingsRepository ?? backend?.settings,
      paymentGateway: paymentGateway ?? await backend?.paymentGateway(),
      billingBackend: backend?.billingBackend,
      menuLatency: menuLatency,
      orderLatency: orderLatency,
      paymentTime: paymentTime,
      seedDemoData: seedDemoData,
      clock: clock,
    );

    final staff = StaffController(
      staffRepo,
      admin,
      audit,
      onAccountChanged: admin.refreshActor,
      clock: clock,
    );

    final inventory = InventoryController(
      inventoryRepository ??
          backend?.inventory ??
          LocalInventoryRepository(
            storage,
            seed: () => demo ? DemoSeed.inventory(now) : [],
          ),
      admin,
      audit,
      services.catalog,
      autoUnavailable: () =>
          services.settings.settings.autoUnavailableWhenOutOfStock,
      clock: clock,
    );

    LiveUpdates? live;
    if (backend == null) {
      await admin.restore();
      await staff.load();
      await inventory.load();
      services.startMenu();
    } else {
      // Everything is re-read whenever a staff member signs in (the server
      // decides what their role may see), and kept current while signed in.
      Future<void> reloadAll() async {
        for (final load in <Future<void> Function()>[
          services.settings.load,
          () => services.catalog.load(force: true),
          services.orders.load,
          services.billing.load,
          staff.load,
          inventory.load,
        ]) {
          try {
            await load();
          } on Object catch (error) {
            // Screens show their own error or empty states; nothing invented.
            debugPrint('Loading after sign-in failed: $error');
          }
        }
      }

      String? signedIn;
      admin.addListener(() {
        final id = admin.actor?.id;
        if (id == signedIn) return;
        signedIn = id;
        if (id == null) {
          unawaited(backend.realtime.stop());
        } else {
          unawaited(reloadAll());
          unawaited(backend.realtime.start());
        }
      });
      live = LiveUpdates(
        backend.realtime,
        handlers: {
          'orders': services.orders.load,
          'bills': services.billing.load,
          'menu': services.catalog.refresh,
          'settings': services.settings.load,
          'tables': services.settings.load,
          'inventory': inventory.load,
          'staff': staff.load,
        },
      );
      services.startMenu();
      try {
        await admin.restore();
      } on Object catch (error) {
        debugPrint('Restoring the staff session failed: $error');
      }
    }

    return AdminDependencies._(
      config: config,
      services: services,
      admin: admin,
      staff: staff,
      inventory: inventory,
      sections: ServiceSectionController(storage),
      audit: audit,
      printer: printer,
      backend: backend,
      liveUpdates: live,
    );
  }

  /// The API connection (null in the offline demo).
  final DineQrBackend? backend;
  final LiveUpdates? liveUpdates;

  final AppConfig config;
  final DineQrServices services;
  final AdminSessionController admin;
  final StaffController staff;
  final InventoryController inventory;
  final ServiceSectionController sections;
  final AuditLog audit;
  final ThermalPrinter printer;

  SettingsController get settings => services.settings;
  CatalogController get catalog => services.catalog;
  OrderController get orders => services.orders;
  BillingController get billing => services.billing;

  late final DemoData demoData = DemoData._(this);
}

/// Resets the admin demo (only meaningful in demo mode).
class DemoData {
  DemoData._(this._deps);

  final AdminDependencies _deps;

  bool get isAvailable => _deps.config.demoMode;

  /// Owner reset: menu, settings, tables, staff, stock, orders and bills.
  Future<void> resetEverything() async {
    if (!isAvailable) {
      throw StateError('Resetting data is only available in demo mode.');
    }
    _deps.admin.require(Permission.manageSettings);
    await _deps.services.resetDemoRecords();
    await _deps.catalog.clearFavorites();
    await _deps.catalog.resetMenu();
    await _deps.settings.reset();
    await _deps.inventory.resetDemo();
    await _deps.staff.resetDemo();
    await _deps.admin.signOut(reason: 'Demo data was reset. Sign in again.');
  }
}
