import 'package:flutter/material.dart';

import '../data/models/staff.dart';

/// Sections of the staff dashboard and the permission each needs.
enum AdminModule {
  dashboard(
    'Dashboard',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard_rounded,
    Permission.viewDashboard,
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

  /// Modules a role can open, in navigation order.
  static List<AdminModule> forRole(StaffRole role) => [
    for (final module in values)
      if (role.can(module.permission)) module,
  ];
}

/// Which module the admin shell shows. Modules use it to jump to another
/// section (e.g. a dashboard tile opening Bills).
class AdminShellController extends ValueNotifier<AdminModule> {
  AdminShellController(super.value);

  void open(AdminModule module) => value = module;
}
