import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/brand_effects.dart';
import '../../core/animations/loaders.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/brand_surfaces.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/order_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/order_status.dart';
import '../../data/models/restaurant_order.dart';
import '../../state/order_controller.dart';
import '../feedback/feedback_sheet.dart';
import 'tracking_timeline.dart';

/// Screen 10: live timeline for one order, with a demo-only control to
/// simulate the kitchen moving it forward.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Future<void> _advance() async {
    final orders = context.read<OrderController>();
    final updated = await orders.advanceStatus(widget.orderId);
    if (updated == null || !mounted) return;
    HapticFeedback.selectionClick();
    if (updated.status == OrderStatus.served && updated.canRate) {
      // Let the timeline finish animating before asking for a rating.
      await Future<void>.delayed(
        Motion.of(context, const Duration(milliseconds: 650)),
      );
      if (mounted) await showFeedbackSheet(context, widget.orderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = context.select<OrderController, RestaurantOrder?>(
      (orders) => orders.byId(widget.orderId),
    );
    final busy = context.select<OrderController, bool>(
      (orders) => orders.isBusy(widget.orderId),
    );

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Order Tracking'),
      ),
      body: order == null
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Order not found',
              message: 'This order is no longer on this device.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              children: [
                FadeSlideIn(child: _OrderHeader(order: order)),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(index: 1, child: TrackingTimeline(order: order)),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(index: 2, child: _KitchenCard(order: order)),
                const SizedBox(height: AppSpacing.lg),
                if (order.canRate)
                  FadeSlideIn(
                    index: 3,
                    child: PrimaryButton(
                      label: 'Rate Your Experience',
                      icon: Icons.star_rounded,
                      onPressed: () => showFeedbackSheet(context, order.id),
                    ),
                  )
                else if (order.feedback != null)
                  _RatedNote(rating: order.feedback!.rating)
                else if (order.isActive)
                  FadeSlideIn(
                    index: 3,
                    child: _DemoControls(
                      order: order,
                      busy: busy,
                      onAdvance: _advance,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    final steps = OrderStatus.values.length;
    final reached = order.status.index + 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepRed.withValues(alpha: 0.26),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: BrandPanel(
        watermark: true,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order ${AppFormat.orderNumber(order.id)}',
                        style: AppTypography.sectionTitle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Table ${AppFormat.table(order.tableNumber)} · '
                        '${AppFormat.itemCount(order.itemCount)} · '
                        '${AppFormat.time(order.createdAt)}',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                OrderStatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            BrandProgressBar(
              value: reached / steps,
              trackColor: Colors.white.withValues(alpha: 0.18),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Step $reached of $steps',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (order.isActive)
                  Text(
                    'Ready by ${AppFormat.time(order.estimatedReadyAt)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.peach,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenCard extends StatelessWidget {
  const _KitchenCard({required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    final table = AppFormat.table(order.tableNumber);
    final (icon, title, message) = switch (order.status) {
      OrderStatus.placed => (
        Icons.receipt_long_rounded,
        'Order received',
        'The kitchen has your order and will start cooking shortly.',
      ),
      OrderStatus.preparing => (
        Icons.soup_kitchen_rounded,
        'Your delicious food is being prepared',
        'Our chefs are cooking everything fresh for you.',
      ),
      OrderStatus.readyToServe => (
        Icons.room_service_rounded,
        'Ready to serve!',
        'Your food is ready and on its way to Table $table.',
      ),
      OrderStatus.served => (
        Icons.restaurant_rounded,
        'Enjoy your meal!',
        'Served at Table $table. We hope you love it.',
      ),
    };
    return AppCard(
      color: AppColors.surfaceSoft,
      border: false,
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.slow),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: IconHalo(key: ValueKey(order.status), icon: icon, size: 88),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.medium),
              child: Column(
                key: ValueKey(order.status),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.cardTitle),
                  const SizedBox(height: 4),
                  Text(message, style: AppTypography.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoControls extends StatelessWidget {
  const _DemoControls({
    required this.order,
    required this.busy,
    required this.onAdvance,
  });

  final RestaurantOrder order;
  final bool busy;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final next = order.status.next;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
        color: AppColors.infoSoft.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DemoTag(),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Simulate kitchen updates',
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'There is no live kitchen in this demo. Move the order forward one '
            'stage at a time to see tracking update.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: next == null ? 'Order completed' : 'Mark as "${next.label}"',
            icon: Icons.fast_forward_rounded,
            height: 46,
            onPressed: busy || next == null ? null : onAdvance,
          ),
        ],
      ),
    );
  }
}

class _RatedNote extends StatelessWidget {
  const _RatedNote({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'You rated this order $rating out of 5',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        children: [
          Text('You rated this order', style: AppTypography.label),
          StarRow(rating: rating, size: 20),
        ],
      ),
    );
  }
}
