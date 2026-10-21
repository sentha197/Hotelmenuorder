import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/loaders.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/food_widgets.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../data/models/menu_item.dart';
import '../../state/cart_controller.dart';
import '../../state/shell_controller.dart';

/// "+" button that turns into a quantity stepper once the dish is in the cart.
/// Quantities stay in sync with the cart everywhere.
class AddToCartControl extends StatelessWidget {
  const AddToCartControl({super.key, required this.item});

  final MenuItem item;

  void _add(BuildContext context, {required bool announce}) {
    final navigator = Navigator.of(context);
    final shell = context.read<ShellController>();
    context.read<CartController>().quickAdd(item);
    HapticFeedback.lightImpact();
    if (announce) {
      showAppSnackBar(
        context,
        '${item.name} added to cart',
        icon: Icons.check_circle_rounded,
        actionLabel: 'VIEW CART',
        onAction: () => AppNav.goToTabWith(navigator, shell, ShellTab.cart),
      );
    }
  }

  void _remove(BuildContext context) {
    final navigator = Navigator.of(context);
    final shell = context.read<ShellController>();
    final result = context.read<CartController>().quickRemove(item);
    if (result == DecrementResult.ambiguous) {
      showAppSnackBar(
        context,
        '${item.name} is in your cart with different options. '
        'Adjust it from the cart.',
        actionLabel: 'OPEN CART',
        onAction: () => AppNav.goToTabWith(navigator, shell, ShellTab.cart),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quantity = context.select<CartController, int>(
      (cart) => cart.quantityOfItem(item.id),
    );
    final orderable = item.isOrderable;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: switch ((quantity, orderable)) {
        (0, true) => _RoundAddButton(
          key: const ValueKey('add'),
          label: 'Add ${item.name} to cart',
          onTap: () => _add(context, announce: true),
        ),
        (0, false) => Semantics(
          key: const ValueKey('sold-out'),
          label: '${item.name} is sold out',
          excludeSemantics: true,
          child: Text(
            'Sold out',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Already in the cart: it can be reduced but not increased while
        // it is sold out.
        _ => QuantitySelector(
          key: const ValueKey('stepper'),
          quantity: quantity,
          compact: true,
          itemName: item.name,
          max: orderable ? CartController.maxQuantity : quantity,
          onIncrement: () => _add(context, announce: false),
          onDecrement: () => _remove(context),
        ),
      },
    );
  }
}

class _RoundAddButton extends StatelessWidget {
  const _RoundAddButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      scale: 0.85,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          gradient: AppColors.ctaGradient,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            const BoxShadow(color: AppColors.lip, offset: Offset(0, 2)),
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

/// Vertical card used in horizontal carousels (Popular Dishes).
class FoodCard extends StatelessWidget {
  const FoodCard({
    super.key,
    required this.item,
    required this.heroTag,
    this.width = 168,
  });

  final MenuItem item;
  final String heroTag;
  final double width;

  static const _radius = AppRadii.lg + 4;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => AppNav.openDish(context, item, heroTag: heroTag),
      scale: 0.97,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: AppColors.divider),
          boxShadow: AppShadows.card,
        ),
        // Used inside fixed-height carousels: the price row sits at the
        // bottom of the card.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Stack(
                children: [
                  SoldOutVeil(
                    soldOut: !item.isOrderable,
                    borderRadius: BorderRadius.circular(_radius - 5),
                    child: Hero(
                      tag: heroTag,
                      child: FoodImage(
                        item.image,
                        width: width - 12,
                        height: 118,
                        borderRadius: BorderRadius.circular(_radius - 5),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: VegIndicator(isVeg: item.isVeg),
                  ),
                  if (item.isChefSpecial)
                    const Positioned(top: 6, right: 6, child: ChefBadge()),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _RatingPill(item: item),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AppTypography.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.shortDescription,
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            CurrencyFormatter.format(item.price),
                            style: AppTypography.price.copyWith(fontSize: 16),
                          ),
                        ),
                        AddToCartControl(item: item),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: AppRadii.pill,
      ),
      child: RatingBadge(
        rating: item.rating,
        reviewCount: item.reviewCount,
        size: 12.5,
      ),
    );
  }
}

/// "Chef's pick" ribbon shown on special dishes.
class ChefBadge extends StatelessWidget {
  const ChefBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: const BoxDecoration(
        gradient: AppColors.emberGradient,
        borderRadius: AppRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            "Chef's pick",
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal list row used in menus and search results.
class FoodListTile extends StatelessWidget {
  const FoodListTile({super.key, required this.item, required this.heroTag});

  final MenuItem item;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => AppNav.openDish(context, item, heroTag: heroTag),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.page,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                SoldOutVeil(
                  soldOut: !item.isOrderable,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Hero(
                    tag: heroTag,
                    child: FoodImage(
                      item.image,
                      width: 88,
                      height: 88,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                  ),
                ),
                if (item.isChefSpecial && item.isOrderable)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: const BoxDecoration(
                        gradient: AppColors.emberGradient,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(AppRadii.lg),
                        ),
                      ),
                      child: Text(
                        "CHEF'S PICK",
                        textAlign: TextAlign.center,
                        style: AppTypography.overline.copyWith(
                          color: Colors.white,
                          fontSize: 8,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      VegIndicator(isVeg: item.isVeg, size: 13),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          style: AppTypography.cardTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.shortDescription,
                    style: AppTypography.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        CurrencyFormatter.format(item.price),
                        style: AppTypography.price,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      RatingBadge(rating: item.rating, size: 13),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AddToCartControl(item: item),
          ],
        ),
      ),
    );
  }
}

/// Dish-row placeholders shown while the menu loads.
class FoodListSkeleton extends StatelessWidget {
  const FoodListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return BrandShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.page,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  SkeletonBox(width: 88, height: 88, radius: AppRadii.lg),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 140, height: 14),
                        SizedBox(height: 8),
                        SkeletonBox(width: 180, height: 10),
                        SizedBox(height: 12),
                        SkeletonBox(width: 60, height: 14),
                      ],
                    ),
                  ),
                  SkeletonBox(width: 34, height: 34, radius: 11),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
