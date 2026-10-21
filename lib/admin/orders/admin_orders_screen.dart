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
import '../../data/models/order_status.dart';
import '../../data/models/restaurant_order.dart';
import '../../data/models/staff.dart';
import '../../state/admin_session_controller.dart';
import '../../state/billing_controller.dart';
import '../../state/order_controller.dart';
import '../widgets/admin_widgets.dart';
import 'admin_order_detail_screen.dart';
import 'new_order_screen.dart';
import 'order_actions.dart';

enum _StatusFilter {
  active('Active'),
  all('All'),
  placed('New'),
  accepted('Accepted'),
  preparing('Preparing'),
  ready('Ready'),
  served('Served'),
  cancelled('Cancelled');

  const _StatusFilter(this.label);

  final String label;

  bool matches(RestaurantOrder o) => switch (this) {
    _StatusFilter.active => o.isActive,
    _StatusFilter.all => true,
    _StatusFilter.placed => o.status == OrderStatus.placed,
    _StatusFilter.accepted => o.status == OrderStatus.accepted,
    _StatusFilter.preparing => o.status == OrderStatus.preparing,
    _StatusFilter.ready => o.status == OrderStatus.readyToServe,
    _StatusFilter.served => o.status == OrderStatus.served,
    _StatusFilter.cancelled => o.status == OrderStatus.cancelled,
  };
}

enum _Period {
  today('Today'),
  week('Last 7 days'),
  all('All time');

  const _Period(this.label);

  final String label;
}

/// Live order management for staff.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final _search = TextEditingController();
  _StatusFilter _status = _StatusFilter.active;
  _Period _period = _Period.all;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _inPeriod(RestaurantOrder order, DateTime now) => switch (_period) {
    _Period.today => DateRange.preset(
      RangePreset.today,
      now,
    ).contains(order.createdAt),
    _Period.week => DateRange.preset(
      RangePreset.last7,
      now,
    ).contains(order.createdAt),
    _Period.all => true,
  };

  bool _matchesQuery(RestaurantOrder order) {
    final q = _query.trim().toLowerCase().replaceAll('#', '');
    if (q.isEmpty) return true;
    if (order.id.toLowerCase().contains(q)) return true;
    final table = int.tryParse(q.replaceAll(RegExp(r'^t(able)?\s*'), ''));
    return table != null && order.tableNumber == table;
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final orders = context.watch<OrderController>().orders;
    final now = DateTime.now();
    final scoped = orders
        .where((o) => _inPeriod(o, now) && _matchesQuery(o))
        .toList();
    final shown = scoped.where(_status.matches).toList()
      ..sort((a, b) {
        // Active orders oldest first (queue), others newest first.
        if (_status == _StatusFilter.active) {
          return a.createdAt.compareTo(b.createdAt);
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    return AdminPage(
      title: 'Orders',
      subtitle: '${orders.where((o) => o.isActive).length} in progress',
      actions: [
        if (admin.can(Permission.createOrders))
          PrimaryButton(
            label: 'New order',
            icon: Icons.add_rounded,
            expand: false,
            height: 44,
            onPressed: () => pushAdminPage<void>(
              context,
              const NewOrderScreen(),
              permission: Permission.createOrders,
            ),
          ),
      ],
      children: [
        AdminSearchField(
          controller: _search,
          hint: 'Search order id or table number',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: AppSpacing.md),
        FilterChipBar<_Period>(
          values: _Period.values,
          selected: _period,
          labelOf: (p) => p.label,
          onSelected: (p) => setState(() => _period = p),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilterChipBar<_StatusFilter>(
          values: _StatusFilter.values,
          selected: _status,
          labelOf: (s) => s.label,
          countOf: (s) => scoped.where(s.matches).length,
          onSelected: (s) => setState(() => _status = s),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (shown.isEmpty)
          const AdminEmpty(
            icon: Icons.receipt_long_outlined,
            title: 'No orders here',
            message: 'Try another filter or period.',
          )
        else
          for (final (index, order) in shown.take(80).indexed)
            FadeSlideIn(
              key: ValueKey(order.id),
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AdminOrderCard(order: order),
              ),
            ),
        if (shown.length > 80)
          Text(
            'Showing the first 80 of ${shown.length}. Narrow the filters to '
            'see more.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
      ],
    );
  }
}

/// Order summary row used in lists and on the dashboard.
class AdminOrderCard extends StatelessWidget {
  const AdminOrderCard({super.key, required this.order, this.compact = false});

  final RestaurantOrder order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final invoice = context.select<BillingController, Invoice?>(
      (billing) => billing.forOrder(order.id),
    );
    final busy = context.select<OrderController, bool>(
      (orders) => orders.isBusy(order.id),
    );
    final action = OrderAction.next(order.status);
    final names = order.lines.map((l) => '${l.quantity}× ${l.name}').toList();
    final age = order.ageInMinutes(DateTime.now());
    return Pressable(
      onTap: () => pushAdminPage<void>(
        context,
        AdminOrderDetailScreen(orderId: order.id),
        permission: Permission.viewOrders,
      ),
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.card,
          border: Border.all(
            color: order.status == OrderStatus.placed
                ? AppColors.accentRed.withValues(alpha: 0.5)
                : AppColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TableBadge(table: order.tableNumber),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              AppFormat.orderNumber(order.id),
                              style: AppTypography.cardTitle,
                            ),
                          ),
                          if (order.isDemoSample) ...[
                            const SizedBox(width: 6),
                            const DemoTag(label: 'SAMPLE'),
                          ],
                          if (order.source == OrderSource.staff) ...[
                            const SizedBox(width: 6),
                            const DemoTag(label: 'STAFF'),
                          ],
                        ],
                      ),
                      Text(
                        order.isActive
                            ? '${AppFormat.time(order.createdAt)} · ${AppFormat.minutes(age)} ago'
                            : AppFormat.dateTime(order.createdAt),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                OrderStatusBadge(status: order.status),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                names.take(3).join(', ') +
                    (names.length > 3 ? ' + ${names.length - 3} more' : ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySecondary,
              ),
              if (order.specialInstructions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.sticky_note_2_outlined,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.specialInstructions,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                // Price and payment status wrap on narrow phones.
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        CurrencyFormatter.format(order.bill.total),
                        style: AppTypography.price,
                      ),
                      if (invoice != null)
                        PaymentStatusBadge(status: invoice.status),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (action != null && action.allowedFor(admin))
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => advanceOrder(context, order),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: Icon(action.icon, size: 16),
                      label: Text(action.label),
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

class _TableBadge extends StatelessWidget {
  const _TableBadge({required this.table});

  final int table;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TABLE',
            style: AppTypography.overline.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 7.5,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            AppFormat.table(table),
            style: AppTypography.cardTitle.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
