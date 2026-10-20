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
import '../../state/cart_controller.dart';
import '../../state/session_controller.dart';
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
    FocusScope.of(context).unfocus();
    Navigator.of(context).pushNamed(Routes.summary);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final shell = context.read<ShellController>();
    final tableLabel = context.select<SessionController, String>(
      (session) => session.tableLabel,
    );

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
                  AppCard(child: BillSummary(bill: cart.bill)),
                ],
              ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CheckoutBar(
              total: cart.bill.total,
              itemCount: cart.totalQuantity,
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
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FoodImage(
                    line.item.image,
                    width: 68,
                    height: 68,
                    borderRadius: BorderRadius.circular(AppRadii.md),
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
                              max: CartController.maxQuantity,
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
    required this.onProceed,
  });

  final Money total;
  final int itemCount;
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
            label: 'Proceed to Place Order',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: onProceed,
          ),
        ],
      ),
    );
  }
}
