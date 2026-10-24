import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/charts.dart';
import '../billing/admin_bill_detail_screen.dart';

/// Sales, collections, taxes and operations for a period, with CSV and PDF
/// exports built from the same figures shown on screen.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  RangePreset _preset = RangePreset.last7;
  DateRange? _custom;
  bool _includeSamples = true;
  bool _showDefinitions = false;
  bool _exporting = false;

  DateRange _range(DateTime now) =>
      _preset == RangePreset.custom && _custom != null
      ? _custom!
      : DateRange.preset(_preset, now);

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _custom == null
          ? null
          : DateTimeRange(
              start: RestaurantTime.wall(_custom!.start),
              end: RestaurantTime.wall(
                _custom!.end.subtract(const Duration(days: 1)),
              ),
            ),
      helpText: 'Report period (restaurant time)',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _preset = RangePreset.custom;
      _custom = DateRange.days(picked.start, picked.end);
    });
  }

  Future<void> _export(SalesReport report, {required bool pdf}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final settings = context.read<SettingsController>().settings;
    final stamp =
        '${AppFormat.fileStamp(report.range.start)}-'
        '${AppFormat.fileStamp(report.range.end.subtract(const Duration(seconds: 1)))}';
    await runAdminAction(context, () async {
      context.read<AdminSessionController>().require(Permission.exportReports);
      if (pdf) {
        final bytes = await ReportPdf.build(
          report,
          settings,
          logoPng: await BrandAssets.logoPng(),
        );
        await FileExport.sharePdf(bytes, 'DineQR-report-$stamp.pdf');
      } else {
        await FileExport.shareCsv(
          ReportCsv.build(report, settings),
          'DineQR-report-$stamp.csv',
        );
      }
    });
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final orders = context.watch<OrderController>();
    final billing = context.watch<BillingController>();
    final catalog = context.watch<CatalogController>();
    final settings = context.watch<SettingsController>().settings;
    final demo = context.read<AppConfig>().demoMode;
    final now = DateTime.now();
    final range = _range(now);
    final report = SalesReport.build(
      orders: orders.orders,
      invoices: billing.invoices,
      range: range,
      now: now,
      includeDemo: _includeSamples,
      categoryOf: (id) => catalog.byId(id)?.category.label ?? 'Other',
    );
    final financials = admin.can(Permission.viewFinancials);
    final canExport = financials && admin.can(Permission.exportReports);
    String money(Money m) => CurrencyFormatter.format(m);

    return AdminPage(
      title: 'Reports',
      subtitle: '${AppFormat.range(range)} · ${settings.utcOffsetLabel}',
      actions: [
        if (canExport) ...[
          IconButton.outlined(
            tooltip: 'Export CSV',
            onPressed: _exporting ? null : () => _export(report, pdf: false),
            icon: const Icon(Icons.table_view_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.outlined(
            tooltip: 'Export PDF',
            onPressed: _exporting ? null : () => _export(report, pdf: true),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ],
      children: [
        FilterChipBar<RangePreset>(
          values: RangePreset.values,
          selected: _preset,
          labelOf: (p) => p == RangePreset.custom && _custom != null
              ? AppFormat.range(_custom!)
              : p.label,
          onSelected: (p) {
            if (p == RangePreset.custom) {
              _pickCustom();
            } else {
              setState(() => _preset = p);
            }
          },
        ),
        if (demo) ...[
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _includeSamples,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _includeSamples = v),
            title: Text('Include sample data', style: AppTypography.cardTitle),
            subtitle: Text(
              report.demoOrders > 0
                  ? '${report.demoOrders} demo sample orders in this period'
                  : 'No sample orders in this period',
              style: AppTypography.caption,
            ),
          ),
        ],
        if (!financials) ...[
          const SizedBox(height: AppSpacing.sm),
          const DemoDataBanner(
            text:
                'Your role sees operational figures. Revenue, taxes and exports '
                'are available to owners and accountants.',
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (report.isEmpty)
          const AdminEmpty(
            icon: Icons.insights_outlined,
            title: 'No activity in this period',
            message: 'Pick another period to see figures.',
          )
        else ...[
          MetricGrid(
            children: [
              if (financials) ...[
                MetricCard(
                  label: 'Net sales',
                  value: money(report.netSales),
                  detail: 'Gross ${money(report.grossSales)}',
                  icon: Icons.trending_up_rounded,
                  highlight: true,
                ),
                MetricCard(
                  label: 'Collected',
                  value: money(report.collected),
                  detail: 'Net ${money(report.netCollected)}',
                  icon: Icons.account_balance_wallet_rounded,
                  accent: AppColors.success,
                ),
                MetricCard(
                  label: 'Outstanding',
                  value: money(report.outstanding),
                  icon: Icons.hourglass_bottom_rounded,
                ),
                MetricCard(
                  label: 'Average order value',
                  value: money(report.averageOrderValue),
                  icon: Icons.functions_rounded,
                ),
              ],
              MetricCard(
                label: 'Orders',
                value: '${report.orderCount}',
                detail: '${report.cancelledCount} cancelled',
                icon: Icons.receipt_long_rounded,
              ),
              MetricCard(
                label: 'Dishes sold',
                value:
                    '${report.items.fold<int>(0, (sum, i) => sum + i.quantity)}',
                icon: Icons.restaurant_rounded,
              ),
            ],
          ),
          if (financials) ...[
            const SizedBox(height: AppSpacing.lg),
            FadeSlideIn(
              child: SectionCard(
                title: 'Daily sales',
                subtitle: 'Billed vs collected',
                child: DailyBarChart(
                  days: [
                    for (final d in report.daily)
                      ChartDay(
                        label: report.daily.length <= 7
                            ? AppFormat.weekday(d.dayStart)
                            : RestaurantTime.wall(d.dayStart).day.toString(),
                        detail:
                            '${AppFormat.weekday(d.dayStart)} '
                            '${AppFormat.shortDate(d.dayStart)} · '
                            '${d.orders} orders',
                        billed: d.billed,
                        collected: d.collected,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FadeSlideIn(
              index: 1,
              child: SectionCard(
                title: 'Breakdown',
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _showDefinitions = !_showDefinitions),
                  child: Text(
                    _showDefinitions
                        ? 'Hide definitions'
                        : 'How it is calculated',
                  ),
                ),
                child: Column(
                  children: [
                    _Line('Gross sales', money(report.grossSales)),
                    _Line('Discounts', '− ${money(report.discounts)}'),
                    _Line('Service charges', money(report.serviceCharges)),
                    _Line('Taxes', money(report.taxes)),
                    _Line('Billed', money(report.billed), strong: true),
                    const Divider(),
                    _Line('Collected', money(report.collected)),
                    _Line('Refunds', '− ${money(report.refunds)}'),
                    _Line(
                      'Net collected',
                      money(report.netCollected),
                      strong: true,
                    ),
                    _Line('Net sales', money(report.netSales), strong: true),
                    _Line('Outstanding', money(report.outstanding)),
                    _Line(
                      'Bills',
                      '${report.paidBills} paid · ${report.partiallyPaidBills} '
                          'partly paid · ${report.unpaidBills} unpaid',
                    ),
                    _Line(
                      'Failed payment attempts',
                      '${report.failedPayments}',
                    ),
                    AnimatedSize(
                      duration: Motion.of(context, Motion.medium),
                      child: _showDefinitions
                          ? Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (term, meaning)
                                      in SalesReport.definitions)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '$term: ',
                                              style: AppTypography.label
                                                  .copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            TextSpan(
                                              text: meaning,
                                              style: AppTypography.caption,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _TwoUp(
            left: SectionCard(
              title: 'Best-selling dishes',
              child: RankedBars(
                values: [
                  for (final item in report.items)
                    RankedValue(
                      label: item.name,
                      detail: '${item.quantity} sold',
                      value: financials ? item.revenue.paise : item.quantity,
                      amountLabel: financials
                          ? money(item.revenue)
                          : '${item.quantity}',
                    ),
                ],
              ),
            ),
            right: SectionCard(
              title: 'Categories',
              child: RankedBars(
                values: [
                  for (final c in report.categories)
                    RankedValue(
                      label: c.name,
                      detail: '${c.quantity} items',
                      value: financials ? c.revenue.paise : c.quantity,
                      amountLabel: financials
                          ? money(c.revenue)
                          : '${c.quantity}',
                    ),
                ],
              ),
            ),
          ),
          if (financials) ...[
            const SizedBox(height: AppSpacing.lg),
            _TwoUp(
              left: SectionCard(
                title: 'Payment collection',
                subtitle: 'Successful payments by method',
                child: report.byMethod.isEmpty
                    ? const AdminEmpty(
                        icon: Icons.payments_outlined,
                        title: 'No payments',
                        message: 'Nothing was collected in this period.',
                      )
                    : DonutChart(
                        slices: [
                          for (final (i, e)
                              in (report.byMethod.entries.toList()..sort(
                                    (a, b) => b.value.compareTo(a.value),
                                  ))
                                  .indexed)
                            DonutSlice(
                              label: e.key.label,
                              amount: e.value,
                              color: DonutChart
                                  .palette[i % DonutChart.palette.length],
                            ),
                        ],
                      ),
              ),
              right: SectionCard(
                title: 'Tax summary',
                subtitle: 'As recorded on bills',
                child: report.taxLines.isEmpty
                    ? const AdminEmpty(
                        icon: Icons.percent_rounded,
                        title: 'No taxes recorded',
                        message: 'No bills in this period.',
                      )
                    : Column(
                        children: [
                          for (final t in report.taxLines) ...[
                            _Line(t.label, money(t.tax), strong: true),
                            _Line(
                              'Taxable amount (${t.bills} bills)',
                              money(t.taxable),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            if (report.outstandingBills.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Outstanding bills',
                subtitle:
                    '${report.outstandingBills.length} with a balance due',
                child: Column(
                  children: [
                    for (final invoice in report.outstandingBills.take(10))
                      _BillLine(invoice: invoice),
                  ],
                ),
              ),
            ],
            if (report.refundRecords.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Refunds',
                child: Column(
                  children: [
                    for (final r in report.refundRecords)
                      _Line(
                        '${AppFormat.date(r.createdAt)} · ${r.reason}'
                            '${r.isSimulated ? ' (simulated)' : ''}',
                        '− ${money(r.amount)}',
                      ),
                  ],
                ),
              ),
            ],
          ],
          if (report.tables.length >= 2) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionCard(
              title: 'Table utilisation',
              subtitle: 'Orders per table',
              child: RankedBars(
                maxRows: 6,
                values: [
                  for (final t in report.tables)
                    RankedValue(
                      label: OrderTables.label(t.table),
                      detail: financials ? money(t.billed) : '',
                      value: t.orders,
                      amountLabel: '${t.orders} orders',
                    ),
                ],
              ),
            ),
          ],
          if (canExport) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Export CSV',
                    icon: Icons.table_view_outlined,
                    onPressed: _exporting
                        ? null
                        : () => _export(report, pdf: false),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: 'Export PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    isLoading: _exporting,
                    onPressed: _exporting
                        ? null
                        : () => _export(report, pdf: true),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: AppSpacing.lg),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: strong
                    ? AppTypography.cardTitle
                    : AppTypography.bodySecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Right-aligned; long values (e.g. bill counts) wrap.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: AppTypography.label.copyWith(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillLine extends StatelessWidget {
  const _BillLine({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => pushAdminPage<void>(
        context,
        AdminBillDetailScreen(invoiceId: invoice.id),
        permission: Permission.viewBills,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${invoice.billNumber} · ${invoice.tableLabel}',
                style: AppTypography.label,
              ),
            ),
            Text(
              'Due ${CurrencyFormatter.format(invoice.outstanding)}',
              style: AppTypography.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
