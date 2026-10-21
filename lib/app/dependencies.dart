import '../data/demo/demo_seed.dart';
import '../data/models/order_status.dart';
import '../data/models/staff.dart';
import '../data/repositories/billing_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/menu_repository.dart';
import '../data/repositories/order_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/staff_repository.dart';
import '../data/services/auth_service.dart';
import '../data/services/payment_gateway.dart';
import '../data/services/thermal_printer.dart';
import '../data/storage/key_value_store.dart';
import '../state/admin_session_controller.dart';
import '../state/billing_controller.dart';
import '../state/cart_controller.dart';
import '../state/catalog_controller.dart';
import '../state/inventory_controller.dart';
import '../state/order_controller.dart';
import '../state/session_controller.dart';
import '../state/settings_controller.dart';
import '../state/shell_controller.dart';
import '../state/staff_controller.dart';

/// Runtime switches for the app.
class AppConfig {
  const AppConfig({this.enableCamera = true, this.demoMode = true});

  /// When false the QR screen always uses demo mode (used by tests).
  final bool enableCamera;

  /// Offline demo: sample data, the payment simulator, demo staff accounts
  /// and the guest-side kitchen simulator. Production builds set this to
  /// false and provide real services.
  final bool demoMode;
}

/// Creates and wires the app's state objects.
class AppDependencies {
  AppDependencies._({
    required this.config,
    required this.session,
    required this.catalog,
    required this.cart,
    required this.orders,
    required this.shell,
    required this.settings,
    required this.billing,
    required this.admin,
    required this.staff,
    required this.inventory,
    required this.audit,
    required this.printer,
  });

  static Future<AppDependencies> create({
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
    final storage = store ?? await _openStorage();
    final now = (clock ?? DateTime.now)();
    final demo = config.demoMode;
    // Sample orders and bills only on a fresh install, so an existing
    // history is never mixed with invented records.
    final fresh = storage.read(StorageKeys.orders) == null;
    final seedData = (seedDemoData ?? demo) && fresh;
    final seed = seedData ? DemoSeed.generate(now) : DemoSeed.empty;

    final staff =
        staffRepository ??
        LocalStaffRepository(
          storage,
          seed: () => demo ? DemoCredentials.seedAccounts(now) : [],
        );
    final audit = AuditLog(staff, clock: clock);
    final admin = AdminSessionController(
      authService ??
          (demo
              ? DemoAuthService(staff, storage, clock: clock)
              : const UnavailableAuthService()),
      audit,
      clock: clock,
    );

    final settings = SettingsController(
      settingsRepository ?? LocalSettingsRepository(storage),
      admin,
      audit,
    );
    await settings.load();

    final catalog = CatalogController(
      menuRepository ??
          DemoMenuRepository(latency: menuLatency, store: storage),
      storage,
      guard: admin,
      audit: audit,
      showSoldOut: () => settings.settings.showSoldOutDishes,
    );
    settings.addListener(catalog.refreshVisibility);

    final cart = CartController(
      storage,
      pricingSource: () => settings.pricing,
      offerLookup: (code) => settings.settings.offerByCode(code),
    );
    settings.addListener(cart.pricingChanged);

    final billing = BillingController(
      billingRepository ?? LocalBillingRepository(storage, seed: seed.invoices),
      paymentGateway ??
          (demo
              ? SimulatedPaymentGateway(processingTime: paymentTime)
              : const UnavailablePaymentGateway()),
      guard: admin,
      audit: audit,
      settings: () => settings.settings,
      clock: clock,
    );

    final orders = OrderController(
      orderRepository ??
          LocalOrderRepository(
            storage,
            clock: clock,
            latency: orderLatency,
            seedDemoOrders: seedData,
            seed: seed.orders,
          ),
      guard: admin,
      audit: audit,
      isTableOrderable: settings.isOrderable,
      prepBuffer: () => settings.settings.prepBufferMinutes,
      onPlaced: (order) => billing.createForOrder(order),
      onCancelled: billing.voidForOrder,
    );

    final staffController = StaffController(
      staff,
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
      catalog,
      autoUnavailable: () => settings.settings.autoUnavailableWhenOutOfStock,
      clock: clock,
    );

    // Restore the saved cart once the menu is available, and keep it in
    // step with menu edits (new prices, sold-out or removed dishes).
    catalog.addListener(() {
      if (catalog.state != LoadState.ready) return;
      cart
        ..hydrate(catalog.allItems)
        ..syncWithMenu(catalog.allItems);
    });

    await orders.load();
    await billing.load();
    await _ensureBills(orders, billing);
    await admin.restore();
    await staffController.load();
    await inventory.load();
    catalog.load();

    final deps = AppDependencies._(
      config: config,
      session: SessionController(storage),
      catalog: catalog,
      cart: cart,
      orders: orders,
      shell: ShellController(),
      settings: settings,
      billing: billing,
      admin: admin,
      staff: staffController,
      inventory: inventory,
      audit: audit,
      printer: printer,
    );
    return deps.._demoData = DemoData._(deps, storage, clock ?? DateTime.now);
  }

  /// Every order has a bill (orders from before billing existed get one).
  static Future<void> _ensureBills(
    OrderController orders,
    BillingController billing,
  ) async {
    for (final order in orders.orders.reversed) {
      if (billing.forOrder(order.id) != null) continue;
      await billing.createForOrder(order);
      if (order.status == OrderStatus.cancelled) {
        await billing.voidForOrder(order);
      }
    }
  }

  static Future<KeyValueStore> _openStorage() async {
    try {
      return await SharedPrefsStore.create();
    } on Object {
      // Fall back to memory so the demo still runs without device storage.
      return MemoryStore();
    }
  }

  final AppConfig config;
  final SessionController session;
  final CatalogController catalog;
  final CartController cart;
  final OrderController orders;
  final ShellController shell;
  final SettingsController settings;
  final BillingController billing;
  final AdminSessionController admin;
  final StaffController staff;
  final InventoryController inventory;
  final AuditLog audit;
  final ThermalPrinter printer;
  DemoData? _demoData;

  /// Demo reset helpers (only meaningful in demo mode).
  DemoData get demoData => _demoData!;
}

/// Resets demo data. Orders and bills are regenerated from one seed so they
/// always match.
class DemoData {
  DemoData._(this._deps, this._store, this._clock);

  final AppDependencies _deps;
  final KeyValueStore _store;
  final DateTime Function() _clock;

  bool get isAvailable => _deps.config.demoMode;

  /// Guest reset: cart, favourites, orders and bills.
  Future<void> resetGuestData() async {
    _requireDemo();
    _deps.cart.clear();
    await _deps.catalog.clearFavorites();
    final seed = DemoSeed.generate(_clock());
    await _deps.billing.resetDemo(seed.invoices);
    await _deps.orders.resetDemo(orders: seed.orders);
  }

  /// Owner reset: everything, including menu, settings, staff and stock.
  Future<void> resetEverything() async {
    _requireDemo();
    _deps.admin.require(Permission.manageSettings);
    await resetGuestData();
    await _deps.catalog.resetMenu();
    await _deps.settings.reset();
    await _deps.inventory.resetDemo();
    await _deps.staff.resetDemo();
    await _store.delete(StorageKeys.table);
    await _deps.admin.signOut(reason: 'Demo data was reset. Sign in again.');
  }

  void _requireDemo() {
    if (!isAvailable) {
      throw StateError('Resetting data is only available in demo mode.');
    }
  }
}
