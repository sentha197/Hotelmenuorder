import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../widgets/admin_widgets.dart';
import '../orders/order_actions.dart';

enum _Lane {
  incoming(
    'New',
    'Waiting to be accepted or started',
    Icons.notifications_active_rounded,
    AppColors.primary,
  ),
  cooking(
    'Preparing',
    'On the stove',
    Icons.soup_kitchen_rounded,
    AppColors.warmOrange,
  ),
  ready(
    'Ready',
    'Waiting for service',
    Icons.room_service_rounded,
    AppColors.success,
  ),
  done(
    'Done',
    'Served in the last 4 hours',
    Icons.task_alt_rounded,
    AppColors.textMuted,
  );

  static const working = [incoming, cooking, ready];

  /// How long served orders stay in [done].
  static const doneWindow = Duration(hours: 4);

  const _Lane(this.label, this.hint, this.icon, this.color);

  final String label;
  final String hint;
  final IconData icon;

  /// Status colour used for the card rail, counts and empty state.
  final Color color;

  bool contains(RestaurantOrder order) => switch (this) {
    _Lane.incoming =>
      order.status == OrderStatus.placed ||
          order.status == OrderStatus.accepted,
    _Lane.cooking => order.status == OrderStatus.preparing,
    _Lane.ready => order.status == OrderStatus.readyToServe,
    _Lane.done => order.status == OrderStatus.served,
  };

  String get emptyMessage => switch (this) {
    _Lane.incoming => 'New orders will appear here as guests place them.',
    _Lane.cooking => 'Nothing is being prepared right now.',
    _Lane.ready => 'Nothing is waiting to be served.',
    _Lane.done => 'Nothing has been served in the last 4 hours.',
  };
}

/// Kitchen display: orders grouped by stage, oldest first. Narrow screens
/// get one lane at a time behind filter chips; a kitchen display wide enough
/// shows the three working lanes side by side.
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

  /// Reloads from the backend; failures are reported by [runAdminAction].
  Future<void> _refresh() async {
    await runAdminAction(context, () => context.read<OrderController>().load());
  }

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

    final overdue = active.where((o) => o.isOverdue(now)).length;
    final subtitle = [
      '${active.length} active',
      if (overdue > 0) '$overdue past the estimate',
      '${done.length} served recently',
    ].join(' · ');

    return AdminPage(
      title: 'Kitchen',
      subtitle: subtitle,
      onRefresh: _refresh,
      actions: [
        IconButton.outlined(
          tooltip: 'Refresh orders',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Wide enough for three readable lanes side by side.
            final wide = constraints.maxWidth >= 900;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: wide
                  ? _wide(lane, now, active.length, done.length)
                  : _narrow(lane, now),
            );
          },
        ),
      ],
    );
  }

  List<Widget> _narrow(
    List<RestaurantOrder> Function(_Lane) lane,
    DateTime now,
  ) {
    final orders = lane(_lane);
    return [
      FilterChipBar<_Lane>(
        values: _Lane.values,
        selected: _lane,
        labelOf: (l) => l.label,
        countOf: (l) => lane(l).length,
        onSelected: (l) => setState(() => _lane = l),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(_lane.hint, style: AppTypography.caption),
      const SizedBox(height: AppSpacing.md),
      if (orders.isEmpty)
        AdminEmpty(
          icon: _lane.icon,
          title: 'Nothing in ${_lane.label.toLowerCase()}',
          message: _lane.emptyMessage,
        )
      else
        for (final (index, order) in orders.indexed)
          FadeSlideIn(
            key: ValueKey(order.id),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _TicketCard(order: order, now: now, lane: _lane),
            ),
          ),
    ];
  }

  List<Widget> _wide(
    List<RestaurantOrder> Function(_Lane) lane,
    DateTime now,
    int activeCount,
    int doneCount,
  ) {
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            selectedForegroundColor: Colors.white,
            selectedBackgroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.border),
          ),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.local_fire_department_rounded),
              label: Text('Active ($activeCount)'),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.task_alt_rounded),
              label: Text('Completed ($doneCount)'),
            ),
          ],
          selected: {_showDone},
          onSelectionChanged: (value) =>
              setState(() => _showDone = value.single),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      if (_showDone)
        _LaneColumn(lane: _Lane.done, orders: lane(_Lane.done), now: now)
      else
        // Aligned to the top rather than stretched, so the row sizes to its
        // tallest lane without needing a bounded height.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in _Lane.working) ...[
              Expanded(
                child: _LaneColumn(lane: l, orders: lane(l), now: now),
              ),
              if (l != _Lane.working.last) const SizedBox(width: AppSpacing.md),
            ],
          ],
        ),
    ];
  }
}

/// One lane on the wide layout: a titled header then its order cards.
class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.lane,
    required this.orders,
    required this.now,
  });

  final _Lane lane;
  final List<RestaurantOrder> orders;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: lane.color.withValues(alpha: 0.08),
            borderRadius: AppRadii.card,
            border: Border.all(color: lane.color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(lane.icon, size: 18, color: lane.color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  lane.label,
                  style: AppTypography.sectionTitle.copyWith(color: lane.color),
                ),
              ),
              Text(
                '${orders.length}',
                style: AppTypography.sectionTitle.copyWith(color: lane.color),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (orders.isEmpty)
          AdminEmpty(
            icon: lane.icon,
            title: 'Nothing here',
            message: lane.emptyMessage,
          )
        else
          for (final (index, order) in orders.indexed)
            FadeSlideIn(
              key: ValueKey(order.id),
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _TicketCard(order: order, now: now, lane: lane),
              ),
            ),
      ],
    );
  }
}

/// One order: where it came from, what to cook, and the next step.
class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.order,
    required this.now,
    required this.lane,
  });

  final RestaurantOrder order;
  final DateTime now;
  final _Lane lane;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final busy = context.select<OrderController, bool>(
      (orders) => orders.isBusy(order.id),
    );
    final action = OrderAction.next(order.status, order.type);
    final overdue = order.isOverdue(now);
    final age = order.ageInMinutes(now);
    final overBy = now.difference(order.estimatedReadyAt).inMinutes;
    // An overdue ticket is called out in red whichever lane it sits in.
    final accent = overdue ? AppColors.accentRed : lane.color;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.card,
        border: Border.all(
          color: overdue ? AppColors.accentRed : AppColors.divider,
          width: overdue ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // A Stack, not a stretched Row: the card sits in a vertical list, so
      // its height is unbounded and a Row could not stretch the rail.
      child: Stack(
        children: [
          Padding(
            // Leaves room for the rail drawn below.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + 5,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  order: order,
                  now: now,
                  age: age,
                  overdue: overdue,
                  overBy: overBy,
                  accent: accent,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final line in order.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _Line(line: line),
                  ),
                if (order.specialInstructions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  _Instructions(text: order.specialInstructions),
                ],
                if (action != null && action.allowedFor(admin)) ...[
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: action.label,
                    icon: action.icon,
                    height: 46,
                    isLoading: busy,
                    // Finishing a dish is the green step, as elsewhere.
                    color: action.target == OrderStatus.readyToServe
                        ? AppColors.success
                        : null,
                    onPressed: busy ? null : () => advanceOrder(context, order),
                  ),
                ],
              ],
            ),
          ),
          // Status rail: the lane colour, readable at a glance across the
          // pass. Stretched to the card's height by the stack.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 5,
            child: ColoredBox(color: accent),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.order,
    required this.now,
    required this.age,
    required this.overdue,
    required this.overBy,
    required this.accent,
  });

  final RestaurantOrder order;
  final DateTime now;
  final int age;
  final bool overdue;
  final int overBy;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Table number: the first thing the pass needs.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            children: [
              Text(
                order.isTakeaway ? 'TAKEAWAY' : 'TABLE',
                style: AppTypography.caption.copyWith(
                  color: accent,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (order.isTakeaway)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.shopping_bag_rounded,
                    size: 22,
                    color: accent,
                    semanticLabel: 'Takeaway',
                  ),
                )
              else
                Text(
                  OrderTables.shortLabel(order.tableNumber),
                  style: AppTypography.headline.copyWith(
                    fontSize: 22,
                    color: accent,
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppFormat.orderNumber(order.id),
                style: AppTypography.cardTitle,
              ),
              Text(switch (order.status) {
                OrderStatus.accepted => 'Accepted · ${AppFormat.minutes(age)}',
                OrderStatus.served =>
                  '${OrderStatus.served.shortLabelFor(order.type)} '
                      '${AppFormat.time(order.statusTimes[OrderStatus.served] ?? now)}',
                _ => AppFormat.minutes(age),
              }, style: AppTypography.caption),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentRed,
                borderRadius: AppRadii.pill,
              ),
              child: Text(
                overBy < 1 ? 'Due now' : '+$overBy min',
                style: AppTypography.label.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line});

  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 32),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Text(
            '${line.quantity}×',
            textAlign: TextAlign.center,
            style: AppTypography.sectionTitle.copyWith(
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  VegIndicator(isVeg: line.isVeg, size: 12),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(line.name, style: AppTypography.sectionTitle),
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
    );
  }
}

/// Special instructions, called out so the pass cannot miss them.
class _Instructions extends StatelessWidget {
  const _Instructions({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.priority_high_rounded,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.label.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
