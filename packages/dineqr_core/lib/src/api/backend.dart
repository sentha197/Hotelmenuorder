import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../repositories/billing_repository.dart';
import '../repositories/geofence_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/legal_repository.dart';
import '../repositories/menu_repository.dart';
import '../repositories/network_access_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/staff_repository.dart';
import '../state/billing_controller.dart';
import '../storage/key_value_store.dart';
import 'api_auth.dart';
import 'api_client.dart';
import 'api_repositories.dart';
import 'realtime.dart';

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
    this.networkAccess,
    this.networkSettings,
    this.legal,
    this.legalAdmin,
    this.location,
    this.geofenceSettings,
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
      networkAccess: HttpNetworkAccessChecker(api),
      legal: HttpLegalRepository(api),
      location: HttpGuestLocationChecker(api),
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
      networkSettings: HttpNetworkAccessSettingsRepository(api),
      legalAdmin: HttpLegalAdminRepository(api),
      geofenceSettings: HttpGeofenceSettingsRepository(api),
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

  /// The guest's dine-in Wi-Fi check (customer app only).
  final NetworkAccessChecker? networkAccess;

  /// The dine-in Wi-Fi restriction's settings (staff app only).
  final NetworkAccessSettingsRepository? networkSettings;

  /// The published Terms & Conditions and Privacy Policy and the guest's
  /// acceptances (customer app only).
  final LegalRepository? legal;

  /// Document versions and the acceptance history (staff app only).
  final LegalAdminRepository? legalAdmin;

  /// The guest's GPS ordering-area check (customer app only).
  final GuestLocationChecker? location;

  /// The GPS ordering area's settings (staff app only).
  final GeofenceSettingsRepository? geofenceSettings;

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
