import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';

/// DineQR takes no payment in the app: guests order here and pay at the
/// restaurant's billing counter.
abstract final class PayAtCounter {
  /// Shown once the order is placed.
  static const placedMessage =
      'Your order has been placed successfully! Please visit the billing '
      'counter to complete your payment.';

  /// Shown wherever an order's total is shown afterwards.
  static const reminder = 'Pay at the billing counter.';

  /// Shown before the order is placed (cart and checkout).
  static const beforeOrdering =
      'No payment is needed now. Place your order and pay at the billing '
      'counter.';
}

/// The order's total and where to pay it: the billing counter.
class PayAtCounterNotice extends StatelessWidget {
  const PayAtCounterNotice({
    super.key,
    required this.total,
    this.message = PayAtCounter.reminder,
  });

  final Money total;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$message Total bill ${CurrencyFormatter.format(total)}.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: AppColors.warmOrange.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.deepRed,
                  size: 24,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text('Total bill', style: AppTypography.cardTitle),
                ),
                Text(
                  CurrencyFormatter.format(total),
                  style: AppTypography.headline.copyWith(
                    fontSize: 22,
                    color: AppColors.deepRed,
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

/// The dishes in an order, each with quantity and price, and the total.
class OrderItemsCard extends StatelessWidget {
  const OrderItemsCard({super.key, required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your order', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.sm),
          for (final line in order.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: VegIndicator(isVeg: line.isVeg, size: 11),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${line.quantity} × ${line.name}',
                          style: AppTypography.label.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (line.options.isNotEmpty)
                          Text(
                            line.options.join(' · '),
                            style: AppTypography.caption,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    CurrencyFormatter.format(line.lineTotal),
                    style: AppTypography.label,
                  ),
                ],
              ),
            ),
          const Divider(),
          BillSummary(bill: order.bill),
        ],
      ),
    );
  }
}
