import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin/admin_gate.dart';
import '../core/animations/motion.dart';
import '../data/models/menu_item.dart';
import '../features/billing/bill_screen.dart';
import '../features/billing/payment_history_screen.dart';
import '../features/billing/payment_screen.dart';
import '../features/billing/receipt_preview_screen.dart';
import '../features/checkout/order_summary_screen.dart';
import '../features/dish_details/dish_details_screen.dart';
import '../features/menu/menu_list_screen.dart';
import '../features/more/credits_screen.dart';
import '../features/order_history/order_details_screen.dart';
import '../features/order_success/order_placed_screen.dart';
import '../features/order_tracking/order_tracking_screen.dart';
import '../features/qr_scanner/qr_scanner_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/splash/splash_screen.dart';
import '../features/table_confirmation/table_confirmation_screen.dart';
import '../state/billing_controller.dart';
import '../state/order_controller.dart';
import '../state/shell_controller.dart';

abstract final class Routes {
  static const splash = '/';
  static const scan = '/scan';
  static const welcome = '/welcome';
  static const home = '/home';
  static const menu = '/menu';
  static const dish = '/dish';
  static const summary = '/summary';
  static const orderPlaced = '/order-placed';
  static const tracking = '/tracking';
  static const orderDetails = '/order-details';
  static const credits = '/credits';
  static const bill = '/bill';
  static const payment = '/pay';
  static const payments = '/payments';
  static const receipt = '/receipt';

  /// Staff area. Not linked from the guest interface; reached through the
  /// separate admin entry point (`lib/main_admin.dart`) or the `/admin` URL
  /// on the web. Every privileged action is also checked by permission.
  static const admin = '/admin';
}

class ScanArgs {
  const ScanArgs({this.fromSplash = false});

  final bool fromSplash;
}

class MenuArgs {
  const MenuArgs({this.category, this.favoritesOnly = false});

  final MenuCategory? category;
  final bool favoritesOnly;
}

class DishArgs {
  const DishArgs({required this.itemId, this.heroTag});

  final String itemId;
  final String? heroTag;
}

abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;
    switch (settings.name) {
      case Routes.splash:
        return _page(settings, (_) => const SplashScreen());
      case Routes.scan:
        if (args is ScanArgs && args.fromSplash) {
          return _fade(settings, (_) => const QrScannerScreen());
        }
        return _page(settings, (_) => const QrScannerScreen());
      case Routes.welcome:
        return _page(
          settings,
          (_) => TableConfirmationScreen(tableNumber: args as int),
        );
      case Routes.home:
        return _fade(settings, (_) => const MainShell());
      case Routes.menu:
        final menu = args is MenuArgs ? args : const MenuArgs();
        return _page(
          settings,
          (_) => MenuListScreen(
            initialCategory: menu.category,
            favoritesOnly: menu.favoritesOnly,
          ),
        );
      case Routes.dish:
        final dish = args as DishArgs;
        return _page(
          settings,
          (_) => DishDetailsScreen(itemId: dish.itemId, heroTag: dish.heroTag),
        );
      case Routes.summary:
        return _page(settings, (_) => const OrderSummaryScreen());
      case Routes.orderPlaced:
        return _fade(
          settings,
          (_) => OrderPlacedScreen(orderId: args as String),
        );
      case Routes.tracking:
        return _page(
          settings,
          (_) => OrderTrackingScreen(orderId: args as String),
        );
      case Routes.orderDetails:
        return _page(
          settings,
          (_) => OrderDetailsScreen(orderId: args as String),
        );
      case Routes.credits:
        return _page(settings, (_) => const CreditsScreen());
      case Routes.bill:
        return _page(settings, (_) => BillScreen(invoiceId: args as String));
      case Routes.payment:
        return _page(settings, (_) => PaymentScreen(invoiceId: args as String));
      case Routes.payments:
        return _page(settings, (_) => const PaymentHistoryScreen());
      case Routes.receipt:
        return _page(
          settings,
          (_) => ReceiptPreviewScreen(invoiceId: args as String),
        );
      case Routes.admin:
        return _fade(settings, (_) => const AdminGate());
    }
    // Unknown routes fall back to the main shell rather than a blank page.
    return _fade(
      const RouteSettings(name: Routes.home),
      (_) => const MainShell(),
    );
  }

  /// The admin entry opens only the admin stack (no guest splash beneath).
  static List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    if (initialRoute.startsWith(Routes.admin)) {
      return [onGenerateRoute(const RouteSettings(name: Routes.admin))];
    }
    return [onGenerateRoute(const RouteSettings(name: Routes.splash))];
  }

  static Route<T> _page<T>(RouteSettings settings, WidgetBuilder builder) =>
      MaterialPageRoute<T>(settings: settings, builder: builder);

  static Route<T> _fade<T>(RouteSettings settings, WidgetBuilder builder) =>
      PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 550),
        reverseTransitionDuration: Motion.page,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (Motion.reduced(context)) return child;
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      );
}

/// Navigation shortcuts shared by every screen.
abstract final class AppNav {
  /// Returns to the main shell and shows [tab].
  static void goToTab(BuildContext context, ShellTab tab, {int? ordersTab}) =>
      goToTabWith(
        Navigator.of(context),
        context.read<ShellController>(),
        tab,
        ordersTab: ordersTab,
      );

  /// Same as [goToTab] for callbacks that may outlive their widget (snackbar
  /// actions): capture the navigator and shell first.
  static void goToTabWith(
    NavigatorState navigator,
    ShellController shell,
    ShellTab tab, {
    int? ordersTab,
  }) {
    navigator.popUntil(
      (route) => route.settings.name == Routes.home || route.isFirst,
    );
    shell.select(tab, ordersTab: ordersTab);
  }

  static Future<void> openDish(
    BuildContext context,
    MenuItem item, {
    String? heroTag,
  }) => Navigator.of(context).pushNamed(
    Routes.dish,
    arguments: DishArgs(itemId: item.id, heroTag: heroTag),
  );

  static Future<void> openMenu(
    BuildContext context, {
    MenuCategory? category,
    bool favoritesOnly = false,
  }) => Navigator.of(context).pushNamed(
    Routes.menu,
    arguments: MenuArgs(category: category, favoritesOnly: favoritesOnly),
  );

  static Future<void> openTracking(BuildContext context, String orderId) =>
      Navigator.of(context).pushNamed(Routes.tracking, arguments: orderId);

  static Future<void> openOrderDetails(BuildContext context, String orderId) =>
      Navigator.of(context).pushNamed(Routes.orderDetails, arguments: orderId);

  static Future<void> openBill(BuildContext context, String invoiceId) =>
      Navigator.of(context).pushNamed(Routes.bill, arguments: invoiceId);

  /// Opens the bill of [orderId], creating it if it is missing.
  static Future<void> openBillForOrder(
    BuildContext context,
    String orderId,
  ) async {
    final billing = context.read<BillingController>();
    var invoice = billing.forOrder(orderId);
    if (invoice == null) {
      final order = context.read<OrderController>().byId(orderId);
      if (order == null) return;
      invoice = await billing.createForOrder(order);
      if (!context.mounted) return;
    }
    return openBill(context, invoice.id);
  }

  static Future<void> openPayment(BuildContext context, String invoiceId) =>
      Navigator.of(context).pushNamed(Routes.payment, arguments: invoiceId);

  static Future<void> openReceipt(BuildContext context, String invoiceId) =>
      Navigator.of(context).pushNamed(Routes.receipt, arguments: invoiceId);

  static Future<void> openPayments(BuildContext context) =>
      Navigator.of(context).pushNamed(Routes.payments);
}
