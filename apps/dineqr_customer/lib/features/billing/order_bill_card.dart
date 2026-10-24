import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';

import '../../app/routes.dart';

/// Bill status of an order with View Bill, and Pay Now while something is
/// due (online, in cash or at the counter; otherwise the receipt once paid).
class OrderBillCard extends StatelessWidget {
  const OrderBillCard({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final canPay = !invoice.isVoid && !invoice.payableNow.isZero;
    final hasPayment = invoice.latestSuccessfulPayment != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Bill ${invoice.billNumber}',
                  style: AppTypography.cardTitle,
                ),
              ),
              PaymentStatusBadge(status: invoice.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            invoice.outstanding.isZero
                ? 'Total ${CurrencyFormatter.format(invoice.total)} · '
                      '${invoice.isVoid ? 'nothing to pay' : 'nothing due'}'
                : 'Balance due ${CurrencyFormatter.format(invoice.outstanding)} '
                      'of ${CurrencyFormatter.format(invoice.total)}',
            style: AppTypography.bodySecondary,
          ),
          if (invoice.hasPendingPayment) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'A payment of ${CurrencyFormatter.format(invoice.pendingAmount)} '
              'is waiting for confirmation.',
              style: AppTypography.caption.copyWith(color: AppColors.info),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'View Bill',
                  icon: Icons.receipt_long_rounded,
                  height: 46,
                  onPressed: () => AppNav.openBill(context, invoice.id),
                ),
              ),
              if (canPay) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: 'Pay Now',
                    icon: Icons.lock_rounded,
                    height: 46,
                    onPressed: () => AppNav.openPayment(context, invoice.id),
                  ),
                ),
              ] else if (hasPayment) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SecondaryButton(
                    label: 'Receipt',
                    icon: Icons.download_rounded,
                    height: 46,
                    onPressed: () => AppNav.openReceipt(context, invoice.id),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
