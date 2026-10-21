import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/food_widgets.dart';
import '../../core/widgets/illustrations.dart';
import '../../core/widgets/order_widgets.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/discount_offer.dart';
import '../../state/cart_controller.dart';
import '../../state/session_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/shell_controller.dart';

/// Screen 7: the cart tab.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final TextEditingController _instructions = TextEditingController(
    text: context.read<CartController>().specialInstructions,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep the field in sync when the cart is cleared elsewhere (e.g. after
    // an order is placed).
    final saved = Provider.of<CartController>(context).specialInstructions;
    if (saved != _instructions.text) _instructions.text = saved;
  }

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _clearAll() async {
    final cart = context.read<CartController>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear your cart?',
      message:
          'All ${cart.totalQuantity} items will be removed from your cart.',
      confirmLabel: 'Clear All',
      icon: Icons.remove_shopping_cart_outlined,
    );
    if (confirmed) {
      cart.clear(keepInstructions: true);
      HapticFeedback.mediumImpact();
    }
  }

  void _proceed() {
    final cart = context.read<CartController>();
    if (cart.isEmpty) {
      showAppSnackBar(context, 'Add a dish before placing an order.');
      return;
    }
    if (cart.unavailableLines.isNotEmpty) {
      showAppSnackBar(context, 'Remove sold-out dishes to continue.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pushNamed(Routes.summary);
  }

  void _removeUnavailable() {
    final cart = context.read<CartController>();
    final lines = cart.unavailableLines;
    for (final line in lines) {
      cart.remove(line.id);
    }
    HapticFeedback.lightImpact();
    showAppSnackBar(
      context,
      lines.length == 1
          ? '${lines.single.item.name} removed'
          : '${lines.length} sold-out dishes removed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final shell = context.read<ShellController>();
    final tableLabel = context.select<SessionController, String>(
      (session) => session.tableLabel,
    );
    final unavailable = cart.unavailableLines;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: AppBackButton(onPressed: () => shell.select(ShellTab.home)),
        title: const Text('My Cart'),
        actions: [
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            child: cart.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: _clearAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: AppTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Clear All'),
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AnimatedSwitcher(
        duration: Motion.of(context, Motion.medium),
        child: cart.isEmpty
            ? EmptyState(
                key: const ValueKey('empty'),
                illustration: const EmptyCartIllustration(),
                icon: Icons.shopping_bag_outlined,
                title: 'Your cart is empty',
                message:
                    'Looks like you have not added anything yet. '
                    'Explore the menu and pick something delicious.',
                actionLabel: 'Browse Menu',
                onAction: () => shell.select(ShellTab.menu),
              )
            : ListView(
                key: const ValueKey('cart'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom,
                ),
                children: [
                  if (tableLabel.isNotEmpty) _TableStrip(label: tableLabel),
                  if (unavailable.isNotEmpty)
                    _SoldOutNotice(
                      count: unavailable.length,
                      onRemove: _removeUnavailable,
                    ),
                  for (final line in cart.lines)
                    _CartLineTile(key: ValueKey(line.id), line: line),
                  const SizedBox(height: AppSpacing.lg),
                  Text.rich(
                    TextSpan(
                      text: 'Special Instructions ',
                      style: AppTypography.cardTitle,
                      children: [
                        TextSpan(
                          text: '(Optional)',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _instructions,
                    onChanged: cart.updateInstructions,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: CartController.maxInstructionsLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'E.g. Less spicy, no onions...',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _CouponCard(),
                  AppCard(child: BillSummary(bill: cart.bill)),
                ],
              ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CheckoutBar(
              total: cart.bill.total,
              itemCount: cart.totalQuantity,
              blocked: unavailable.isNotEmpty,
              onProceed: _proceed,
            ),
    );
  }
}

class _TableStrip extends StatelessWidget {
  const _TableStrip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.accentRed, AppColors.warmOrange],
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.table_restaurant_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Ordering for $label',
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.verified_rounded,
                size: 18,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One cart line. Animates out before it is removed.
class _CartLineTile extends StatefulWidget {
  const _CartLineTile({super.key, required this.line});

  final CartItem line;

  @override
  State<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends State<_CartLineTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );
  late final Animation<double> _visible = ReverseAnimation(
    CurvedAnimation(parent: _exit, curve: Curves.easeInCubic),
  );
  bool _removing = false;

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    if (_removing) return;
    _removing = true;
    final cart = context.read<CartController>();
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.lightImpact();
    if (!Motion.reduced(context)) await _exit.forward();
    final removed = cart.remove(widget.line.id);
    if (removed == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          content: Text('${removed.line.item.name} removed from cart'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => cart.restore(removed),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final cart = context.read<CartController>();
    final soldOut = !line.item.isOrderable;
    return SizeTransition(
      sizeFactor: _visible,
      child: FadeTransition(
        opacity: _visible,
        child: FadeSlideIn(
          offset: const Offset(0.08, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadii.card,
                border: Border.all(
                  color: soldOut
                      ? AppColors.error.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SoldOutVeil(
                    soldOut: soldOut,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: FoodImage(
                      line.item.image,
                      width: 68,
                      height: 68,
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
                            VegIndicator(isVeg: line.item.isVeg, size: 12),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                line.item.name,
                                style: AppTypography.cardTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (line.optionLabels.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            line.optionLabels.join(' · '),
                            style: AppTypography.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (soldOut) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Sold out right now. Remove it to continue.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedMoneyText(
                                    line.lineTotal,
                                    style: AppTypography.price,
                                  ),
                                  if (line.quantity > 1)
                                    Text(
                                      '${CurrencyFormatter.format(line.unitPrice)} each',
                                      style: AppTypography.caption.copyWith(
                                        fontSize: 10.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            QuantitySelector(
                              quantity: line.quantity,
                              compact: true,
                              itemName: line.item.name,
                              max: soldOut
                                  ? line.quantity
                                  : CartController.maxQuantity,
                              onIncrement: () => cart.increment(line.id),
                              onDecrement: () {
                                if (line.quantity <= 1) {
                                  _remove();
                                } else {
                                  cart.decrement(line.id);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Remove ${line.item.name}',
                      onPressed: _remove,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.primary,
                        size: 21,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.total,
    required this.itemCount,
    required this.blocked,
    required this.onProceed,
  });

  final Money total;
  final int itemCount;

  /// Sold-out dishes must be removed first.
  final bool blocked;
  final VoidCallback onProceed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Amount', style: AppTypography.sectionTitle),
                    Text(
                      '${AppFormat.itemCount(itemCount)} · incl. taxes',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              AnimatedMoneyText(
                total,
                style: AppTypography.headline.copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: blocked
                ? 'Remove sold-out dishes first'
                : 'Proceed to Place Order',
            trailingIcon: blocked ? null : Icons.arrow_forward_rounded,
            onPressed: blocked ? null : onProceed,
          ),
        ],
      ),
    );
  }
}

class _SoldOutNotice extends StatelessWidget {
  const _SoldOutNotice({required this.count, required this.onRemove});

  final int count;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              count == 1
                  ? 'A dish in your cart has sold out.'
                  : '$count dishes in your cart have sold out.',
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onRemove,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: Text(count == 1 ? 'Remove it' : 'Remove them'),
          ),
        ],
      ),
    );
  }
}

/// Applied coupon and what it saves, or an entry to the restaurant's active
/// offers. Hidden when there is nothing to apply.
class _CouponCard extends StatelessWidget {
  const _CouponCard();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final offers = context
        .watch<SettingsController>()
        .settings
        .offers
        .where((offer) => offer.isActive)
        .toList(growable: false);
    final code = cart.offerCode;
    if (code == null && offers.isEmpty) return const SizedBox.shrink();
    final offer = cart.appliedOffer;
    final (icon, title, subtitle, tone) = code == null
        ? (
            Icons.local_offer_outlined,
            'Apply a coupon',
            '${offers.length} ${offers.length == 1 ? 'offer' : 'offers'} '
                'available',
            AppColors.primary,
          )
        : switch (cart.offerProblem) {
            null => (
              Icons.check_circle_rounded,
              '$code applied',
              'You save ${CurrencyFormatter.format(cart.discount)} on this '
                  'order',
              AppColors.success,
            ),
            OfferError.belowMinimum => (
              Icons.info_outline_rounded,
              '$code saved',
              'Add ${CurrencyFormatter.format(offer!.shortfall(cart.subtotal))}'
                  ' more to get ${offer.benefit}',
              AppColors.warning,
            ),
            final OfferError problem => (
              Icons.error_outline_rounded,
              '$code cannot be used',
              problem.message,
              AppColors.error,
            ),
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        button: code == null,
        child: Pressable(
          onTap: code == null ? () => _CouponSheet.show(context) : null,
          scale: 0.98,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.medium),
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, 6, 12),
            decoration: BoxDecoration(
              color: code == null ? Colors.white : tone.withValues(alpha: 0.07),
              borderRadius: AppRadii.card,
              border: Border.all(
                color: code == null
                    ? AppColors.border
                    : tone.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: tone, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.cardTitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppTypography.caption),
                    ],
                  ),
                ),
                if (code != null)
                  TextButton(
                    onPressed: cart.removeOffer,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text('Remove'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CouponSheet extends StatefulWidget {
  const _CouponSheet();

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => const _CouponSheet(),
  );

  @override
  State<_CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends State<_CouponSheet> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _apply(String code) {
    if (!DiscountOffer.isValidCode(code)) {
      setState(() => _error = 'Enter the code shown on the offer.');
      return;
    }
    final problem = context.read<CartController>().applyOffer(code);
    if (problem == OfferError.unknownCode || problem == OfferError.inactive) {
      setState(() => _error = problem!.message);
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final offers = context
        .watch<SettingsController>()
        .settings
        .offers
        .where((offer) => offer.isActive)
        .toList(growable: false);
    final subtotal = context.select<CartController, Money>(
      (cart) => cart.subtotal,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.page + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Apply a coupon', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(16),
                  ],
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: _apply,
                  decoration: InputDecoration(
                    hintText: 'Enter coupon code',
                    prefixIcon: const Icon(Icons.local_offer_outlined),
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              PrimaryButton(
                label: 'Apply',
                expand: false,
                height: 52,
                onPressed: () => _apply(_code.text),
              ),
            ],
          ),
          if (offers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Available offers',
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: offers.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final offer = offers[index];
                  final shortfall = offer.shortfall(subtotal);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  offer.code,
                                  style: AppTypography.overline.copyWith(
                                    color: AppColors.primary,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                offer.title.isEmpty
                                    ? offer.benefit
                                    : offer.title,
                                style: AppTypography.label.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(offer.summary, style: AppTypography.caption),
                              if (!shortfall.isZero)
                                Text(
                                  'Add ${CurrencyFormatter.format(shortfall)} '
                                  'more to use it',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.warning,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _apply(offer.code),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                          child: const Text('APPLY'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
