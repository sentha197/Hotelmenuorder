import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/restaurant_time.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/order_widgets.dart';
import '../../data/models/billing.dart';
import '../../data/models/staff.dart';
import '../../state/billing_controller.dart';
import '../widgets/admin_widgets.dart';
import 'admin_bill_detail_screen.dart';

enum _BillFilter {
  all('All'),
  unpaid('Unpaid'),
  partial('Partially paid'),
  paid('Paid'),
  pending('Pending'),
  failed('Failed'),
  refunded('Refunded'),
  voided('Void');

  const _BillFilter(this.label);

  final String label;

  bool matches(Invoice i) => switch (this) {
    _BillFilter.all => true,
    _BillFilter.unpaid => i.status == InvoiceStatus.unpaid,
    _BillFilter.partial => i.status == InvoiceStatus.partiallyPaid,
    _BillFilter.paid => i.status == InvoiceStatus.paid,
    _BillFilter.pending => i.status == InvoiceStatus.pending,
    _BillFilter.failed =>
      i.status == InvoiceStatus.failed ||
          i.payments.any((p) => p.status == PaymentStatus.failed),
    _BillFilter.refunded =>
      i.status == InvoiceStatus.refunded ||
          i.status == InvoiceStatus.partiallyRefunded ||
          i.refundDue,
    _BillFilter.voided => i.isVoid,
  };
}

/// All bills with filters, totals and reconciliation.
class AdminBillsScreen extends StatefulWidget {
  const AdminBillsScreen({super.key});

  @override
  State<AdminBillsScreen> createState() => _AdminBillsScreenState();
}

class _AdminBillsScreenState extends State<AdminBillsScreen> {
  final _search = TextEditingController();
  _BillFilter _status = _BillFilter.all;
  RangePreset? _period = RangePreset.last7;
  PaymentMethodType? _method;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Invoice i, DateTime now) {
    final period = _period;
    if (period != null &&
        !DateRange.preset(period, now).contains(i.createdAt)) {
      return false;
    }
    final method = _method;
    if (method != null &&
        !i.payments.any(
          (p) => p.method == method && p.status == PaymentStatus.succeeded,
        )) {
      return false;
    }
    final q = _query.trim().toLowerCase().replaceAll('#', '');
    if (q.isEmpty) return true;
    return i.billNumber.toLowerCase().contains(q) ||
        i.orderId.toLowerCase().contains(q) ||
        AppFormat.table(i.tableNumber) == q.padLeft(2, '0') ||
        i.payments.any((p) => p.reference.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingController>();
    final now = DateTime.now();
    final scoped = billing.invoices.where((i) => _matches(i, now)).toList();
    final shown = scoped.where(_status.matches).toList();
    final total = Money.sum(shown.where((i) => !i.isVoid).map((i) => i.total));
    final collected = Money.sum(shown.map((i) => i.netPaid));
    final due = Money.sum(shown.map((i) => i.outstanding));
    return AdminPage(
      title: 'Bills',
      subtitle: billing.isSimulated
          ? 'Online payments use the demo simulator'
          : 'Online payments via ${billing.gateway.providerName}',
      children: [
        MetricGrid(
          minTileWidth: 150,
          children: [
            MetricCard(
              label: 'Bills',
              value: '${shown.length}',
              icon: Icons.request_quote_outlined,
            ),
            MetricCard(
              label: 'Billed',
              value: CurrencyFormatter.format(total),
              icon: Icons.receipt_long_rounded,
            ),
            MetricCard(
              label: 'Collected (net)',
              value: CurrencyFormatter.format(collected),
              icon: Icons.account_balance_wallet_rounded,
              accent: AppColors.success,
            ),
            MetricCard(
              label: 'Outstanding',
              value: CurrencyFormatter.format(due),
              icon: Icons.hourglass_bottom_rounded,
              accent: due.isZero ? AppColors.textSecondary : AppColors.primary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AdminSearchField(
          controller: _search,
          hint: 'Bill number, order id, table or reference',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: AppSpacing.md),
        FilterChipBar<RangePreset?>(
          values: const [
            RangePreset.today,
            RangePreset.last7,
            RangePreset.last30,
            null,
          ],
          selected: _period,
          labelOf: (p) => p?.label ?? 'All time',
          onSelected: (p) => setState(() => _period = p),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilterChipBar<_BillFilter>(
          values: _BillFilter.values,
          selected: _status,
          labelOf: (f) => f.label,
          countOf: (f) => scoped.where(f.matches).length,
          onSelected: (f) => setState(() => _status = f),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilterChipBar<PaymentMethodType?>(
          values: [null, ...PaymentMethodType.values],
          selected: _method,
          labelOf: (m) => m?.label ?? 'Any method',
          onSelected: (m) => setState(() => _method = m),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (shown.isEmpty)
          const AdminEmpty(
            icon: Icons.request_quote_outlined,
            title: 'No bills match',
            message: 'Try another filter or period.',
          )
        else
          for (final (index, invoice) in shown.take(100).indexed)
            FadeSlideIn(
              key: ValueKey(invoice.id),
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _BillRow(invoice: invoice),
              ),
            ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final last = invoice.latestSuccessfulPayment;
    return Pressable(
      onTap: () => pushAdminPage<void>(
        context,
        AdminBillDetailScreen(invoiceId: invoice.id),
        permission: Permission.viewBills,
      ),
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.card,
          border: Border.all(
            color: invoice.hasPendingPayment || invoice.refundDue
                ? AppColors.info.withValues(alpha: 0.5)
                : AppColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              invoice.billNumber,
                              style: AppTypography.cardTitle,
                            ),
                          ),
                          if (invoice.isDemoSample) ...[
                            const SizedBox(width: 6),
                            const DemoTag(label: 'SAMPLE'),
                          ],
                        ],
                      ),
                      Text(
                        '${AppFormat.orderNumber(invoice.orderId)} · Table '
                        '${AppFormat.table(invoice.tableNumber)} · '
                        '${AppFormat.dateTime(invoice.createdAt)}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                PaymentStatusBadge(status: invoice.status),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.xs,
              children: [
                _Amount('Total', invoice.total),
                _Amount('Paid', invoice.amountPaid, color: AppColors.success),
                if (!invoice.amountRefunded.isZero)
                  _Amount(
                    'Refunded',
                    invoice.amountRefunded,
                    color: AppColors.warning,
                  ),
                _Amount(
                  'Due',
                  invoice.outstanding,
                  color: invoice.outstanding.isZero
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
              ],
            ),
            if (last != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  last.method.label,
                  if (last.reference.isNotEmpty) 'Ref ${last.reference}',
                  if (last.isSimulated) 'simulated',
                ].join(' · '),
                style: AppTypography.caption,
              ),
            ],
            if (invoice.refundDue)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Order cancelled after payment: refund due',
                  style: AppTypography.caption.copyWith(color: AppColors.info),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.amount, {this.color});

  final String label;
  final Money amount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        Text(
          CurrencyFormatter.format(amount),
          style: AppTypography.label.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
