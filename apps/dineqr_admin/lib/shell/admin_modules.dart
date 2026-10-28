import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';

/// Sections of the admin app and the permission each needs.
enum AdminModule {
  dashboard(
    'Dashboard',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard_rounded,
    Permission.viewDashboard,
  ),
  service(
    'Service',
    Icons.room_service_outlined,
    Icons.room_service_rounded,
    Permission.serveOrders,
  ),
  orders(
    'Orders',
    Icons.receipt_long_outlined,
    Icons.receipt_long_rounded,
    Permission.viewOrders,
  ),
  kitchen(
    'Kitchen',
    Icons.soup_kitchen_outlined,
    Icons.soup_kitchen_rounded,
    Permission.manageKitchen,
  ),
  bills(
    'Bills',
    Icons.request_quote_outlined,
    Icons.request_quote_rounded,
    Permission.viewBills,
  ),
  payments(
    'Payments',
    Icons.payments_outlined,
    Icons.payments_rounded,
    Permission.viewPayments,
  ),
  menu(
    'Menu',
    Icons.restaurant_menu_outlined,
    Icons.restaurant_menu_rounded,
    Permission.viewMenu,
  ),
  tables(
    'Tables & QR',
    Icons.table_restaurant_outlined,
    Icons.table_restaurant_rounded,
    Permission.viewTables,
  ),
  reports(
    'Reports',
    Icons.insights_outlined,
    Icons.insights_rounded,
    Permission.viewReports,
  ),
  inventory(
    'Inventory',
    Icons.inventory_2_outlined,
    Icons.inventory_2_rounded,
    Permission.manageInventory,
  ),
  staff(
    'Staff',
    Icons.badge_outlined,
    Icons.badge_rounded,
    Permission.manageStaff,
  ),
  settings(
    'Settings',
    Icons.settings_outlined,
    Icons.settings_rounded,
    Permission.manageSettings,
  ),
  activity(
    'Activity log',
    Icons.history_outlined,
    Icons.history_rounded,
    Permission.viewAuditLog,
  );

  const AdminModule(this.label, this.icon, this.selectedIcon, this.permission);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Permission permission;

  /// Modules a role can open, in that role's navigation order: its main
  /// work first (the kitchen display for kitchen staff, the service board
  /// for waiters, the counter for cashiers). The first one is where the
  /// role lands after signing in. [permissions] is what the person may
  /// actually do when the owner customised it; the role's own otherwise.
  static List<AdminModule> forRole(
    StaffRole role, {
    Set<Permission>? permissions,
  }) {
    final granted = permissions ?? role.permissions;
    final allowed = {
      for (final module in values)
        if (granted.contains(module.permission)) module,
    };
    return [
      for (final module in role.workspace.order)
        if (allowed.remove(module)) module,
      // Anything permitted but not placed in the role's order still shows.
      ...values.where(allowed.contains),
    ];
  }
}

/// How a role's workspace is presented: its name, icon and the order of its
/// modules. Presentation only; what a role may do is defined by
/// [StaffRole.permissions] (and, with a backend, enforced by the server).
class RoleWorkspace {
  const RoleWorkspace(this.title, this.icon, this.order);

  final String title;
  final IconData icon;
  final List<AdminModule> order;
}

extension StaffRoleWorkspace on StaffRole {
  RoleWorkspace get workspace => switch (this) {
    StaffRole.owner =>
      const RoleWorkspace('Owner', Icons.workspace_premium_rounded, [
        AdminModule.dashboard,
        AdminModule.orders,
        AdminModule.kitchen,
        AdminModule.bills,
        AdminModule.service,
        AdminModule.payments,
        AdminModule.menu,
        AdminModule.tables,
        AdminModule.reports,
        AdminModule.inventory,
        AdminModule.staff,
        AdminModule.settings,
        AdminModule.activity,
      ]),
    StaffRole.manager =>
      const RoleWorkspace('Operations', Icons.manage_accounts_rounded, [
        AdminModule.dashboard,
        AdminModule.orders,
        AdminModule.kitchen,
        AdminModule.service,
        AdminModule.tables,
        AdminModule.menu,
        AdminModule.inventory,
        AdminModule.bills,
        AdminModule.payments,
        AdminModule.reports,
        AdminModule.activity,
      ]),
    // No set order: whatever the owner switched on, in the usual order.
    StaffRole.custom => const RoleWorkspace('Custom', Icons.badge_rounded, []),
    StaffRole.cashier =>
      const RoleWorkspace('Counter', Icons.point_of_sale_rounded, [
        AdminModule.bills,
        AdminModule.orders,
        AdminModule.payments,
        AdminModule.tables,
        AdminModule.dashboard,
      ]),
    StaffRole.kitchen => const RoleWorkspace(
      'Kitchen',
      Icons.soup_kitchen_rounded,
      [AdminModule.kitchen, AdminModule.orders, AdminModule.menu],
    ),
    StaffRole.waiter =>
      const RoleWorkspace('Service', Icons.room_service_rounded, [
        AdminModule.service,
        AdminModule.orders,
        AdminModule.tables,
        AdminModule.bills,
        AdminModule.menu,
      ]),
    StaffRole.accountant =>
      const RoleWorkspace('Finance', Icons.account_balance_rounded, [
        AdminModule.dashboard,
        AdminModule.reports,
        AdminModule.bills,
        AdminModule.payments,
        AdminModule.orders,
        AdminModule.activity,
      ]),
  };
}

/// Which module the admin shell shows. Modules use it to jump to another
/// section (e.g. a dashboard tile opening Bills).
class AdminShellController extends ValueNotifier<AdminModule> {
  AdminShellController(super.value);

  void open(AdminModule module) => value = module;
}
