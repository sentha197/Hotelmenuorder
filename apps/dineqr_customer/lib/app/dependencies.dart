import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

import '../state/session_controller.dart';
import '../state/shell_controller.dart';

/// Runtime switches for the customer app.
class CustomerConfig {
  const CustomerConfig({
    this.enableCamera = true,
    this.demoMode = true,
    this.api,
  });

  /// From the build:
  /// - `--dart-define=DINEQR_API_URL=<url>` runs against the DineQR API;
  /// - `--dart-define=DINEQR_MODE=demo` runs the offline demo explicitly.
  /// Without either, a debug build uses the local development API
  /// ([ApiConfig.localDevelopmentUrl]) and a profile or release build the
  /// deployed API ([ApiConfig.productionUrl]). An address that cannot work
  /// leaves [isConfigured] false, and the app says so instead of showing any
  /// invented data.
  factory CustomerConfig.fromEnvironment() {
    const mode = String.fromEnvironment('DINEQR_MODE');
    if (mode == 'demo') return const CustomerConfig();
    return CustomerConfig(demoMode: false, api: ApiConfig.fromEnvironment());
  }

  /// When false the QR screen always uses demo mode (used by tests).
  final bool enableCamera;

  /// Offline demo: sample orders, the payment simulator and the labelled
  /// kitchen simulator on the tracking screen. Off in production builds.
  final bool demoMode;

  /// The DineQR API (backend mode).
  final ApiConfig? api;

  bool get isConfigured => demoMode || api != null;

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
    this.backend,
    this.liveUpdates,
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
    final api = config.demoMode ? null : config.api;
    final backend = api == null ? null : DineQrBackend.guest(api, storage);
    // Nothing here waits on the server, so the splash shows at once. The
    // splash waits only for [prepare]; the rest loads in the background.
    final services = await DineQrServices.create(
      store: storage,
      config: config.app,
      menuRepository: menuRepository ?? backend?.menu,
      orderRepository: orderRepository ?? backend?.orders,
      billingRepository: billingRepository ?? backend?.billing,
      settingsRepository: settingsRepository ?? backend?.settings,
      paymentGateway: paymentGateway ?? backend?.payments,
      billingBackend: backend?.billingBackend,
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

    // Live updates: staff status changes, menu, settings and table changes
    // reach the guest without a restart; data is re-read from the API.
    LiveUpdates? live;
    final guest = backend?.guestSession;
    if (backend != null) {
      // Orders and bills belong to a guest session; without one the server
      // can only refuse them, so polling skips them.
      Future<void> Function() inSession(Future<void> Function() load) =>
          () => guest!.isActive ? load() : Future<void>.value();
      live = LiveUpdates(
        backend.realtime,
        handlers: {
          'orders': inSession(services.orders.load),
          'bills': inSession(services.billing.load),
          'menu': services.catalog.refresh,
          'settings': services.settings.load,
          'tables': services.settings.load,
        },
      );
      if (paymentGateway == null) unawaited(backend.loadPaymentConfig());
      if (guest!.isActive) {
        // A session from an earlier start: its own orders and bills.
        unawaited(backend.realtime.start());
        unawaited(_loadGuestRecords(services));
      }
    }

    final dependencies = CustomerDependencies._(
      config: config,
      services: services,
      session: SessionController(
        storage,
        clock: clock,
        // With the API, a table session is a server guest session: the
        // server checks the table (or that takeaway is open) and scopes the
        // guest's orders and bills.
        hasServerSession: guest == null ? null : () => guest.isActive,
        onStart: backend == null
            ? null
            : (table) async {
                await guest!.start(TableQrParser.payloadFor(table));
                unawaited(backend.realtime.start());
                await _loadGuestRecords(services);
              },
      ),
      cart: cart,
      shell: ShellController(),
      printer: printer,
      backend: backend,
      liveUpdates: live,
    );
    // Started now, so it is under way while the splash plays.
    dependencies.prepare().ignore();
    return dependencies;
  }

  /// The guest session's orders and bills, side by side. A failure leaves
  /// the lists as they are (screens show their empty states, and live
  /// updates load them again).
  static Future<void> _loadGuestRecords(DineQrServices services) async {
    try {
      await Future.wait([services.orders.load(), services.billing.load()]);
    } on Object catch (error) {
      debugPrint('Loading the guest\'s orders failed: $error');
    }
  }

  Future<void>? _prepared;

  /// What the splash waits for before it moves on: the restaurant's
  /// settings and tables, which the scanner checks codes against (including
  /// whether takeaway is open) and which decide whether a table can be
  /// resumed. The menu, payment options and the guest's orders load in the
  /// background. Local (demo) data is already loaded.
  ///
  /// Throws [ApiException] when the server cannot be reached; calling it
  /// again retries.
  Future<void> prepare() => _prepared ??= () async {
    if (backend == null) return;
    try {
      await services.settings.load();
    } on Object {
      _prepared = null;
      rethrow;
    }
  }();

  final CustomerConfig config;
  final DineQrServices services;
  final SessionController session;
  final CartController cart;
  final ShellController shell;
  final ThermalPrinter printer;

  /// The API connection (null in the offline demo).
  final DineQrBackend? backend;
  final LiveUpdates? liveUpdates;

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
