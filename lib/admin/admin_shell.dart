import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/dependencies.dart';
import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import '../core/animations/motion.dart';
import '../core/brand/dineqr_logo.dart';
import '../core/widgets/app_buttons.dart';
import '../core/widgets/dialogs.dart';
import '../data/models/order_status.dart';
import '../data/models/staff.dart';
import '../state/admin_session_controller.dart';
import '../state/billing_controller.dart';
import '../state/order_controller.dart';
import 'activity/activity_screen.dart';
import 'admin_modules.dart';
import 'billing/admin_bills_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'inventory/inventory_screen.dart';
import 'kitchen/kitchen_screen.dart';
import 'menu/menu_admin_screen.dart';
import 'orders/admin_orders_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/admin_settings_screen.dart';
import 'staff/staff_screen.dart';
import 'tables/tables_screen.dart';

/// The signed-in staff dashboard. Navigation shows only the modules the
/// staff member's role allows; each module also checks permissions for its
/// actions.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late final AdminShellController _shell;
  Timer? _expiryCheck;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final role = context.read<AdminSessionController>().actor?.role;
    final modules = role == null
        ? const <AdminModule>[]
        : AdminModule.forRole(role);
    _shell = AdminShellController(
      modules.isEmpty ? AdminModule.dashboard : modules.first,
    );
    final admin = context.read<AdminSessionController>();
    _expiryCheck = Timer.periodic(
      const Duration(seconds: 30),
      (_) => admin.checkExpiry(),
    );
    _lifecycle = AppLifecycleListener(onResume: admin.checkExpiry);
  }

  @override
  void dispose() {
    _expiryCheck?.cancel();
    _lifecycle.dispose();
    _shell.dispose();
    super.dispose();
  }

  Widget _buildModule(AdminModule module) => switch (module) {
    AdminModule.dashboard => const DashboardScreen(),
    AdminModule.orders => const AdminOrdersScreen(),
    AdminModule.kitchen => const KitchenScreen(),
    AdminModule.bills => const AdminBillsScreen(),
    AdminModule.menu => const MenuAdminScreen(),
    AdminModule.tables => const TablesScreen(),
    AdminModule.reports => const ReportsScreen(),
    AdminModule.inventory => const InventoryScreen(),
    AdminModule.staff => const StaffScreen(),
    AdminModule.settings => const AdminSettingsScreen(),
    AdminModule.activity => const ActivityScreen(),
  };

  Future<void> _signOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to use the dashboard.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
    );
    if (confirmed && mounted) {
      await context.read<AdminSessionController>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AdminSessionController>().actor;
    if (staff == null) return const SizedBox.shrink();
    final modules = AdminModule.forRole(staff.role);
    final newOrders = context.select<OrderController, int>(
      (orders) => orders.activeOrders
          .where((o) => o.status == OrderStatus.placed)
          .length,
    );
    final pendingBills = context.select<BillingController, int>(
      (billing) => billing.invoices.where((i) => i.hasPendingPayment).length,
    );
    int badgeFor(AdminModule module) => switch (module) {
      AdminModule.orders || AdminModule.kitchen => newOrders,
      AdminModule.bills => pendingBills,
      _ => 0,
    };

    return ChangeNotifierProvider.value(
      value: _shell,
      child: ValueListenableBuilder<AdminModule>(
        valueListenable: _shell,
        builder: (context, current, _) {
          final selected = modules.contains(current)
              ? current
              : (modules.isEmpty ? AdminModule.dashboard : modules.first);
          final body = modules.isEmpty
              ? const Center(
                  child: Text('No modules are enabled for your role.'),
                )
              : AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  switchInCurve: Motion.standard,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.015),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(selected),
                    child: _buildModule(selected),
                  ),
                );
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final header = _Header(
                staff: staff,
                title: selected.label,
                onSignOut: _signOut,
                showLogo: !wide,
              );
              if (wide) {
                return Scaffold(
                  backgroundColor: AppColors.softWhite,
                  body: Row(
                    children: [
                      _SideNav(
                        modules: modules,
                        selected: selected,
                        extended: constraints.maxWidth >= 1200,
                        badgeFor: badgeFor,
                        onSelect: _shell.open,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            header,
                            Expanded(child: body),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              final primary = modules.take(4).toList();
              final hasMore = modules.length > primary.length;
              final index = primary.contains(selected)
                  ? primary.indexOf(selected)
                  : primary.length; // "More"
              return Scaffold(
                backgroundColor: AppColors.softWhite,
                body: Column(
                  children: [
                    header,
                    Expanded(child: body),
                  ],
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: index.clamp(
                    0,
                    primary.length - (hasMore ? 0 : 1),
                  ),
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.primarySoft,
                  surfaceTintColor: Colors.transparent,
                  height: 66,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (i) {
                    HapticFeedback.selectionClick();
                    if (i < primary.length) {
                      _shell.open(primary[i]);
                    } else {
                      _showMore(context, modules.skip(4).toList(), selected);
                    }
                  },
                  destinations: [
                    for (final module in primary)
                      NavigationDestination(
                        icon: _BadgeIcon(
                          icon: module.icon,
                          count: badgeFor(module),
                        ),
                        selectedIcon: _BadgeIcon(
                          icon: module.selectedIcon,
                          count: badgeFor(module),
                          color: AppColors.primary,
                        ),
                        label: module.label,
                      ),
                    if (hasMore)
                      const NavigationDestination(
                        icon: Icon(Icons.grid_view_outlined),
                        selectedIcon: Icon(
                          Icons.grid_view_rounded,
                          color: AppColors.primary,
                        ),
                        label: 'More',
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showMore(
    BuildContext context,
    List<AdminModule> modules,
    AdminModule selected,
  ) {
    showBrandSheet<void>(
      context,
      isScrollControlled: false,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final module in modules)
                SizedBox(
                  width: 100,
                  child: Pressable(
                    onTap: () {
                      Navigator.pop(sheet);
                      _shell.open(module);
                    },
                    semanticLabel: module.label,
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: module == selected
                                ? AppColors.primary
                                : AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(AppRadii.lg),
                          ),
                          child: Icon(
                            module.selectedIcon,
                            color: module == selected
                                ? Colors.white
                                : AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          module.label,
                          textAlign: TextAlign.center,
                          style: AppTypography.label,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.icon, required this.count, this.color});

  final IconData icon;
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      backgroundColor: AppColors.accentRed,
      child: Icon(icon, color: color),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.staff,
    required this.title,
    required this.onSignOut,
    required this.showLogo,
  });

  final StaffAccount staff;
  final String title;
  final VoidCallback onSignOut;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final demo = context.read<AppConfig>().demoMode;
    final canLeave = Navigator.of(context).canPop();
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              if (canLeave)
                IconButton(
                  tooltip: 'Back to guest app',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                ),
              if (showLogo) ...[
                const DineQrMark(size: 34, semanticLabel: null),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.screenTitle,
                ),
              ),
              if (demo) ...[
                const DemoTag(),
                const SizedBox(width: AppSpacing.sm),
              ],
              PopupMenuButton<String>(
                tooltip: 'Account',
                position: PopupMenuPosition.under,
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'signout') onSignOut();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(staff.name, style: AppTypography.cardTitle),
                        Text(
                          '${staff.role.label} · ${staff.email}',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'signout',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, size: 20),
                        SizedBox(width: AppSpacing.sm),
                        Text('Sign out'),
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primarySoft,
                    child: Text(
                      staff.name.isEmpty ? '?' : staff.name[0].toUpperCase(),
                      style: AppTypography.cardTitle.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.modules,
    required this.selected,
    required this.extended,
    required this.badgeFor,
    required this.onSelect,
  });

  final List<AdminModule> modules;
  final AdminModule selected;
  final bool extended;
  final int Function(AdminModule module) badgeFor;
  final ValueChanged<AdminModule> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      extended: extended,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primarySoft,
      selectedIndex: modules.indexOf(selected).clamp(0, modules.length - 1),
      onDestinationSelected: (i) => onSelect(modules[i]),
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      selectedLabelTextStyle: AppTypography.label.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: AppTypography.label.copyWith(
        color: AppColors.textSecondary,
      ),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: extended
            ? const DineQrLockup(height: 32)
            : const DineQrMark(size: 44, semanticLabel: 'DineQR'),
      ),
      destinations: [
        for (final module in modules)
          NavigationRailDestination(
            icon: _BadgeIcon(icon: module.icon, count: badgeFor(module)),
            selectedIcon: _BadgeIcon(
              icon: module.selectedIcon,
              count: badgeFor(module),
              color: AppColors.primary,
            ),
            label: Text(module.label),
          ),
      ],
    );
  }
}
