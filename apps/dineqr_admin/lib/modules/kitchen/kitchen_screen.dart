import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../orders/order_actions.dart';

enum _Lane {
  incoming(
    'New',
    'Waiting to be accepted or started',
    Icons.notifications_active_rounded,
  ),
  cooking('Preparing', 'On the stove', Icons.soup_kitchen_rounded),
  ready('Ready', 'Waiting for service', Icons.room_service_rounded),
  done('Done', 'Served in the last 4 hours', Icons.task_alt_rounded);

  static const working = [incoming, cooking, ready];

  /// How long served orders stay in [done].
  static const doneWindow = Duration(hours: 4);

  const _Lane(this.label, this.hint, this.icon);

  final String label;
  final String hint;
  final IconData icon;

  bool contains(RestaurantOrder order) => switch (this) {
    _Lane.incoming =>
      order.status == OrderStatus.placed ||
          order.status == OrderStatus.accepted,
    _Lane.cooking => order.status == OrderStatus.preparing,
    _Lane.ready => order.status == OrderStatus.readyToServe,
    _Lane.done => order.status == OrderStatus.served,
  };
}

/// Kitchen display: large cards per lane, oldest first.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  Timer? _clock;
  _Lane _lane = _Lane.incoming;

  /// Wide layout: the three working lanes, or completed orders.
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    // Refresh order ages while the screen is open.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  static DateTime _servedAt(RestaurantOrder order) =>
      order.statusTimes[OrderStatus.served] ?? order.createdAt;

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderController>();
    final active = orders.activeOrders;
    final now = DateTime.now();
    final done =
        orders.orders
            .where(
              (o) =>
                  _Lane.done.contains(o) &&
                  now.difference(_servedAt(o)) < _Lane.doneWindow,
            )
            .toList()
          ..sort((a, b) => _servedAt(b).compareTo(_servedAt(a)));
    List<RestaurantOrder> lane(_Lane l) => l == _Lane.done
        ? done.take(30).toList(growable: false)
        : active.where(l.contains).toList(growable: false);
    return ColoredBox(
      color: AppColors.charcoal,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (wide) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<bool>(
                      style: SegmentedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        selectedForegroundColor: Colors.white,
                        selectedBackgroundColor: AppColors.primary,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.local_fire_department_rounded),
                          label: Text('Active (${active.length})'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.task_alt_rounded),
                          label: Text('Completed (${done.length})'),
                        ),
                      ],
                      selected: {_showDone},
                      onSelectionChanged: (value) =>
                          setState(() => _showDone = value.single),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.medium),
                    child: _showDone
                        ? _LaneColumn(
                            key: const ValueKey('done'),
                            lane: _Lane.done,
                            orders: lane(_Lane.done),
                            now: now,
                          )
                        : Padding(
                            key: const ValueKey('working'),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final l in _Lane.working)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                      ),
                                      child: _LaneColumn(
                                        lane: l,
                                        orders: lane(l),
                                        now: now,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: Row(
                  children: [
                    for (final l in _Lane.values)
                      Expanded(
                        child: _LaneTab(
                          lane: l,
                          count: lane(l).length,
                          selected: l == _lane,
                          onTap: () => setState(() => _lane = l),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _LaneColumn(
                  key: ValueKey(_lane),
                  lane: _lane,
                  orders: lane(_lane),
                  now: now,
                  showHeader: false,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LaneTab extends StatelessWidget {
  const _LaneTab({
    required this.lane,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final _Lane lane;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.ctaGradient : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: AppTypography.headline.copyWith(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              Text(
                lane.label,
                style: AppTypography.label.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    super.key,
    required this.lane,
    required this.orders,
    required this.now,
    this.showHeader = true,
  });

  final _Lane lane;
  final List<RestaurantOrder> orders;
  final DateTime now;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Icon(lane.icon, color: AppColors.warmOrange),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${lane.label} (${orders.length})',
                  style: AppTypography.sectionTitle.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    lane.hint,
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (orders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
            child: Column(
              children: [
                Icon(
                  lane.icon,
                  size: 40,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  switch (lane) {
                    _Lane.ready => 'Nothing waiting right now',
                    _Lane.done => 'Nothing served in the last 4 hours',
                    _ => 'Nothing here right now',
                  },
                  style: AppTypography.label.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        for (final (index, order) in orders.indexed)
          FadeSlideIn(
            key: ValueKey(order.id),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _TicketCard(order: order, now: now),
            ),
          ),
      ],
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.order, required this.now});

  final RestaurantOrder order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final busy = context.select<OrderController, bool>(
      (orders) => orders.isBusy(order.id),
    );
    final action = OrderAction.next(order.status);
    final overdue = order.isOverdue(now);
    final age = order.ageInMinutes(now);
    final overBy = now.difference(order.estimatedReadyAt).inMinutes;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: overdue ? AppColors.accentRed : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              gradient: overdue ? AppColors.ctaGradient : null,
              color: overdue ? null : AppColors.paleWarm,
            ),
            child: Row(
              children: [
                Text(
                  'T${AppFormat.table(order.tableNumber)}',
                  style: AppTypography.display.copyWith(
                    fontSize: 30,
                    color: overdue ? Colors.white : AppColors.primary,
                    height: 1,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppFormat.orderNumber(order.id),
                        style: AppTypography.cardTitle.copyWith(
                          color: overdue ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        switch (order.status) {
                          OrderStatus.accepted =>
                            'Accepted · ${AppFormat.minutes(age)}',
                          OrderStatus.served =>
                            'Served ${AppFormat.time(order.statusTimes[OrderStatus.served] ?? now)}',
                          _ => AppFormat.minutes(age),
                        },
                        style: AppTypography.caption.copyWith(
                          color: overdue
                              ? Colors.white.withValues(alpha: 0.9)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (overdue)
                  Semantics(
                    label: overBy < 1
                        ? 'Due now'
                        : 'Past the preparation estimate by $overBy minutes',
                    excludeSemantics: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        overBy < 1 ? 'Due now' : '+$overBy min',
                        style: AppTypography.label.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in order.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${line.quantity}×',
                            style: AppTypography.sectionTitle.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  VegIndicator(isVeg: line.isVeg, size: 12),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      line.name,
                                      style: AppTypography.sectionTitle,
                                    ),
                                  ),
                                ],
                              ),
                              if (line.options.isNotEmpty)
                                Text(
                                  line.options.join(' · '),
                                  style: AppTypography.label.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (order.specialInstructions.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Text(
                      '⚠ ${order.specialInstructions}',
                      style: AppTypography.cardTitle.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                if (action != null && action.allowedFor(admin)) ...[
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => advanceOrder(context, order),
                      style: FilledButton.styleFrom(
                        backgroundColor: order.status == OrderStatus.preparing
                            ? AppColors.success
                            : AppColors.primary,
                        textStyle: AppTypography.button.copyWith(fontSize: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                      ),
                      icon: Icon(action.icon),
                      label: Text(action.label),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
