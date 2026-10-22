import 'package:dineqr_core/dineqr_core.dart';

import '../state/session_controller.dart';
import '../state/shell_controller.dart';

/// Runtime switches for the customer app.
class CustomerConfig {
  const CustomerConfig({this.enableCamera = true, this.demoMode = true});

  /// When false the QR screen always uses demo mode (used by tests).
  final bool enableCamera;

  /// Offline demo: sample orders, the payment simulator and the labelled
  /// kitchen simulator on the tracking screen.
  final bool demoMode;

  AppConfig get app => AppConfig(demoMode: demoMode);
}

/// Creates and wires the customer app's state. Staff sign-in, staff
/// accounts and inventory are not part of this app; privileged actions are
/// refused by [GuestAccess].
class CustomerDependencies {
  CustomerDependencies._({
    required this.config,
    required this.services,
    required this.session,
    required this.cart,
    required this.shell,
    required this.printer,
  });

  static Future<CustomerDependencies> create({
    KeyValueStore? store,
    MenuRepository? menuRepository,
    OrderRepository? orderRepository,
    BillingRepository? billingRepository,
    SettingsRepository? settingsRepository,
    PaymentGateway? paymentGateway,
    ThermalPrinter printer = const UnavailableThermalPrinter(),
    CustomerConfig config = const CustomerConfig(),
    Duration menuLatency = const Duration(milliseconds: 450),
    Duration orderLatency = const Duration(milliseconds: 900),
    Duration paymentTime = const Duration(milliseconds: 1400),
    bool? seedDemoData,
    DateTime Function()? clock,
  }) async {
    final storage = store ?? await DineQrServices.openStorage();
    final services = await DineQrServices.create(
      store: storage,
      config: config.app,
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
    final settings = services.settings;
    final catalog = services.catalog;

    final cart = CartController(
      storage,
      pricingSource: () => settings.pricing,
      offerLookup: (code) => settings.settings.offerByCode(code),
    );
    settings.addListener(cart.pricingChanged);

    // Restore the saved cart once the menu is available, and keep it in
    // step with menu changes (new prices, sold-out or removed dishes).
    catalog.addListener(() {
      if (catalog.state != LoadState.ready) return;
      cart
        ..hydrate(catalog.allItems)
        ..syncWithMenu(catalog.allItems);
    });
    services.startMenu();

    return CustomerDependencies._(
      config: config,
      services: services,
      session: SessionController(storage, clock: clock),
      cart: cart,
      shell: ShellController(),
      printer: printer,
    );
  }

  final CustomerConfig config;
  final DineQrServices services;
  final SessionController session;
  final CartController cart;
  final ShellController shell;
  final ThermalPrinter printer;

  SettingsController get settings => services.settings;
  CatalogController get catalog => services.catalog;
  OrderController get orders => services.orders;
  BillingController get billing => services.billing;

  late final DemoData demoData = DemoData._(this);
}

/// Resets the guest demo (only meaningful in demo mode).
class DemoData {
  DemoData._(this._deps);

  final CustomerDependencies _deps;

  bool get isAvailable => _deps.config.demoMode;

  /// Cart, favourites, orders and bills.
  Future<void> resetGuestData() async {
    if (!isAvailable) {
      throw StateError('Resetting data is only available in demo mode.');
    }
    _deps.cart.clear();
    await _deps.catalog.clearFavorites();
    await _deps.services.resetDemoRecords();
  }
}
