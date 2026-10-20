import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/brand_effects.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/food_widgets.dart';
import '../../core/widgets/order_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/restaurant_order.dart';
import '../../state/order_controller.dart';
import '../../state/shell_controller.dart';
import '../feedback/feedback_sheet.dart';

/// Screen 11: current and past orders.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final ShellController _shell = context.read<ShellController>();
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: _shell.takePendingOrdersTab() ?? 0,
  );

  @override
  void initState() {
    super.initState();
    _shell.addListener(_onShellChanged);
  }

  void _onShellChanged() {
    final requested = _shell.takePendingOrdersTab();
    if (requested != null && requested != _tabs.index) {
      _tabs.animateTo(requested);
    }
  }

  @override
  void dispose() {
    _shell.removeListener(_onShellChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderController>();
    final current = orders.currentOrders;
    final past = orders.pastOrders;
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: () => _shell.select(ShellTab.home)),
        title: const Text('My Orders'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            height: 46,
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              2,
              AppSpacing.page,
              10,
            ),
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppColors.paleWarm,
              borderRadius: AppRadii.pill,
            ),
            // Segmented control: the gradient pill slides between tabs.
            child: TabBar(
              controller: _tabs,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: AppTypography.label.copyWith(
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: AppTypography.label.copyWith(
                fontWeight: FontWeight.w600,
              ),
              indicator: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: AppRadii.pill,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              tabs: [
                Tab(
                  text: current.isEmpty
                      ? 'Current Orders'
                      : 'Current (${current.length})',
                ),
                Tab(
                  text: past.isEmpty ? 'Past Orders' : 'Past (${past.length})',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OrderList(
            key: const PageStorageKey('current-orders'),
            orders: current,
            empty: EmptyState(
              icon: Icons.room_service_outlined,
              title: 'No active orders',
              message:
                  'Orders you place will appear here so you can track them.',
              actionLabel: 'Browse Menu',
              onAction: () => _shell.select(ShellTab.menu),
            ),
          ),
          _OrderList(
            key: const PageStorageKey('past-orders'),
            orders: past,
            empty: const EmptyState(
              icon: Icons.history_rounded,
              title: 'No past orders yet',
              message: 'Served orders move here once they reach your table.',
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({super.key, required this.orders, required this.empty});

  final List<RestaurantOrder> orders;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return empty;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      itemCount: orders.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.lg),
      itemBuilder: (context, index) => FadeSlideIn(
        key: ValueKey(orders[index].id),
        index: index,
        child: OrderCard(order: orders[index]),
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    const preview = 3;
    final hidden = order.lines.length - preview;
    final (_, accent) = OrderStatusBadge.colorsFor(order.status);
    return Pressable(
      onTap: () => AppNav.openOrderDetails(context, order.id),
      scale: 0.98,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadii.card,
          border: Border.all(color: AppColors.divider),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg - 4,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThumbStack(images: [for (final l in order.lines) l.image]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order ${AppFormat.orderNumber(order.id)}',
                          style: AppTypography.cardTitle.copyWith(
                            fontSize: 15.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Table ${AppFormat.table(order.tableNumber)}',
                          style: AppTypography.label.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppFormat.dateTime(order.createdAt),
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      OrderStatusBadge(status: order.status),
                      if (order.isDemoSample) ...[
                        const SizedBox(height: 6),
                        const DemoTag(label: 'SAMPLE'),
                      ],
                    ],
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: DashedDivider(),
              ),
              for (final line in order.lines.take(preview))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      VegIndicator(isVeg: line.isVeg, size: 11),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          line.name,
                          style: AppTypography.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text(
                          'x${line.quantity}',
                          style: AppTypography.caption,
                        ),
                      ),
                      SizedBox(
                        width: 68,
                        child: Text(
                          CurrencyFormatter.format(line.lineTotal),
                          textAlign: TextAlign.right,
                          style: AppTypography.label,
                        ),
                      ),
                    ],
                  ),
                ),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+ $hidden more ${hidden == 1 ? 'dish' : 'dishes'}',
                    style: AppTypography.caption,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text('Total Amount', style: AppTypography.cardTitle),
                  ),
                  Text(
                    CurrencyFormatter.format(order.bill.total),
                    style: AppTypography.price.copyWith(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(flex: 2, child: _SecondaryAction(order: order)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 3,
                    child: PrimaryButton(
                      label: 'View Details',
                      height: 44,
                      trailingIcon: Icons.arrow_forward_rounded,
                      onPressed: () =>
                          AppNav.openOrderDetails(context, order.id),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Up to three overlapping dish thumbnails.
class _ThumbStack extends StatelessWidget {
  const _ThumbStack({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final shown = images.take(3).toList();
    const size = 40.0;
    const step = 22.0;
    return SizedBox(
      width: size + step * (shown.length - 1).clamp(0, 2),
      height: size,
      child: Stack(
        children: [
          for (final (index, image) in shown.indexed)
            Positioned(
              left: step * index,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: FoodImage(image, width: size - 4, height: size - 4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    if (order.isActive) {
      return SecondaryButton(
        label: 'Track',
        icon: Icons.delivery_dining_rounded,
        height: 44,
        onPressed: () => AppNav.openTracking(context, order.id),
      );
    }
    if (order.canRate) {
      return SecondaryButton(
        label: 'Rate',
        icon: Icons.star_outline_rounded,
        height: 44,
        onPressed: () => showFeedbackSheet(context, order.id),
      );
    }
    final feedback = order.feedback;
    if (feedback != null) {
      return Center(child: StarRow(rating: feedback.rating));
    }
    return Center(
      child: Text(
        order.isDemoSample ? 'Example order' : 'Served',
        style: AppTypography.caption,
      ),
    );
  }
}
