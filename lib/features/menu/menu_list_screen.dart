import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/food_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/menu_filter.dart';
import '../../data/models/menu_item.dart';
import '../../state/catalog_controller.dart';
import '../../state/shell_controller.dart';
import 'menu_widgets.dart';

/// Screen 5: full menu / category list with diet filters, search and sort.
/// Used both as the "Menu" tab ([embedded]) and as a pushed category page.
class MenuListScreen extends StatefulWidget {
  const MenuListScreen({
    super.key,
    this.initialCategory,
    this.favoritesOnly = false,
    this.embedded = false,
  });

  final MenuCategory? initialCategory;
  final bool favoritesOnly;
  final bool embedded;

  @override
  State<MenuListScreen> createState() => _MenuListScreenState();
}

class _MenuListScreenState extends State<MenuListScreen> {
  late MenuFilter _filter = MenuFilter(
    category: widget.initialCategory,
    favoritesOnly: widget.favoritesOnly,
  );
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchOpen = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _update(MenuFilter filter) => setState(() => _filter = filter);

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchFocus.requestFocus();
    } else {
      _search.clear();
      _searchFocus.unfocus();
      _update(_filter.copyWith(query: ''));
    }
  }

  String get _title {
    if (widget.favoritesOnly) return 'My Favorites';
    return _filter.category?.label ?? 'Our Menu';
  }

  /// Hero tags must be unique per route, so include where this list lives.
  String get _heroPrefix => widget.embedded ? 'menu-tab' : 'menu-page';

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final items = catalog.filter(_filter);

    return Scaffold(
      resizeToAvoidBottomInset: !widget.embedded,
      appBar: AppBar(
        leading: AppBackButton(
          onPressed: widget.embedded
              ? () => context.read<ShellController>().select(ShellTab.home)
              : null,
        ),
        title: AnimatedSwitcher(
          duration: Motion.of(context, Motion.fast),
          child: Text(_title, key: ValueKey(_title)),
        ),
        actions: [
          IconButton(
            tooltip: _searchOpen ? 'Close search' : 'Search dishes',
            onPressed: _toggleSearch,
            icon: AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                key: ValueKey(_searchOpen),
              ),
            ),
          ),
          _SortButton(
            value: _filter.sort,
            onSelected: (sort) => _update(_filter.copyWith(sort: sort)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: Motion.of(context, Motion.medium),
            curve: Motion.standard,
            child: _searchOpen
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      AppSpacing.xs,
                      AppSpacing.page,
                      AppSpacing.sm,
                    ),
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) =>
                          _update(_filter.copyWith(query: value)),
                      onSubmitted: (_) => _searchFocus.unfocus(),
                      decoration: const InputDecoration(
                        hintText: 'Search in this menu...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (!widget.favoritesOnly)
            _CategoryTabs(
              selected: _filter.category,
              countFor: catalog.countIn,
              onSelected: (category) =>
                  _update(_filter.copyWith(category: () => category)),
            ),
          _DietChips(
            selected: _filter.diet,
            resultCount: catalog.state == LoadState.ready ? items.length : null,
            onSelected: (diet) => _update(_filter.copyWith(diet: diet)),
          ),
          const Divider(),
          Expanded(child: _buildList(catalog, items)),
        ],
      ),
    );
  }

  Widget _buildList(CatalogController catalog, List<MenuItem> items) {
    if (catalog.state == LoadState.loading) {
      return const SingleChildScrollView(child: FoodListSkeleton());
    }
    if (catalog.state == LoadState.error) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Menu unavailable',
        message: 'We could not load the menu. Please try again.',
        actionLabel: 'Retry',
        onAction: () => catalog.load(force: true),
      );
    }
    if (items.isEmpty) {
      if (widget.favoritesOnly && _filter.isDefault) {
        return EmptyState(
          icon: Icons.favorite_border_rounded,
          title: 'No favorites yet',
          message: 'Tap the heart on any dish to save it here.',
          actionLabel: 'Browse Menu',
          onAction: () => AppNav.goToTab(context, ShellTab.menu),
        );
      }
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No dishes match',
        message: 'Try a different filter or search term.',
        actionLabel: 'Clear filters',
        onAction: () {
          _search.clear();
          _update(
            MenuFilter(
              category: _filter.category,
              favoritesOnly: widget.favoritesOnly,
            ),
          );
        },
      );
    }
    final listKey = ValueKey(
      '${_filter.category}-${_filter.diet}-${_filter.sort}-${_filter.query.trim()}',
    );
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      child: ListView.separated(
        key: listKey,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(
          top: AppSpacing.xs,
          bottom: AppSpacing.xxl,
        ),
        itemCount: items.length,
        separatorBuilder: (context, index) =>
            const Divider(indent: AppSpacing.page, endIndent: AppSpacing.page),
        itemBuilder: (context, index) => FadeSlideIn(
          index: index,
          child: FoodListTile(
            item: items[index],
            heroTag: '$_heroPrefix-${items[index].id}',
          ),
        ),
      ),
    );
  }
}

/// Category pills. The selected pill fills with the brand gradient.
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.selected,
    required this.countFor,
    required this.onSelected,
  });

  final MenuCategory? selected;
  final int Function(MenuCategory? category) countFor;
  final ValueChanged<MenuCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <MenuCategory?>[null, ...MenuCategory.values];
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          4,
          AppSpacing.page,
          6,
        ),
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = options[index];
          final isSelected = category == selected;
          final label = category?.label ?? 'All';
          final count = countFor(category);
          return Semantics(
            selected: isSelected,
            button: true,
            label: '$label, $count dishes',
            excludeSemantics: true,
            child: Pressable(
              onTap: () => onSelected(category),
              scale: 0.94,
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.medium),
                curve: Motion.standard,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? null : AppColors.paleWarm,
                  gradient: isSelected ? AppColors.ctaGradient : null,
                  borderRadius: AppRadii.pill,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: Motion.of(context, Motion.fast),
                      style: AppTypography.label.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      child: Text(label),
                    ),
                    const SizedBox(width: 6),
                    AnimatedContainer(
                      duration: Motion.of(context, Motion.medium),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.white,
                        borderRadius: AppRadii.pill,
                      ),
                      child: Text(
                        '$count',
                        style: AppTypography.caption.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DietChips extends StatelessWidget {
  const _DietChips({
    required this.selected,
    required this.onSelected,
    required this.resultCount,
  });

  final DietFilter selected;
  final ValueChanged<DietFilter> onSelected;
  final int? resultCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final diet in DietFilter.values) ...[
                    _DietChip(
                      diet: diet,
                      selected: diet == selected,
                      onTap: () => onSelected(diet),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
          if (resultCount != null)
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              child: Text(
                '$resultCount ${resultCount == 1 ? 'dish' : 'dishes'}',
                key: ValueKey(resultCount),
                style: AppTypography.caption,
              ),
            ),
        ],
      ),
    );
  }
}

/// Diet filter chip, tinted green for veg and red for non-veg when active.
class _DietChip extends StatelessWidget {
  const _DietChip({
    required this.diet,
    required this.selected,
    required this.onTap,
  });

  final DietFilter diet;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (tint, soft) = switch (diet) {
      DietFilter.all => (AppColors.charcoal, AppColors.softWhite),
      DietFilter.veg => (AppColors.veg, AppColors.successSoft),
      DietFilter.nonVeg => (AppColors.nonVeg, AppColors.primarySoft),
    };
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.standard,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? soft : Colors.white,
            borderRadius: AppRadii.pill,
            border: Border.all(
              color: selected ? tint : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (diet != DietFilter.all) ...[
                VegIndicator(isVeg: diet == DietFilter.veg, size: 12),
                const SizedBox(width: 6),
              ],
              Text(
                diet.label,
                style: AppTypography.label.copyWith(
                  color: selected ? tint : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.value, required this.onSelected});

  final MenuSort value;
  final ValueChanged<MenuSort> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MenuSort>(
      tooltip: 'Sort dishes',
      initialValue: value,
      onSelected: onSelected,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Badge(
        isLabelVisible: value != MenuSort.popularity,
        smallSize: 8,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.tune_rounded),
      ),
      itemBuilder: (context) => [
        for (final sort in MenuSort.values)
          PopupMenuItem(
            value: sort,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sort.label,
                    style: AppTypography.label.copyWith(
                      fontWeight: sort == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (sort == value)
                  const Icon(
                    Icons.check_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
