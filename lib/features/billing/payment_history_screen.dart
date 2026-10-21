import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/order_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/billing.dart';
import '../../state/billing_controller.dart';
import '../../state/order_controller.dart';
import 'invoice_view.dart';

/// The guest's bills and payments on this device.
class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderController>().guestOrders;
    final bills = context.watch<BillingController>().forOrders(orders);
    final paid = Money.sum(bills.map((b) => b.netPaid));
    final due = Money.sum(bills.map((b) => b.outstanding));
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Bills & Payments'),
      ),
      body: bills.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No bills yet',
              message: 'Bills for the orders you place will appear here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              children: [
                FadeSlideIn(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Total(
                          label: 'Paid',
                          amount: paid,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _Total(
                          label: 'Balance due',
                          amount: due,
                          color: due.isZero
                              ? AppColors.textSecondary
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final (index, bill) in bills.indexed)
                  FadeSlideIn(
                    index: index + 1,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _BillTile(invoice: bill),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final Money amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption),
          const SizedBox(height: 2),
          AnimatedMoneyText(
            amount,
            style: AppTypography.headline.copyWith(fontSize: 20, color: color),
          ),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final last = invoice.latestSuccessfulPayment;
    return Pressable(
      onTap: () => AppNav.openBill(context, invoice.id),
      scale: 0.98,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invoice.billNumber, style: AppTypography.cardTitle),
                      Text(
                        'Order ${AppFormat.orderNumber(invoice.orderId)} · '
                        '${AppFormat.dateTime(invoice.createdAt)}',
                        style: AppTypography.caption,
                      ),
                      if (invoice.isDemoSample || invoice.isSimulated) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (invoice.isDemoSample)
                              const DemoTag(label: 'SAMPLE'),
                            if (invoice.isSimulated)
                              const DemoTag(label: 'SIMULATED'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                PaymentStatusBadge(status: invoice.status),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: DashedDivider(),
            ),
            _Line('Total', CurrencyFormatter.format(invoice.total)),
            _Line('Paid', CurrencyFormatter.format(invoice.amountPaid)),
            if (!invoice.amountRefunded.isZero)
              _Line(
                'Refunded',
                CurrencyFormatter.format(invoice.amountRefunded),
              ),
            _Line('Balance due', CurrencyFormatter.format(invoice.outstanding)),
            if (last != null)
              _Line(
                'Method',
                [
                  last.method.label,
                  if (last.reference.isNotEmpty) last.reference,
                ].join(' · '),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Receipt',
                    icon: Icons.download_rounded,
                    height: 42,
                    onPressed: () => AppNav.openReceipt(context, invoice.id),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: invoice.outstanding.isZero ? 'View Bill' : 'Pay',
                    height: 42,
                    icon: invoice.outstanding.isZero
                        ? Icons.receipt_long_rounded
                        : last == null
                        ? Icons.lock_rounded
                        : last.method.icon,
                    onPressed: () => AppNav.openBill(context, invoice.id),
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

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.bodySecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
