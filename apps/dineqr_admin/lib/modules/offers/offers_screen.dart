import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';
import 'offer_fields.dart';
import 'promotion_editor_screen.dart';

enum _Tab {
  specials('Special offers', Icons.local_offer_rounded),
  combos('Combos', Icons.layers_rounded),
  coupons('Coupons', Icons.confirmation_number_rounded);

  const _Tab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Offers and promotions: special offers (automatic discounts on chosen
/// dishes), combos (dishes sold together for one price) and coupons (codes
/// guests enter). Guests see changes at once; the server prices every order
/// from these, so what an order pays never depends on the app.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  _Tab _tab = _Tab.specials;

  Future<void> _create() async {
    switch (_tab) {
      case _Tab.specials || _Tab.combos:
        await pushAdminPage<void>(
          context,
          PromotionEditorScreen(
            kind: _tab == _Tab.combos
                ? PromotionKind.combo
                : PromotionKind.special,
          ),
          permission: Permission.manageOffers,
        );
      case _Tab.coupons:
        await editCoupon(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final settings = context.watch<SettingsController>().settings;
    final today = catalog.today;
    final promotions = catalog.promotions;
    final specials = promotions.where((p) => p.isSpecial).toList();
    final combos = promotions.where((p) => p.isCombo).toList();
    final live = [
      ...promotions.where((p) => p.isLiveOn(today)),
      ...settings.offers.where((o) => o.isLiveOn(today)),
    ].length;
    return AdminPage(
      title: 'Offers',
      subtitle: '$live live now · special offers, combos and coupons',
      onRefresh: () => Future.wait([
        catalog.refresh(),
        context.read<SettingsController>().load(),
      ]),
      actions: [
        PrimaryButton(
          label: switch (_tab) {
            _Tab.specials => 'New offer',
            _Tab.combos => 'New combo',
            _Tab.coupons => 'New coupon',
          },
          icon: Icons.add_rounded,
          expand: false,
          height: 44,
          onPressed: _create,
        ),
      ],
      children: [
        SegmentedButton<_Tab>(
          segments: [
            for (final tab in _Tab.values)
              ButtonSegment(
                value: tab,
                label: Text(tab.label),
                icon: Icon(tab.icon),
              ),
          ],
          selected: {_tab},
          onSelectionChanged: (value) => setState(() => _tab = value.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.primarySoft,
            selectedForegroundColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(switch (_tab) {
          _Tab.specials =>
            'A discount on chosen dishes, applied by itself: guests see the '
                'offer price on the menu. A dish gets one special offer (the '
                'best); a coupon applies on top.',
          _Tab.combos =>
            'Dishes sold together for one price, added to the cart as one '
                'item. Guests see what the dishes cost separately and what '
                'they save.',
          _Tab.coupons =>
            'Codes guests enter in their cart. A coupon applies after any '
                'special offer or combo saving, and its minimum order counts '
                'what is left.',
        }, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.lg),
        switch (_tab) {
          _Tab.specials => _PromotionList(
            promotions: specials,
            today: today,
            empty: const AdminEmpty(
              icon: Icons.local_offer_outlined,
              title: 'No special offers',
              message: 'Create one, e.g. 20% off starters this weekend.',
            ),
          ),
          _Tab.combos => _PromotionList(
            promotions: combos,
            today: today,
            empty: const AdminEmpty(
              icon: Icons.layers_outlined,
              title: 'No combos',
              message: 'Create one, e.g. a biryani, a starter and a drink.',
            ),
          ),
          _Tab.coupons => _CouponList(offers: settings.offers, today: today),
        },
      ],
    );
  }
}

class _PromotionList extends StatelessWidget {
  const _PromotionList({
    required this.promotions,
    required this.today,
    required this.empty,
  });

  final List<Promotion> promotions;
  final DateTime today;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (promotions.isEmpty) return empty;
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          for (final (index, promotion) in promotions.indexed) ...[
            if (index > 0) const Divider(),
            FadeSlideIn(
              key: ValueKey(promotion.id),
              index: index,
              child: _PromotionRow(promotion: promotion, today: today),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromotionRow extends StatelessWidget {
  const _PromotionRow({required this.promotion, required this.today});

  final Promotion promotion;
  final DateTime today;

  Future<void> _edit(BuildContext context) => pushAdminPage<void>(
    context,
    PromotionEditorScreen(kind: promotion.kind, promotionId: promotion.id),
    permission: Permission.manageOffers,
  );

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${promotion.title}?',
      message:
          'Guests will no longer see it. Orders that used it keep what they '
          'were charged.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await runAdminAction(
      context,
      () => context.read<CatalogController>().deletePromotion(promotion.id),
      success: '${promotion.title} deleted',
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<CatalogController>();
    final view = promotion.isCombo ? catalog.comboView(promotion) : null;
    final image = promotion.image.isNotEmpty
        ? promotion.image
        : (view?.image ?? catalog.dishesIn(promotion).firstOrNull?.image ?? '');
    final what = promotion.isCombo
        ? [
            if (view != null) view.partLabels.join(' + '),
            [
              CurrencyFormatter.format(promotion.comboPrice ?? Money.zero),
              if (view != null && !view.saving.isZero)
                'saves ${CurrencyFormatter.format(view.saving)}',
            ].join(' · '),
          ].join('\n')
        : '${promotion.badge} · '
              '${catalog.dishesIn(promotion).map((d) => d.name).join(', ')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FoodImage(
            image,
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: InkWell(
              onTap: () => _edit(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(promotion.title, style: AppTypography.cardTitle),
                      OfferStatusChip(promotion.statusOn(today)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    what,
                    style: AppTypography.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${OfferRules.validity(promotion.startsOn, promotion.endsOn)}'
                    ' · ${usageText(promotion.usedCount, promotion.usageLimit)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: promotion.isActive,
            activeThumbColor: AppColors.primary,
            onChanged: (active) => runAdminAction(
              context,
              () => catalog.setPromotionActive(promotion.id, active),
              success: active
                  ? '${promotion.title} is active'
                  : '${promotion.title} paused',
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) =>
                value == 'edit' ? _edit(context) : _delete(context),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CouponList extends StatelessWidget {
  const _CouponList({required this.offers, required this.today});

  final List<DiscountOffer> offers;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) {
      return const AdminEmpty(
        icon: Icons.confirmation_number_outlined,
        title: 'No coupons',
        message: 'Add a code such as WELCOME10.',
      );
    }
    final settings = context.read<SettingsController>();
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          for (final (index, offer) in offers.indexed) ...[
            if (index > 0) const Divider(),
            ListTile(
              key: ValueKey(offer.code),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.confirmation_number_rounded,
                color: AppColors.vibrantOrange,
              ),
              title: Wrap(
                spacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${offer.code} · ${offer.title}',
                    style: AppTypography.cardTitle,
                  ),
                  OfferStatusChip(offer.statusOn(today)),
                ],
              ),
              subtitle: Text(
                '${offer.summary}\n'
                '${OfferRules.validity(offer.startsOn, offer.endsOn)} · '
                '${usageText(offer.usedCount, offer.usageLimit)}',
                style: AppTypography.caption,
              ),
              onTap: () => editCoupon(context, offer),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: offer.isActive,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => runAdminAction(
                      context,
                      () => settings.setOfferActive(offer.code, v),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await editCoupon(context, offer);
                        return;
                      }
                      final confirmed = await showConfirmDialog(
                        context,
                        title: 'Delete ${offer.code}?',
                        message:
                            'Guests can no longer apply it. Orders that used '
                            'it keep their discount.',
                        confirmLabel: 'Delete',
                        icon: Icons.delete_outline_rounded,
                      );
                      if (!confirmed || !context.mounted) return;
                      await runAdminAction(
                        context,
                        () => settings.deleteOffer(offer.code),
                        success: '${offer.code} deleted',
                      );
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
        ],
      ),
    );
  }
}

/// Opens the coupon dialog for [offer] (null: a new one) and saves it.
Future<void> editCoupon(BuildContext context, DiscountOffer? offer) async {
  final settings = context.read<SettingsController>();
  final result = await showDialog<DiscountOffer>(
    context: context,
    builder: (_) => CouponDialog(offer: offer),
  );
  if (result == null || !context.mounted) return;
  await runAdminAction(
    context,
    () => settings.saveOffer(result, originalCode: offer?.code),
    success: 'Coupon ${result.code.toUpperCase()} saved',
  );
}

/// A coupon's code, title, discount, minimum order, cap, dates and usage
/// limit.
class CouponDialog extends StatefulWidget {
  const CouponDialog({super.key, required this.offer});

  final DiscountOffer? offer;

  @override
  State<CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<CouponDialog> {
  late final _code = TextEditingController(text: widget.offer?.code ?? '');
  late final _title = TextEditingController(text: widget.offer?.title ?? '');
  late DiscountType _type = widget.offer?.type ?? DiscountType.percent;
  late final _value = TextEditingController(
    text: widget.offer == null
        ? ''
        : (widget.offer!.type == DiscountType.percent
              ? PricingConfig.formatRate(
                  widget.offer!.value,
                ).replaceAll('%', '')
              : '${widget.offer!.value ~/ 100}'),
  );
  late final _min = TextEditingController(
    text: widget.offer == null || widget.offer!.minSubtotal.isZero
        ? ''
        : '${widget.offer!.minSubtotal.paise ~/ 100}',
  );
  late final _max = TextEditingController(
    text: widget.offer?.maxDiscount == null
        ? ''
        : '${widget.offer!.maxDiscount!.paise ~/ 100}',
  );
  late final _limit = TextEditingController(
    text: widget.offer?.usageLimit?.toString() ?? '',
  );
  late DateTime? _startsOn = widget.offer?.startsOn;
  late DateTime? _endsOn = widget.offer?.endsOn;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _title, _value, _min, _max, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final value = _type == DiscountType.percent
        ? SettingsController.parsePercent(_value.text)
        : SettingsController.parseRupees(_value.text)?.paise;
    final min = _min.text.trim().isEmpty
        ? Money.zero
        : SettingsController.parseRupees(_min.text);
    final max = _max.text.trim().isEmpty
        ? null
        : SettingsController.parseRupees(_max.text);
    final limit = UsageLimitField.parse(_limit);
    if (value == null ||
        min == null ||
        (_max.text.trim().isNotEmpty && max == null)) {
      setState(() => _error = 'Check the amounts.');
      return;
    }
    if (limit == -1) {
      setState(() => _error = 'The usage limit is a whole number of orders.');
      return;
    }
    final dates = SettingsController.validateDates(_startsOn, _endsOn);
    if (dates != null) {
      setState(() => _error = dates);
      return;
    }
    Navigator.pop(
      context,
      DiscountOffer(
        code: _code.text,
        title: _title.text,
        type: _type,
        value: value,
        minSubtotal: min,
        maxDiscount: _type == DiscountType.percent ? max : null,
        isActive: widget.offer?.isActive ?? true,
        startsOn: _startsOn,
        endsOn: _endsOn,
        usageLimit: limit,
        usedCount: widget.offer?.usedCount ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.offer == null ? 'New coupon' : 'Edit ${widget.offer!.code}',
        style: AppTypography.sectionTitle,
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _code,
                maxLength: 16,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              TextField(
                controller: _title,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<DiscountType>(
                segments: [
                  for (final t in DiscountType.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _type == DiscountType.percent
                      ? 'Discount'
                      : 'Amount off',
                  suffixText: _type == DiscountType.percent ? '%' : null,
                  prefixText: _type == DiscountType.flat
                      ? '${CurrencyFormatter.symbol} '
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _min,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Minimum order (optional)',
                  prefixText: '${CurrencyFormatter.symbol} ',
                  helperText: 'After any special offer or combo saving.',
                ),
              ),
              if (_type == DiscountType.percent) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Maximum discount (optional)',
                    prefixText: '${CurrencyFormatter.symbol} ',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              OfferDatesField(
                startsOn: _startsOn,
                endsOn: _endsOn,
                onChanged: (start, end) => setState(() {
                  _startsOn = start;
                  _endsOn = end;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              UsageLimitField(
                controller: _limit,
                used: widget.offer?.usedCount ?? 0,
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
