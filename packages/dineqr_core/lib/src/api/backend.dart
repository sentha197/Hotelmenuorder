import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/billing.dart';
import '../repositories/billing_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/menu_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/payment_settings_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/staff_repository.dart';
import '../services/payment_gateway.dart';
import '../state/billing_controller.dart';
import '../storage/key_value_store.dart';
import '../utils/currency.dart';
import 'api_auth.dart';
import 'api_client.dart';
import 'api_repositories.dart';
import 'realtime.dart';

/// Describes the server's live payment gateway to the billing screens:
/// whether one is configured (so live mode can be chosen) and its name. In
/// backend mode payments run through [BillingBackend], never through this
/// object's methods; demo-mode payments go to the server's simulator, which
/// needs nothing from here.
///
/// It starts as "not available" and is filled in from `/payments/config` in
/// the background ([DineQrBackend.loadPaymentConfig]), so starting an app
/// never waits for it. Listeners (the billing controller) hear when it
/// changes.
class ServerPaymentGateway extends ChangeNotifier implements PaymentGateway {
  ServerPaymentGateway();

  String _providerName = 'Server';
  bool _available = false;
  bool _isSimulated = false;
  bool _loaded = false;

  @override
  String get providerName => _providerName;

  bool get available => _available;

  @override
  bool get isSimulated => _isSimulated;

  /// Whether the server's configuration has been read.
  bool get isLoaded => _loaded;

  void update({
    required String providerName,
    required bool available,
    required bool isSimulated,
  }) {
    _providerName = providerName;
    _available = available;
    _isSimulated = isSimulated;
    _loaded = true;
    notifyListeners();
  }

  @override
  Set<PaymentMethodType> get supportedMethods =>
      _available ? PaymentMethodType.online.toSet() : const {};

  static Never _serverOnly() =>
      throw StateError('Payments are processed by the server.');

  @override
  Future<PaymentResult> collect(
    PaymentRequest request, {
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) => _serverOnly();

  @override
  Future<PaymentResult> checkStatus(PaymentTransaction pending) =>
      _serverOnly();

  @override
  Future<PaymentResult> refund(
    PaymentTransaction payment,
    Money amount, {
    required String reason,
    required String idempotencyKey,
  }) => _serverOnly();
}

/// Everything one app needs to run against the DineQR API: an [ApiClient]
/// with the right credentials, the HTTP repositories, the server-side
/// billing operations and the live-update connection.
class DineQrBackend {
  DineQrBackend._({
    required this.config,
    required this.api,
    required this.menu,
    required this.settings,
    required this.orders,
    required this.billing,
    required this.billingBackend,
    required this.realtime,
    this.guestSession,
    this.auth,
    this.staff,
    this.inventory,
    this.paymentSettings,
  });

  /// The customer app: a table-scoped guest session from the scanned QR.
  factory DineQrBackend.guest(
    ApiConfig config,
    KeyValueStore store, {
    http.Client? client,
  }) {
    final api = ApiClient(config, client: client);
    final session = GuestSession(api, store);
    return DineQrBackend._(
      config: config,
      api: api,
      menu: HttpMenuRepository(api, staff: false),
      settings: HttpSettingsRepository(api, staff: false),
      orders: HttpOrderRepository(api, staff: false),
      billing: HttpBillingRepository(api, staff: false),
      billingBackend: HttpBillingBackend(api),
      realtime: RealtimeClient(config, token: session.token),
      guestSession: session,
    );
  }

  /// The admin app: staff sign-in with short-lived access tokens.
  factory DineQrBackend.staff(
    ApiConfig config,
    TokenStorage tokens, {
    http.Client? client,
  }) {
    final api = ApiClient(config, client: client);
    final auth = HttpAuthService(
      config,
      tokens,
      plain: ApiClient(config, client: client),
    )..attach(api);
    return DineQrBackend._(
      config: config,
      api: api,
      menu: HttpMenuRepository(
        api,
        staff: true,
        signedIn: () => auth.hasSession,
      ),
      settings: HttpSettingsRepository(
        api,
        staff: true,
        signedIn: () => auth.hasSession,
      ),
      orders: HttpOrderRepository(api, staff: true),
      billing: HttpBillingRepository(api, staff: true),
      billingBackend: HttpBillingBackend(api),
      realtime: RealtimeClient(config, token: auth.accessToken),
      auth: auth,
      staff: HttpStaffRepository(api),
      inventory: HttpInventoryRepository(api),
      paymentSettings: HttpPaymentSettingsRepository(api),
    );
  }

  final ApiConfig config;
  final ApiClient api;
  final MenuRepository menu;
  final SettingsRepository settings;
  final OrderRepository orders;
  final BillingRepository billing;
  final BillingBackend billingBackend;
  final RealtimeClient realtime;
  final GuestSession? guestSession;
  final HttpAuthService? auth;
  final StaffRepository? staff;
  final InventoryRepository? inventory;

  /// The restaurant's UPI payment settings (staff app only).
  final PaymentSettingsRepository? paymentSettings;

  /// The server's live payment gateway. "Not available" until
  /// [loadPaymentConfig] has read it, and if the server cannot be reached
  /// (demo and counter payments still work).
  final ServerPaymentGateway payments = ServerPaymentGateway();

  Future<void>? _paymentConfig;

  /// Reads the live gateway into [payments]. Concurrent calls share one
  /// request; a failed read leaves it "not available" and can be retried.
  Future<void> loadPaymentConfig() => _paymentConfig ??= () async {
    try {
      final json = (await api.get('/payments/config'))! as Map<String, dynamic>;
      // Servers from before payment modes describe only the provider in
      // use, which is live only when it is not their simulator.
      final live =
          json['liveAvailable'] as bool? ??
          ((json['available'] as bool? ?? false) && json['simulated'] != true);
      payments.update(
        providerName:
            json['liveProvider'] as String? ??
            json['provider'] as String? ??
            'Server',
        available: live,
        isSimulated: false,
      );
    } on ApiException catch (error) {
      debugPrint('Payment configuration not loaded: ${error.code}');
    } finally {
      _paymentConfig = null;
    }
  }();

  /// [payments] once its configuration has been read (or could not be).
  Future<PaymentGateway> paymentGateway() async {
    await loadPaymentConfig();
    return payments;
  }

  /// Wakes a server that went idle, and its database, without keeping the
  /// answer: a hosted server stops when unused and its first request is
  /// slow, so starting it while the splash plays (and the staff member signs
  /// in) saves them that wait. Nothing waits for it or uses it.
  Future<void> warmUp() async {
    try {
      await api.get('/settings');
    } on ApiException catch (error) {
      debugPrint('Warm-up request failed: ${error.code}');
    }
  }
}
