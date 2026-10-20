import '../../core/utils/currency.dart';

enum MenuCategory {
  starters('Starters', 'assets/images/chicken_65.jpg'),
  mainCourse('Main Course', 'assets/images/butter_chicken.jpg'),
  beverages('Beverages', 'assets/images/cold_coffee.jpg'),
  desserts('Desserts', 'assets/images/gulab_jamun.jpg');

  const MenuCategory(this.label, this.coverImage);

  final String label;
  final String coverImage;
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

  final String id;
  final String name;
  final Money price;
}

/// A portion size. The first option of a dish is its default.
class PortionOption {
  const PortionOption({
    required this.id,
    required this.label,
    this.extraPrice = Money.zero,
    this.detail,
  });

  final String id;
  final String label;
  final Money extraPrice;
  final String? detail;
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
    required this.isVeg,
    required this.rating,
    required this.reviewCount,
    this.isPopular = false,
    this.isChefSpecial = false,
    this.hasSpiceLevel = false,
    this.defaultSpice = SpiceLevel.medium,
    this.portions = const [],
    this.addOns = const [],
    this.prepMinutes = 15,
  });

  final String id;
  final String name;
  final MenuCategory category;
  final String description;
  final String shortDescription;
  final Money price;
  final String image;
  final bool isVeg;
  final double rating;
  final int reviewCount;
  final bool isPopular;
  final bool isChefSpecial;
  final bool hasSpiceLevel;
  final SpiceLevel defaultSpice;
  final List<PortionOption> portions;
  final List<AddOn> addOns;
  final int prepMinutes;

  PortionOption? get defaultPortion => portions.isEmpty ? null : portions.first;

  bool get isCustomizable =>
      hasSpiceLevel || portions.length > 1 || addOns.isNotEmpty;

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

  @override
  bool operator ==(Object other) => other is MenuItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
