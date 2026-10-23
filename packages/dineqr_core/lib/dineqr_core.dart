/// Shared DineQR business layer: typed models, money and time rules, QR
/// parsing, repositories (demo and backend seams), services and the
/// ChangeNotifier controllers used by both the customer and admin apps.
///
/// UI code, navigation and platform configuration stay in the apps.
library;

export 'src/api/api_auth.dart';
export 'src/api/api_client.dart';
export 'src/api/api_repositories.dart';
export 'src/api/backend.dart';
export 'src/api/realtime.dart';
export 'src/demo/assets.dart';
export 'src/demo/demo_menu_data.dart';
export 'src/demo/demo_seed.dart';
export 'src/demo/image_credits.dart';
export 'src/models/billing.dart';
export 'src/models/cart_item.dart';
export 'src/models/discount_offer.dart';
export 'src/models/inventory.dart';
export 'src/models/menu_filter.dart';
export 'src/models/menu_item.dart';
export 'src/models/order_feedback.dart';
export 'src/models/order_status.dart';
export 'src/models/order_type.dart';
export 'src/models/pricing.dart';
export 'src/models/restaurant_order.dart';
export 'src/models/restaurant_settings.dart';
export 'src/models/staff.dart';
export 'src/qr/table_qr_parser.dart';
export 'src/repositories/billing_repository.dart';
export 'src/repositories/inventory_repository.dart';
export 'src/repositories/menu_repository.dart';
export 'src/repositories/order_repository.dart';
export 'src/repositories/settings_repository.dart';
export 'src/repositories/staff_repository.dart';
export 'src/runtime/dineqr_services.dart';
export 'src/services/auth_service.dart';
export 'src/services/payment_gateway.dart';
export 'src/services/payment_ledger.dart';
export 'src/services/report_csv.dart';
export 'src/services/report_service.dart';
export 'src/services/thermal_printer.dart';
export 'src/state/access.dart';
export 'src/state/billing_controller.dart';
export 'src/state/cart_controller.dart';
export 'src/state/catalog_controller.dart';
export 'src/state/order_controller.dart';
export 'src/state/settings_controller.dart';
export 'src/storage/key_value_store.dart';
export 'src/utils/currency.dart';
export 'src/utils/formatters.dart';
export 'src/utils/restaurant_time.dart';
