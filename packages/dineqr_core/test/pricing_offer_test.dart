import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bill breakdown', () {
    test('discount, service charge and tax follow one formula', () {
      final bill = BillBreakdown.fromSubtotal(
        const Money.rupees(1000),
        const PricingConfig(
          taxRateBasisPoints: 500,
          serviceChargeBasisPoints: 1000,
        ),
        discount: const Money.rupees(100),
        discountLabel: 'Offer TEST',
      );
      // (1000 − 100) = 900; service 10% = 90; taxable 990; tax 5% = 49.50.
      expect(bill.discount, const Money.rupees(100));
      expect(bill.serviceCharge, const Money.rupees(90));
      expect(bill.taxableAmount, const Money.rupees(990));
      expect(bill.tax, const Money(4950));
      expect(bill.total, const Money(103950));
      expect(bill.discountLabel, 'Offer TEST');
      expect(bill.hasDiscount && bill.hasServiceCharge, isTrue);
    });

    test('a discount never exceeds the subtotal', () {
      final bill = BillBreakdown.fromSubtotal(
        const Money.rupees(50),
        const PricingConfig(),
        discount: const Money.rupees(75),
      );
      expect(bill.discount, const Money.rupees(50));
      expect(bill.total, Money.zero);
    });

    test('tax rounds half up to the paisa', () {
      // 5% of ₹10.10 = 50.5 paise → 51 paise.
      final bill = BillBreakdown.fromSubtotal(
        const Money(1010),
        const PricingConfig(),
      );
      expect(bill.tax, const Money(51));
      expect(bill.total, const Money(1061));
    });

    test('labels show configured names and rates', () {
      const config = PricingConfig(
        taxName: 'GST',
        taxRateBasisPoints: 1250,
        serviceChargeBasisPoints: 750,
      );
      expect(config.taxLabel, 'GST (12.5%)');
      expect(config.serviceChargeLabel, contains('7.5%'));
    });
  });

  group('offers', () {
    const percent = DiscountOffer(
      code: 'WELCOME10',
      title: 'Welcome',
      type: DiscountType.percent,
      value: 1000,
      minSubtotal: Money.rupees(300),
      maxDiscount: Money.rupees(100),
    );
    const flat = DiscountOffer(
      code: 'FEAST75',
      title: 'Feast',
      type: DiscountType.flat,
      value: 7500,
      minSubtotal: Money.rupees(800),
    );

    test('percentage offers respect the minimum and the cap', () {
      expect(percent.check(const Money.rupees(299)), OfferError.belowMinimum);
      expect(percent.discountFor(const Money.rupees(299)), Money.zero);
      expect(percent.shortfall(const Money.rupees(299)), const Money.rupees(1));
      expect(percent.discountFor(const Money.rupees(500)), Money.rupees(50));
      expect(percent.discountFor(const Money.rupees(5000)), Money.rupees(100));
      expect(percent.benefit, '10% off');
      expect(percent.summary, '10% off · min ₹300 · up to ₹100');
    });

    test('flat offers and inactive offers', () {
      expect(flat.discountFor(const Money.rupees(800)), Money.rupees(75));
      final off = flat.copyWith(isActive: false);
      expect(off.check(const Money.rupees(900)), OfferError.inactive);
      expect(off.discountFor(const Money.rupees(900)), Money.zero);
    });

    test('codes are normalised and validated', () {
      expect(DiscountOffer.normalize(' welcome10 '), 'WELCOME10');
      expect(DiscountOffer.isValidCode('ab'), isFalse);
      expect(DiscountOffer.isValidCode('SAVE-10'), isFalse);
      expect(DiscountOffer.isValidCode('save10'), isTrue);
    });

    test('the cart applies a saved code once it qualifies', () {
      const settings = RestaurantSettings();
      final cart = CartController(
        MemoryStore(),
        pricingSource: () => settings.pricing,
        offerLookup: settings.offerByCode,
      );
      expect(cart.applyOffer('NOPE99'), OfferError.unknownCode);
      expect(cart.offerCode, isNull);

      cart.add(dish('masala_dosa'));
      expect(cart.applyOffer('welcome10'), OfferError.belowMinimum);
      expect(cart.offerCode, 'WELCOME10');
      expect(cart.discount, Money.zero);
      expect(cart.bill.hasDiscount, isFalse);

      cart.add(dish('chicken_65'), quantity: 3);
      expect(cart.offerProblem, isNull);
      expect(cart.discount, isNot(Money.zero));
      expect(cart.bill.discountLabel, 'Offer WELCOME10');
      expect(
        cart.bill.total,
        BillBreakdown.fromSubtotal(
          cart.subtotal,
          settings.pricing,
          discount: cart.discount,
        ).total,
      );

      cart.removeOffer();
      expect(cart.bill.hasDiscount, isFalse);
    });

    test('a saved code survives a restart but is cleared with the cart', () {
      const settings = RestaurantSettings();
      final store = MemoryStore();
      CartController(store, offerLookup: settings.offerByCode)
        ..add(dish('chicken_65'), quantity: 3)
        ..applyOffer('FEAST75');
      final restored = CartController(store, offerLookup: settings.offerByCode);
      expect(restored.offerCode, 'FEAST75');
      restored.clear();
      expect(restored.offerCode, isNull);
    });
  });

  group('sold-out dishes', () {
    test('cannot be added or increased, and are reported', () {
      final cart = CartController(MemoryStore());
      final dosa = dish('masala_dosa');
      cart.add(dosa, quantity: 2);
      final soldOut = dosa.copyWith(isAvailable: false);
      expect(() => cart.add(soldOut), throwsStateError);

      cart.syncWithMenu([soldOut]);
      expect(cart.unavailableLines.single.item.id, dosa.id);
      final line = cart.lines.single;
      cart.increment(line.id);
      expect(cart.lines.single.quantity, 2);
      cart.decrement(line.id);
      expect(cart.lines.single.quantity, 1);
    });

    test('archived dishes are removed from the cart', () {
      final cart = CartController(MemoryStore());
      final dosa = dish('masala_dosa');
      cart.add(dosa);
      cart.add(dish('chicken_65'));
      final removed = cart.syncWithMenu([
        dosa.copyWith(isArchived: true),
        dish('chicken_65'),
      ]);
      expect(removed, 1);
      expect(cart.lines.single.item.id, 'chicken_65');
    });

    test('menus list sold-out dishes last', () {
      final items = [
        dish('chicken_65').copyWith(isAvailable: false),
        dish('masala_dosa'),
        dish('gulab_jamun'),
      ];
      final sorted = const MenuFilter(
        sort: MenuSort.priceLowToHigh,
      ).apply(items);
      expect(sorted.last.id, 'chicken_65');
      expect(sorted.first.price.compareTo(sorted[1].price) <= 0, isTrue);
    });
  });
}
