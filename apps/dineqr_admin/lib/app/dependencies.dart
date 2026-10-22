import 'package:dineqr_core/dineqr_core.dart';

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
  });

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
    Duration menuLatency = const Duration(milliseconds: 450),
    Duration orderLatency = const Duration(milliseconds: 900),
    Duration paymentTime = const Duration(milliseconds: 1400),
    bool? seedDemoData,
    DateTime Function()? clock,
  }) async {
    final storage = store ?? await DineQrServices.openStorage();
    final now = (clock ?? DateTime.now)();
    final demo = config.demoMode;

    final staffRepo =
        staffRepository ??
        LocalStaffRepository(
          storage,
          // Demo accounts exist only in demo mode, on a fresh install.
          seed: () => demo ? DemoCredentials.seedAccounts(now) : [],
        );
    final audit = AuditLog(staffRepo, clock: clock);
    final admin = AdminSessionController(
      authService ??
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
      menuRepository: menuRepository,
      orderRepository: orderRepository,
      billingRepository: billingRepository,
      settingsRepository: settingsRepository,
      paymentGateway: paymentGateway,
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

    await admin.restore();
    await staff.load();
    await inventory.load();
    services.startMenu();

    return AdminDependencies._(
      config: config,
      services: services,
      admin: admin,
      staff: staff,
      inventory: inventory,
      sections: ServiceSectionController(storage),
      audit: audit,
      printer: printer,
    );
  }

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
