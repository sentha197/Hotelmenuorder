import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/loaders.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/brand_surfaces.dart';
import '../../core/brand/dineqr_logo.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/food_widgets.dart';
import '../../core/widgets/order_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/cart_item.dart';
import '../../state/cart_controller.dart';
import '../../state/order_controller.dart';
import '../../state/session_controller.dart';
import '../../state/shell_controller.dart';

/// Screen 8: review before placing the order.
class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({super.key});

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  /// Set once the order went through, so the emptied cart is not shown as an
  /// empty state while the success screen opens.
  bool _submitted = false;

  Future<void> _placeOrder() async {
    final navigator = Navigator.of(context);
    final orders = context.read<OrderController>();
    try {
      final order = await orders.placeOrder(
        cart: context.read<CartController>(),
        tableNumber: context.read<SessionController>().tableNumber,
      );
      _submitted = true;
      HapticFeedback.heavyImpact();
      navigator.pushNamedAndRemoveUntil(
        Routes.orderPlaced,
        (route) => route.settings.name == Routes.home,
        arguments: order.id,
      );
    } on CheckoutException catch (error) {
      if (error.error == CheckoutError.alreadyPlacing || !mounted) return;
      showAppSnackBar(
        context,
        error.error.message,
        icon: Icons.error_outline_rounded,
      );
      if (error.error == CheckoutError.missingTable) {
        navigator.pushNamed(Routes.scan);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final isPlacing = context.select<OrderController, bool>((o) => o.isPlacing);
    final table = context.select<SessionController, int?>((s) => s.tableNumber);

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('Order Summary'),
        ),
        body: _submitted || isPlacing
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const QrPulseLoader(
                      size: 34,
                      color: AppColors.primary,
                      semanticLabel: 'Placing your order',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Placing your order…', style: AppTypography.label),
                  ],
                ),
              )
            : EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Nothing to review',
                message:
                    'Your cart is empty. Add a few dishes to place an order.',
                actionLabel: 'Browse Menu',
                onAction: () => AppNav.goToTab(context, ShellTab.menu),
              ),
      );
    }

    final bill = cart.bill;
    final instructions = cart.specialInstructions.trim();
    return PopScope(
      // Leaving mid-submission could hide the result of the order.
      canPop: !isPlacing,
      child: Scaffold(
        appBar: AppBar(
          leading: AppBackButton(onPressed: isPlacing ? () {} : null),
          title: const Text('Order Summary'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.xxl,
          ),
          children: [
            FadeSlideIn(child: _TableCard(table: table)),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              index: 1,
              child: Text(
                'Your Items (${cart.totalQuantity})',
                style: AppTypography.sectionTitle,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FadeSlideIn(
              index: 2,
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  children: [
                    for (final (index, line) in cart.lines.indexed) ...[
                      if (index > 0) const Divider(),
                      _SummaryLine(line: line),
                    ],
                  ],
                ),
              ),
            ),
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(
                index: 3,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              'Special Instructions',
                              style: AppTypography.cardTitle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(instructions, style: AppTypography.bodySecondary),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FadeSlideIn(
              index: 4,
              child: AppCard(child: BillSummary(bill: bill)),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              index: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Demo checkout: the order is saved on this device only and '
                      'no real restaurant is contacted.',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.md,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: PrimaryButton(
                label: 'Place Order · ${CurrencyFormatter.format(bill.total)}',
                isLoading: isPlacing,
                onPressed: isPlacing ? null : _placeOrder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table});

  final int? table;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepRed.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: BrandPanel(
        watermark: true,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: const Icon(
                Icons.table_restaurant_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Serving to table',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  if (table == null)
                    Text(
                      'Not selected',
                      style: AppTypography.sectionTitle.copyWith(
                        color: Colors.white,
                      ),
                    )
                  else
                    LayeredGradientText(
                      AppFormat.table(table!),
                      style: AppTypography.headline.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white, AppColors.peach],
                      ),
                      baseColor: AppColors.depthOnRed,
                    ),
                ],
              ),
            ),
            if (table != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadii.pill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: AppColors.success,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Confirmed',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.line});

  final CartItem line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FoodImage(
            line.item.image,
            width: 42,
            height: 42,
            borderRadius: BorderRadius.circular(AppRadii.sm + 2),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    VegIndicator(isVeg: line.item.isVeg, size: 11),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line.item.name,
                        style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (line.optionLabels.isNotEmpty)
                  Text(
                    line.optionLabels.join(' · '),
                    style: AppTypography.caption.copyWith(fontSize: 11),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              'x${line.quantity}',
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              CurrencyFormatter.format(line.lineTotal),
              textAlign: TextAlign.right,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
