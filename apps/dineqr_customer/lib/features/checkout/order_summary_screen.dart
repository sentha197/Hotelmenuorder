import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
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
        // The server's reason when it gave one (e.g. prices changed).
        error.message,
        icon: Icons.error_outline_rounded,
      );
      final settings = context.read<SettingsController>();
      if (error.detail != null) {
        // The menu or prices changed on the server: show the current ones.
        context.read<CatalogController>().refresh().ignore();
        settings.load().ignore();
      }
      switch (error.error) {
        case CheckoutError.tableUnavailable ||
            CheckoutError.takeawayUnavailable:
          // Pick up the restaurant's current tables and takeaway setting,
          // then let the guest scan where they can order.
          settings.load().ignore();
          navigator.pushNamed(Routes.scan);
        case CheckoutError.missingTable || CheckoutError.sessionExpired:
          navigator.pushNamed(Routes.scan);
        case CheckoutError.itemsUnavailable:
          // Back to the cart, where sold-out dishes are marked.
          navigator.maybePop();
        default:
          break;
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
    final demo = context.read<AppConfig>().demoMode;
    final offer = cart.appliedOffer;
    final offerNote = switch (cart.offerProblem) {
      null => null,
      OfferError.belowMinimum when offer != null =>
        '${offer.code} is not applied: add '
            '${CurrencyFormatter.format(offer.shortfall(cart.subtotal))} more '
            'to get ${offer.benefit}.',
      final OfferError problem => '${cart.offerCode}: ${problem.message}',
    };
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
            if (offerNote != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Note(icon: Icons.local_offer_outlined, text: offerNote),
            ],
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              index: 5,
              child: _Note(
                icon: Icons.info_outline_rounded,
                text: demo
                    ? 'Demo checkout: the order is saved on this device only '
                          'and no real restaurant is contacted. You can pay '
                          'the bill after placing the order.'
                    : 'You can pay the bill after placing the order.',
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

/// Where the order goes: the table it is served to, or takeaway to collect
/// at the counter.
class _TableCard extends StatelessWidget {
  const _TableCard({required this.table});

  final int? table;

  @override
  Widget build(BuildContext context) {
    final takeaway = table != null && OrderTables.isTakeaway(table!);
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
              child: Icon(
                takeaway
                    ? Icons.shopping_bag_rounded
                    : Icons.table_restaurant_rounded,
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
                    takeaway ? 'Takeaway' : 'Serving to table',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  if (takeaway)
                    Text(
                      'Collect at the counter',
                      style: AppTypography.sectionTitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (table == null)
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

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppTypography.caption)),
      ],
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
                Text(
                  '${CurrencyFormatter.format(line.unitPrice)} each',
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
