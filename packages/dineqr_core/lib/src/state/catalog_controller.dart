import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../demo/assets.dart';
import '../models/discount_offer.dart';
import '../models/menu_filter.dart';
import '../models/menu_item.dart';
import '../models/offer_pricing.dart';
import '../models/promotion.dart';
import '../models/staff.dart';
import '../repositories/menu_repository.dart';
import '../storage/key_value_store.dart';
import '../utils/currency.dart';
import 'access.dart';
import 'settings_controller.dart';

enum LoadState { loading, ready, error }

/// Menu catalogue (guest view and admin editing) and the guest's favourites.
class CatalogController extends ChangeNotifier {
  CatalogController(
    this._repository,
    this._store, {
    this._guard,
    this._audit,
    bool Function()? showSoldOut,
    DateTime Function()? clock,
  }) : _showSoldOut = showSoldOut ?? (() => true),
       _clock = clock ?? DateTime.now {
    final raw = _store.read(StorageKeys.favorites);
    if (raw != null) {
      try {
        _favorites = (jsonDecode(raw) as List).cast<String>().toSet();
      } on Object {
        _favorites = {};
      }
    }
  }

  final MenuRepository _repository;
  final KeyValueStore _store;
  final AccessGuard? _guard;
  final AuditLog? _audit;
  final bool Function() _showSoldOut;
  final DateTime Function() _clock;

  LoadState _state = LoadState.loading;
  List<MenuItem> _all = const [];
  List<MenuCategory> _categories = const [];
  List<Promotion> _promotions = const [];
  Set<String> _favorites = {};
  Future<void>? _pending;

  LoadState get state => _state;

  /// Dishes guests can see: not archived, in an active category, and (unless
  /// sold-out dishes are hidden) also those that are temporarily sold out.
  List<MenuItem> get items => [
    for (final item in _all)
      if (!item.isArchived &&
          item.category.isActive &&
          (item.isAvailable || _showSoldOut()))
        item,
  ];

  /// Every dish, including archived ones (admin).
  List<MenuItem> get allItems => _all;

  /// Active categories in display order (guest view).
  List<MenuCategory> get categories => [
    for (final c in _categories)
      if (c.isActive) c,
  ];

  /// All categories in display order (admin).
  List<MenuCategory> get allCategories => _categories;

  Set<String> get favorites => Set.unmodifiable(_favorites);

  List<MenuItem> get popular =>
      items.where((item) => item.isPopular).toList(growable: false);

  List<MenuItem> get chefSpecials =>
      items.where((item) => item.isChefSpecial).toList(growable: false);

  /// Dishes the restaurant put in the home banner carousel; one that cannot
  /// be ordered right now is skipped.
  List<MenuItem> get banners => items
      .where((item) => item.isFeatured && item.isOrderable)
      .toList(growable: false);

  /// Highly rated dishes not already featured as popular (nor, when there
  /// are enough others, as chef's specials).
  List<MenuItem> get recommended {
    final orderable = items.where((i) => i.isOrderable && !i.isPopular);
    final fresh = orderable.where((i) => !i.isChefSpecial).toList();
    final candidates = (fresh.length >= 3 ? fresh : orderable.toList())
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return candidates.take(6).toList(growable: false);
  }

  List<MenuItem> get favoriteItems => items
      .where((item) => _favorites.contains(item.id))
      .toList(growable: false);

  /// Loads the menu once; concurrent callers share the same request.
  Future<void> load({bool force = false}) {
    if (!force && _state == LoadState.ready) return Future.value();
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  Future<void> _fetch() async {
    _state = LoadState.loading;
    notifyListeners();
    try {
      _categories = await _repository.fetchCategories();
      _all = await _repository.fetchMenu();
      _promotions = await _repository.fetchPromotions();
      _state = LoadState.ready;
    } on Object {
      _state = LoadState.error;
    }
    notifyListeners();
  }

  /// Re-reads the menu without showing a loading state (live updates). The
  /// current menu stays on screen if the refresh fails.
  Future<void> refresh() async {
    if (_state != LoadState.ready) return load(force: true);
    final categories = await _repository.fetchCategories();
    final items = await _repository.fetchMenu();
    final promotions = await _repository.fetchPromotions();
    _categories = categories;
    _all = items;
    _promotions = promotions;
    notifyListeners();
  }

  /// Settings that change what guests see were updated.
  void refreshVisibility() => notifyListeners();

  MenuItem? byId(String id) {
    for (final item in _all) {
      if (item.id == id) return item;
    }
    return null;
  }

  MenuCategory? categoryById(String id) =>
      _categories.where((c) => c.id == id).firstOrNull;

  List<MenuItem> filter(MenuFilter filter) =>
      filter.apply(items, favorites: _favorites);

  int countIn(MenuCategory? category) => category == null
      ? items.length
      : items.where((item) => item.category == category).length;

  /// Non-archived dishes in a category (admin).
  int dishCountIn(String categoryId) => _all
      .where((item) => !item.isArchived && item.category.id == categoryId)
      .length;

  bool isFavorite(String itemId) => _favorites.contains(itemId);

  /// Returns the new favourite state.
  bool toggleFavorite(String itemId) {
    final added = !_favorites.remove(itemId);
    if (added) _favorites.add(itemId);
    notifyListeners();
    _persist();
    return added;
  }

  Future<void> clearFavorites() async {
    _favorites = {};
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() =>
      _store.write(StorageKeys.favorites, jsonEncode(_favorites.toList()));

  // ------------------------------------------------------------ admin: dishes

  static const bundledImages = [
    'assets/images/affogato.jpg',
    'assets/images/butter_chicken.jpg',
    'assets/images/butter_naan.jpg',
    'assets/images/chicken_65.jpg',
    'assets/images/chicken_biryani.jpg',
    'assets/images/chilli_chicken.jpg',
    'assets/images/cold_coffee.jpg',
    'assets/images/dal_makhani.jpg',
    'assets/images/french_fries.jpg',
    'assets/images/fresh_lime_soda.jpg',
    'assets/images/gulab_jamun.jpg',
    'assets/images/lassi.jpg',
    'assets/images/masala_dosa.jpg',
    'assets/images/paneer_butter_masala.jpg',
    'assets/images/paneer_tikka.jpg',
    'assets/images/rasmalai.jpg',
    'assets/images/samosa.jpg',
    'assets/images/spring_roll.jpg',
    'assets/images/tandoori_chicken.jpg',
    'assets/images/veg_biryani.jpg',
    'assets/images/veg_manchurian.jpg',
  ];

  /// Returns a message for the first invalid field, or null.
  String? validateItem(MenuItem item) {
    final name = item.name.trim();
    if (name.length < 2 || name.length > 40) {
      return 'Dish name must be 2 to 40 characters.';
    }
    final duplicate = _all.any(
      (other) =>
          other.id != item.id &&
          !other.isArchived &&
          other.name.trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) return 'Another dish is already called "$name".';
    if (item.shortDescription.trim().length > 60) {
      return 'Short description can be at most 60 characters.';
    }
    if (item.description.trim().length > 400) {
      return 'Description can be at most 400 characters.';
    }
    if (item.price.paise < 100 || item.price.paise > 10000000) {
      return 'Price must be between '
          '${CurrencyFormatter.format(const Money.rupees(1))} and '
          '${CurrencyFormatter.format(const Money.rupees(100000))}.';
    }
    if (item.prepMinutes < 1 || item.prepMinutes > 180) {
      return 'Preparation time must be 1 to 180 minutes.';
    }
    if (categoryById(item.category.id) == null) {
      return 'Choose a category.';
    }
    final portionIds = <String>{};
    for (final portion in item.portions) {
      if (portion.label.trim().isEmpty) return 'Every portion needs a name.';
      if (!portionIds.add(portion.id)) return 'Portion names must be unique.';
      if (portion.extraPrice.paise < 0) {
        return 'Portion surcharges cannot be negative.';
      }
    }
    final addOnIds = <String>{};
    for (final addOn in item.addOns) {
      if (addOn.name.trim().isEmpty) return 'Every add-on needs a name.';
      if (!addOnIds.add(addOn.id)) return 'Add-on names must be unique.';
      if (addOn.price.paise < 0 || addOn.price.paise > 1000000) {
        return 'Add-on prices must be between '
            '${CurrencyFormatter.format(Money.zero)} and '
            '${CurrencyFormatter.format(const Money.rupees(10000))}.';
      }
    }
    if (!_isAllowedImage(item.image)) {
      return 'Choose a bundled photo or upload one.';
    }
    return null;
  }

  /// A dish or category photo must be blank, one of the bundled photos, or a
  /// URL the backend returned from an upload.
  static bool _isAllowedImage(String image) =>
      image.isEmpty ||
      bundledImages.contains(image) ||
      DineQrAssets.isNetwork(image);

  /// Whether dish photos can be uploaded. False for the offline demo, which
  /// has no image storage: the editor then offers bundled photos only.
  bool get canUploadPhotos => _repository is DishImageUploader;

  /// Uploads a dish photo and returns the URL to store on the dish. The
  /// caller still has to save the dish for the photo to be kept.
  Future<String> uploadDishPhoto(List<int> bytes) async {
    _require(Permission.manageMenu);
    final repository = _repository;
    // DishImageUploader is a separate capability, not a MenuRepository
    // subtype, so the check cannot promote: cast once it has passed.
    if (repository is! DishImageUploader) {
      throw const ValidationException(
        'This build has no image storage, so photos cannot be uploaded.',
      );
    }
    final uploader = repository as DishImageUploader;
    if (bytes.isEmpty) {
      throw const ValidationException('That photo file is empty.');
    }
    if (bytes.length > DishImageUploader.maxBytes) {
      final limit = DishImageUploader.maxBytes ~/ (1024 * 1024);
      throw ValidationException(
        'That photo is too large. The limit is $limit MB.',
      );
    }
    // No type check here: the server decodes the file and says what it
    // accepts, so the app never refuses a photo for its format. The server
    // never uses the client's name either; this one is only for tidiness.
    final extension = DishImageUploader.extensionFor(bytes) ?? 'img';
    return uploader.uploadDishImage(bytes: bytes, filename: 'dish.$extension');
  }

  /// A unique id derived from [name], e.g. `paneer_roll`.
  String newItemId(String name) =>
      _uniqueId(name, _all.map((i) => i.id).toSet(), fallback: 'dish');

  static String _uniqueId(
    String name,
    Set<String> taken, {
    required String fallback,
  }) {
    var base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty) base = fallback;
    var id = base;
    var n = 2;
    while (taken.contains(id)) {
      id = '${base}_${n++}';
    }
    return id;
  }

  /// Option ids from labels, used by the dish editor.
  static String optionId(String label, Set<String> taken) =>
      _uniqueId(label, taken, fallback: 'option');

  Future<void> saveItem(MenuItem item) async {
    _require(Permission.manageMenu);
    final error = validateItem(item);
    if (error != null) throw ValidationException(error);
    final previous = byId(item.id);
    final saved = item.copyWith(
      name: item.name.trim(),
      shortDescription: item.shortDescription.trim(),
      description: item.description.trim(),
      category: categoryById(item.category.id),
    );
    await _repository.saveItem(saved);
    _replaceItem(saved);
    await _audit?.record(
      previous == null ? 'menu.create' : 'menu.update',
      previous == null
          ? 'Added dish ${saved.name} (${CurrencyFormatter.format(saved.price)})'
          : _describeItemChange(previous, saved),
      targetId: saved.id,
    );
  }

  static String _describeItemChange(MenuItem a, MenuItem b) {
    final changes = [
      if (a.price != b.price)
        'price ${CurrencyFormatter.format(a.price)} → '
            '${CurrencyFormatter.format(b.price)}',
      if (a.name != b.name) 'name',
      if (a.category.id != b.category.id) 'category',
      if (a.isVeg != b.isVeg) b.isVeg ? 'marked veg' : 'marked non-veg',
      if (a.description != b.description ||
          a.shortDescription != b.shortDescription)
        'description',
      if (a.addOns.length != b.addOns.length) 'add-ons',
      if (a.portions.length != b.portions.length) 'portions',
      if (a.isAvailable != b.isAvailable)
        b.isAvailable ? 'available' : 'sold out',
      if (a.image != b.image) 'photo',
    ];
    return 'Updated ${b.name}'
        '${changes.isEmpty ? '' : ': ${changes.join(', ')}'}';
  }

  /// [system] is used by automatic stock rules (still audited).
  Future<void> setAvailable(
    String itemId,
    bool available, {
    bool system = false,
    String reason = '',
  }) async {
    if (!system) _require(Permission.manageMenu);
    final item = byId(itemId);
    if (item == null || item.isAvailable == available) return;
    final saved = item.copyWith(isAvailable: available);
    await _repository.saveItem(saved);
    _replaceItem(saved);
    await _audit?.record(
      'menu.availability',
      '${available ? 'Marked available' : 'Marked sold out'}: ${item.name}'
          '${reason.isEmpty ? '' : ' ($reason)'}',
      targetId: itemId,
    );
  }

  Future<void> setArchived(String itemId, bool archived) async {
    _require(Permission.manageMenu);
    final item = byId(itemId);
    if (item == null || item.isArchived == archived) return;
    final saved = item.copyWith(isArchived: archived);
    await _repository.saveItem(saved);
    _replaceItem(saved);
    await _audit?.record(
      archived ? 'menu.archive' : 'menu.restore',
      '${archived ? 'Archived' : 'Restored'} ${item.name}',
      targetId: itemId,
    );
  }

  void _replaceItem(MenuItem saved) {
    final exists = _all.any((i) => i.id == saved.id);
    _all = exists
        ? [for (final i in _all) i.id == saved.id ? saved : i]
        : [..._all, saved];
    notifyListeners();
  }

  // -------------------------------------------------------- admin: categories

  String? validateCategory(MenuCategory category) {
    final label = category.label.trim();
    if (label.length < 2 || label.length > 24) {
      return 'Category name must be 2 to 24 characters.';
    }
    final duplicate = _categories.any(
      (c) =>
          c.id != category.id &&
          c.label.trim().toLowerCase() == label.toLowerCase(),
    );
    if (duplicate) return 'A category called "$label" already exists.';
    if (category.coverImage.isNotEmpty &&
        !bundledImages.contains(category.coverImage)) {
      return 'Choose one of the available photos.';
    }
    return null;
  }

  String newCategoryId(String label) => _uniqueId(
    label,
    _categories.map((c) => c.id).toSet(),
    fallback: 'category',
  );

  Future<void> saveCategory(MenuCategory category) async {
    _require(Permission.manageCategories);
    final error = validateCategory(category);
    if (error != null) throw ValidationException(error);
    final exists = _categories.any((c) => c.id == category.id);
    final saved = category.copyWith(
      label: category.label.trim(),
      sortOrder: exists ? category.sortOrder : _categories.length,
    );
    await _saveCategories(
      exists
          ? [for (final c in _categories) c.id == saved.id ? saved : c]
          : [..._categories, saved],
    );
    await _audit?.record(
      exists ? 'category.update' : 'category.create',
      '${exists ? 'Updated' : 'Added'} category ${saved.label}',
      targetId: saved.id,
    );
  }

  Future<void> setCategoryActive(String id, bool active) async {
    _require(Permission.manageCategories);
    final category = categoryById(id);
    if (category == null) return;
    await _saveCategories([
      for (final c in _categories)
        c.id == id ? c.copyWith(isActive: active) : c,
    ]);
    await _audit?.record(
      'category.toggle',
      '${active ? 'Showed' : 'Hid'} category ${category.label}',
      targetId: id,
    );
  }

  /// Applies a new display order (ids from first to last).
  Future<void> reorderCategories(List<String> orderedIds) async {
    _require(Permission.manageCategories);
    final byId = {for (final c in _categories) c.id: c};
    if (orderedIds.toSet().length != byId.length ||
        !orderedIds.every(byId.containsKey)) {
      throw const ValidationException('The category list changed. Try again.');
    }
    await _saveCategories([
      for (final (index, id) in orderedIds.indexed)
        byId[id]!.copyWith(sortOrder: index),
    ]);
    await _audit?.record('category.reorder', 'Reordered categories');
  }

  /// Only empty categories can be deleted; dishes must be moved first.
  Future<void> deleteCategory(String id) async {
    _require(Permission.manageCategories);
    final category = categoryById(id);
    if (category == null) return;
    final used = _all.where((item) => item.category.id == id).length;
    if (used > 0) {
      throw ValidationException(
        '${category.label} still has $used '
        '${used == 1 ? 'dish' : 'dishes'} (including archived). '
        'Move them to another category first.',
      );
    }
    await _saveCategories([
      for (final (index, c) in _categories.where((c) => c.id != id).indexed)
        c.copyWith(sortOrder: index),
    ]);
    await _audit?.record(
      'category.delete',
      'Deleted category ${category.label}',
      targetId: id,
    );
  }

  Future<void> _saveCategories(List<MenuCategory> categories) async {
    await _repository.saveCategories(categories);
    _categories = await _repository.fetchCategories();
    _all = await _repository.fetchMenu();
    _promotions = await _repository.fetchPromotions();
    notifyListeners();
  }

  // ------------------------------------------- offers: specials and combos

  /// Today in restaurant time (offers are live by restaurant days).
  DateTime get today => OfferRules.today(_clock());

  /// Every special offer and combo the app knows, in display order (staff
  /// apps: all of them; guests: those live when the menu was read).
  List<Promotion> get promotions =>
      [..._promotions]..sort(OfferPricing.byOrder);

  Promotion? promotionById(String id) =>
      _promotions.where((p) => p.id == id).firstOrNull;

  /// Special offers live today, in tie-break order.
  List<Promotion> get liveSpecials =>
      OfferPricing.liveSpecials(_promotions, today);

  /// Combos live today whose dishes are all on the menu, in display order.
  /// One with a sold-out dish is listed but cannot be ordered
  /// ([ComboView.dishesOrderable]).
  List<ComboView> get liveCombos {
    final menu = {for (final item in _all) item.id: item};
    return [
      for (final combo in promotions)
        if (combo.isCombo && combo.isLiveOn(today))
          if (combo.comboView(menu) case final view?)
            if (view.dishes.every((d) => !d.item.isArchived)) view,
    ];
  }

  /// Special offers live today that cover at least one dish guests can see:
  /// the banners on the guest home screen.
  List<Promotion> get specialBanners {
    final visible = {for (final item in items) item.id};
    return [
      for (final special in liveSpecials)
        if (special.items.any((i) => visible.contains(i.itemId))) special,
    ]..sort(OfferPricing.byOrder);
  }

  /// The best special offer live today on [item] (as ordered without
  /// extras) and what it takes off one, for badges and prices on menus.
  ({Promotion offer, Money perUnit})? specialFor(MenuItem item) =>
      OfferPricing.bestSpecial(
        item.id,
        ComboView.defaultUnitPrice(item),
        liveSpecials,
      );

  /// The dishes [special] covers that guests can see.
  List<MenuItem> dishesIn(Promotion special) => [
    for (final entry in special.items)
      if (byId(entry.itemId) case final item?)
        if (!item.isArchived) item,
  ];

  /// [combo] with its dishes from the current menu.
  ComboView? comboView(Promotion combo) =>
      combo.comboView({for (final item in _all) item.id: item});

  /// Returns a message for the first invalid field, or null (same rules as
  /// the server's PromotionService).
  String? validatePromotion(Promotion promotion) {
    final title = promotion.title.trim();
    if (title.length < 2 || title.length > 60) {
      return 'Give it a title of 2 to 60 characters.';
    }
    if (promotion.description.trim().length > 300) {
      return 'The description can be at most 300 characters.';
    }
    if (!_isAllowedImage(promotion.image)) {
      return 'Choose a bundled photo or upload a picture.';
    }
    final dates = SettingsController.validateDates(
      promotion.startsOn,
      promotion.endsOn,
    );
    if (dates != null) return dates;
    final limit = SettingsController.validateUsageLimit(promotion.usageLimit);
    if (limit != null) return limit;
    final ids = promotion.items.map((i) => i.itemId).toList();
    if (ids.toSet().length != ids.length) {
      return 'Each dish can be listed once.';
    }
    for (final id in ids) {
      final dish = byId(id);
      if (dish == null || dish.isArchived) {
        return 'Some of the chosen dishes are no longer on the menu.';
      }
    }
    if (promotion.isSpecial) {
      if (ids.isEmpty || ids.length > maxSpecialDishes) {
        return 'Choose 1 to $maxSpecialDishes dishes for the offer.';
      }
      final value = promotion.discountValue;
      if (promotion.discountType == DiscountType.percent) {
        if (value < 100 || value > 10000) {
          return 'A percentage discount is 1% to 100%.';
        }
      } else if (value < 100 || value > 10000000) {
        return 'A flat discount is '
            '${CurrencyFormatter.format(const Money.rupees(1))} to '
            '${CurrencyFormatter.format(const Money.rupees(100000))}.';
      }
      return null;
    }
    final units = promotion.items.fold(0, (sum, i) => sum + i.quantity);
    if (ids.isEmpty || ids.length > maxComboDishes || units < 2) {
      return 'A combo holds at least two dishes, from 1 to $maxComboDishes '
          'different ones.';
    }
    if (promotion.items.any(
      (i) => i.quantity < 1 || i.quantity > maxComboQuantity,
    )) {
      return 'Each dish can be in a combo 1 to $maxComboQuantity times.';
    }
    final price = promotion.comboPrice;
    if (price == null || price.paise < 100 || price.paise > 10000000) {
      return 'The combo price must be between '
          '${CurrencyFormatter.format(const Money.rupees(1))} and '
          '${CurrencyFormatter.format(const Money.rupees(100000))}.';
    }
    final original = comboView(promotion)!.originalPrice;
    if (price.compareTo(original) >= 0) {
      return 'A combo must cost less than its dishes do separately '
          '(${CurrencyFormatter.format(original)}).';
    }
    return null;
  }

  static const maxSpecialDishes = 100;
  static const maxComboDishes = 10;
  static const maxComboQuantity = 10;

  /// A unique id for a new offer, e.g. `combo_family_feast`. Never a dish's
  /// id: a combo line is filed under its combo's id.
  String newPromotionId(String title, PromotionKind kind) {
    var base = '${kind.name}_$title';
    if (base.length > 34) base = base.substring(0, 34);
    return _uniqueId(base, {
      ..._promotions.map((p) => p.id),
      ..._all.map((i) => i.id),
    }, fallback: kind.name);
  }

  Future<void> savePromotion(Promotion promotion) async {
    _require(Permission.manageOffers);
    final error = validatePromotion(promotion);
    if (error != null) throw ValidationException(error);
    final previous = promotionById(promotion.id);
    final saved = await _repository.savePromotion(
      promotion.copyWith(
        title: promotion.title.trim(),
        description: promotion.description.trim(),
      ),
    );
    _replacePromotion(saved);
    await _audit?.record(
      previous == null ? 'promotion.create' : 'promotion.update',
      '${previous == null ? 'Created' : 'Updated'} '
      '${saved.kind.label.toLowerCase()} "${saved.title}"',
      targetId: saved.id,
    );
  }

  Future<void> setPromotionActive(String id, bool active) async {
    _require(Permission.manageOffers);
    final promotion = promotionById(id);
    if (promotion == null || promotion.isActive == active) return;
    _replacePromotion(await _repository.setPromotionActive(id, active));
    await _audit?.record(
      'promotion.toggle',
      '${active ? 'Activated' : 'Paused'} "${promotion.title}"',
      targetId: id,
    );
  }

  /// Orders that used it keep their own copy of what it gave them.
  Future<void> deletePromotion(String id) async {
    _require(Permission.manageOffers);
    final promotion = promotionById(id);
    if (promotion == null) return;
    await _repository.deletePromotion(id);
    _promotions = [
      for (final p in _promotions)
        if (p.id != id) p,
    ];
    notifyListeners();
    await _audit?.record(
      'promotion.delete',
      'Deleted "${promotion.title}"',
      targetId: id,
    );
  }

  void _replacePromotion(Promotion saved) {
    final exists = _promotions.any((p) => p.id == saved.id);
    _promotions = exists
        ? [for (final p in _promotions) p.id == saved.id ? saved : p]
        : [..._promotions, saved];
    notifyListeners();
  }

  /// Whether offer pictures can be uploaded (not in the offline demo).
  bool get canUploadOfferPhotos => _repository is OfferImageUploader;

  /// Uploads a picture for a special offer or combo and returns its URL.
  Future<String> uploadOfferPhoto(List<int> bytes) async {
    _require(Permission.manageOffers);
    final repository = _repository;
    if (repository is! OfferImageUploader) {
      throw const ValidationException(
        'This build has no image storage, so pictures cannot be uploaded.',
      );
    }
    final uploader = repository as OfferImageUploader;
    if (bytes.isEmpty) {
      throw const ValidationException('That picture file is empty.');
    }
    if (bytes.length > DishImageUploader.maxBytes) {
      final limit = DishImageUploader.maxBytes ~/ (1024 * 1024);
      throw ValidationException(
        'That picture is too large. The limit is $limit MB.',
      );
    }
    final extension = DishImageUploader.extensionFor(bytes) ?? 'img';
    return uploader.uploadOfferImage(
      bytes: bytes,
      filename: 'offer.$extension',
    );
  }

  /// Restores the original menu (demo reset).
  Future<void> resetMenu() async {
    await _repository.reset();
    await load(force: true);
  }

  void _require(Permission permission) {
    final guard = _guard;
    if (guard == null) {
      throw StateError('Admin changes need an AccessGuard.');
    }
    guard.require(permission);
  }
}
