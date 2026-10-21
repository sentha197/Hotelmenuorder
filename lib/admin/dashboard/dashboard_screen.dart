import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/restaurant_time.dart';
import '../../data/models/order_status.dart';
import '../../data/models/staff.dart';
import '../../data/services/report_service.dart';
import '../../state/admin_session_controller.dart';
import '../../state/billing_controller.dart';
import '../../state/catalog_controller.dart';
import '../../state/inventory_controller.dart';
import '../../state/order_controller.dart';
import '../../state/settings_controller.dart';
import '../admin_modules.dart';
import '../orders/admin_orders_screen.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/charts.dart';

/// Daily overview: live operations, money in and out, and alerts.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  RangePreset _preset = RangePreset.today;

  double? _change(Money now, Money before) {
    if (before.isZero) return null;
    return (now.paise - before.paise) / before.paise;
  }

  double? _countChange(int now, int before) =>
      before == 0 ? null : (now - before) / before;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final orders = context.watch<OrderController>();
    final billing = context.watch<BillingController>();
    final catalog = context.watch<CatalogController>();
    final inventory = context.watch<InventoryController>();
    final settings = context.watch<SettingsController>().settings;
    final demo = context.read<AppConfig>().demoMode;
    final now = DateTime.now();
    final range = DateRange.preset(_preset, now);
    String categoryOf(String id) => catalog.byId(id)?.category.label ?? 'Other';
    final report = SalesReport.build(
      orders: orders.orders,
      invoices: billing.invoices,
      range: range,
      now: now,
      categoryOf: categoryOf,
    );
    final previous = SalesReport.build(
      orders: orders.orders,
      invoices: billing.invoices,
      range: range.previous,
      now: now,
      categoryOf: categoryOf,
    );
    final week = SalesReport.build(
      orders: orders.orders,
      invoices: billing.invoices,
      range: DateRange.preset(RangePreset.last7, now),
      now: now,
    );
    final financials = admin.can(Permission.viewFinancials);
    final seesMoney = financials || admin.can(Permission.collectPayments);
    final active = orders.activeOrders;
    final pending = active
        .where(
          (o) =>
              o.status == OrderStatus.placed ||
              o.status == OrderStatus.accepted,
        )
        .length;
    final preparing = active
        .where((o) => o.status == OrderStatus.preparing)
        .length;
    final shell = context.read<AdminShellController>();
    final pendingPayments = billing.invoices
        .where((i) => i.hasPendingPayment)
        .length;
    final refundsDue = billing.invoices.where((i) => i.refundDue).length;
    final lowStock = admin.can(Permission.manageInventory)
        ? inventory.lowStock.length
        : 0;
    final periodLabel = _preset == RangePreset.today ? "Today's" : '7-day';

    return AdminPage(
      title: 'Hello, ${admin.actor?.name.split(' ').first ?? ''}',
      subtitle:
          '${settings.name} · ${AppFormat.date(now)} · ${settings.utcOffsetLabel}',
      children: [
        if (demo && report.demoOrders > 0) ...[
          const DemoDataBanner(
            text:
                'Includes clearly labelled sample orders and simulated payments. '
                'Nothing here represents real money.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        FilterChipBar<RangePreset>(
          values: const [RangePreset.today, RangePreset.last7],
          selected: _preset,
          labelOf: (p) => p.label,
          onSelected: (p) => setState(() => _preset = p),
        ),
        const SizedBox(height: AppSpacing.md),
        MetricGrid(
          children: [
            if (financials)
              MetricCard(
                label: '$periodLabel revenue (collected)',
                value: CurrencyFormatter.format(report.netCollected),
                detail: 'Billed ${CurrencyFormatter.format(report.billed)}',
                icon: Icons.account_balance_wallet_rounded,
                change: _change(report.netCollected, previous.netCollected),
                highlight: true,
                onTap: admin.can(Permission.viewReports)
                    ? () => shell.open(AdminModule.reports)
                    : null,
              ),
            MetricCard(
              label: 'Total orders',
              value: '${report.orderCount}',
              detail: '${report.cancelledCount} cancelled',
              icon: Icons.receipt_long_rounded,
              change: _countChange(report.orderCount, previous.orderCount),
              onTap: () => shell.open(AdminModule.orders),
            ),
            MetricCard(
              label: 'Completed orders',
              value: '${report.completedCount}',
              icon: Icons.check_circle_rounded,
              accent: AppColors.success,
            ),
            MetricCard(
              label: 'Pending orders',
              value: '$pending',
              detail: 'Live, not yet cooking',
              icon: Icons.notifications_active_rounded,
              accent: AppColors.info,
              onTap: () => shell.open(
                admin.can(Permission.manageKitchen)
                    ? AdminModule.kitchen
                    : AdminModule.orders,
              ),
            ),
            MetricCard(
              label: 'Preparing orders',
              value: '$preparing',
              detail: 'Live',
              icon: Icons.soup_kitchen_rounded,
              accent: AppColors.warning,
            ),
            if (financials)
              MetricCard(
                label: 'Average order value',
                value: CurrencyFormatter.format(report.averageOrderValue),
                icon: Icons.functions_rounded,
                change: _change(
                  report.averageOrderValue,
                  previous.averageOrderValue,
                ),
              ),
            MetricCard(
              label: 'Paid bills',
              value: '${report.paidBills}',
              icon: Icons.task_alt_rounded,
              accent: AppColors.success,
              onTap: admin.can(Permission.viewBills)
                  ? () => shell.open(AdminModule.bills)
                  : null,
            ),
            MetricCard(
              label: 'Unpaid bills',
              value: '${report.unpaidBills + report.partiallyPaidBills}',
              detail: '${report.partiallyPaidBills} partly paid',
              icon: Icons.pending_actions_rounded,
              accent: AppColors.primary,
              onTap: admin.can(Permission.viewBills)
                  ? () => shell.open(AdminModule.bills)
                  : null,
            ),
            if (seesMoney)
              MetricCard(
                label: 'Outstanding amount',
                value: CurrencyFormatter.format(report.outstanding),
                icon: Icons.hourglass_bottom_rounded,
                accent: AppColors.primary,
              ),
            MetricCard(
              label: 'Failed payments',
              value: '${report.failedPayments}',
              detail: 'Declined attempts',
              icon: Icons.error_outline_rounded,
              accent: AppColors.error,
            ),
          ],
        ),
        if (pendingPayments + refundsDue + lowStock > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          _Alerts(
            pendingPayments: pendingPayments,
            refundsDue: refundsDue,
            lowStock: lowStock,
            onBills: admin.can(Permission.viewBills)
                ? () => shell.open(AdminModule.bills)
                : null,
            onInventory: lowStock > 0
                ? () => shell.open(AdminModule.inventory)
                : null,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final chart = financials
                ? SectionCard(
                    title: 'Last 7 days',
                    subtitle: 'Billed vs collected per day',
                    child: DailyBarChart(
                      days: [
                        for (final d in week.daily)
                          ChartDay(
                            label: AppFormat.weekday(d.dayStart),
                            detail:
                                '${AppFormat.weekday(d.dayStart)} '
                                '${AppFormat.shortDate(d.dayStart)} · '
                                '${d.orders} orders',
                            billed: d.billed,
                            collected: d.collected,
                          ),
                      ],
                    ),
                  )
                : null;
            final live = SectionCard(
              title: 'Live orders',
              subtitle: '${active.length} in progress',
              child: active.isEmpty
                  ? const AdminEmpty(
                      icon: Icons.coffee_rounded,
                      title: 'All quiet',
                      message: 'New orders appear here as guests place them.',
                    )
                  : Column(
                      children: [
                        for (final order in active.take(5))
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AdminOrderCard(order: order, compact: true),
                          ),
                        if (active.length > 5)
                          TextButton(
                            onPressed: () => shell.open(AdminModule.orders),
                            child: Text('View all ${active.length}'),
                          ),
                      ],
                    ),
            );
            final top = SectionCard(
              title: 'Top dishes',
              subtitle: _preset.label,
              child: report.items.isEmpty
                  ? const AdminEmpty(
                      icon: Icons.restaurant_rounded,
                      title: 'No sales yet',
                      message: 'Best sellers show up once orders come in.',
                    )
                  : RankedBars(
                      maxRows: 5,
                      values: [
                        for (final item in report.items)
                          RankedValue(
                            label: item.name,
                            detail: '${item.quantity} sold',
                            value: financials
                                ? item.revenue.paise
                                : item.quantity,
                            amountLabel: financials
                                ? CurrencyFormatter.format(item.revenue)
                                : '${item.quantity}',
                          ),
                      ],
                    ),
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (chart != null) ...[
                    FadeSlideIn(child: chart),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  FadeSlideIn(index: 1, child: live),
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(index: 2, child: top),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chart != null) ...[
                  FadeSlideIn(child: chart),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: FadeSlideIn(index: 1, child: live)),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: FadeSlideIn(index: 2, child: top)),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Revenue counts successful payments only (pending and failed '
          'payments are excluded), minus refunds.',
          textAlign: TextAlign.center,
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({
    required this.pendingPayments,
    required this.refundsDue,
    required this.lowStock,
    this.onBills,
    this.onInventory,
  });

  final int pendingPayments;
  final int refundsDue;
  final int lowStock;
  final VoidCallback? onBills;
  final VoidCallback? onInventory;

  @override
  Widget build(BuildContext context) {
    Widget alert(
      IconData icon,
      String text,
      Color color,
      VoidCallback? onTap,
    ) => ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(text),
      labelStyle: AppTypography.label.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
      shape: const StadiumBorder(),
      onPressed: onTap,
    );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (pendingPayments > 0)
          alert(
            Icons.hourglass_top_rounded,
            '$pendingPayments payment${pendingPayments == 1 ? '' : 's'} awaiting confirmation',
            AppColors.info,
            onBills,
          ),
        if (refundsDue > 0)
          alert(
            Icons.undo_rounded,
            '$refundsDue refund${refundsDue == 1 ? '' : 's'} due',
            AppColors.warning,
            onBills,
          ),
        if (lowStock > 0)
          alert(
            Icons.inventory_2_outlined,
            '$lowStock item${lowStock == 1 ? '' : 's'} low on stock',
            AppColors.primary,
            onInventory,
          ),
      ],
    );
  }
}
