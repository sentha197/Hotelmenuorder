import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';
import '../billing/admin_bill_detail_screen.dart';

/// Payment history: every payment attempt and refund against the bills,
/// with the same totals as Reports. Tap a line to open its bill (receipts,
/// reconciliation and refunds live there).
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  /// Lines rendered at once; narrower filters show the rest.
  static const pageSize = 150;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  RangePreset _preset = RangePreset.today;
  LedgerFilter _filter = LedgerFilter.all;
  PaymentMethodType? _method;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingController>();
    final demo = context.read<AppConfig>().demoMode;
    final ledger = PaymentLedger.build(
      invoices: billing.invoices,
      range: DateRange.preset(_preset, DateTime.now()),
      filter: _filter,
      method: _method,
      query: _query,
    );
    final shown = ledger.entries.take(PaymentsScreen.pageSize).toList();

    return AdminPage(
      title: 'Payments',
      subtitle: 'Payments and refunds recorded against bills',
      children: [
        if (ledger.hasSimulated) ...[
          DemoDataBanner(
            text: demo
                ? 'Payments in this demo are simulated or samples. No money '
                      'was charged or refunded.'
                : 'Payments marked DEMO were made in demo mode: simulated, '
                      'not verified by any bank. No money was charged or '
                      'refunded for them.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        FilterChipBar<RangePreset>(
          values: const [
            RangePreset.today,
            RangePreset.yesterday,
            RangePreset.last7,
            RangePreset.last30,
          ],
          selected: _preset,
          labelOf: (p) => p.label,
          onSelected: (p) => setState(() => _preset = p),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilterChipBar<LedgerFilter>(
          values: LedgerFilter.values,
          selected: _filter,
          labelOf: (f) => f.label,
          onSelected: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilterChipBar<PaymentMethodType?>(
          values: const [null, ...PaymentMethodType.values],
          selected: _method,
          labelOf: (m) => m?.label ?? 'All methods',
          onSelected: (m) => setState(() => _method = m),
        ),
        const SizedBox(height: AppSpacing.sm),
        AdminSearchField(
          controller: _search,
          hint: 'Search reference, bill, order or table',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: AppSpacing.md),
        MetricGrid(
          children: [
            MetricCard(
              label: 'Collected',
              value: CurrencyFormatter.format(ledger.collected),
              detail: 'Successful payments',
              icon: Icons.account_balance_wallet_rounded,
              accent: AppColors.success,
              highlight: true,
            ),
            MetricCard(
              label: 'Refunded',
              value: CurrencyFormatter.format(ledger.refunded),
              detail: 'Net ${CurrencyFormatter.format(ledger.netCollected)}',
              icon: Icons.undo_rounded,
              accent: AppColors.warning,
            ),
            MetricCard(
              label: 'Pending',
              value: CurrencyFormatter.format(ledger.pendingAmount),
              detail: 'Awaiting confirmation',
              icon: Icons.hourglass_top_rounded,
              accent: AppColors.info,
            ),
            MetricCard(
              label: 'Failed attempts',
              value: '${ledger.failedCount}',
              detail: 'No money moved',
              icon: Icons.error_outline_rounded,
              accent: AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title:
              '${ledger.entries.length} '
              '${ledger.entries.length == 1 ? 'entry' : 'entries'}',
          subtitle: AppFormat.range(ledger.range),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: shown.isEmpty
              ? const AdminEmpty(
                  icon: Icons.payments_outlined,
                  title: 'No payments',
                  message: 'Nothing matches these filters.',
                )
              : Column(
                  children: [
                    for (final (i, entry) in shown.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _LedgerRow(entry: entry),
                    ],
                    if (ledger.entries.length > shown.length)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'Showing the latest ${shown.length}. Narrow the '
                          'dates or filters to see older entries.',
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final LedgerEntry entry;

  (Color, IconData) get _look {
    final payment = entry.payment;
    if (payment == null) return (AppColors.warning, Icons.undo_rounded);
    return switch (payment.status) {
      PaymentStatus.succeeded => (AppColors.success, _methodIcon(payment)),
      PaymentStatus.pending => (AppColors.info, Icons.hourglass_top_rounded),
      PaymentStatus.failed => (AppColors.error, Icons.error_outline_rounded),
      PaymentStatus.cancelled => (AppColors.textMuted, Icons.block_rounded),
    };
  }

  static IconData _methodIcon(PaymentTransaction payment) =>
      switch (payment.method) {
        PaymentMethodType.upi => Icons.phone_iphone_rounded,
        PaymentMethodType.card => Icons.credit_card_rounded,
        PaymentMethodType.netBanking => Icons.account_balance_rounded,
        PaymentMethodType.wallet => Icons.account_balance_wallet_rounded,
        PaymentMethodType.cash => Icons.payments_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final invoice = entry.invoice;
    final (color, icon) = _look;
    final payment = entry.payment;
    // Only successful payments and processed refunds moved money.
    final moved =
        entry.refund?.status == RefundStatus.processed ||
        payment?.status == PaymentStatus.succeeded;
    final title = entry.isRefund
        ? 'Refund'
        : '${payment!.methodLabel} · ${payment.status.label}';
    final reference = entry.reference.isEmpty
        ? ''
        : ' · Ref ${entry.reference}';
    return InkWell(
      onTap: () => pushAdminPage<void>(
        context,
        AdminBillDetailScreen(invoiceId: invoice.id),
        permission: Permission.viewBills,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTypography.cardTitle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isSimulated) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const DemoTag(),
                      ],
                    ],
                  ),
                  Text(
                    '${invoice.billNumber} · ${invoice.tableLabel}$reference',
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    AppFormat.dateTime(entry.at),
                    style: AppTypography.caption.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              entry.isRefund
                  ? '−${CurrencyFormatter.format(entry.refund!.amount)}'
                  : CurrencyFormatter.format(payment!.amount),
              style: AppTypography.cardTitle.copyWith(
                color: moved ? color : AppColors.textMuted,
                decoration: moved ? null : TextDecoration.lineThrough,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
