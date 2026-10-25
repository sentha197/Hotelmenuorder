import '../utils/currency.dart';

/// A menu category. Categories are restaurant data (editable from the admin
/// dashboard); the four defaults below seed a fresh install.
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.label,
    required this.coverImage,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
    id: json['id'] as String,
    label: json['label'] as String,
    coverImage: json['cover'] as String? ?? '',
    sortOrder: json['sort'] as int? ?? 0,
    isActive: json['active'] as bool? ?? true,
  );

  static const starters = MenuCategory(
    id: 'starters',
    label: 'Starters',
    coverImage: 'assets/images/chicken_65.jpg',
  );
  static const mainCourse = MenuCategory(
    id: 'mainCourse',
    label: 'Main Course',
    coverImage: 'assets/images/butter_chicken.jpg',
    sortOrder: 1,
  );
  static const beverages = MenuCategory(
    id: 'beverages',
    label: 'Beverages',
    coverImage: 'assets/images/cold_coffee.jpg',
    sortOrder: 2,
  );
  static const desserts = MenuCategory(
    id: 'desserts',
    label: 'Desserts',
    coverImage: 'assets/images/gulab_jamun.jpg',
    sortOrder: 3,
  );

  /// Categories of a fresh install, in display order.
  static const defaults = [starters, mainCourse, beverages, desserts];

  final String id;
  final String label;
  final String coverImage;

  /// Position in menus (lower first).
  final int sortOrder;

  /// Inactive categories (and their dishes) are hidden from guests.
  final bool isActive;

  MenuCategory copyWith({
    String? label,
    String? coverImage,
    int? sortOrder,
    bool? isActive,
  }) => MenuCategory(
    id: id,
    label: label ?? this.label,
    coverImage: coverImage ?? this.coverImage,
    sortOrder: sortOrder ?? this.sortOrder,
    isActive: isActive ?? this.isActive,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'cover': coverImage,
    'sort': sortOrder,
    'active': isActive,
  };

  // Identity is the id: renaming a category keeps its dishes.
  @override
  bool operator ==(Object other) => other is MenuCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MenuCategory($id)';
}

enum SpiceLevel {
  mild('Mild'),
  medium('Medium'),
  spicy('Spicy');

  const SpiceLevel(this.label);

  final String label;

  static SpiceLevel? tryParse(String? name) {
    for (final level in values) {
      if (level.name == name) return level;
    }
    return null;
  }
}

/// A paid extra that can be added to a dish (e.g. extra cheese).
class AddOn {
  const AddOn({required this.id, required this.name, required this.price});

  factory AddOn.fromJson(Map<String, dynamic> json) => AddOn(
    id: json['id'] as String,
    name: json['name'] as String,
    price: Money(json['price'] as int),
  );

  final String id;
  final String name;
  final Money price;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price.paise,
  };
}

/// A portion size. The first option of a dish is its default.
class PortionOption {
  const PortionOption({
    required this.id,
    required this.label,
    this.extraPrice = Money.zero,
    this.detail,
  });

  factory PortionOption.fromJson(Map<String, dynamic> json) => PortionOption(
    id: json['id'] as String,
    label: json['label'] as String,
    extraPrice: Money(json['extra'] as int? ?? 0),
    detail: json['detail'] as String?,
  );

  final String id;
  final String label;
  final Money extraPrice;
  final String? detail;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    if (!extraPrice.isZero) 'extra': extraPrice.paise,
    if (detail != null) 'detail': detail,
  };
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.shortDescription,
    required this.price,
    required this.image,
    this.gallery = const [],
    required this.isVeg,
    required this.rating,
    required this.reviewCount,
    this.isPopular = false,
    this.isChefSpecial = false,
    this.isFeatured = false,
    this.hasSpiceLevel = false,
    this.defaultSpice = SpiceLevel.medium,
    this.portions = const [],
    this.addOns = const [],
    this.prepMinutes = 15,
    this.isAvailable = true,
    this.isArchived = false,
  });

  /// [categories] resolves the stored category id; unknown ids fall back to a
  /// placeholder so a dish is never lost.
  factory MenuItem.fromJson(
    Map<String, dynamic> json, {
    required Map<String, MenuCategory> categories,
  }) {
    final categoryId = json['category'] as String;
    return MenuItem(
      id: json['id'] as String,
      name: json['name'] as String,
      category:
          categories[categoryId] ??
          MenuCategory(id: categoryId, label: categoryId, coverImage: ''),
      description: json['description'] as String? ?? '',
      shortDescription: json['short'] as String? ?? '',
      price: Money(json['price'] as int),
      image: json['image'] as String? ?? '',
      gallery: [
        for (final path in json['gallery'] as List? ?? const [])
          if (path is String && path.isNotEmpty) path,
      ],
      isVeg: json['veg'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: json['reviews'] as int? ?? 0,
      isPopular: json['popular'] as bool? ?? false,
      isChefSpecial: json['special'] as bool? ?? false,
      isFeatured: json['featured'] as bool? ?? false,
      hasSpiceLevel: json['spicy'] as bool? ?? false,
      defaultSpice:
          SpiceLevel.tryParse(json['defaultSpice'] as String?) ??
          SpiceLevel.medium,
      portions: [
        for (final p in json['portions'] as List? ?? const [])
          PortionOption.fromJson(p as Map<String, dynamic>),
      ],
      addOns: [
        for (final a in json['addOns'] as List? ?? const [])
          AddOn.fromJson(a as Map<String, dynamic>),
      ],
      prepMinutes: json['prep'] as int? ?? 15,
      isAvailable: json['available'] as bool? ?? true,
      isArchived: json['archived'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final MenuCategory category;
  final String description;
  final String shortDescription;
  final Money price;
  final String image;

  /// Extra photos shown after [image] in the dish gallery (a backend may
  /// send several; the demo dishes have one photo each).
  final List<String> gallery;

  /// [image] followed by the [gallery], without blanks or repeats.
  List<String> get photos =>
      {if (image.isNotEmpty) image, ...gallery}.toList(growable: false);

  final bool isVeg;
  final double rating;
  final int reviewCount;
  final bool isPopular;
  final bool isChefSpecial;

  /// Shown as a banner in the home screen carousel.
  final bool isFeatured;
  final bool hasSpiceLevel;
  final SpiceLevel defaultSpice;
  final List<PortionOption> portions;
  final List<AddOn> addOns;
  final int prepMinutes;

  /// Temporarily sold out (still listed, cannot be ordered).
  final bool isAvailable;

  /// Removed from the menu but kept for history and possible restore.
  final bool isArchived;

  PortionOption? get defaultPortion => portions.isEmpty ? null : portions.first;

  bool get isCustomizable =>
      hasSpiceLevel || portions.length > 1 || addOns.isNotEmpty;

  /// Whether guests can order it right now.
  bool get isOrderable => isAvailable && !isArchived && category.isActive;

  PortionOption? portionById(String? id) {
    for (final portion in portions) {
      if (portion.id == id) return portion;
    }
    return null;
  }

  AddOn? addOnById(String id) {
    for (final addOn in addOns) {
      if (addOn.id == id) return addOn;
    }
    return null;
  }

  MenuItem copyWith({
    String? name,
    MenuCategory? category,
    String? description,
    String? shortDescription,
    Money? price,
    String? image,
    List<String>? gallery,
    bool? isVeg,
    bool? isPopular,
    bool? isChefSpecial,
    bool? isFeatured,
    bool? hasSpiceLevel,
    SpiceLevel? defaultSpice,
    List<PortionOption>? portions,
    List<AddOn>? addOns,
    int? prepMinutes,
    bool? isAvailable,
    bool? isArchived,
  }) => MenuItem(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    description: description ?? this.description,
    shortDescription: shortDescription ?? this.shortDescription,
    price: price ?? this.price,
    image: image ?? this.image,
    gallery: gallery ?? this.gallery,
    isVeg: isVeg ?? this.isVeg,
    rating: rating,
    reviewCount: reviewCount,
    isPopular: isPopular ?? this.isPopular,
    isChefSpecial: isChefSpecial ?? this.isChefSpecial,
    isFeatured: isFeatured ?? this.isFeatured,
    hasSpiceLevel: hasSpiceLevel ?? this.hasSpiceLevel,
    defaultSpice: defaultSpice ?? this.defaultSpice,
    portions: portions ?? this.portions,
    addOns: addOns ?? this.addOns,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    isAvailable: isAvailable ?? this.isAvailable,
    isArchived: isArchived ?? this.isArchived,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.id,
    'description': description,
    'short': shortDescription,
    'price': price.paise,
    'image': image,
    if (gallery.isNotEmpty) 'gallery': gallery,
    'veg': isVeg,
    'rating': rating,
    'reviews': reviewCount,
    if (isPopular) 'popular': true,
    if (isChefSpecial) 'special': true,
    if (isFeatured) 'featured': true,
    if (hasSpiceLevel) 'spicy': true,
    'defaultSpice': defaultSpice.name,
    if (portions.isNotEmpty) 'portions': [for (final p in portions) p.toJson()],
    if (addOns.isNotEmpty) 'addOns': [for (final a in addOns) a.toJson()],
    'prep': prepMinutes,
    if (!isAvailable) 'available': false,
    if (isArchived) 'archived': true,
  };

  // No value equality on purpose: an edited dish is a new object, so screens
  // selecting a dish rebuild when an admin changes it. Compare ids instead.
}
