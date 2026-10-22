import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../state/service_section_controller.dart';
import '../../widgets/admin_widgets.dart';
import '../billing/admin_bill_detail_screen.dart';
import '../orders/admin_order_detail_screen.dart';
import '../orders/new_order_screen.dart';
import '../orders/order_actions.dart';

/// The service board for waiters: dishes ready to take to tables, what the
/// kitchen is still working on, and the state of each table. A waiter can
/// narrow it to the tables they are covering.
class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});

  /// A ready dish waiting longer than this is flagged.
  static const readyTooLong = Duration(minutes: 5);

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Keep "ready for N min" current while the board is open.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _editSection(String staffId, Set<int> current) async {
    final tables = context
        .read<SettingsController>()
        .tables
        .where((t) => t.isActive)
        .map((t) => t.number)
        .toList();
    final picked = await showBrandSheet<Set<int>>(
      context,
      builder: (sheet) => _SectionPicker(tables: tables, initial: current),
    );
    if (picked == null || !mounted) return;
    await context.read<ServiceSectionController>().setTables(staffId, picked);
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final staff = admin.actor;
    if (staff == null) return const SizedBox.shrink();
    final orders = context.watch<OrderController>();
    final settings = context.watch<SettingsController>();
    final billing = context.watch<BillingController>();
    final section = context.watch<ServiceSectionController>().tablesFor(
      staff.id,
    );
    bool mine(int table) => section.isEmpty || section.contains(table);
    final now = DateTime.now();

    final active = orders.activeOrders.where((o) => mine(o.tableNumber));
    final ready =
        active.where((o) => o.status == OrderStatus.readyToServe).toList()
          ..sort((a, b) => _readyAt(a).compareTo(_readyAt(b)));
    final cooking = active
        .where((o) => o.status != OrderStatus.readyToServe)
        .toList();
    final tables = settings.tables
        .where((t) => t.isActive && mine(t.number))
        .toList();
    final canBills = admin.can(Permission.viewBills);
    final canCreate = admin.can(Permission.createOrders);

    return AdminPage(
      title: 'Service',
      subtitle: section.isEmpty
          ? 'All tables'
          : 'Your section · ${section.length} '
                '${section.length == 1 ? 'table' : 'tables'}',
      actions: [
        if (canCreate)
          FilledButton.icon(
            onPressed: () => pushAdminPage<void>(
              context,
              const NewOrderScreen(),
              permission: Permission.createOrders,
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New order'),
          ),
      ],
      children: [
        _SectionBar(
          section: section,
          onEdit: () => _editSection(staff.id, section),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Ready to serve',
          subtitle: ready.isEmpty
              ? 'Nothing waiting'
              : '${ready.length} waiting · oldest first',
          child: ready.isEmpty
              ? const AdminEmpty(
                  icon: Icons.room_service_outlined,
                  title: 'All served',
                  message:
                      'Dishes the kitchen marks ready appear here to take to '
                      'the table.',
                )
              : Column(
                  children: [
                    for (final order in ready)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _ReadyCard(
                          key: ValueKey(order.id),
                          order: order,
                          waiting: now.difference(_readyAt(order)),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'In the kitchen',
          subtitle: cooking.isEmpty
              ? 'No open orders'
              : '${cooking.length} on the way',
          child: cooking.isEmpty
              ? Text(
                  'New orders for your tables show here until they are ready.',
                  style: AppTypography.bodySecondary,
                )
              : Column(
                  children: [
                    for (final order in cooking)
                      _CookingRow(order: order, now: now),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Tables',
          subtitle: 'Tap a table for its orders and bill',
          child: tables.isEmpty
              ? Text('No active tables.', style: AppTypography.bodySecondary)
              : Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final table in tables)
                      _TableTile(
                        table: table,
                        state: _TableState.of(
                          table.number,
                          orders.activeForTable(table.number),
                          canBills
                              ? _dueBills(billing, table.number, now)
                              : const [],
                        ),
                        onTap: () => _openTable(
                          table.number,
                          canBills: canBills,
                          canCreate: canCreate,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  void _openTable(
    int number, {
    required bool canBills,
    required bool canCreate,
  }) {
    showBrandSheet<void>(
      context,
      builder: (sheet) => _TableSheet(
        number: number,
        canBills: canBills,
        canCreate: canCreate,
        parent: context,
      ),
    );
  }

  static DateTime _readyAt(RestaurantOrder order) =>
      order.statusTimes[OrderStatus.readyToServe] ?? order.createdAt;
}

/// Bills for [table] that still have money due, from today's service.
List<Invoice> _dueBills(BillingController billing, int table, DateTime now) =>
    billing.invoices
        .where(
          (i) =>
              i.tableNumber == table &&
              !i.isVoid &&
              i.outstanding.paise > 0 &&
              now.difference(i.createdAt) < const Duration(hours: 12),
        )
        .toList(growable: false);

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.section, required this.onEdit});

  final Set<int> section;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final sorted = section.toList()..sort();
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.orangeSoft,
        borderRadius: AppRadii.card,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.table_restaurant_rounded,
            size: 20,
            color: AppColors.orangeText,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              sorted.isEmpty
                  ? 'Showing every table. Pick the tables you are covering '
                        'to focus the board.'
                  : 'My tables: ${sorted.map(AppFormat.table).join(', ')}',
              style: AppTypography.label.copyWith(color: AppColors.orangeText),
            ),
          ),
          TextButton(
            onPressed: onEdit,
            child: Text(sorted.isEmpty ? 'Choose' : 'Edit'),
          ),
        ],
      ),
    );
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({super.key, required this.order, required this.waiting});

  final RestaurantOrder order;
  final Duration waiting;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final busy = context.select<OrderController, bool>(
      (orders) => orders.isBusy(order.id),
    );
    final late = waiting > ServiceScreen.readyTooLong;
    final minutes = waiting.inMinutes;
    return Container(
      decoration: BoxDecoration(
        color: late ? AppColors.primarySoft : AppColors.successSoft,
        borderRadius: AppRadii.card,
        border: Border.all(
          color: (late ? AppColors.primary : AppColors.success).withValues(
            alpha: 0.35,
          ),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TableBadge(number: order.tableNumber, late: late),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppFormat.orderNumber(order.id),
                        style: AppTypography.cardTitle,
                      ),
                    ),
                    Text(
                      minutes < 1 ? 'Ready now' : 'Ready $minutes min',
                      style: AppTypography.label.copyWith(
                        color: late ? AppColors.primary : AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final line in order.lines)
                  Text(
                    '${line.quantity} × ${line.name}',
                    style: AppTypography.body,
                  ),
                if (order.specialInstructions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ${order.specialInstructions}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.orangeText,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                if (admin.can(Permission.serveOrders))
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      onPressed: busy
                          ? null
                          : () => advanceOrder(context, order),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(
                        'Served at table ${AppFormat.table(order.tableNumber)}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableBadge extends StatelessWidget {
  const _TableBadge({required this.number, this.late = false});

  final int number;
  final bool late;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: late ? AppColors.primary : AppColors.success,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TABLE',
            style: AppTypography.overline.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 8,
            ),
          ),
          Text(
            AppFormat.table(number),
            style: AppTypography.headline.copyWith(
              color: Colors.white,
              fontSize: 20,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CookingRow extends StatelessWidget {
  const _CookingRow({required this.order, required this.now});

  final RestaurantOrder order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final eta = order.estimatedReadyAt.difference(now).inMinutes;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: () => pushAdminPage<void>(
        context,
        AdminOrderDetailScreen(orderId: order.id),
        permission: Permission.viewOrders,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                'T${AppFormat.table(order.tableNumber)}',
                style: AppTypography.cardTitle,
              ),
            ),
            Expanded(
              child: Text(
                '${AppFormat.orderNumber(order.id)} · '
                '${AppFormat.itemCount(order.itemCount)}',
                style: AppTypography.bodySecondary,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(eta > 0 ? '~$eta min' : 'Due', style: AppTypography.caption),
            const SizedBox(width: AppSpacing.sm),
            OrderStatusBadge(status: order.status),
          ],
        ),
      ),
    );
  }
}

/// What a table needs right now, for its tile.
enum _TableState {
  free('Free', AppColors.textSecondary, AppColors.softWhite),
  ordering('Ordered', AppColors.info, AppColors.infoSoft),
  ready('Ready', AppColors.success, AppColors.successSoft),
  billDue('Bill due', AppColors.orangeText, AppColors.orangeSoft);

  const _TableState(this.label, this.color, this.background);

  final String label;
  final Color color;
  final Color background;

  static _TableState of(
    int table,
    List<RestaurantOrder> active,
    List<Invoice> dueBills,
  ) {
    if (active.any((o) => o.status == OrderStatus.readyToServe)) return ready;
    if (active.isNotEmpty) return ordering;
    if (dueBills.isNotEmpty) return billDue;
    return free;
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.state,
    required this.onTap,
  });

  final RestaurantTable table;
  final _TableState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Table ${table.number}, ${state.label}',
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medium),
        width: 92,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: state.background,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: state.color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppFormat.table(table.number),
              style: AppTypography.headline.copyWith(fontSize: 20),
            ),
            Text(
              state.label,
              style: AppTypography.caption.copyWith(
                color: state.color,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${table.seats} seats',
              style: AppTypography.caption.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableSheet extends StatelessWidget {
  const _TableSheet({
    required this.number,
    required this.canBills,
    required this.canCreate,
    required this.parent,
  });

  final int number;
  final bool canBills;
  final bool canCreate;

  /// The board's context, still mounted after the sheet closes.
  final BuildContext parent;

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderController>().activeForTable(number);
    final bills = canBills
        ? _dueBills(context.watch<BillingController>(), number, DateTime.now())
        : const <Invoice>[];
    void open(Widget page, Permission permission) {
      Navigator.pop(context);
      pushAdminPage<void>(parent, page, permission: permission);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Table ${AppFormat.table(number)}',
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.md),
            if (orders.isEmpty && bills.isEmpty)
              Text(
                'No open orders or bills.',
                style: AppTypography.bodySecondary,
              ),
            for (final order in orders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_rounded),
                title: Text(AppFormat.orderNumber(order.id)),
                subtitle: Text(AppFormat.itemCount(order.itemCount)),
                trailing: OrderStatusBadge(status: order.status),
                onTap: () => open(
                  AdminOrderDetailScreen(orderId: order.id),
                  Permission.viewOrders,
                ),
              ),
            for (final bill in bills)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.request_quote_rounded),
                title: Text(bill.billNumber),
                subtitle: Text(
                  '${CurrencyFormatter.format(bill.outstanding)} due',
                ),
                trailing: PaymentStatusBadge(status: bill.status),
                onTap: () => open(
                  AdminBillDetailScreen(invoiceId: bill.id),
                  Permission.viewBills,
                ),
              ),
            if (canCreate) ...[
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'New order for this table',
                icon: Icons.add_rounded,
                onPressed: () => open(
                  NewOrderScreen(initialTable: number),
                  Permission.createOrders,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionPicker extends StatefulWidget {
  const _SectionPicker({required this.tables, required this.initial});

  final List<int> tables;
  final Set<int> initial;

  @override
  State<_SectionPicker> createState() => _SectionPickerState();
}

class _SectionPickerState extends State<_SectionPicker> {
  late final Set<int> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('My tables', style: AppTypography.sectionTitle),
            Text(
              'Saved on this device for you. Leave all unselected to see '
              'every table.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final table in widget.tables)
                      FilterChip(
                        label: Text(AppFormat.table(table)),
                        selected: _picked.contains(table),
                        onSelected: (on) => setState(
                          () => on ? _picked.add(table) : _picked.remove(table),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'All tables',
                    onPressed: () => Navigator.pop(context, <int>{}),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: 'Save',
                    onPressed: () => Navigator.pop(context, _picked),
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
