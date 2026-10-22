import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../widgets/admin_widgets.dart';
import 'dish_editor_screen.dart';

enum _Tab { dishes, categories }

enum _DishFilter {
  all('All'),
  available('Available'),
  soldOut('Sold out'),
  archived('Archived');

  const _DishFilter(this.label);

  final String label;

  bool matches(MenuItem item) => switch (this) {
    _DishFilter.all => !item.isArchived,
    _DishFilter.available => !item.isArchived && item.isAvailable,
    _DishFilter.soldOut => !item.isArchived && !item.isAvailable,
    _DishFilter.archived => item.isArchived,
  };
}

/// Dishes and categories. Edits appear in the guest menu right away.
class MenuAdminScreen extends StatefulWidget {
  const MenuAdminScreen({super.key});

  @override
  State<MenuAdminScreen> createState() => _MenuAdminScreenState();
}

class _MenuAdminScreenState extends State<MenuAdminScreen> {
  final _search = TextEditingController();
  _Tab _tab = _Tab.dishes;
  _DishFilter _filter = _DishFilter.all;
  String? _categoryId;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final catalog = context.watch<CatalogController>();
    final canEdit = admin.can(Permission.manageMenu);
    final canEditCategories = admin.can(Permission.manageCategories);
    return AdminPage(
      title: 'Menu',
      subtitle:
          '${catalog.allItems.where((i) => !i.isArchived).length} dishes · '
          '${catalog.allCategories.length} categories',
      actions: [
        if (_tab == _Tab.dishes && canEdit)
          PrimaryButton(
            label: 'Add dish',
            icon: Icons.add_rounded,
            expand: false,
            height: 44,
            onPressed: () => pushAdminPage<void>(
              context,
              const DishEditorScreen(),
              permission: Permission.manageMenu,
            ),
          ),
        if (_tab == _Tab.categories && canEditCategories)
          PrimaryButton(
            label: 'Add category',
            icon: Icons.add_rounded,
            expand: false,
            height: 44,
            onPressed: () => _editCategory(context, null),
          ),
      ],
      children: [
        SegmentedButton<_Tab>(
          segments: const [
            ButtonSegment(
              value: _Tab.dishes,
              label: Text('Dishes'),
              icon: Icon(Icons.restaurant_rounded),
            ),
            ButtonSegment(
              value: _Tab.categories,
              label: Text('Categories'),
              icon: Icon(Icons.category_rounded),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (value) => setState(() => _tab = value.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.primarySoft,
            selectedForegroundColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_tab == _Tab.dishes)
          ..._dishes(context, catalog, canEdit)
        else
          ..._categories(context, catalog, canEditCategories),
      ],
    );
  }

  List<Widget> _dishes(
    BuildContext context,
    CatalogController catalog,
    bool canEdit,
  ) {
    final q = _query.trim().toLowerCase();
    final dishes =
        catalog.allItems
            .where(
              (item) =>
                  _filter.matches(item) &&
                  (_categoryId == null || item.category.id == _categoryId) &&
                  (q.isEmpty || item.name.toLowerCase().contains(q)),
            )
            .toList()
          ..sort((a, b) {
            final c = a.category.sortOrder.compareTo(b.category.sortOrder);
            return c != 0 ? c : a.name.compareTo(b.name);
          });
    return [
      AdminSearchField(
        controller: _search,
        hint: 'Search dishes',
        onChanged: (value) => setState(() => _query = value),
      ),
      const SizedBox(height: AppSpacing.md),
      FilterChipBar<_DishFilter>(
        values: _DishFilter.values,
        selected: _filter,
        labelOf: (f) => f.label,
        countOf: (f) => catalog.allItems.where(f.matches).length,
        onSelected: (f) => setState(() => _filter = f),
      ),
      const SizedBox(height: AppSpacing.sm),
      FilterChipBar<String?>(
        values: [null, for (final c in catalog.allCategories) c.id],
        selected: _categoryId,
        labelOf: (id) => id == null
            ? 'All categories'
            : catalog.categoryById(id)?.label ?? id,
        onSelected: (id) => setState(() => _categoryId = id),
      ),
      const SizedBox(height: AppSpacing.lg),
      if (dishes.isEmpty)
        const AdminEmpty(
          icon: Icons.no_food_outlined,
          title: 'No dishes here',
          message: 'Try another filter, or add a dish.',
        )
      else
        SectionCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: [
              for (final (index, item) in dishes.indexed) ...[
                if (index > 0) const Divider(),
                FadeSlideIn(
                  key: ValueKey(item.id),
                  index: index,
                  child: _DishRow(item: item, canEdit: canEdit),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  List<Widget> _categories(
    BuildContext context,
    CatalogController catalog,
    bool canEdit,
  ) {
    final categories = catalog.allCategories;
    return [
      if (canEdit)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'Drag to change the order guests see. Hidden categories and their '
            'dishes are not shown to guests.',
            style: AppTypography.caption,
          ),
        ),
      SectionCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            if (!canEdit) return;
            final ids = [for (final c in categories) c.id];
            ids.insert(newIndex, ids.removeAt(oldIndex));
            runAdminAction(context, () => catalog.reorderCategories(ids));
          },
          children: [
            for (final (index, category) in categories.indexed)
              ListTile(
                key: ValueKey(category.id),
                leading: canEdit
                    ? ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator_rounded),
                      )
                    : null,
                title: Text(category.label, style: AppTypography.cardTitle),
                subtitle: Text(
                  '${catalog.dishCountIn(category.id)} dishes'
                  '${category.isActive ? '' : ' · hidden from guests'}',
                  style: AppTypography.caption,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: category.isActive,
                      activeThumbColor: AppColors.primary,
                      onChanged: canEdit
                          ? (value) => runAdminAction(
                              context,
                              () =>
                                  catalog.setCategoryActive(category.id, value),
                            )
                          : null,
                    ),
                    if (canEdit)
                      PopupMenuButton<String>(
                        tooltip: 'Category actions',
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await _editCategory(context, category);
                          } else if (value == 'delete') {
                            final ok = await showConfirmDialog(
                              context,
                              title: 'Delete ${category.label}?',
                              message:
                                  'Only empty categories can be deleted. This '
                                  'cannot be undone.',
                              confirmLabel: 'Delete',
                              icon: Icons.delete_outline_rounded,
                            );
                            if (ok && context.mounted) {
                              await runAdminAction(
                                context,
                                () => catalog.deleteCategory(category.id),
                                success: '${category.label} deleted',
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Future<void> _editCategory(
    BuildContext context,
    MenuCategory? category,
  ) async {
    final catalog = context.read<CatalogController>();
    final result = await showDialog<MenuCategory>(
      context: context,
      builder: (_) => _CategoryDialog(
        category: category,
        newId: category == null ? catalog.newCategoryId('category') : null,
      ),
    );
    if (result == null || !context.mounted) return;
    final saved = category == null
        ? MenuCategory(
            id: catalog.newCategoryId(result.label),
            label: result.label,
            coverImage: result.coverImage,
          )
        : result;
    await runAdminAction(
      context,
      () => catalog.saveCategory(saved),
      success: 'Saved ${saved.label}',
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.item, required this.canEdit});

  final MenuItem item;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<CatalogController>();
    return InkWell(
      onTap: canEdit
          ? () => pushAdminPage<void>(
              context,
              DishEditorScreen(itemId: item.id),
              permission: Permission.manageMenu,
            )
          : null,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Opacity(
              opacity: item.isArchived || !item.isAvailable ? 0.5 : 1,
              child: FoodImage(
                item.image,
                width: 52,
                height: 52,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      VegIndicator(isVeg: item.isVeg, size: 11),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.cardTitle,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    [
                      item.category.label,
                      CurrencyFormatter.format(item.price),
                      if (item.isArchived) 'Archived',
                      if (!item.isArchived && !item.isAvailable) 'Sold out',
                    ].join(' · '),
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            if (!item.isArchived)
              Semantics(
                label: 'Available',
                child: Switch(
                  value: item.isAvailable,
                  activeThumbColor: AppColors.success,
                  onChanged: canEdit
                      ? (value) => runAdminAction(
                          context,
                          () => catalog.setAvailable(item.id, value),
                          success: value
                              ? '${item.name} is available'
                              : '${item.name} marked sold out',
                        )
                      : null,
                ),
              )
            else if (canEdit)
              TextButton(
                onPressed: () => runAdminAction(
                  context,
                  () => catalog.setArchived(item.id, false),
                  success: '${item.name} restored',
                ),
                child: const Text('Restore'),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.category, required this.newId});

  final MenuCategory? category;
  final String? newId;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.label ?? '',
  );
  late String _cover = widget.category?.coverImage ?? '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.category;
    return AlertDialog(
      title: Text(
        existing == null ? 'New category' : 'Edit category',
        style: AppTypography.sectionTitle,
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Cover photo', style: AppTypography.label),
              const SizedBox(height: AppSpacing.sm),
              PhotoPicker(
                selected: _cover,
                onSelected: (value) => setState(() => _cover = value),
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
          onPressed: () => Navigator.pop(
            context,
            existing?.copyWith(label: _name.text, coverImage: _cover) ??
                MenuCategory(
                  id: widget.newId ?? 'category',
                  label: _name.text,
                  coverImage: _cover,
                ),
          ),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
