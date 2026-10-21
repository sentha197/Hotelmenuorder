import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/brand_assets.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/file_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/table_qr_code.dart';
import '../../data/models/restaurant_settings.dart';
import '../../data/models/staff.dart';
import '../../data/services/receipt_pdf.dart';
import '../../features/qr_scanner/table_qr_parser.dart';
import '../../state/admin_session_controller.dart';
import '../../state/billing_controller.dart';
import '../../state/order_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/admin_widgets.dart';

enum TableState {
  available('Available', AppColors.success),
  occupied('Occupied', AppColors.warning),
  billDue('Bill due', AppColors.primary),
  inactive('Inactive', AppColors.textMuted);

  const TableState(this.label, this.color);

  final String label;
  final Color color;
}

/// Tables, their live status and QR codes.
class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  static Future<void> _printAll(BuildContext context) =>
      runAdminAction(context, () async {
        final settings = context.read<SettingsController>();
        final active = settings.tables.where((t) => t.isActive).toList();
        if (active.isEmpty) {
          throw const ValidationException('There are no active tables.');
        }
        final bytes = await TableQrPdf.build(
          active,
          restaurantName: settings.settings.name,
          payloadFor: TableQrParser.payloadFor,
          logoPng: await BrandAssets.logoPng(),
        );
        await FileExport.printPdf(bytes, 'DineQR table QR codes');
      });

  Future<void> _addTable(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final next = settings.tables.isEmpty ? 1 : settings.tables.last.number + 1;
    final result = await showDialog<RestaurantTable>(
      context: context,
      builder: (_) => _TableDialog(table: RestaurantTable(number: next)),
    );
    if (result == null || !context.mounted) return;
    await runAdminAction(
      context,
      () => settings.addTable(
        result.number,
        seats: result.seats,
        area: result.area,
      ),
      success: 'Table ${AppFormat.table(result.number)} added',
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final tables = context.watch<SettingsController>().tables;
    final orders = context.watch<OrderController>();
    final billing = context.watch<BillingController>();
    final canEdit = admin.can(Permission.manageTables);
    TableState stateOf(RestaurantTable t) {
      if (!t.isActive) return TableState.inactive;
      if (orders.activeForTable(t.number).isNotEmpty) {
        return TableState.occupied;
      }
      final due = billing.invoices.any(
        (i) => i.tableNumber == t.number && !i.outstanding.isZero,
      );
      return due ? TableState.billDue : TableState.available;
    }

    final counts = {
      for (final s in TableState.values)
        s: tables.where((t) => stateOf(t) == s).length,
    };
    return AdminPage(
      title: 'Tables & QR codes',
      subtitle:
          '${tables.length} tables · ${counts[TableState.occupied]} occupied',
      actions: [
        if (canEdit) ...[
          IconButton.outlined(
            tooltip: 'Print all QR codes',
            onPressed: () => _printAll(context),
            icon: const Icon(Icons.print_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
          PrimaryButton(
            label: 'Add table',
            icon: Icons.add_rounded,
            expand: false,
            height: 44,
            onPressed: () => _addTable(context),
          ),
        ],
      ],
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            for (final s in TableState.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${s.label} (${counts[s]})', style: AppTypography.label),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 140).floor().clamp(2, 8);
            const gap = AppSpacing.md;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (index, table) in tables.indexed)
                  SizedBox(
                    width: width,
                    child: FadeSlideIn(
                      index: index,
                      child: _TableTile(
                        table: table,
                        state: stateOf(table),
                        openOrders: orders.activeForTable(table.number).length,
                        onTap: () => _showTable(context, table),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Table QR codes contain only "${TableQrParser.payloadFor(5).replaceAll('05', 'NN')}". '
          'They identify where a guest sits and never give access to this '
          'dashboard.',
          style: AppTypography.caption,
        ),
      ],
    );
  }

  void _showTable(BuildContext context, RestaurantTable table) {
    showBrandSheet<void>(
      context,
      builder: (_) => _TableSheet(number: table.number),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.state,
    required this.openOrders,
    required this.onTap,
  });

  final RestaurantTable table;
  final TableState state;
  final int openOrders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel:
          'Table ${table.number}, ${state.label}, ${table.seats} seats',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.card,
          border: Border.all(
            color: state.color.withValues(alpha: 0.5),
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppFormat.table(table.number),
                  style: AppTypography.headline.copyWith(
                    fontSize: 24,
                    color: state == TableState.inactive
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.qr_code_2_rounded, color: AppColors.textMuted),
              ],
            ),
            Text(
              '${table.seats} seats${table.area.isEmpty ? '' : ' · ${table.area}'}',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: state.color.withValues(alpha: 0.1),
                borderRadius: AppRadii.pill,
              ),
              child: Text(
                state == TableState.occupied && openOrders > 1
                    ? '${state.label} · $openOrders orders'
                    : state.label,
                style: AppTypography.caption.copyWith(
                  color: state.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// QR preview and actions for one table.
class _TableSheet extends StatelessWidget {
  const _TableSheet({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final settings = context.watch<SettingsController>();
    final orders = context.watch<OrderController>();
    final billing = context.watch<BillingController>();
    final table = settings.table(number);
    if (table == null) return const SizedBox(height: 120);
    final canEdit = admin.can(Permission.manageTables);
    final payload = TableQrParser.payloadFor(number);
    final open = orders.activeForTable(number);
    final unpaid = billing.invoices
        .where((i) => i.tableNumber == number && !i.outstanding.isZero)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Text(
            'Table ${AppFormat.table(number)}',
            style: AppTypography.headline.copyWith(fontSize: 22),
          ),
          Text(
            '${table.seats} seats${table.area.isEmpty ? '' : ' · ${table.area}'}'
            '${table.isActive ? '' : ' · inactive'}',
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Opacity(
            opacity: table.isActive ? 1 : 0.35,
            child: TableQrCode(
              payload: payload,
              size: 220,
              semanticLabel: 'QR code for table $number',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(payload, style: AppTypography.caption),
          if (!table.isActive)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Guests scanning this code are told the table is not taking '
                'orders.',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: AppColors.primary),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (open.isNotEmpty || unpaid.isNotEmpty)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final o in open)
                    InfoRow(
                      'Order ${o.id}',
                      '${o.status.shortLabel} · ${AppFormat.time(o.createdAt)}',
                    ),
                  for (final i in unpaid)
                    InfoRow(
                      i.billNumber,
                      'Due ${CurrencyFormatter.format(i.outstanding)}',
                      valueColor: AppColors.primary,
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children: [
              SecondaryButton(
                label: 'Print QR',
                icon: Icons.print_outlined,
                expand: false,
                height: 44,
                onPressed: () => runAdminAction(context, () async {
                  final bytes = await TableQrPdf.build(
                    [table],
                    restaurantName: settings.settings.name,
                    payloadFor: TableQrParser.payloadFor,
                    logoPng: await BrandAssets.logoPng(),
                  );
                  await FileExport.printPdf(bytes, 'Table $number QR');
                }),
              ),
              SecondaryButton(
                label: 'Share PDF',
                icon: Icons.ios_share_rounded,
                expand: false,
                height: 44,
                onPressed: () => runAdminAction(context, () async {
                  final bytes = await TableQrPdf.build(
                    [table],
                    restaurantName: settings.settings.name,
                    payloadFor: TableQrParser.payloadFor,
                    logoPng: await BrandAssets.logoPng(),
                  );
                  await FileExport.sharePdf(
                    bytes,
                    'DineQR-table-${AppFormat.table(number)}.pdf',
                  );
                }),
              ),
              if (canEdit) ...[
                SecondaryButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  expand: false,
                  height: 44,
                  onPressed: () async {
                    final result = await showDialog<RestaurantTable>(
                      context: context,
                      builder: (_) => _TableDialog(table: table, editing: true),
                    );
                    if (result == null || !context.mounted) return;
                    await runAdminAction(
                      context,
                      () => settings.updateTable(result),
                      success: 'Table updated',
                    );
                  },
                ),
                SecondaryButton(
                  label: table.isActive ? 'Deactivate' : 'Activate',
                  icon: table.isActive
                      ? Icons.block_outlined
                      : Icons.check_circle_outline_rounded,
                  expand: false,
                  height: 44,
                  onPressed: () => runAdminAction(
                    context,
                    () => settings.setTableActive(number, !table.isActive),
                  ),
                ),
                SecondaryButton(
                  label: 'Remove',
                  icon: Icons.delete_outline_rounded,
                  expand: false,
                  height: 44,
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Remove table $number?',
                      message:
                          'Its QR code will stop working. Past orders and '
                          'bills are kept.',
                      confirmLabel: 'Remove',
                      icon: Icons.delete_outline_rounded,
                    );
                    if (!confirmed || !context.mounted) return;
                    final ok = await runAdminAction(
                      context,
                      () => settings.removeTable(
                        number,
                        hasOpenOrders: open.isNotEmpty || unpaid.isNotEmpty,
                      ),
                      success: 'Table $number removed',
                    );
                    if (ok && context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TableDialog extends StatefulWidget {
  const _TableDialog({required this.table, this.editing = false});

  final RestaurantTable table;
  final bool editing;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late final _number = TextEditingController(text: '${widget.table.number}');
  late final _seats = TextEditingController(text: '${widget.table.seats}');
  late final _area = TextEditingController(text: widget.table.area);
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _seats.dispose();
    _area.dispose();
    super.dispose();
  }

  void _submit() {
    final number = int.tryParse(_number.text.trim());
    final seats = int.tryParse(_seats.text.trim());
    if (number == null || seats == null) {
      setState(() => _error = 'Enter numbers for the table and seats.');
      return;
    }
    final error = SettingsController.validateTable(number, seats);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      RestaurantTable(
        number: number,
        seats: seats,
        area: _area.text.trim(),
        isActive: widget.table.isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.editing
            ? 'Edit table ${AppFormat.table(widget.table.number)}'
            : 'Add table',
        style: AppTypography.sectionTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _number,
            enabled: !widget.editing,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Table number'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _seats,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Seats'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _area,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: 'Area (optional)',
              hintText: 'e.g. Terrace',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(widget.editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
