import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';

/// Create or edit a dish. Validation happens in [CatalogController] so the
/// same rules apply wherever a dish is saved.
class DishEditorScreen extends StatefulWidget {
  const DishEditorScreen({super.key, this.itemId});

  /// Null for a new dish.
  final String? itemId;

  @override
  State<DishEditorScreen> createState() => _DishEditorScreenState();
}

class _OptionRow {
  _OptionRow({String name = '', String detail = '', String price = ''})
    : name = TextEditingController(text: name),
      detail = TextEditingController(text: detail),
      price = TextEditingController(text: price);

  final TextEditingController name;
  final TextEditingController detail;
  final TextEditingController price;

  void dispose() {
    name.dispose();
    detail.dispose();
    price.dispose();
  }
}

class _DishEditorScreenState extends State<DishEditorScreen> {
  late final CatalogController _catalog = context.read<CatalogController>();
  late final MenuItem? _original = widget.itemId == null
      ? null
      : _catalog.byId(widget.itemId!);

  late final _name = TextEditingController(text: _original?.name ?? '');
  late final _short = TextEditingController(
    text: _original?.shortDescription ?? '',
  );
  late final _description = TextEditingController(
    text: _original?.description ?? '',
  );
  late final _price = TextEditingController(
    text: _original == null ? '' : _plain(_original.price),
  );
  late final _prep = TextEditingController(
    text: '${_original?.prepMinutes ?? 15}',
  );
  late String _categoryId =
      _original?.category.id ??
      (_catalog.allCategories.isEmpty ? '' : _catalog.allCategories.first.id);
  late bool _isVeg = _original?.isVeg ?? true;
  late String _image = _original?.image ?? '';
  late bool _popular = _original?.isPopular ?? false;
  late bool _special = _original?.isChefSpecial ?? false;
  late bool _featured = _original?.isFeatured ?? false;
  late bool _available = _original?.isAvailable ?? true;
  late bool _spicy = _original?.hasSpiceLevel ?? false;
  late SpiceLevel _defaultSpice = _original?.defaultSpice ?? SpiceLevel.medium;
  late final List<_OptionRow> _portions = [
    for (final p in _original?.portions ?? const <PortionOption>[])
      _OptionRow(
        name: p.label,
        detail: p.detail ?? '',
        price: p.extraPrice.isZero ? '' : _plain(p.extraPrice),
      ),
  ];
  late final List<_OptionRow> _addOns = [
    for (final a in _original?.addOns ?? const <AddOn>[])
      _OptionRow(name: a.name, price: _plain(a.price)),
  ];
  bool _saving = false;

  static String _plain(Money m) => m.paise % 100 == 0
      ? '${m.paise ~/ 100}'
      : (m.paise / 100).toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_name, _short, _description, _price, _prep]) {
      c.dispose();
    }
    for (final row in [..._portions, ..._addOns]) {
      row.dispose();
    }
    super.dispose();
  }

  /// Builds the dish from the form, or throws [ValidationException] for
  /// fields that cannot even be parsed.
  MenuItem _build() {
    final price = SettingsController.parseRupees(_price.text);
    if (price == null) {
      throw const ValidationException('Enter a price, e.g. 180 or 180.50.');
    }
    final prep = int.tryParse(_prep.text.trim());
    if (prep == null) {
      throw const ValidationException('Enter the preparation time in minutes.');
    }
    final category = _catalog.categoryById(_categoryId);
    if (category == null) throw const ValidationException('Choose a category.');
    final portionIds = <String>{};
    final portions = <PortionOption>[];
    for (final row in _portions) {
      final label = row.name.text.trim();
      if (label.isEmpty && row.price.text.trim().isEmpty) continue;
      final extra = row.price.text.trim().isEmpty
          ? Money.zero
          : SettingsController.parseRupees(row.price.text);
      if (extra == null) {
        throw ValidationException('Check the surcharge for "$label".');
      }
      final id = CatalogController.optionId(label, portionIds);
      portionIds.add(id);
      portions.add(
        PortionOption(
          id: id,
          label: label,
          extraPrice: extra,
          detail: row.detail.text.trim().isEmpty
              ? null
              : row.detail.text.trim(),
        ),
      );
    }
    final addOnIds = <String>{};
    final addOns = <AddOn>[];
    for (final row in _addOns) {
      final name = row.name.text.trim();
      if (name.isEmpty && row.price.text.trim().isEmpty) continue;
      final addOnPrice = SettingsController.parseRupees(row.price.text);
      if (addOnPrice == null) {
        throw ValidationException('Enter a price for the add-on "$name".');
      }
      final id = CatalogController.optionId(name, addOnIds);
      addOnIds.add(id);
      addOns.add(AddOn(id: id, name: name, price: addOnPrice));
    }
    final base =
        _original ??
        MenuItem(
          id: _catalog.newItemId(_name.text),
          name: '',
          category: category,
          description: '',
          shortDescription: '',
          price: price,
          image: '',
          isVeg: _isVeg,
          rating: 0,
          reviewCount: 0,
        );
    return base.copyWith(
      name: _name.text,
      category: category,
      description: _description.text,
      shortDescription: _short.text,
      price: price,
      image: _image,
      isVeg: _isVeg,
      isPopular: _popular,
      isChefSpecial: _special,
      isFeatured: _featured,
      hasSpiceLevel: _spicy,
      defaultSpice: _defaultSpice,
      portions: portions,
      addOns: addOns,
      prepMinutes: prep,
      isAvailable: _available,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await runAdminAction(
      context,
      () => _catalog.saveItem(_build()),
      success: 'Saved ${_name.text.trim()}',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _archive(bool archived) async {
    final original = _original;
    if (original == null) return;
    if (archived) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Archive ${original.name}?',
        message:
            'Guests will no longer see it. Past orders and bills keep it. You '
            'can restore it from the Archived filter.',
        confirmLabel: 'Archive',
        icon: Icons.archive_outlined,
      );
      if (!confirmed || !mounted) return;
    }
    final ok = await runAdminAction(
      context,
      () => _catalog.setArchived(original.id, archived),
      success: archived
          ? '${original.name} archived'
          : '${original.name} restored',
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CatalogController>().allCategories;
    final original = _original;
    if (widget.itemId != null && original == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: const AdminEmpty(
          icon: Icons.no_food_outlined,
          title: 'Dish not found',
          message: 'It may have been removed by a demo reset.',
        ),
      );
    }
    return Scaffold(
      backgroundColor: adminBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(original == null ? 'New dish' : 'Edit ${original.name}'),
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
                  if (original != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Price changes apply to new orders only. Existing '
                        'orders and bills keep the price they were placed at.',
                        style: AppTypography.caption,
                      ),
                    ),
                  SectionCard(
                    title: 'Basics',
                    child: Column(
                      children: [
                        TextField(
                          controller: _name,
                          maxLength: 40,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DropdownButtonFormField<String>(
                          initialValue:
                              categories.any((c) => c.id == _categoryId)
                              ? _categoryId
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: [
                            for (final c in categories)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  c.isActive ? c.label : '${c.label} (hidden)',
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _categoryId = value ?? _categoryId,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _price,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Price',
                                  prefixText: '${CurrencyFormatter.symbol} ',
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: TextField(
                                controller: _prep,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Prep time',
                                  suffixText: 'min',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('Veg'),
                              icon: VegIndicator(isVeg: true, size: 13),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text('Non-veg'),
                              icon: VegIndicator(isVeg: false, size: 13),
                            ),
                          ],
                          selected: {_isVeg},
                          onSelectionChanged: (value) =>
                              setState(() => _isVeg = value.first),
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: AppColors.primarySoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    title: 'Description',
                    child: Column(
                      children: [
                        TextField(
                          controller: _short,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            labelText: 'Short description (menu list)',
                          ),
                        ),
                        TextField(
                          controller: _description,
                          maxLength: 400,
                          minLines: 3,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Full description (dish page)',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    title: 'Photo',
                    subtitle: _catalog.canUploadPhotos
                        ? 'Upload a photo of the dish, or pick one of the '
                              'bundled sample photos.'
                        : 'This build has no image storage, so only the '
                              'bundled sample photos are available.',
                    child: DishPhotoField(
                      image: _image,
                      onChanged: (value) => setState(() => _image = value),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    title: 'Visibility',
                    child: Column(
                      children: [
                        _Toggle(
                          title: 'Available to order',
                          subtitle: 'Turn off to show it as sold out.',
                          value: _available,
                          onChanged: (v) => setState(() => _available = v),
                        ),
                        _Toggle(
                          title: 'Popular',
                          subtitle:
                              'Shown in Popular Dishes on the home screen.',
                          value: _popular,
                          onChanged: (v) => setState(() => _popular = v),
                        ),
                        _Toggle(
                          title: "Chef's special",
                          subtitle: "Shown in Chef's Specials with a badge.",
                          value: _special,
                          onChanged: (v) => setState(() => _special = v),
                        ),
                        _Toggle(
                          title: 'Home banner',
                          subtitle:
                              'Shown as a banner at the top of the home '
                              'screen. Turn off to remove it.',
                          value: _featured,
                          onChanged: (v) => setState(() => _featured = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    title: 'Customisation',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Toggle(
                          title: 'Spice level choice',
                          subtitle: 'Guests pick mild, medium or spicy.',
                          value: _spicy,
                          onChanged: (v) => setState(() => _spicy = v),
                        ),
                        if (_spicy)
                          DropdownButtonFormField<SpiceLevel>(
                            initialValue: _defaultSpice,
                            decoration: const InputDecoration(
                              labelText: 'Default spice level',
                            ),
                            items: [
                              for (final level in SpiceLevel.values)
                                DropdownMenuItem(
                                  value: level,
                                  child: Text(level.label),
                                ),
                            ],
                            onChanged: (value) => setState(
                              () => _defaultSpice = value ?? _defaultSpice,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        _OptionEditor(
                          title: 'Portions',
                          hint:
                              'The first portion is the default. Leave empty '
                              'for a single size.',
                          rows: _portions,
                          withDetail: true,
                          priceLabel: 'Surcharge',
                          onAdd: () =>
                              setState(() => _portions.add(_OptionRow())),
                          onRemove: (row) => setState(() {
                            _portions.remove(row);
                            row.dispose();
                          }),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _OptionEditor(
                          title: 'Paid add-ons',
                          hint: 'Optional extras guests can tick.',
                          rows: _addOns,
                          withDetail: false,
                          priceLabel: 'Price',
                          onAdd: () =>
                              setState(() => _addOns.add(_OptionRow())),
                          onRemove: (row) => setState(() {
                            _addOns.remove(row);
                            row.dispose();
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: original == null ? 'Add dish' : 'Save changes',
                    icon: Icons.check_rounded,
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  if (original != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    SecondaryButton(
                      label: original.isArchived
                          ? 'Restore dish'
                          : 'Archive dish',
                      icon: original.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      onPressed: () => _archive(!original.isArchived),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
      title: Text(title, style: AppTypography.cardTitle),
      subtitle: Text(subtitle, style: AppTypography.caption),
    );
  }
}

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    required this.title,
    required this.hint,
    required this.rows,
    required this.withDetail,
    required this.priceLabel,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String hint;
  final List<_OptionRow> rows;
  final bool withDetail;
  final String priceLabel;
  final VoidCallback onAdd;
  final ValueChanged<_OptionRow> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.cardTitle),
        Text(hint, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.sm),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      isDense: true,
                    ),
                  ),
                ),
                if (withDetail) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: row.detail,
                      decoration: const InputDecoration(
                        labelText: 'Detail',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: priceLabel,
                      prefixText: CurrencyFormatter.symbol,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => onRemove(row),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text('Add ${title.toLowerCase().replaceAll('paid ', '')}'),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        ),
      ],
    );
  }
}

/// The dish photo: a preview of whatever is set, buttons to upload a new one
/// from the gallery or the camera, and the bundled sample photos as a
/// fallback. An uploaded photo and a bundled sample are labelled differently
/// so a sample is never mistaken for the restaurant's own picture.
class DishPhotoField extends StatefulWidget {
  const DishPhotoField({
    super.key,
    required this.image,
    required this.onChanged,
    this.upload,
    this.canUpload,
  });

  /// Empty, a bundled asset path, or an uploaded photo's URL.
  final String image;
  final ValueChanged<String> onChanged;

  /// Stores picked bytes and returns the URL (default: a dish photo; the
  /// Offers section passes its own).
  final Future<String> Function(List<int> bytes)? upload;

  /// Whether [upload] is possible (default: whether dish photos are).
  final bool? canUpload;

  @override
  State<DishPhotoField> createState() => _DishPhotoFieldState();
}

class _DishPhotoFieldState extends State<DishPhotoField> {
  bool _busy = false;
  bool _showSamples = false;
  String? _error;

  /// The camera is only offered where image_picker can open one.
  static bool get _hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isUploaded => DineQrAssets.isNetwork(widget.image);

  Future<void> _pick(ImageSource source) async {
    final catalog = context.read<CatalogController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Downscaled before upload: a phone photo is far larger than any
      // menu needs, and the backend caps the file size.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return; // Cancelled.
      final bytes = await picked.readAsBytes();
      final url = await (widget.upload ?? catalog.uploadDishPhoto)(bytes);
      if (mounted) widget.onChanged(url);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (error) {
          ValidationException(:final message) => message,
          ApiException(:final message) => message,
          PermissionDeniedException(:final message) => message,
          _ => 'The photo could not be uploaded. Please try again.',
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpload =
        widget.canUpload ?? context.read<CatalogController>().canUploadPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Preview(image: widget.image, busy: _busy, uploaded: _isUploaded),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (canUpload) ...[
              SecondaryButton(
                label: widget.image.isEmpty ? 'Upload photo' : 'Replace',
                icon: Icons.photo_library_outlined,
                expand: false,
                height: 42,
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              ),
              if (_hasCamera)
                SecondaryButton(
                  label: 'Camera',
                  icon: Icons.photo_camera_outlined,
                  expand: false,
                  height: 42,
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                ),
            ],
            SecondaryButton(
              label: _showSamples ? 'Hide samples' : 'Use a sample',
              icon: Icons.grid_view_rounded,
              expand: false,
              height: 42,
              onPressed: _busy
                  ? null
                  : () => setState(() => _showSamples = !_showSamples),
            ),
            if (widget.image.isNotEmpty)
              SecondaryButton(
                label: 'Remove',
                icon: Icons.delete_outline_rounded,
                expand: false,
                height: 42,
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _error = null);
                        widget.onChanged('');
                      },
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: AppColors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: AppTypography.label.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
        if (_showSamples) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Sample photos ship with the app. They are useful while setting '
            'up, but replace them with your own before going live.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          PhotoPicker(
            selected: widget.image,
            onSelected: (value) {
              setState(() => _error = null);
              widget.onChanged(value);
            },
          ),
        ],
      ],
    );
  }
}

/// Large preview of the current photo, with a label saying where it came
/// from and a spinner while a new one uploads.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.image,
    required this.busy,
    required this.uploaded,
  });

  final String image;
  final bool busy;
  final bool uploaded;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadii.card,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: image.isEmpty
                ? DecoratedBox(
                    decoration: const BoxDecoration(color: AppColors.softWhite),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 34,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No photo yet',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : FoodImage(image, fit: BoxFit.cover),
          ),
          if (image.isNotEmpty)
            Positioned(
              left: AppSpacing.sm,
              top: AppSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  uploaded ? 'Your photo' : 'Sample photo',
                  style: AppTypography.label.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                        'Uploading…',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Selectable grid of the bundled food photos.
class PhotoPicker extends StatelessWidget {
  const PhotoPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = ['', ...CatalogController.bundledImages];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final image in options)
          Semantics(
            selected: image == selected,
            button: true,
            label: image.isEmpty
                ? 'No photo'
                : image.split('/').last.split('.').first.replaceAll('_', ' '),
            child: GestureDetector(
              onTap: () => onSelected(image),
              child: Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(
                    color: image == selected
                        ? AppColors.primary
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: image.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: AppColors.softWhite,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: const Icon(
                          Icons.hide_image_outlined,
                          color: AppColors.textMuted,
                        ),
                      )
                    : FoodImage(
                        image,
                        width: 56,
                        height: 56,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
