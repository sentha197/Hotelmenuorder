import '../data/repositories/menu_repository.dart';
import '../data/repositories/order_repository.dart';
import '../data/storage/key_value_store.dart';
import '../state/cart_controller.dart';
import '../state/catalog_controller.dart';
import '../state/order_controller.dart';
import '../state/session_controller.dart';
import '../state/shell_controller.dart';

/// Runtime switches for the app.
class AppConfig {
  const AppConfig({this.enableCamera = true});

  /// When false the QR screen always uses demo mode (used by tests).
  final bool enableCamera;
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
  });

  static Future<AppDependencies> create({
    KeyValueStore? store,
    MenuRepository? menuRepository,
    OrderRepository? orderRepository,
    AppConfig config = const AppConfig(),
  }) async {
    final storage = store ?? await _openStorage();
    final catalog = CatalogController(
      menuRepository ?? const DemoMenuRepository(),
      storage,
    );
    final cart = CartController(storage);
    final orders = OrderController(
      orderRepository ?? LocalOrderRepository(storage),
    );
    // Restore the saved cart as soon as the menu is available.
    catalog.addListener(() {
      if (catalog.state == LoadState.ready) cart.hydrate(catalog.items);
    });
    await orders.load();
    catalog.load();
    return AppDependencies._(
      config: config,
      session: SessionController(storage),
      catalog: catalog,
      cart: cart,
      orders: orders,
      shell: ShellController(),
    );
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
}
