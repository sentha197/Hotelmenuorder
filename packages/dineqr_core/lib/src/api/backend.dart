import 'package:http/http.dart' as http;

import '../models/billing.dart';
import '../repositories/billing_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/menu_repository.dart';
import '../repositories/order_repository.dart';
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

/// Describes the server's payment provider to the billing screens. In
/// backend mode payments run through [BillingBackend], never through this
/// object's methods.
class ServerPaymentGateway implements PaymentGateway {
  const ServerPaymentGateway({
    required this.providerName,
    required this.available,
    required this.isSimulated,
  });

  @override
  final String providerName;
  final bool available;

  @override
  final bool isSimulated;

  @override
  Set<PaymentMethodType> get supportedMethods =>
      available ? PaymentMethodType.online.toSet() : const {};

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
      menu: HttpMenuRepository(api, staff: true),
      settings: HttpSettingsRepository(api, staff: true),
      orders: HttpOrderRepository(api, staff: true),
      billing: HttpBillingRepository(api, staff: true),
      billingBackend: HttpBillingBackend(api),
      realtime: RealtimeClient(config, token: auth.accessToken),
      auth: auth,
      staff: HttpStaffRepository(api),
      inventory: HttpInventoryRepository(api),
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

  /// The server's payment provider, or "unavailable" when it cannot be
  /// reached (counter payments still work).
  Future<PaymentGateway> paymentGateway() async {
    try {
      final json = (await api.get('/payments/config'))! as Map<String, dynamic>;
      return ServerPaymentGateway(
        providerName: json['provider'] as String? ?? 'Server',
        available: json['available'] as bool? ?? false,
        isSimulated: json['simulated'] as bool? ?? false,
      );
    } on ApiException {
      return const UnavailablePaymentGateway();
    }
  }
}
