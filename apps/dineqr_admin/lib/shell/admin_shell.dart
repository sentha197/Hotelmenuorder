import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/admin_theme.dart';
import '../brand/admin_brand.dart';
import '../modules/activity/activity_screen.dart';
import '../modules/billing/admin_bills_screen.dart';
import '../modules/dashboard/dashboard_screen.dart';
import '../modules/inventory/inventory_screen.dart';
import '../modules/kitchen/kitchen_screen.dart';
import '../modules/menu/menu_admin_screen.dart';
import '../modules/orders/admin_orders_screen.dart';
import '../modules/payments/payments_screen.dart';
import '../modules/reports/reports_screen.dart';
import '../modules/service/service_screen.dart';
import '../modules/settings/admin_settings_screen.dart';
import '../modules/staff/staff_screen.dart';
import '../modules/tables/tables_screen.dart';
import '../state/admin_session_controller.dart';
import 'admin_modules.dart';

/// The signed-in workspace. Navigation shows only the modules the staff
/// member's role allows, in that role's order, and opens on the role's main
/// module. Each module also checks permissions for its actions.
///
/// Layout: a burgundy frame (top bar, and a side navigation on tablets and
/// desktop) around a neutral content canvas.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  /// Width at which navigation moves from the bottom bar to the side.
  static const sideNavBreakpoint = 900.0;

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
    final admin = context.read<AdminSessionController>();
    final actor = admin.actor;
    final modules = actor == null
        ? const <AdminModule>[]
        : AdminModule.forRole(actor.role, permissions: actor.permissions);
    _shell = AdminShellController(
      modules.isEmpty ? AdminModule.dashboard : modules.first,
    );
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
    AdminModule.service => const ServiceScreen(),
    AdminModule.orders => const AdminOrdersScreen(),
    AdminModule.kitchen => const KitchenScreen(),
    AdminModule.bills => const AdminBillsScreen(),
    AdminModule.payments => const PaymentsScreen(),
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
      message: 'You will need to sign in again to use DineQR Admin.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
    );
    if (confirmed && mounted) {
      await context.read<AdminSessionController>().signOut();
    }
  }

  void _open(AdminModule module) {
    if (_shell.value == module) return;
    HapticFeedback.selectionClick();
    _shell.open(module);
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AdminSessionController>().actor;
    if (staff == null) return const SizedBox.shrink();
    final modules = AdminModule.forRole(
      staff.role,
      permissions: staff.permissions,
    );
    final newOrders = context.select<OrderController, int>(
      (orders) => orders.activeOrders
          .where((o) => o.status == OrderStatus.placed)
          .length,
    );
    final readyOrders = context.select<OrderController, int>(
      (orders) => orders.activeOrders
          .where((o) => o.status == OrderStatus.readyToServe)
          .length,
    );
    final pendingBills = context.select<BillingController, int>(
      (billing) => billing.invoices.where((i) => i.hasPendingPayment).length,
    );
    int badgeFor(AdminModule module) => switch (module) {
      AdminModule.orders || AdminModule.kitchen => newOrders,
      AdminModule.service => readyOrders,
      AdminModule.bills || AdminModule.payments => pendingBills,
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
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.012),
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
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= AdminShell.sideNavBreakpoint;
                final header = _Header(
                  staff: staff,
                  title: selected.label,
                  onSignOut: _signOut,
                  showLogo: !wide,
                );
                if (wide) {
                  return Scaffold(
                    backgroundColor: AdminColors.canvas,
                    body: Row(
                      children: [
                        _SideNav(
                          staff: staff,
                          modules: modules,
                          selected: selected,
                          extended: constraints.maxWidth >= 1200,
                          badgeFor: badgeFor,
                          onSelect: _open,
                          onSignOut: _signOut,
                        ),
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
                  backgroundColor: AdminColors.canvas,
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
                    shadowColor: Colors.black,
                    elevation: 8,
                    height: 66,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    onDestinationSelected: (i) {
                      if (i < primary.length) {
                        _open(primary[i]);
                      } else {
                        HapticFeedback.selectionClick();
                        _showMore(
                          context,
                          modules.skip(4).toList(),
                          selected,
                          badgeFor,
                        );
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
                        NavigationDestination(
                          icon: _BadgeIcon(
                            icon: Icons.grid_view_outlined,
                            count: modules
                                .skip(4)
                                .fold(0, (sum, m) => sum + badgeFor(m)),
                          ),
                          selectedIcon: const Icon(
                            Icons.grid_view_rounded,
                            color: AppColors.primary,
                          ),
                          label: 'More',
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showMore(
    BuildContext context,
    List<AdminModule> modules,
    AdminModule selected,
    int Function(AdminModule module) badgeFor,
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
              for (final (i, module) in modules.indexed)
                FadeSlideIn(
                  index: i,
                  child: SizedBox(
                    width: 100,
                    child: Pressable(
                      onTap: () {
                        Navigator.pop(sheet);
                        _open(module);
                      },
                      semanticLabel: module.label,
                      child: Column(
                        children: [
                          Badge(
                            isLabelVisible: badgeFor(module) > 0,
                            label: Text('${badgeFor(module)}'),
                            backgroundColor: AppColors.accentRed,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: module == selected
                                    ? AppColors.primary
                                    : AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.lg,
                                ),
                              ),
                              child: Icon(
                                module.selectedIcon,
                                color: module == selected
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
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

/// The top bar of the frame: module title, the role's workspace, demo
/// label and the account menu.
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
    final workspace = staff.role.workspace;
    return Material(
      color: AdminColors.frame,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                if (showLogo) ...[
                  const DineQrMark(
                    size: 34,
                    tone: DineQrTone.inverted,
                    semanticLabel: 'DineQR Admin',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: Motion.of(context, Motion.fast),
                        child: Text(
                          title,
                          key: ValueKey(title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.screenTitle.copyWith(
                            color: AdminColors.frameText,
                          ),
                        ),
                      ),
                      Text(
                        '${workspace.title} workspace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AdminColors.frameMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (demo) ...[
                  const DemoTag(onDark: true),
                  const SizedBox(width: AppSpacing.sm),
                ],
                _AccountMenu(staff: staff, onSignOut: onSignOut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.staff, required this.onSignOut});

  final StaffAccount staff;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        child: _Avatar(staff: staff),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.staff});

  static const radius = 18.0;

  final StaffAccount staff;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      child: Text(
        staff.name.isEmpty ? '?' : staff.name[0].toUpperCase(),
        style: AppTypography.cardTitle.copyWith(
          color: Colors.white,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

/// Side navigation for tablets and desktop: the burgundy frame with the
/// role's modules, the signed-in staff member and sign out.
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.staff,
    required this.modules,
    required this.selected,
    required this.extended,
    required this.badgeFor,
    required this.onSelect,
    required this.onSignOut,
  });

  final StaffAccount staff;
  final List<AdminModule> modules;
  final AdminModule selected;
  final bool extended;
  final int Function(AdminModule module) badgeFor;
  final ValueChanged<AdminModule> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final width = extended ? 248.0 : 96.0;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AdminColors.frame, AdminColors.navy],
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                extended ? AppSpacing.xl : 0,
                AppSpacing.lg,
                extended ? AppSpacing.lg : 0,
                AppSpacing.md,
              ),
              child: extended
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: DineQrAdminLockup(height: 38),
                    )
                  : const Center(
                      child: DineQrMark(
                        size: 46,
                        tone: DineQrTone.inverted,
                        semanticLabel: 'DineQR Admin',
                      ),
                    ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                children: [
                  for (final module in modules)
                    _NavItem(
                      module: module,
                      selected: module == selected,
                      extended: extended,
                      badge: badgeFor(module),
                      onTap: () => onSelect(module),
                    ),
                ],
              ),
            ),
            const Divider(color: Color(0x22FFFFFF), height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: extended
                  ? Row(
                      children: [
                        _Avatar(staff: staff),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                staff.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.label.copyWith(
                                  color: AdminColors.frameText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                staff.role.label,
                                style: AppTypography.caption.copyWith(
                                  color: AdminColors.frameMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sign out',
                          onPressed: onSignOut,
                          color: AdminColors.frameMuted,
                          icon: const Icon(Icons.logout_rounded),
                        ),
                      ],
                    )
                  : IconButton(
                      tooltip: 'Sign out',
                      onPressed: onSignOut,
                      color: AdminColors.frameMuted,
                      icon: const Icon(Icons.logout_rounded),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.module,
    required this.selected,
    required this.extended,
    required this.badge,
    required this.onTap,
  });

  final AdminModule module;
  final bool selected;
  final bool extended;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AdminColors.frameMuted;
    final icon = _BadgeIcon(
      icon: selected ? module.selectedIcon : module.icon,
      count: badge,
      color: color,
    );
    final label = Text(
      module.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: extended ? TextAlign.start : TextAlign.center,
      style: AppTypography.label.copyWith(
        color: color,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: extended ? 13.5 : 11,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.standard,
              padding: EdgeInsets.symmetric(
                horizontal: extended ? AppSpacing.md : AppSpacing.xs,
                vertical: extended ? 11 : 9,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.md),
                gradient: selected
                    ? const LinearGradient(
                        colors: [AppColors.primary, AppColors.accentRed],
                      )
                    : null,
                boxShadow: selected
                    ? AppShadows.glow(AppColors.accentRed)
                    : null,
              ),
              child: extended
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: label),
                      ],
                    )
                  : Column(children: [icon, const SizedBox(height: 4), label]),
            ),
          ),
        ),
      ),
    );
  }
}
