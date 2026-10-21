import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/inventory.dart';
import '../../state/catalog_controller.dart';
import '../../state/inventory_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/admin_widgets.dart';

enum _StockFilter {
  all('All'),
  low('Low'),
  out('Out of stock');

  const _StockFilter(this.label);

  final String label;

  bool matches(InventoryItem i) => switch (this) {
    _StockFilter.all => true,
    _StockFilter.low => i.isLow,
    _StockFilter.out => i.isOutOfStock,
  };
}

/// Ingredients and supplies. Stock changes only through recorded
/// adjustments.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  _StockFilter _filter = _StockFilter.all;

  Future<void> _edit(InventoryItem? item) async {
    final inventory = context.read<InventoryController>();
    final result = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => _ItemDialog(item: item),
    );
    if (result == null || !mounted) return;
    // New items get an id from their final name.
    final toSave = item == null
        ? InventoryItem(
            id: inventory.newItemId(result.name),
            name: result.name,
            unit: result.unit,
            quantity: result.quantity,
            reorderLevel: result.reorderLevel,
            updatedAt: DateTime.now(),
            supplier: result.supplier,
            linkedDishIds: result.linkedDishIds,
          )
        : result;
    await runAdminAction(
      context,
      () => inventory.saveItem(toSave),
      success: 'Saved ${toSave.name.trim()}',
    );
  }

  Future<void> _adjust(InventoryItem item) async {
    final result = await showDialog<({double change, String reason})>(
      context: context,
      builder: (_) => _AdjustDialog(item: item),
    );
    if (result == null || !mounted) return;
    await runAdminAction(
      context,
      () => context.read<InventoryController>().adjust(
        item.id,
        result.change,
        result.reason,
      ),
      success: 'Stock updated',
    );
  }

  void _history(InventoryItem item) {
    showBrandSheet<void>(
      context,
      builder: (_) => _HistorySheet(itemId: item.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();
    final autoRule = context
        .watch<SettingsController>()
        .settings
        .autoUnavailableWhenOutOfStock;
    final items = inventory.items.where(_filter.matches).toList();
    return AdminPage(
      title: 'Inventory',
      subtitle:
          '${inventory.items.length} items · ${inventory.lowStock.length} need attention',
      actions: [
        PrimaryButton(
          label: 'Add item',
          icon: Icons.add_rounded,
          expand: false,
          height: 44,
          onPressed: () => _edit(null),
        ),
      ],
      children: [
        Text(
          'Stock changes only through the adjustments you record; nothing is '
          'deducted automatically from orders.'
          '${autoRule ? ' Dishes linked to an item are marked sold out when it '
                    'runs out and available again when restocked.' : ''}',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        FilterChipBar<_StockFilter>(
          values: _StockFilter.values,
          selected: _filter,
          labelOf: (f) => f.label,
          countOf: (f) => inventory.items.where(f.matches).length,
          onSelected: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (items.isEmpty)
          const AdminEmpty(
            icon: Icons.inventory_2_outlined,
            title: 'Nothing here',
            message: 'Add items to track their stock.',
          )
        else
          for (final (index, item) in items.indexed)
            FadeSlideIn(
              key: ValueKey(item.id),
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _ItemCard(
                  item: item,
                  onAdjust: () => _adjust(item),
                  onEdit: () => _edit(item),
                  onHistory: () => _history(item),
                ),
              ),
            ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onAdjust,
    required this.onEdit,
    required this.onHistory,
  });

  final InventoryItem item;
  final VoidCallback onAdjust;
  final VoidCallback onEdit;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final (label, color) = item.isOutOfStock
        ? ('Out of stock', AppColors.error)
        : item.isLow
        ? ('Low', AppColors.warning)
        : ('In stock', AppColors.success);
    final catalog = context.read<CatalogController>();
    final dishes = [
      for (final id in item.linkedDishIds) catalog.byId(id)?.name ?? id,
    ];
    final fraction = item.reorderLevel <= 0
        ? 1.0
        : (item.quantity / (item.reorderLevel * 2)).clamp(0.0, 1.0);
    return SectionCard(
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
                            item.name,
                            style: AppTypography.cardTitle,
                          ),
                        ),
                        if (item.isDemoSample) ...[
                          const SizedBox(width: 6),
                          const DemoTag(label: 'SAMPLE'),
                        ],
                      ],
                    ),
                    Text(
                      [
                        'Reorder at ${InventoryController.format(item.reorderLevel)} ${item.unit}',
                        if (item.supplier.isNotEmpty) item.supplier,
                        'Updated ${AppFormat.dateTime(item.updatedAt)}',
                      ].join(' · '),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${InventoryController.format(item.quantity)} ${item.unit}',
                    style: AppTypography.headline.copyWith(
                      fontSize: 20,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: AppTypography.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadii.pill,
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: color,
              backgroundColor: AppColors.skeleton,
            ),
          ),
          if (dishes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Used in: ${dishes.join(', ')}', style: AppTypography.caption),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                onPressed: onAdjust,
                icon: const Icon(Icons.exposure_rounded, size: 18),
                label: const Text('Adjust stock'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: onHistory,
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('History'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.item});

  final InventoryItem item;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  bool _adding = true;
  String _reason = 'Delivery received';
  String? _error;

  static const _addReasons = ['Delivery received', 'Count correction'];
  static const _removeReasons = [
    'Used in kitchen',
    'Wasted',
    'Count correction',
  ];

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a quantity above zero.');
      return;
    }
    if (!_adding && value > widget.item.quantity) {
      setState(
        () => _error =
            'Only ${InventoryController.format(widget.item.quantity)} '
            '${widget.item.unit} in stock.',
      );
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(context, (
      change: _adding ? value : -value,
      reason: note.isEmpty ? _reason : '$_reason: $note',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final reasons = _adding ? _addReasons : _removeReasons;
    return AlertDialog(
      title: Text(
        'Adjust ${widget.item.name}',
        style: AppTypography.sectionTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'In stock: ${InventoryController.format(widget.item.quantity)} '
              '${widget.item.unit}',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Add'),
                  icon: Icon(Icons.add_rounded),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Remove'),
                  icon: Icon(Icons.remove_rounded),
                ),
              ],
              selected: {_adding},
              onSelectionChanged: (value) => setState(() {
                _adding = value.first;
                _reason = (_adding ? _addReasons : _removeReasons).first;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _quantity,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantity',
                suffixText: widget.item.unit,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: [
                for (final r in reasons)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (value) => setState(() => _reason = value ?? _reason),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _note,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.item});

  final InventoryItem? item;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _quantity = TextEditingController(
    text: widget.item == null
        ? ''
        : InventoryController.format(widget.item!.quantity),
  );
  late final _reorder = TextEditingController(
    text: widget.item == null
        ? ''
        : InventoryController.format(widget.item!.reorderLevel),
  );
  late final _supplier = TextEditingController(
    text: widget.item?.supplier ?? '',
  );
  late String _unit = widget.item?.unit ?? 'kg';
  late final Set<String> _dishes = {...?widget.item?.linkedDishIds};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _reorder.dispose();
    _supplier.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity =
        widget.item?.quantity ??
        double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    final reorder = double.tryParse(_reorder.text.trim().replaceAll(',', '.'));
    if (quantity == null || reorder == null) {
      setState(() => _error = 'Enter numbers for quantity and reorder level.');
      return;
    }
    final base = widget.item;
    Navigator.pop(
      context,
      base == null
          ? InventoryItem(
              id: 'new',
              name: _name.text,
              unit: _unit,
              quantity: quantity,
              reorderLevel: reorder,
              updatedAt: DateTime.now(),
              supplier: _supplier.text.trim(),
              linkedDishIds: _dishes.toList(),
            )
          : base.copyWith(
              name: _name.text,
              unit: _unit,
              reorderLevel: reorder,
              supplier: _supplier.text.trim(),
              linkedDishIds: _dishes.toList(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dishes = context.read<CatalogController>().allItems.where(
      (d) => !d.isArchived,
    );
    return AlertDialog(
      title: Text(
        widget.item == null
            ? 'New inventory item'
            : 'Edit ${widget.item!.name}',
        style: AppTypography.sectionTitle,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantity,
                      enabled: widget.item == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: widget.item == null
                            ? 'Opening stock'
                            : 'Stock (use Adjust)',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  DropdownButton<String>(
                    value: _unit,
                    items: [
                      for (final u in InventoryController.units)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (value) =>
                        setState(() => _unit = value ?? _unit),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _reorder,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Reorder level'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _supplier,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Supplier (optional)',
                ),
              ),
              Text('Linked dishes (optional)', style: AppTypography.label),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final dish in dishes)
                    FilterChip(
                      label: Text(dish.name),
                      selected: _dishes.contains(dish.id),
                      selectedColor: AppColors.primarySoft,
                      checkmarkColor: AppColors.primary,
                      onSelected: (on) => setState(() {
                        if (on) {
                          _dishes.add(dish.id);
                        } else {
                          _dishes.remove(dish.id);
                        }
                      }),
                    ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();
    final item = inventory.byId(itemId);
    final moves = inventory.movementsFor(itemId);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${item?.name ?? 'Item'} history',
            style: AppTypography.screenTitle,
          ),
          const SizedBox(height: AppSpacing.md),
          if (moves.isEmpty)
            const AdminEmpty(
              icon: Icons.history_rounded,
              title: 'No adjustments yet',
              message: 'Stock changes you record appear here.',
            )
          else
            for (final m in moves)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  m.change > 0
                      ? Icons.add_circle_outline_rounded
                      : Icons.remove_circle_outline_rounded,
                  color: m.change > 0 ? AppColors.success : AppColors.primary,
                ),
                title: Text(
                  '${m.change > 0 ? '+' : ''}${InventoryController.format(m.change)} '
                  '${item?.unit ?? ''} · ${m.reason}',
                  style: AppTypography.label,
                ),
                subtitle: Text(
                  '${AppFormat.dateTime(m.at)}'
                  '${m.by.isEmpty ? '' : ' · ${m.by}'} · balance '
                  '${InventoryController.format(m.balance)}',
                  style: AppTypography.caption,
                ),
              ),
        ],
      ),
    );
  }
}
