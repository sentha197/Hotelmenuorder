import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/shell_controller.dart';
import '../cart/cart_screen.dart';
import '../home/home_screen.dart';
import '../menu/menu_list_screen.dart';
import '../more/more_screen.dart';
import '../order_history/orders_screen.dart';

/// Main screen after the table is confirmed: five tabs with a shared bottom
/// navigation. Tabs are built on first visit and then kept alive.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final Set<ShellTab> _visited = {};

  Widget _buildTab(ShellTab tab) => switch (tab) {
    ShellTab.home => const HomeScreen(),
    ShellTab.menu => const MenuListScreen(embedded: true),
    ShellTab.cart => const CartScreen(),
    ShellTab.orders => const OrdersScreen(),
    ShellTab.more => const MoreScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final current = shell.current;
    _visited.add(current);

    return PopScope(
      canPop: current == ShellTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.select(ShellTab.home);
      },
      child: Scaffold(
        body: Stack(
          children: [
            for (final tab in ShellTab.values)
              Offstage(
                offstage: tab != current,
                child: TickerMode(
                  enabled: tab == current,
                  child: HeroMode(
                    enabled: tab == current,
                    child: _visited.contains(tab)
                        ? _TabFade(
                            active: tab == current,
                            child: _buildTab(tab),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _BottomNav(
          current: current,
          onSelect: (tab) {
            if (tab != current) HapticFeedback.selectionClick();
            shell.select(tab);
          },
        ),
      ),
    );
  }
}

/// Quick fade-up whenever a tab becomes visible.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.fast + const Duration(milliseconds: 40),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !Motion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Motion.standard);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onSelect});

  final ShellTab current;
  final ValueChanged<ShellTab> onSelect;

  static const _items = {
    ShellTab.home: (Icons.home_outlined, Icons.home_rounded, 'Home'),
    ShellTab.menu: (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Menu'),
    ShellTab.cart: (
      Icons.shopping_bag_outlined,
      Icons.shopping_bag_rounded,
      'Cart',
    ),
    ShellTab.orders: (
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
      'Orders',
    ),
    ShellTab.more: (Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
  };

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<CartController, int>(
      (cart) => cart.totalQuantity,
    );
    final activeOrders = context.select<OrderController, int>(
      (orders) => orders.currentOrders.length,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (final entry in _items.entries)
                Expanded(
                  child: _NavItem(
                    icon: entry.value.$1,
                    selectedIcon: entry.value.$2,
                    label: entry.value.$3,
                    selected: entry.key == current,
                    badge: switch (entry.key) {
                      ShellTab.cart => cartCount,
                      ShellTab.orders => activeOrders,
                      _ => 0,
                    },
                    onTap: () => onSelect(entry.key),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '$label, $badge' : label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightColor: Colors.transparent,
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Soft pill that grows behind the selected icon.
            AnimatedContainer(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.brand,
              width: selected ? 54 : 34,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySoft : Colors.transparent,
                borderRadius: AppRadii.pill,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.06 : 1,
                    duration: Motion.of(context, Motion.medium),
                    curve: Curves.easeOutBack,
                    child: selected
                        ? ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback:
                                AppColors.emberGradient.createShader,
                            child: Icon(
                              selectedIcon,
                              color: Colors.white,
                              size: 24,
                            ),
                          )
                        : Icon(icon, color: color, size: 24),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: selected ? 4 : -6,
                      top: -4,
                      child: BounceOnChange(
                        trigger: badge,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: AppColors.emberGradient,
                            borderRadius: AppRadii.pill,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badge > 99 ? '99+' : '$badge',
                            style: AppTypography.caption.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: Motion.of(context, Motion.fast),
              style: AppTypography.caption.copyWith(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
