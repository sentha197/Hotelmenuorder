import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../state/shell_controller.dart';
import 'dish_gallery.dart';

/// Screen 6: dish details with customization, quantity and add to cart.
class DishDetailsScreen extends StatefulWidget {
  const DishDetailsScreen({super.key, required this.itemId, this.heroTag});

  final String itemId;
  final String? heroTag;

  @override
  State<DishDetailsScreen> createState() => _DishDetailsScreenState();
}

class _DishDetailsScreenState extends State<DishDetailsScreen> {
  static const _imageHeight = 330.0;

  final _scroll = ScrollController();
  bool _collapsed = false;
  bool _initialized = false;

  SpiceLevel? _spice;
  String? _portionId;
  final Set<String> _addOns = {};
  int _quantity = 1;
  bool _justAdded = false;
  Timer? _addedTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final collapsed = _scroll.offset > _imageHeight - kToolbarHeight - 60;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _addedTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _initFrom(MenuItem item) {
    if (_initialized) return;
    _initialized = true;
    _spice = item.hasSpiceLevel ? item.defaultSpice : null;
    _portionId = item.defaultPortion?.id;
  }

  DishCustomization get _customization => DishCustomization(
    spice: _spice,
    portionId: _portionId,
    addOnIds: _addOns,
  );

  void _addToCart(MenuItem item) {
    final navigator = Navigator.of(context);
    final shell = context.read<ShellController>();
    context.read<CartController>().add(
      item,
      customization: _customization,
      quantity: _quantity,
    );
    HapticFeedback.mediumImpact();
    setState(() => _justAdded = true);
    _addedTimer?.cancel();
    _addedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _justAdded = false);
    });
    showAppSnackBar(
      context,
      '$_quantity × ${item.name} added to cart',
      icon: Icons.check_circle_rounded,
      actionLabel: 'VIEW CART',
      onAction: () => AppNav.goToTabWith(navigator, shell, ShellTab.cart),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only dishes guests may see (not archived or in a hidden category).
    final item = context.select<CatalogController, MenuItem?>(
      (catalog) =>
          catalog.items.where((i) => i.id == widget.itemId).firstOrNull,
    );
    if (item == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: EmptyState(
          icon: Icons.no_food_outlined,
          title: 'Dish not available',
          message: 'This dish is not on the menu right now.',
          actionLabel: 'Back to menu',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    }
    _initFrom(item);
    final customization = _customization;
    final unitPrice = item.price + customization.extraFor(item);
    final total = unitPrice * _quantity;
    final heroTag = widget.heroTag ?? 'dish-${item.id}';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _collapsed
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: _imageHeight,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
              systemOverlayStyle: _collapsed
                  ? SystemUiOverlayStyle.dark
                  : SystemUiOverlayStyle.light,
              title: AnimatedOpacity(
                opacity: _collapsed ? 1 : 0,
                duration: Motion.of(context, Motion.fast),
                child: Text(item.name),
              ),
              leading: Center(
                child: CircleIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              actions: [
                _FavoriteButton(itemId: item.id),
                const SizedBox(width: AppSpacing.sm),
                const _CartButton(),
                const SizedBox(width: AppSpacing.md),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                stretchModes: const [StretchMode.zoomBackground],
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    DishGallery(item: item, heroTag: heroTag),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.heroImageOverlay,
                      ),
                    ),
                  ],
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Container(
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.xxl,
              ),
              sliver: SliverList.list(
                children: [
                  FadeSlideIn(child: _Header(item: item)),
                  const SizedBox(height: AppSpacing.md),
                  FadeSlideIn(
                    index: 1,
                    child: Text(
                      item.description,
                      style: AppTypography.bodySecondary.copyWith(
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (item.isCustomizable) ...[
                    const SizedBox(height: AppSpacing.xl),
                    FadeSlideIn(
                      index: 2,
                      child: Text(
                        'Customize',
                        style: AppTypography.sectionTitle,
                      ),
                    ),
                  ],
                  if (item.hasSpiceLevel)
                    FadeSlideIn(
                      index: 3,
                      child: _OptionGroup(
                        title: 'Spice Level',
                        child: Row(
                          children: [
                            for (final level in SpiceLevel.values) ...[
                              Expanded(
                                child: _ChoiceChip(
                                  label: level.label,
                                  selected: _spice == level,
                                  onTap: () => setState(() => _spice = level),
                                ),
                              ),
                              if (level != SpiceLevel.values.last)
                                const SizedBox(width: AppSpacing.sm),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (item.portions.length > 1)
                    FadeSlideIn(
                      index: 4,
                      child: _OptionGroup(
                        title: 'Portion',
                        child: Row(
                          children: [
                            for (final portion in item.portions) ...[
                              Expanded(
                                child: _ChoiceChip(
                                  label: portion.label,
                                  detail: [
                                    ?portion.detail,
                                    if (!portion.extraPrice.isZero)
                                      CurrencyFormatter.formatExtra(
                                        portion.extraPrice,
                                      ),
                                  ].join(' · '),
                                  selected: _portionId == portion.id,
                                  onTap: () =>
                                      setState(() => _portionId = portion.id),
                                ),
                              ),
                              if (portion != item.portions.last)
                                const SizedBox(width: AppSpacing.sm),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (item.addOns.isNotEmpty)
                    FadeSlideIn(
                      index: 5,
                      child: _OptionGroup(
                        title: 'Add-ons',
                        trailing: 'Optional',
                        child: Column(
                          children: [
                            for (final addOn in item.addOns)
                              _AddOnTile(
                                addOn: addOn,
                                selected: _addOns.contains(addOn.id),
                                onChanged: (selected) => setState(() {
                                  if (selected) {
                                    _addOns.add(addOn.id);
                                  } else {
                                    _addOns.remove(addOn.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  FadeSlideIn(
                    index: 6,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quantity',
                                style: AppTypography.sectionTitle,
                              ),
                              Text(
                                '${CurrencyFormatter.format(unitPrice)} each',
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                        QuantitySelector(
                          quantity: _quantity,
                          min: 1,
                          max: CartController.maxQuantity,
                          itemName: item.name,
                          onIncrement: () => setState(() => _quantity++),
                          onDecrement: () => setState(() => _quantity--),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _AddToCartBar(
          total: total,
          justAdded: _justAdded,
          onAdd: item.isOrderable ? () => _addToCart(item) : null,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.name,
                style: AppTypography.headline.copyWith(fontSize: 23),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            LayeredGradientText(
              CurrencyFormatter.format(item.price),
              style: AppTypography.headline.copyWith(fontSize: 23),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accentRed, AppColors.primary],
              ),
              baseColor: AppColors.primarySoft,
              depth: 0.07,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                VegIndicator(isVeg: item.isVeg),
                const SizedBox(width: 6),
                Text(
                  item.isVeg ? 'Veg' : 'Non-veg',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: item.isVeg ? AppColors.veg : AppColors.nonVeg,
                  ),
                ),
              ],
            ),
            RatingBadge(rating: item.rating, reviewCount: item.reviewCount),
            _MetaChip(
              icon: Icons.schedule_rounded,
              label: '${item.prepMinutes} min',
            ),
            _MetaChip(
              icon: Icons.restaurant_rounded,
              label: item.category.label,
            ),
            if (item.isChefSpecial)
              const _MetaChip(
                icon: Icons.workspace_premium_rounded,
                label: "Chef's special",
                color: AppColors.warning,
              ),
          ],
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color == AppColors.textSecondary
            ? AppColors.softWhite
            : color.withValues(alpha: 0.1),
        borderRadius: AppRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.cardTitle.copyWith(fontSize: 14),
                ),
              ),
              if (trailing != null)
                Text(trailing!, style: AppTypography.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasDetail = detail != null && detail!.isNotEmpty;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.95,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.standard,
          constraints: BoxConstraints(minHeight: hasDetail ? 54 : 42),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? null : Colors.white,
            gradient: selected ? AppColors.ctaGradient : null,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.border,
              width: 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (hasDetail)
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontSize: 10.5,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddOnTile extends StatelessWidget {
  const _AddOnTile({
    required this.addOn,
    required this.selected,
    required this.onChanged,
  });

  final AddOn addOn;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: selected,
      label: '${addOn.name}, ${CurrencyFormatter.formatExtra(addOn.price)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
              ),
              Expanded(child: Text(addOn.name, style: AppTypography.label)),
              Text(
                CurrencyFormatter.formatExtra(addOn.price),
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.select<CatalogController, bool>(
      (catalog) => catalog.isFavorite(itemId),
    );
    return Center(
      child: FavoriteBurst(
        active: isFavorite,
        child: CircleIconButton(
          icon: isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconColor: isFavorite ? AppColors.primary : AppColors.textPrimary,
          tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
          onPressed: () {
            HapticFeedback.lightImpact();
            final added = context.read<CatalogController>().toggleFavorite(
              itemId,
            );
            showAppSnackBar(
              context,
              added ? 'Saved to your favorites' : 'Removed from favorites',
              icon: added
                  ? Icons.favorite_rounded
                  : Icons.heart_broken_outlined,
              duration: const Duration(seconds: 2),
            );
          },
        ),
      ),
    );
  }
}

class _CartButton extends StatelessWidget {
  const _CartButton();

  @override
  Widget build(BuildContext context) {
    final count = context.select<CartController, int>(
      (cart) => cart.totalQuantity,
    );
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleIconButton(
            icon: Icons.shopping_bag_outlined,
            tooltip: 'View cart, $count items',
            onPressed: () => AppNav.goToTab(context, ShellTab.cart),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: BounceOnChange(
                trigger: count,
                child: _CountBadge(count: count),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadii.pill,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _AddToCartBar extends StatelessWidget {
  const _AddToCartBar({
    required this.total,
    required this.justAdded,
    required this.onAdd,
  });

  final Money total;
  final bool justAdded;

  /// Null while the dish is sold out.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: onAdd == null
              ? const PrimaryButton(
                  label: 'Sold out right now',
                  icon: Icons.block_rounded,
                  onPressed: null,
                )
              : PrimaryButton(
                  label: 'Add to Cart',
                  color: justAdded ? AppColors.success : null,
                  onPressed: onAdd,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.fast),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(
                            begin: 0.85,
                            end: 1.0,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: justAdded
                          ? Row(
                              key: const ValueKey('added'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'Added to Cart',
                                  style: AppTypography.button.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              key: const ValueKey('add'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'Add to Cart',
                                  style: AppTypography.button.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '  ·  ',
                                  style: AppTypography.button.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                                AnimatedMoneyText(
                                  total,
                                  style: AppTypography.button.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
