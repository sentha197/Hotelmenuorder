import 'package:menu_order/data/demo/demo_menu_data.dart';
import 'package:menu_order/data/models/menu_item.dart';
import 'package:menu_order/data/models/restaurant_order.dart';
import 'package:menu_order/data/models/staff.dart';
import 'package:menu_order/data/repositories/order_repository.dart';
import 'package:menu_order/data/storage/key_value_store.dart';
import 'package:menu_order/state/admin_session_controller.dart';
import 'package:menu_order/state/cart_controller.dart';
import 'package:menu_order/state/order_controller.dart';

MenuItem dish(String id) => demoMenuItems.firstWhere((item) => item.id == id);

StaffAccount staffWith(StaffRole role, {String id = 'T1'}) => StaffAccount(
  id: id,
  name: 'Test ${role.label}',
  email: '${role.name}@test.local',
  role: role,
  passwordHash: '',
  salt: '',
  createdAt: DateTime.utc(2026),
);

/// Access guard for a fixed role, or signed out when [actor] is null.
class FakeGuard implements AccessGuard {
  FakeGuard([StaffRole? role]) : actor = role == null ? null : staffWith(role);

  @override
  StaffAccount? actor;

  @override
  bool can(Permission permission) => actor?.can(permission) ?? false;

  @override
  void require(Permission permission) {
    final who = actor;
    if (who == null) throw const SessionExpiredException();
    if (!who.can(permission)) throw PermissionDeniedException(permission);
  }
}

/// Places a guest order for [items] (dish id → quantity) at [table].
Future<RestaurantOrder> placeTestOrder(
  OrderController orders,
  Map<String, int> items, {
  int table = 5,
}) {
  final cart = CartController(MemoryStore());
  for (final MapEntry(:key, :value) in items.entries) {
    cart.add(dish(key), quantity: value);
  }
  return orders.placeOrder(cart: cart, tableNumber: table);
}

Future<OrderController> testOrders(
  MemoryStore store, {
  AccessGuard? guard,
  AuditLog? audit,
}) async {
  final orders = OrderController(
    LocalOrderRepository(store, latency: Duration.zero, seedDemoOrders: false),
    guard: guard,
    audit: audit,
  );
  await orders.load();
  return orders;
}
