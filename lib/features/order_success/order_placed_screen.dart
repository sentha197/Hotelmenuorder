import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/brand_effects.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/brand_surfaces.dart';
import '../../core/brand/dineqr_logo.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/illustrations.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/billing.dart';
import '../../data/models/restaurant_order.dart';
import '../../state/billing_controller.dart';
import '../../state/order_controller.dart';
import '../../state/shell_controller.dart';

/// Screen 9: confirmation for the order that was just created.
class OrderPlacedScreen extends StatelessWidget {
  const OrderPlacedScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = context.select<OrderController, RestaurantOrder?>(
      (orders) => orders.byId(orderId),
    );
    final invoice = context.select<BillingController, Invoice?>(
      (billing) => billing.forOrder(orderId),
    );
    final shell = context.read<ShellController>();
    final demo = context.read<AppConfig>().demoMode;

    if (order == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Order not found',
          message: 'We could not find this order on this device.',
          actionLabel: 'View Orders',
          onAction: () => AppNav.goToTab(context, ShellTab.orders),
        ),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) shell.select(ShellTab.home);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: Stack(
            children: [
              // Warm glow behind the emblem.
              Positioned(
                left: -120,
                right: -120,
                top: -220,
                child: Container(
                  height: 520,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.orangeSoft,
                        AppColors.paleWarm,
                        Colors.white,
                      ],
                      stops: [0.2, 0.6, 1],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: ConfettiBurst(seed: 11, pieceCount: 30),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () =>
                              AppNav.goToTab(context, ShellTab.home),
                        ),
                        const Expanded(
                          child: Center(child: DineQrLockup(height: 26)),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl,
                        ),
                        child: Column(
                          children: [
                            const SuccessEmblem(
                              size: 104,
                              delay: Duration(milliseconds: 150),
                              semanticLabel: 'Order placed',
                            ),
                            FadeSlideIn(
                              index: 3,
                              child: Text(
                                'Order Placed\nSuccessfully!',
                                textAlign: TextAlign.center,
                                style: AppTypography.headline.copyWith(
                                  fontSize: 26,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FadeSlideIn(
                              index: 4,
                              child: Text(
                                demo
                                    ? 'This order is saved on this device only. '
                                          'It has not been sent to a real '
                                          'kitchen, and its progress is '
                                          'simulated.'
                                    : 'Your order has been sent to the kitchen. '
                                          'Follow its progress and we will '
                                          'serve it at your table.',
                                textAlign: TextAlign.center,
                                style: AppTypography.bodySecondary,
                              ),
                            ),
                            if (demo) ...[
                              const SizedBox(height: AppSpacing.md),
                              const FadeSlideIn(
                                index: 4,
                                child: DemoTag(
                                  label: 'DEMO · NOT SENT TO A KITCHEN',
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xl),
                            FadeSlideIn(
                              index: 5,
                              child: _OrderNumberCard(
                                order: order,
                                invoice: invoice,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        AppSpacing.sm,
                        AppSpacing.page,
                        AppSpacing.md,
                      ),
                      child: FadeSlideIn(
                        index: 6,
                        child: Column(
                          children: [
                            PrimaryButton(
                              label: 'Track Order',
                              icon: Icons.delivery_dining_rounded,
                              onPressed: () =>
                                  Navigator.of(context).pushReplacementNamed(
                                    Routes.tracking,
                                    arguments: order.id,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: SecondaryButton(
                                    label: 'View Bill',
                                    icon: Icons.request_quote_outlined,
                                    onPressed: () => AppNav.openBillForOrder(
                                      context,
                                      order.id,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: SecondaryButton(
                                    label: 'My Orders',
                                    icon: Icons.receipt_long_rounded,
                                    onPressed: () => AppNav.goToTab(
                                      context,
                                      ShellTab.orders,
                                      ordersTab: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderNumberCard extends StatelessWidget {
  const _OrderNumberCard({required this.order, required this.invoice});

  final RestaurantOrder order;
  final Invoice? invoice;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          const BoxShadow(color: AppColors.panelLip, offset: Offset(0, 3)),
          BoxShadow(
            color: AppColors.deepRed.withValues(alpha: 0.3),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: BrandPanel(
        watermark: true,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          children: [
            Text(
              'ORDER NUMBER',
              style: AppTypography.overline.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 4),
            WipeReveal(
              delay: const Duration(milliseconds: 650),
              child: LayeredGradientText(
                AppFormat.orderNumber(order.id),
                style: AppTypography.headline.copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, AppColors.peach],
                ),
                baseColor: AppColors.depthOnRed,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: Icons.table_restaurant_rounded,
                    label: 'Table',
                    value: AppFormat.table(order.tableNumber),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Stat(
                    icon: Icons.restaurant_menu_rounded,
                    label: 'Items',
                    value: '${order.itemCount}',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Stat(
                    icon: Icons.payments_outlined,
                    label: 'Total',
                    value: CurrencyFormatter.format(order.bill.total),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoLine(
              icon: Icons.event_available_rounded,
              text: 'Placed ${AppFormat.dateTime(order.createdAt)}',
            ),
            const SizedBox(height: 4),
            _InfoLine(
              icon: Icons.schedule_rounded,
              text:
                  'Estimated ready by ${AppFormat.time(order.estimatedReadyAt)}',
            ),
            if (invoice != null) ...[
              const SizedBox(height: 4),
              _InfoLine(
                icon: Icons.request_quote_outlined,
                text:
                    'Bill ${invoice!.billNumber} · '
                    '${invoice!.status.label}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: AppColors.warmOrange),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: AppTypography.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.warmOrange),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppTypography.cardTitle.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
