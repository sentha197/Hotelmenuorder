import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../state/shell_controller.dart';
import '../menu/menu_widgets.dart';

/// "Add" for a combo, turning into a quantity stepper once it is in the
/// cart (like [AddToCartControl] for dishes).
class ComboAddControl extends StatelessWidget {
  const ComboAddControl({super.key, required this.combo});

  final ComboView combo;

  String get _title => combo.combo.title;

  void _add(BuildContext context, {required bool announce}) {
    final navigator = Navigator.of(context);
    final shell = context.read<ShellController>();
    context.read<CartController>().addCombo(combo);
    HapticFeedback.lightImpact();
    if (announce) {
      showAppSnackBar(
        context,
        '$_title added to cart',
        icon: Icons.check_circle_rounded,
        actionLabel: 'VIEW CART',
        onAction: () => AppNav.goToTabWith(navigator, shell, ShellTab.cart),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final quantity = cart.quantityOfCombo(combo.combo.id);
    final orderable = combo.dishesOrderable && combo.combo.isLiveOn(cart.today);
    if (quantity == 0 && !orderable) {
      return Text(
        'Unavailable',
        style: AppTypography.caption.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (quantity == 0) {
      return PrimaryButton(
        label: 'Add',
        icon: Icons.add_rounded,
        expand: false,
        height: 34,
        onPressed: () => _add(context, announce: true),
      );
    }
    return QuantitySelector(
      quantity: quantity,
      compact: true,
      itemName: _title,
      max: orderable ? CartController.maxQuantity : quantity,
      onIncrement: () => _add(context, announce: false),
      onDecrement: () => cart.decrement(CartItem.comboLineId(combo.combo.id)),
    );
  }
}

/// A combo in a horizontal list: picture, what is in it, its price against
/// the dishes bought separately, and how much it saves.
class ComboCard extends StatelessWidget {
  const ComboCard({super.key, required this.combo, this.width = 236});

  final ComboView combo;
  final double width;

  static const _radius = AppRadii.lg + 4;

  @override
  Widget build(BuildContext context) {
    final saving = combo.saving;
    return Pressable(
      onTap: () => showComboDetails(context, combo),
      scale: 0.97,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: AppColors.divider),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Stack(
                children: [
                  SoldOutVeil(
                    soldOut: !combo.dishesOrderable,
                    borderRadius: BorderRadius.circular(_radius - 5),
                    child: FoodImage(
                      combo.image,
                      width: width - 12,
                      height: 112,
                      borderRadius: BorderRadius.circular(_radius - 5),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: VegIndicator(isVeg: combo.isVeg),
                  ),
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: OfferTag('Combo', icon: Icons.layers_rounded),
                  ),
                  if (!saving.isZero)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: OfferTag(
                        'Save ${CurrencyFormatter.format(saving)}',
                        icon: null,
                      ),
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
                      combo.combo.title,
                      style: AppTypography.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      combo.partLabels.join(' + '),
                      style: AppTypography.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OfferPrice(
                            price: combo.price,
                            original: combo.originalPrice,
                            style: AppTypography.price.copyWith(fontSize: 16),
                          ),
                        ),
                        ComboAddControl(combo: combo),
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

/// The combo's dishes, price, saving and dates, with "Add".
Future<void> showComboDetails(BuildContext context, ComboView combo) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _OfferSheet(
        image: combo.image,
        eyebrow: 'COMBO',
        title: combo.combo.title,
        description: combo.combo.description,
        validity: combo.combo.endsOn == null
            ? null
            : 'Until ${AppFormat.day(combo.combo.endsOn!)}',
        body: [
          for (final dish in combo.dishes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: FoodImage(
                dish.item.image,
                width: 48,
                height: 48,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              title: Text(
                ComboView.partLabel(dish.quantity, dish.item.name),
                style: AppTypography.cardTitle.copyWith(fontSize: 14),
              ),
              subtitle: dish.item.isOrderable
                  ? null
                  : Text(
                      'Sold out right now',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
              trailing: Text(
                CurrencyFormatter.format(
                  ComboView.defaultUnitPrice(dish.item) * dish.quantity,
                ),
                style: AppTypography.caption,
              ),
            ),
        ],
        footer: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OfferPrice(price: combo.price, original: combo.originalPrice),
                  if (!combo.saving.isZero)
                    Text(
                      'You save ${CurrencyFormatter.format(combo.saving)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            ComboAddControl(combo: combo),
          ],
        ),
      ),
    );

/// A special offer: what it takes off, its dishes (each with its offer
/// price, to add from here) and its dates.
Future<void> showSpecialOffer(BuildContext context, Promotion special) {
  final catalog = context.read<CatalogController>();
  final dishes = catalog.dishesIn(special);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _OfferSheet(
      image: special.image.isNotEmpty
          ? special.image
          : (dishes.firstOrNull?.image ?? ''),
      eyebrow: '${special.badge} · SPECIAL OFFER',
      title: special.title,
      description: special.description,
      validity: special.endsOn == null
          ? 'Applied automatically, no code needed'
          : 'Applied automatically until ${AppFormat.day(special.endsOn!)}',
      body: [
        for (final item in dishes)
          FoodListTile(item: item, heroTag: 'offer-${special.id}-${item.id}'),
      ],
    ),
  );
}

class _OfferSheet extends StatelessWidget {
  const _OfferSheet({
    required this.image,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.body,
    this.validity,
    this.footer,
  });

  final String image;
  final String eyebrow;
  final String title;
  final String description;
  final String? validity;
  final List<Widget> body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.lg,
              ),
              children: [
                if (image.isNotEmpty)
                  FoodImage(
                    image,
                    width: double.infinity,
                    height: 150,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  eyebrow,
                  style: AppTypography.overline.copyWith(
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(title, style: AppTypography.sectionTitle),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(description, style: AppTypography.bodySecondary),
                ],
                if (validity != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      const Icon(
                        Icons.event_available_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(validity!, style: AppTypography.caption),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                ...body,
              ],
            ),
          ),
          if (footer != null)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.md,
                  AppSpacing.page,
                  AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: footer,
              ),
            ),
        ],
      ),
    );
  }
}
