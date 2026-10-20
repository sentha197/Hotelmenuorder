import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/brand_effects.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/brand_surfaces.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/food_widgets.dart';
import '../../core/widgets/order_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/restaurant_order.dart';
import '../../state/order_controller.dart';
import '../feedback/feedback_sheet.dart';
import '../order_tracking/tracking_timeline.dart';

/// Full receipt for one order.
class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = context.select<OrderController, RestaurantOrder?>(
      (orders) => orders.byId(orderId),
    );
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Order Details'),
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
                FadeSlideIn(child: _Overview(order: order)),
                const SizedBox(height: AppSpacing.xl),
                Text('Items', style: AppTypography.sectionTitle),
                const SizedBox(height: AppSpacing.sm),
                FadeSlideIn(
                  index: 1,
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      children: [
                        for (final (index, line) in order.lines.indexed) ...[
                          if (index > 0) const Divider(),
                          _LineRow(line: line),
                        ],
                      ],
                    ),
                  ),
                ),
                if (order.specialInstructions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Special Instructions',
                          style: AppTypography.cardTitle,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          order.specialInstructions,
                          style: AppTypography.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FadeSlideIn(
                  index: 2,
                  child: AppCard(child: BillSummary(bill: order.bill)),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Status', style: AppTypography.sectionTitle),
                const SizedBox(height: AppSpacing.md),
                FadeSlideIn(index: 3, child: TrackingTimeline(order: order)),
                if (order.feedback != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _FeedbackCard(order: order),
                ],
              ],
            ),
      bottomNavigationBar: order == null || !(order.isActive || order.canRate)
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.md,
                ),
                child: order.isActive
                    ? PrimaryButton(
                        label: 'Track Order',
                        icon: Icons.delivery_dining_rounded,
                        onPressed: () => AppNav.openTracking(context, order.id),
                      )
                    : PrimaryButton(
                        label: 'Rate Your Experience',
                        icon: Icons.star_rounded,
                        onPressed: () => showFeedbackSheet(context, order.id),
                      ),
              ),
            ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepRed.withValues(alpha: 0.24),
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
                  child: Text(
                    AppFormat.orderNumber(order.id),
                    style: AppTypography.headline.copyWith(
                      fontSize: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
                OrderStatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                _Meta(
                  icon: Icons.table_restaurant_rounded,
                  text: 'Table ${AppFormat.table(order.tableNumber)}',
                ),
                _Meta(
                  icon: Icons.schedule_rounded,
                  text: AppFormat.dateTime(order.createdAt),
                ),
              ],
            ),
            if (order.isDemoSample) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const DemoTag(label: 'SAMPLE', onDark: true),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Example order included with the demo, not placed by you.',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.warmOrange),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTypography.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.88),
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          FoodImage(
            line.image,
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(AppRadii.sm + 2),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    VegIndicator(isVeg: line.isVeg, size: 11),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line.name,
                        style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  [
                    '${line.quantity} × ${CurrencyFormatter.format(line.unitPrice)}',
                    ...line.options,
                  ].join(' · '),
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.format(line.lineTotal),
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    final feedback = order.feedback!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Your Rating', style: AppTypography.cardTitle),
              const Spacer(),
              StarRow(rating: feedback.rating, size: 20),
            ],
          ),
          if (feedback.comment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('"${feedback.comment}"', style: AppTypography.bodySecondary),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Submitted ${AppFormat.dateTime(feedback.submittedAt)}',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}
