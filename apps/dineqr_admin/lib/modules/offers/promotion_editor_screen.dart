import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';
import '../menu/dish_editor_screen.dart';
import 'offer_fields.dart';

/// Creates or edits a special offer (a discount on chosen dishes) or a combo
/// (dishes sold together for one price). Changes reach guests at once; orders
/// already placed keep what they were charged.
class PromotionEditorScreen extends StatefulWidget {
  const PromotionEditorScreen({
    super.key,
    required this.kind,
    this.promotionId,
  });

  final PromotionKind kind;

  /// The offer being edited; null creates one.
  final String? promotionId;

  @override
  State<PromotionEditorScreen> createState() => _PromotionEditorScreenState();
}

class _PromotionEditorScreenState extends State<PromotionEditorScreen> {
  late final CatalogController _catalog = context.read<CatalogController>();
  late final Promotion? _original = widget.promotionId == null
      ? null
      : _catalog.promotionById(widget.promotionId!);

  bool get _isCombo => widget.kind == PromotionKind.combo;

  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _description = TextEditingController(
    text: _original?.description ?? '',
  );
  late String _image = _original?.image ?? '';
  late DiscountType _type = _original?.discountType ?? DiscountType.percent;
  late final _value = TextEditingController(
    text: _original == null || !_original.isSpecial
        ? ''
        : (_original.discountType == DiscountType.percent
              ? PricingConfig.formatRate(
                  _original.discountValue,
                ).replaceAll('%', '')
              : _rupees(Money(_original.discountValue))),
  );
  late final _price = TextEditingController(
    text: _original?.comboPrice == null ? '' : _rupees(_original!.comboPrice!),
  );
  late final _limit = TextEditingController(
    text: _original?.usageLimit?.toString() ?? '',
  );
  late DateTime? _startsOn = _original?.startsOn;
  late DateTime? _endsOn = _original?.endsOn;
  late bool _active = _original?.isActive ?? true;

  /// Dish id → quantity (always 1 for special offers), in display order.
  late final Map<String, int> _dishes = {
    for (final item in _original?.items ?? const <PromotionItem>[])
      item.itemId: item.quantity,
  };
  bool _saving = false;

  static String _rupees(Money amount) => amount.paise % 100 == 0
      ? '${amount.paise ~/ 100}'
      : (amount.paise / 100).toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_title, _description, _value, _price, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The form as an offer, or null (with a message) when a number is not
  /// one. Everything else is checked by [CatalogController.savePromotion].
  Promotion? _build() {
    String? problem;
    var value = 0;
    Money? price;
    if (_isCombo) {
      price = SettingsController.parseRupees(_price.text);
      if (price == null) problem = 'Enter the combo price.';
    } else {
      final parsed = _type == DiscountType.percent
          ? SettingsController.parsePercent(_value.text)
          : SettingsController.parseRupees(_value.text)?.paise;
      if (parsed == null) {
        problem = 'Enter the discount.';
      } else {
        value = parsed;
      }
    }
    final limit = UsageLimitField.parse(_limit);
    if (limit == -1) problem = 'The usage limit is a whole number of orders.';
    if (problem != null) {
      runAdminAction(context, () async => throw ValidationException(problem!));
      return null;
    }
    final id =
        _original?.id ?? _catalog.newPromotionId(_title.text, widget.kind);
    return Promotion(
      id: id,
      kind: widget.kind,
      title: _title.text,
      description: _description.text,
      image: _image,
      startsOn: _startsOn,
      endsOn: _endsOn,
      isActive: _active,
      usageLimit: limit,
      usedCount: _original?.usedCount ?? 0,
      sortOrder: _original?.sortOrder ?? 0,
      discountType: _type,
      discountValue: value,
      comboPrice: price,
      items: [
        for (final MapEntry(key: itemId, value: quantity) in _dishes.entries)
          PromotionItem(itemId, quantity: _isCombo ? quantity : 1),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final promotion = _build();
    if (promotion == null) return;
    setState(() => _saving = true);
    final ok = await runAdminAction(
      context,
      () => _catalog.savePromotion(promotion),
      success: 'Saved ${promotion.title.trim()}',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _chooseDishes() async {
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _DishPickerDialog(
        dishes: [
          for (final item in _catalog.allItems)
            if (!item.isArchived) item,
        ],
        selected: _dishes.keys.toSet(),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _dishes.removeWhere((id, _) => !chosen.contains(id));
      for (final id in chosen) {
        _dishes.putIfAbsent(id, () => 1);
      }
    });
  }

  /// What the chosen dishes cost separately (combos), from today's menu.
  Money get _originalPrice => Money.sum([
    for (final MapEntry(key: id, value: quantity) in _dishes.entries)
      if (_catalog.byId(id) case final item?)
        ComboView.defaultUnitPrice(item) * quantity,
  ]);

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    if (widget.promotionId != null && _original == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: const AdminEmpty(
          icon: Icons.local_offer_outlined,
          title: 'Offer not found',
          message: 'It may have been deleted on another device.',
        ),
      );
    }
    final what = _isCombo ? 'combo' : 'special offer';
    return Scaffold(
      backgroundColor: adminBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(
          _original == null ? 'New $what' : 'Edit ${_original.title}',
        ),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_original != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Changes apply to new orders only. Orders already '
                        'placed keep what they were charged.',
                        style: AppTypography.caption,
                      ),
                    ),
                  SectionCard(
                    title: 'Basics',
                    child: Column(
                      children: [
                        TextField(
                          controller: _title,
                          maxLength: 60,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Title',
                            hintText: _isCombo
                                ? 'e.g. Family Feast'
                                : 'e.g. Weekend Snack Hour',
                          ),
                        ),
                        TextField(
                          controller: _description,
                          maxLength: 300,
                          minLines: 2,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            hintText: 'Shown to guests with the offer.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    title: 'Picture',
                    subtitle: _isCombo
                        ? 'Shown on the combo card. Without one, the first '
                              "dish's photo is used."
                        : 'Shown on the home banner. Without one, the first '
                              "dish's photo is used.",
                    child: DishPhotoField(
                      image: _image,
                      onChanged: (value) => setState(() => _image = value),
                      upload: catalog.uploadOfferPhoto,
                      canUpload: catalog.canUploadOfferPhotos,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_isCombo)
                    _comboSection(catalog)
                  else
                    _specialSection(catalog),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    title: 'When and how often',
                    subtitle:
                        'Dates are restaurant days, both included. Leave '
                        'them empty to run until you pause it.',
                    child: Column(
                      children: [
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
                          used: _original?.usedCount ?? 0,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                          activeThumbColor: AppColors.primary,
                          title: Text('Active', style: AppTypography.cardTitle),
                          subtitle: Text(
                            'Guests see it only while it is active and within '
                            'its dates.',
                            style: AppTypography.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: _original == null ? 'Create $what' : 'Save changes',
                    icon: Icons.check_rounded,
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _specialSection(CatalogController catalog) {
    final dishes = [for (final id in _dishes.keys) ?catalog.byId(id)];
    final percent = _type == DiscountType.percent;
    return SectionCard(
      title: 'Discount',
      subtitle:
          'Taken off each of the chosen dishes, with no code. When a dish is '
          'in more than one offer, guests get the bigger saving; a coupon '
          'still applies on top.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: percent ? 'Discount per dish' : 'Amount off per dish',
              suffixText: percent ? '%' : null,
              prefixText: percent ? null : '${CurrencyFormatter.symbol} ',
              helperText: percent
                  ? 'Of the dish as ordered, add-ons included.'
                  : 'Never more than the dish itself.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  dishes.isEmpty
                      ? 'No dishes chosen yet'
                      : '${dishes.length} '
                            '${dishes.length == 1 ? 'dish' : 'dishes'}',
                  style: AppTypography.cardTitle,
                ),
              ),
              TextButton.icon(
                onPressed: _chooseDishes,
                icon: const Icon(Icons.checklist_rounded),
                label: const Text('Choose dishes'),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final item in dishes)
                InputChip(
                  avatar: VegIndicator(isVeg: item.isVeg, size: 12),
                  label: Text(item.name),
                  onDeleted: () => setState(() => _dishes.remove(item.id)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _comboSection(CatalogController catalog) {
    final original = _originalPrice;
    final price = SettingsController.parseRupees(_price.text);
    final saving = price == null ? null : original - price;
    return SectionCard(
      title: 'Dishes and price',
      subtitle:
          'Guests add the combo as one item. Its dishes come with their '
          'default options, and the kitchen sees each of them.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final MapEntry(key: id, value: quantity) in _dishes.entries)
            if (catalog.byId(id) case final item?)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: FoodImage(
                  item.image,
                  width: 44,
                  height: 44,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                title: Text(item.name, style: AppTypography.cardTitle),
                subtitle: Text(
                  '${CurrencyFormatter.format(ComboView.defaultUnitPrice(item))}'
                  ' each${item.isOrderable ? '' : ' · sold out now'}',
                  style: AppTypography.caption,
                ),
                trailing: QuantitySelector(
                  quantity: quantity,
                  compact: true,
                  itemName: item.name,
                  max: CatalogController.maxComboQuantity,
                  onIncrement: () => setState(() => _dishes[id] = quantity + 1),
                  onDecrement: () => setState(() {
                    if (quantity <= 1) {
                      _dishes.remove(id);
                    } else {
                      _dishes[id] = quantity - 1;
                    }
                  }),
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _chooseDishes,
              icon: const Icon(Icons.add_rounded),
              label: Text(_dishes.isEmpty ? 'Add dishes' : 'Change dishes'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _price,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Combo price',
              prefixText: '${CurrencyFormatter.symbol} ',
              helperText: _dishes.isEmpty
                  ? 'Add dishes to see what they cost separately.'
                  : 'Separately: ${CurrencyFormatter.format(original)}'
                        '${saving == null || saving.paise <= 0 ? '' : ' · guests save ${CurrencyFormatter.format(saving)}'}',
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable list of dishes to tick.
class _DishPickerDialog extends StatefulWidget {
  const _DishPickerDialog({required this.dishes, required this.selected});

  final List<MenuItem> dishes;
  final Set<String> selected;

  @override
  State<_DishPickerDialog> createState() => _DishPickerDialogState();
}

class _DishPickerDialogState extends State<_DishPickerDialog> {
  late final Set<String> _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final dishes =
        widget.dishes
            .where((d) => q.isEmpty || d.name.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return AlertDialog(
      title: Text('Choose dishes', style: AppTypography.sectionTitle),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search dishes',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView(
                children: [
                  for (final dish in dishes)
                    CheckboxListTile(
                      value: _selected.contains(dish.id),
                      onChanged: (checked) => setState(
                        () => checked == true
                            ? _selected.add(dish.id)
                            : _selected.remove(dish.id),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(dish.name),
                      subtitle: Text(
                        '${dish.category.label} · '
                        '${CurrencyFormatter.format(dish.price)}',
                      ),
                    ),
                ],
              ),
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
          onPressed: () => Navigator.pop(context, _selected),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text('Done (${_selected.length})'),
        ),
      ],
    );
  }
}
