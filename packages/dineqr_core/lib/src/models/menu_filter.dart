import 'menu_item.dart';

enum DietFilter {
  all('All'),
  veg('Veg'),
  nonVeg('Non Veg');

  const DietFilter(this.label);

  final String label;

  bool matches(MenuItem item) => switch (this) {
    DietFilter.all => true,
    DietFilter.veg => item.isVeg,
    DietFilter.nonVeg => !item.isVeg,
  };
}

enum MenuSort {
  popularity('Popularity'),
  rating('Top rated'),
  priceLowToHigh('Price: low to high'),
  priceHighToLow('Price: high to low');

  const MenuSort(this.label);

  final String label;
}

/// Category, diet, search and sort applied together to the menu.
class MenuFilter {
  const MenuFilter({
    this.category,
    this.diet = DietFilter.all,
    this.query = '',
    this.sort = MenuSort.popularity,
    this.favoritesOnly = false,
  });

  /// `null` means every category.
  final MenuCategory? category;
  final DietFilter diet;
  final String query;
  final MenuSort sort;
  final bool favoritesOnly;

  bool get isDefault =>
      diet == DietFilter.all &&
      query.trim().isEmpty &&
      sort == MenuSort.popularity;

  MenuFilter copyWith({
    MenuCategory? Function()? category,
    DietFilter? diet,
    String? query,
    MenuSort? sort,
    bool? favoritesOnly,
  }) => MenuFilter(
    category: category != null ? category() : this.category,
    diet: diet ?? this.diet,
    query: query ?? this.query,
    sort: sort ?? this.sort,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
  );

  bool matches(MenuItem item, {Set<String> favorites = const {}}) {
    if (category != null && item.category != category) return false;
    if (!diet.matches(item)) return false;
    if (favoritesOnly && !favorites.contains(item.id)) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return item.name.toLowerCase().contains(q) ||
        item.shortDescription.toLowerCase().contains(q) ||
        item.category.label.toLowerCase().contains(q);
  }

  List<MenuItem> apply(
    Iterable<MenuItem> items, {
    Set<String> favorites = const {},
  }) {
    final q = query.trim().toLowerCase();
    final result = items
        .where((item) => matches(item, favorites: favorites))
        .toList();
    int byPopularity(MenuItem a, MenuItem b) {
      // Name matches rank above description matches while searching.
      if (q.isNotEmpty) {
        final aName = a.name.toLowerCase().contains(q) ? 0 : 1;
        final bName = b.name.toLowerCase().contains(q) ? 0 : 1;
        if (aName != bName) return aName.compareTo(bName);
      }
      return b.reviewCount.compareTo(a.reviewCount);
    }

    switch (sort) {
      case MenuSort.popularity:
        result.sort(byPopularity);
      case MenuSort.rating:
        result.sort((a, b) => b.rating.compareTo(a.rating));
      case MenuSort.priceLowToHigh:
        result.sort((a, b) => a.price.compareTo(b.price));
      case MenuSort.priceHighToLow:
        result.sort((a, b) => b.price.compareTo(a.price));
    }
    // Sold-out dishes stay visible but go to the end.
    return [
      ...result.where((item) => item.isOrderable),
      ...result.where((item) => !item.isOrderable),
    ];
  }
}
