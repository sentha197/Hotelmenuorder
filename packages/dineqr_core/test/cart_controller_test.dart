import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

MenuItem dish(String id) => demoMenuItems.firstWhere((item) => item.id == id);

void main() {
  late MemoryStore store;
  late CartController cart;
  final chicken65 = dish('chicken_65'); // ₹180, spice, Half/Full(+140), dips
  final fries = dish('french_fries'); // ₹120
  final naan = dish('butter_naan'); // ₹45

  setUp(() {
    store = MemoryStore();
    cart = CartController(store);
  });

  group('adding items', () {
    test('creates a line with the default customization', () {
      final line = cart.add(chicken65);
      expect(cart.lines, hasLength(1));
      expect(line.quantity, 1);
      expect(line.customization.spice, SpiceLevel.medium);
      expect(line.customization.portionId, 'half');
      expect(cart.totalQuantity, 1);
    });

    test('identical customizations merge into one line', () {
      cart.add(chicken65);
      cart.add(chicken65, quantity: 2);
      cart.add(
        chicken65,
        customization: DishCustomization(
          spice: SpiceLevel.medium,
          portionId: 'half',
        ),
      );
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.quantity, 4);
    });

    test('add-on order does not create a different line', () {
      cart.add(
        chicken65,
        customization: DishCustomization(
          spice: SpiceLevel.spicy,
          addOnIds: ['mint_mayo', 'extra_onion'],
        ),
      );
      cart.add(
        chicken65,
        customization: DishCustomization(
          spice: SpiceLevel.spicy,
          addOnIds: ['extra_onion', 'mint_mayo', 'mint_mayo'],
        ),
      );
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.quantity, 2);
    });

    test('different customizations stay separate', () {
      cart.add(chicken65);
      cart.add(
        chicken65,
        customization: DishCustomization(
          spice: SpiceLevel.spicy,
          portionId: 'half',
        ),
      );
      cart.add(
        chicken65,
        customization: DishCustomization(
          spice: SpiceLevel.medium,
          portionId: 'full',
        ),
      );
      expect(cart.lines, hasLength(3));
      expect(cart.quantityOfItem('chicken_65'), 3);
    });

    test('unit price includes portion and add-on surcharges', () {
      final line = cart.add(
        chicken65,
        customization: DishCustomization(
          spice: SpiceLevel.mild,
          portionId: 'full',
          addOnIds: ['mint_mayo'],
        ),
        quantity: 2,
      );
      expect(line.unitPrice, const Money.rupees(180 + 140 + 30));
      expect(line.lineTotal, const Money.rupees(700));
      expect(line.optionLabels, ['Spice: Mild', 'Full', 'Mint Mayo Dip']);
    });

    test('rejects quantities below one and clamps to the maximum', () {
      expect(() => cart.add(fries, quantity: 0), throwsArgumentError);
      cart.add(fries, quantity: 50);
      expect(cart.lines.single.quantity, CartController.maxQuantity);
    });
  });

  group('changing quantities', () {
    test('increment and decrement update the line', () {
      final id = cart.add(fries).id;
      cart.increment(id);
      cart.increment(id);
      expect(cart.lineById(id)!.quantity, 3);
      expect(cart.decrement(id), DecrementResult.decremented);
      expect(cart.lineById(id)!.quantity, 2);
    });

    test('decrementing the last unit removes the line', () {
      final id = cart.add(fries).id;
      expect(cart.decrement(id), DecrementResult.removed);
      expect(cart.isEmpty, isTrue);
    });

    test('quick add repeats the last customization', () {
      final spicy = DishCustomization(
        spice: SpiceLevel.spicy,
        portionId: 'full',
      );
      cart.add(chicken65, customization: spicy);
      cart.quickAdd(chicken65);
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.customization, spicy);
      expect(cart.lines.single.quantity, 2);
    });

    test('quick remove is ambiguous when several customizations exist', () {
      cart.add(chicken65);
      cart.add(
        chicken65,
        customization: DishCustomization(spice: SpiceLevel.spicy),
      );
      expect(cart.quickRemove(chicken65), DecrementResult.ambiguous);
      expect(cart.totalQuantity, 2);
      expect(cart.quickRemove(fries), DecrementResult.notInCart);
    });
  });

  group('removing items', () {
    test('remove returns the line and restore puts it back in place', () {
      cart.add(fries);
      final naanId = cart.add(naan, quantity: 2).id;
      cart.add(chicken65);
      final removed = cart.remove(naanId)!;
      expect(removed.index, 1);
      expect(cart.lines.map((line) => line.item.id), [
        'french_fries',
        'chicken_65',
      ]);
      cart.restore(removed);
      expect(cart.lines.map((line) => line.item.id), [
        'french_fries',
        'butter_naan',
        'chicken_65',
      ]);
      expect(cart.lineById(naanId)!.quantity, 2);
    });

    test('remove of an unknown line returns null', () {
      expect(cart.remove('missing'), isNull);
    });

    test('clear empties the cart and instructions', () {
      cart.add(fries);
      cart.updateInstructions('No onions');
      cart.clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.totalQuantity, 0);
      expect(cart.specialInstructions, isEmpty);
    });

    test('clear can keep the special instructions', () {
      cart.add(fries);
      cart.updateInstructions('No onions');
      cart.clear(keepInstructions: true);
      expect(cart.isEmpty, isTrue);
      expect(cart.specialInstructions, 'No onions');
    });
  });

  group('pricing', () {
    test('subtotal sums every line', () {
      cart.add(chicken65, quantity: 2); // 360
      cart.add(fries); // 120
      expect(cart.subtotal, const Money.rupees(480));
    });

    test('tax and total use the configured rate', () {
      cart.add(chicken65, quantity: 2);
      cart.add(fries);
      final bill = cart.bill;
      expect(bill.tax, const Money.rupees(24));
      expect(bill.total, const Money.rupees(504));
      expect(bill.taxLabel, 'Taxes (5%)');
    });

    test('tax is rounded half-up to the paisa', () {
      cart.add(chicken65); // 180
      cart.add(dish('veg_manchurian')); // 150
      cart.add(fries); // 120 -> subtotal 450
      expect(cart.bill.tax, const Money(2250));
      expect(cart.bill.total, const Money(47250));
      expect(CurrencyFormatter.format(cart.bill.total), '₹472.50');
      expect(const Money(1).applyRate(5000), const Money(1)); // 0.5 -> 1
      expect(const Money(3).applyRate(1000), const Money(0)); // 0.3 -> 0
    });

    test('a custom tax rate is applied consistently', () {
      final custom = CartController(
        MemoryStore(),
        pricing: const PricingConfig(taxRateBasisPoints: 1800),
      );
      custom.add(fries, quantity: 2); // 240
      expect(custom.bill.tax, const Money.rupees(43) + const Money(20));
      expect(custom.bill.total, const Money(28320));
      expect(custom.bill.taxLabel, 'Taxes (18%)');
    });

    test('an empty cart costs nothing', () {
      expect(cart.bill.subtotal, Money.zero);
      expect(cart.bill.total, Money.zero);
    });
  });

  group('persistence', () {
    test('cart and instructions are restored from storage', () {
      cart.add(
        chicken65,
        customization: DishCustomization(spice: SpiceLevel.spicy),
      );
      cart.add(fries, quantity: 3);
      cart.updateInstructions('Less oil');

      final restored = CartController(store)..hydrate(demoMenuItems);
      expect(restored.lines, hasLength(2));
      expect(restored.lines.first.customization.spice, SpiceLevel.spicy);
      expect(restored.lines.last.quantity, 3);
      expect(restored.specialInstructions, 'Less oil');
      expect(restored.bill.total, cart.bill.total);
    });

    test('lines for dishes no longer on the menu are dropped', () {
      cart.add(chicken65);
      cart.add(fries);
      final restored = CartController(store)
        ..hydrate(demoMenuItems.where((item) => item.id != 'french_fries'));
      expect(restored.lines.map((line) => line.item.id), ['chicken_65']);
    });

    test('corrupt storage is ignored', () {
      final corrupt = MemoryStore({StorageKeys.cart: 'not json'});
      final restored = CartController(corrupt)..hydrate(demoMenuItems);
      expect(restored.isEmpty, isTrue);
    });
  });
}
