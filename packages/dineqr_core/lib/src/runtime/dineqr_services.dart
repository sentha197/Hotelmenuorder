import '../demo/demo_seed.dart';
import '../models/order_status.dart';
import '../repositories/billing_repository.dart';
import '../repositories/menu_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/payment_gateway.dart';
import '../state/access.dart';
import '../state/billing_controller.dart';
import '../state/catalog_controller.dart';
import '../state/order_controller.dart';
import '../state/settings_controller.dart';
import '../storage/key_value_store.dart';

/// Runtime switches shared by both apps.
class AppConfig {
  const AppConfig({this.demoMode = true});

  /// Offline demo: sample data, the payment simulator, demo staff accounts
  /// and the guest-side kitchen simulator, all clearly labelled. Production
  /// builds set this to false and pass real (backend) services.
  final bool demoMode;
}

/// The business services both apps run on: restaurant settings, the menu,
/// orders and bills, wired to one set of repositories with one pricing and
/// billing rule set.
///
/// Each app builds its own instance in its own process. Nothing is shared in
/// memory between the customer and admin apps:
/// - in the offline demo each app keeps its own local data on its device;
/// - with a backend, every repository talks to the same server, which is
///   what makes a guest's order appear on the staff dashboard
///   (see docs/BACKEND_INTEGRATION.md).
class DineQrServices {
  DineQrServices._({
    required this.config,
    required this.store,
    required this.settings,
    required this.catalog,
    required this.orders,
    required this.billing,
    required this._clock,
  });

  /// Wires settings, menu, orders and bills. [guard] checks every
  /// privileged action: the admin app passes its signed-in staff session,
  /// the customer app keeps [GuestAccess], which refuses them all.
  ///
  /// The menu is not loaded yet; call [startMenu] once listeners (such as a
  /// cart that restores itself from the menu) are attached.
  ///
  /// With a server ([billingBackend]) nothing is read here: creating the
  /// services never waits on the network, so an app can show its first
  /// screen at once. Each app then loads settings, orders and bills when it
  /// needs them (the customer app at start-up, the admin app after sign-in).
  /// Local (demo) data is read here, as before.
  static Future<DineQrServices> create({
    required KeyValueStore store,
    AppConfig config = const AppConfig(),
    AccessGuard guard = const GuestAccess(),
    AuditLog? audit,
    MenuRepository? menuRepository,
    OrderRepository? orderRepository,
    BillingRepository? billingRepository,
    SettingsRepository? settingsRepository,
    PaymentGateway? paymentGateway,
    BillingBackend? billingBackend,
    Duration menuLatency = const Duration(milliseconds: 450),
    Duration orderLatency = const Duration(milliseconds: 900),
    Duration paymentTime = const Duration(milliseconds: 1400),
    bool? seedDemoData,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)();
    final demo = config.demoMode;
    // Sample orders and bills only on a fresh install, so an existing
    // history is never mixed with invented records.
    final fresh = store.read(StorageKeys.orders) == null;
    final seedData = (seedDemoData ?? demo) && fresh;
    final seed = seedData ? DemoSeed.generate(now) : DemoSeed.empty;

    final settings = SettingsController(
      settingsRepository ?? LocalSettingsRepository(store),
      guard,
      audit,
    );
    final local = billingBackend == null;
    if (local) await settings.load();

    final catalog = CatalogController(
      menuRepository ?? DemoMenuRepository(latency: menuLatency, store: store),
      store,
      guard: guard,
      audit: audit,
      showSoldOut: () => settings.settings.showSoldOutDishes,
    );
    settings.addListener(catalog.refreshVisibility);

    final billing = BillingController(
      billingRepository ?? LocalBillingRepository(store, seed: seed.invoices),
      paymentGateway ??
          (demo
              ? SimulatedPaymentGateway(processingTime: paymentTime)
              : const UnavailablePaymentGateway()),
      guard: guard,
      audit: audit,
      backend: billingBackend,
      settings: () => settings.settings,
      clock: clock,
    );
    settings.addListener(billing.settingsChanged);

    final orders = OrderController(
      orderRepository ??
          LocalOrderRepository(
            store,
            clock: clock,
            latency: orderLatency,
            seedDemoOrders: seedData,
            seed: seed.orders,
          ),
      guard: guard,
      audit: audit,
      isTableOrderable: settings.isOrderable,
      prepBuffer: () => settings.settings.prepBufferMinutes,
      onPlaced: (order) => billing.createForOrder(order),
      onCancelled: billing.voidForOrder,
    );

    if (local) {
      await orders.load();
      await billing.load();
      await _ensureBills(orders, billing);
    }

    return DineQrServices._(
      config: config,
      store: store,
      settings: settings,
      catalog: catalog,
      orders: orders,
      billing: billing,
      clock: clock ?? DateTime.now,
    );
  }

  /// Device storage, falling back to memory so the demo still runs when
  /// local storage is unavailable.
  static Future<KeyValueStore> openStorage() async {
    try {
      return await SharedPrefsStore.create();
    } on Object {
      return MemoryStore();
    }
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

  final AppConfig config;
  final KeyValueStore store;
  final SettingsController settings;
  final CatalogController catalog;
  final OrderController orders;
  final BillingController billing;
  final DateTime Function() _clock;

  /// Starts loading the menu. The apps show their own loading states.
  void startMenu() => catalog.load();

  /// Demo only: replaces orders and bills with a fresh sample set generated
  /// from one seed, so the two always match.
  Future<void> resetDemoRecords() async {
    if (!config.demoMode) {
      throw StateError('Resetting data is only available in demo mode.');
    }
    final seed = DemoSeed.generate(_clock());
    await billing.resetDemo(seed.invoices);
    await orders.resetDemo(orders: seed.orders);
  }
}
