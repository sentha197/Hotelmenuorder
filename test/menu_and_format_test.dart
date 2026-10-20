import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/core/utils/currency.dart';
import 'package:menu_order/core/utils/formatters.dart';
import 'package:menu_order/data/demo/demo_menu_data.dart';
import 'package:menu_order/data/models/menu_filter.dart';
import 'package:menu_order/data/models/menu_item.dart';

void main() {
  group('demo menu', () {
    test('has at least 15 dishes with unique ids and their own photos', () {
      expect(demoMenuItems.length, greaterThanOrEqualTo(15));
      expect(
        demoMenuItems.map((item) => item.id).toSet(),
        hasLength(demoMenuItems.length),
      );
      expect(
        demoMenuItems.map((item) => item.image).toSet(),
        hasLength(demoMenuItems.length),
      );
    });

    test('includes the required dishes at the required prices', () {
      const expected = {
        'Chicken 65': 180,
        'Paneer Tikka': 200,
        'French Fries': 120,
        'Chilli Chicken': 190,
        'Spring Roll': 140,
        'Veg Manchurian': 150,
        'Chicken Biryani': 260,
        'Veg Biryani': 200,
        'Butter Chicken': 280,
        'Paneer Butter Masala': 230,
        'Masala Dosa': 100,
        'Butter Naan': 45,
        'Fresh Lime Soda': 80,
        'Cold Coffee': 120,
        'Gulab Jamun': 90,
      };
      expected.forEach((name, rupees) {
        final item = demoMenuItems.firstWhere((item) => item.name == name);
        expect(item.price, Money.rupees(rupees), reason: name);
      });
    });
  });

  group('MenuFilter', () {
    test('Veg shows only vegetarian dishes, Non Veg only non-vegetarian', () {
      final veg = const MenuFilter(diet: DietFilter.veg).apply(demoMenuItems);
      final nonVeg = const MenuFilter(
        diet: DietFilter.nonVeg,
      ).apply(demoMenuItems);
      expect(veg, isNotEmpty);
      expect(nonVeg, isNotEmpty);
      expect(veg.every((item) => item.isVeg), isTrue);
      expect(nonVeg.every((item) => !item.isVeg), isTrue);
      expect(veg.length + nonVeg.length, demoMenuItems.length);
      expect(
        const MenuFilter().apply(demoMenuItems),
        hasLength(demoMenuItems.length),
      );
    });

    test('category, diet and search combine', () {
      final starters = const MenuFilter(
        category: MenuCategory.starters,
        diet: DietFilter.veg,
      ).apply(demoMenuItems);
      expect(
        starters.every(
          (item) => item.isVeg && item.category == MenuCategory.starters,
        ),
        isTrue,
      );

      final vegChicken = const MenuFilter(
        diet: DietFilter.veg,
        query: 'chicken',
      ).apply(demoMenuItems);
      expect(vegChicken, isEmpty);

      final paneer = const MenuFilter(query: '  PANEER ').apply(demoMenuItems);
      expect(
        paneer.map((item) => item.name),
        containsAll(['Paneer Tikka', 'Paneer Butter Masala']),
      );
    });

    test('sorts by price', () {
      final cheapest = const MenuFilter(
        sort: MenuSort.priceLowToHigh,
      ).apply(demoMenuItems);
      for (var i = 1; i < cheapest.length; i++) {
        expect(cheapest[i - 1].price <= cheapest[i].price, isTrue);
      }
      final dearest = const MenuFilter(
        sort: MenuSort.priceHighToLow,
      ).apply(demoMenuItems);
      expect(dearest.first.price, cheapest.last.price);
    });

    test('favorites filter uses the provided favorite ids', () {
      final favorites = const MenuFilter(
        favoritesOnly: true,
      ).apply(demoMenuItems, favorites: {'masala_dosa', 'lassi'});
      expect(favorites.map((item) => item.id).toSet(), {
        'masala_dosa',
        'lassi',
      });
    });
  });

  group('formatting', () {
    test('currency uses ₹ with Indian digit grouping', () {
      expect(CurrencyFormatter.format(const Money.rupees(180)), '₹180');
      expect(CurrencyFormatter.format(const Money(47250)), '₹472.50');
      expect(CurrencyFormatter.format(const Money.rupees(1250)), '₹1,250');
      expect(CurrencyFormatter.format(const Money.rupees(123456)), '₹1,23,456');
      expect(CurrencyFormatter.formatExtra(const Money.rupees(30)), '+₹30');
    });

    test('table and order numbers', () {
      expect(AppFormat.table(5), '05');
      expect(AppFormat.table(12), '12');
      expect(AppFormat.orderNumber('OD12345'), '#OD12345');
      expect(AppFormat.itemCount(1), '1 item');
      expect(AppFormat.itemCount(3), '3 items');
    });
  });
}

extension on Money {
  bool operator <=(Money other) => compareTo(other) <= 0;
}
