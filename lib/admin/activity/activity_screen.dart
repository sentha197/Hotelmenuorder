import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/staff.dart';
import '../../state/staff_controller.dart';
import '../widgets/admin_widgets.dart';

enum _Area {
  all('All', ''),
  orders('Orders', 'order.'),
  payments('Payments', 'payment.'),
  menu('Menu', 'menu.|category.'),
  stock('Stock', 'inventory.'),
  tables('Tables', 'table.'),
  staff('Staff', 'staff.'),
  settings('Settings', 'settings.|offer.'),
  access('Sign-ins', 'auth.');

  const _Area(this.label, this.prefixes);

  final String label;
  final String prefixes;

  bool matches(AuditEvent e) =>
      prefixes.isEmpty || prefixes.split('|').any(e.action.startsWith);
}

/// Who changed what, and when (read-only).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _search = TextEditingController();
  _Area _area = _Area.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() => runAdminAction(
    context,
    () => context.read<StaffController>().loadEvents(),
  );

  static IconData _icon(String action) => switch (action.split('.').first) {
    'order' => Icons.receipt_long_rounded,
    'payment' => Icons.payments_rounded,
    'menu' || 'category' => Icons.restaurant_menu_rounded,
    'inventory' => Icons.inventory_2_rounded,
    'table' => Icons.table_restaurant_rounded,
    'staff' => Icons.badge_rounded,
    'settings' || 'offer' => Icons.settings_rounded,
    'auth' => Icons.login_rounded,
    _ => Icons.history_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final events = context.watch<StaffController>().events;
    final q = _query.trim().toLowerCase();
    final shown = events
        .where(
          (e) =>
              _area.matches(e) &&
              (q.isEmpty ||
                  e.summary.toLowerCase().contains(q) ||
                  e.actorName.toLowerCase().contains(q) ||
                  e.targetId.toLowerCase().contains(q)),
        )
        .toList();
    return AdminPage(
      title: 'Activity log',
      subtitle: events.isEmpty
          ? 'Nothing recorded yet'
          : '${events.length} recorded '
                '${events.length == 1 ? 'action' : 'actions'}'
                '${events.length >= 500 ? ' (latest kept)' : ''}',
      onRefresh: _refresh,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        AdminSearchField(
          controller: _search,
          hint: 'Search by person, order, bill or text',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: AppSpacing.md),
        FilterChipBar<_Area>(
          values: _Area.values,
          selected: _area,
          labelOf: (a) => a.label,
          countOf: (a) => events.where(a.matches).length,
          onSelected: (a) => setState(() => _area = a),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (shown.isEmpty)
          const AdminEmpty(
            icon: Icons.history_rounded,
            title: 'Nothing recorded',
            message:
                'Sensitive changes such as refunds, price edits and role '
                'changes appear here.',
          )
        else
          SectionCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                for (final (index, event) in shown.take(200).indexed) ...[
                  if (index > 0) const Divider(),
                  FadeSlideIn(
                    index: index,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primarySoft,
                        child: Icon(
                          _icon(event.action),
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(event.summary, style: AppTypography.label),
                      subtitle: Text(
                        '${event.actorName} (${event.actorRole}) · '
                        '${AppFormat.dateTime(event.at)}',
                        style: AppTypography.caption,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
