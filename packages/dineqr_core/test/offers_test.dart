import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

// The same figures as the server's PromotionTests: the app's preview and
// the server's price must agree to the paisa, or orders are refused with
// "prices changed".

/// 10 Nov 2026, 11:30 in a UTC+05:30 restaurant.
final _now = DateTime.utc(2026, 11, 10, 6);
final _today = DateTime.utc(2026, 11, 10);

Promotion _special(
  String id,
  int basisPoints,
  List<String> dishes, {
  DiscountType type = DiscountType.percent,
  int sortOrder = 0,
  DateTime? startsOn,
  DateTime? endsOn,
  bool active = true,
  int? limit,
  int used = 0,
}) => Promotion(
  id: id,
  kind: PromotionKind.special,
  title: 'Offer $id',
  discountType: type,
  discountValue: basisPoints,
  items: [for (final d in dishes) PromotionItem(d)],
  sortOrder: sortOrder,
  startsOn: startsOn,
  endsOn: endsOn,
  isActive: active,
  usageLimit: limit,
  usedCount: used,
);

/// 2 samosas and fries (₹240 separately) for [price].
Promotion _snackBox({Money price = const Money(19900), DateTime? endsOn}) =>
    Promotion(
      id: 'combo_snack_box',
      kind: PromotionKind.combo,
      title: 'Snack box',
      comboPrice: price,
      endsOn: endsOn,
      items: const [
        PromotionItem('samosa', quantity: 2),
        PromotionItem('french_fries'),
      ],
    );

Map<String, MenuItem> get _menu => {
  for (final item in demoMenuItems) item.id: item,
};

void main() {
  setUp(() => RestaurantTime.configure(330));

  group('special offers', () {
    test('take a share of each unit, add-ons included', () {
      final cart =
          CartController(
              MemoryStore(),
              promotionSource: () => [
                _special('snack', 2000, ['samosa', 'french_fries']),
              ],
              clock: () => _now,
            )
            ..add(dish('samosa'), quantity: 2)
            ..add(
              dish('french_fries'),
              customization: DishCustomization(addOnIds: ['cheese_dip']),
            )
            ..add(dish('spring_roll'));

      final quote = cart.quote;
      // 20% of ₹60 = ₹12 a samosa; 20% of ₹155 (fries + dip) = ₹31.
      final samosa = cart.lines.firstWhere((l) => l.item.id == 'samosa');
      expect(quote.savingFor(samosa.id)!.amount, const Money(2400));
      final fries = cart.lines.firstWhere((l) => l.item.id == 'french_fries');
      expect(quote.savingFor(fries.id)!.amount, const Money(3100));
      expect(
        quote.savingFor(cart.lines.last.id),
        isNull,
        reason: 'spring roll has no offer',
      );
      expect(quote.bill.subtotal, const Money(12000 + 15500 + 14000));
      expect(quote.bill.discount, const Money(5500));
      expect(quote.discounts, [
        const DiscountLine(
          kind: DiscountKind.special,
          label: 'Offer snack',
          amount: Money(5500),
          ref: 'snack',
        ),
      ]);
      expect(quote.bill.discountLabel, 'Offer snack');
    });

    test('the best offer wins, never more than the dish, ties by order', () {
      final specials = OfferPricing.liveSpecials([
        _special('ten', 1000, ['samosa']),
        _special('flat', 10000, ['samosa'], type: DiscountType.flat),
      ], _today);
      final best = OfferPricing.bestSpecial(
        'samosa',
        const Money(6000),
        specials,
      )!;
      // ₹100 off a ₹60 samosa is capped at ₹60, which beats 10%.
      expect(best.offer.id, 'flat');
      expect(best.perUnit, const Money(6000));

      final tied = OfferPricing.liveSpecials([
        _special('b_second', 1000, ['samosa'], sortOrder: 1),
        _special('a_first', 1000, ['samosa'], sortOrder: 1),
        _special('later', 1000, ['samosa'], sortOrder: 2),
      ], _today);
      expect(
        OfferPricing.bestSpecial('samosa', const Money(6000), tied)!.offer.id,
        'a_first',
      );
    });

    test('only offers live today apply; their dates include both ends', () {
      final yesterday = _today.subtract(const Duration(days: 1));
      final tomorrow = _today.add(const Duration(days: 1));
      final live = OfferPricing.liveSpecials([
        _special('ended', 5000, ['samosa'], endsOn: yesterday),
        _special('upcoming', 5000, ['samosa'], startsOn: tomorrow),
        _special('paused', 5000, ['samosa'], active: false),
        _special('used_up', 5000, ['samosa'], limit: 3, used: 3),
        _special(
          'last_day',
          5000,
          ['samosa'],
          startsOn: yesterday,
          endsOn: _today,
        ),
        _special('first_day', 5000, ['samosa'], startsOn: _today),
      ], _today);
      expect(live.map((p) => p.id), ['first_day', 'last_day']);
      expect(
        _special('x', 1, [], endsOn: yesterday).statusOn(_today),
        OfferStatus.ended,
      );
      expect(
        _special('x', 1, [], startsOn: tomorrow).statusOn(_today),
        OfferStatus.scheduled,
      );
      expect(
        _special('x', 1, [], limit: 1, used: 1).statusOn(_today),
        OfferStatus.usedUp,
      );
    });

    test('"today" is the restaurant day, not the device day', () {
      // 23:00 UTC on 9 Nov is already 10 Nov in a UTC+05:30 restaurant.
      expect(OfferRules.today(DateTime.utc(2026, 11, 9, 23)), _today);
      RestaurantTime.configure(-300);
      expect(
        OfferRules.today(DateTime.utc(2026, 11, 10, 3)),
        DateTime.utc(2026, 11, 9),
      );
    });
  });

  group('combos', () {
    test('cost their price, with the saving shown as a discount', () {
      final view = _snackBox().comboView(_menu)!;
      expect(view.originalPrice, const Money(24000));
      expect(view.saving, const Money(4100));
      expect(view.partLabels, ['2 × Punjabi Samosa', 'French Fries']);

      final cart =
          CartController(
              MemoryStore(),
              promotionSource: () => [_snackBox()],
              clock: () => _now,
            )
            ..addCombo(view, quantity: 2)
            ..add(dish('samosa'));
      final combo = cart.lines.first;
      expect(combo.isCombo, isTrue);
      expect(combo.toJson(), {'comboId': 'combo_snack_box', 'quantity': 2});
      expect(cart.quantityOfCombo('combo_snack_box'), 2);
      expect(
        cart.quantityOfItem('samosa'),
        1,
        reason: 'dishes inside a combo are not counted as the dish',
      );

      final quote = cart.quote;
      expect(quote.bill.subtotal, const Money(48000 + 6000));
      expect(quote.savingFor(combo.id)!.amount, const Money(8200));
      expect(quote.discounts.single.kind, DiscountKind.combo);
      expect(quote.bill.discount, const Money(8200));
    });

    test('a combo dearer than its dishes saves nothing', () {
      final view = _snackBox(price: const Money(30000)).comboView(_menu)!;
      expect(view.saving, Money.zero);
      final cart = CartController(
        MemoryStore(),
        promotionSource: () => [_snackBox(price: const Money(30000))],
        clock: () => _now,
      )..addCombo(view);
      expect(cart.quote.discounts, isEmpty);
      expect(cart.bill.subtotal, const Money(24000));
    });

    test('a special offer never applies inside a combo', () {
      final cart = CartController(
        MemoryStore(),
        promotionSource: () => [
          _snackBox(),
          _special('half', 5000, ['samosa', 'french_fries']),
        ],
        clock: () => _now,
      )..addCombo(_snackBox().comboView(_menu)!);
      expect(cart.quote.discounts.single.kind, DiscountKind.combo);
      expect(cart.discount, const Money(4100));
    });

    test('are restored with the cart and dropped once withdrawn', () {
      final store = MemoryStore();
      var promotions = [_snackBox()];
      CartController(
        store,
        promotionSource: () => promotions,
        clock: () => _now,
      ).addCombo(_snackBox().comboView(_menu)!, quantity: 3);

      final restored = CartController(
        store,
        promotionSource: () => promotions,
        clock: () => _now,
      )..hydrate(demoMenuItems);
      expect(restored.quantityOfCombo('combo_snack_box'), 3);

      // The restaurant ends the combo: guests are no longer sent it.
      promotions = [];
      expect(restored.syncWithMenu(demoMenuItems), 1);
      expect(restored.isEmpty, isTrue);
    });

    test('an ended combo or a sold-out dish blocks checkout', () {
      final ended = _snackBox(endsOn: _today.subtract(const Duration(days: 1)));
      final cart = CartController(
        MemoryStore(),
        promotionSource: () => [ended],
        clock: () => _now,
      );
      expect(() => cart.addCombo(ended.comboView(_menu)!), throwsStateError);

      final soldOut = {
        ..._menu,
        'samosa': dish('samosa').copyWith(isAvailable: false),
      };
      final live = CartController(
        MemoryStore(),
        promotionSource: () => [_snackBox()],
        clock: () => _now,
      )..addCombo(_snackBox().comboView(_menu)!);
      live.syncWithMenu(soldOut.values);
      expect(live.unavailableLines, hasLength(1));
    });
  });

  group('coupons', () {
    DiscountOffer coupon({
      int percent = 1000,
      Money min = Money.zero,
      DateTime? startsOn,
      DateTime? endsOn,
      int? limit,
      int used = 0,
    }) => DiscountOffer(
      code: 'TEST10',
      title: 'Test',
      type: DiscountType.percent,
      value: percent,
      minSubtotal: min,
      startsOn: startsOn,
      endsOn: endsOn,
      usageLimit: limit,
      usedCount: used,
    );

    test('apply after item savings, and their minimum counts them', () {
      final offer = coupon(min: const Money.rupees(100));
      CartController cartWith(int samosas) => CartController(
        MemoryStore(),
        offerLookup: (_) => offer,
        promotionSource: () => [
          _special('half', 5000, ['samosa']),
        ],
        clock: () => _now,
      )..add(dish('samosa'), quantity: samosas);

      // 3 samosas: ₹180, ₹90 after the special: below the coupon's ₹100.
      final small = cartWith(3);
      expect(small.applyOffer('TEST10'), OfferError.belowMinimum);
      expect(small.quote.coupon, isNull);
      expect(small.discount, const Money(9000));

      // 4 samosas: ₹240, ₹120 after the special, so 10% (₹12) off that.
      final large = cartWith(4)..applyOffer('TEST10');
      final quote = large.quote;
      expect(quote.coupon?.code, 'TEST10');
      expect(quote.couponDiscount, const Money(1200));
      expect(quote.bill.discount, const Money(13200));
      expect(quote.bill.discountLabel, OfferPricing.combinedLabel);
      expect(quote.discounts.map((d) => (d.kind, d.amount)), [
        (DiscountKind.special, const Money(12000)),
        (DiscountKind.coupon, const Money(1200)),
      ]);
      expect(quote.discounts.last.label, 'Offer TEST10');
    });

    test('cannot be applied outside their dates or once used up', () {
      final yesterday = _today.subtract(const Duration(days: 1));
      final tomorrow = _today.add(const Duration(days: 1));
      for (final (offer, error) in [
        (coupon(endsOn: yesterday), OfferError.ended),
        (coupon(startsOn: tomorrow), OfferError.notStarted),
        (coupon(limit: 5, used: 5), OfferError.usedUp),
      ]) {
        final cart = CartController(
          MemoryStore(),
          offerLookup: (_) => offer,
          clock: () => _now,
        )..add(dish('samosa'), quantity: 4);
        expect(cart.applyOffer('TEST10'), error);
        expect(cart.offerCode, isNull);
      }
      // Valid on its last day.
      final lastDay = CartController(
        MemoryStore(),
        offerLookup: (_) => coupon(endsOn: _today),
        clock: () => _now,
      )..add(dish('samosa'), quantity: 4);
      expect(lastDay.applyOffer('TEST10'), isNull);
      expect(lastDay.discount, const Money(2400));
    });

    test('keep their dates and limits through JSON', () {
      final offer = coupon(
        startsOn: DateTime.utc(2026, 11),
        endsOn: DateTime.utc(2026, 11, 30),
        limit: 200,
        used: 12,
      );
      final json = offer.toJson();
      expect(json['startsOn'], '2026-11-01');
      expect(json['endsOn'], '2026-11-30');
      final back = DiscountOffer.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(back.startsOn, DateTime.utc(2026, 11));
      expect(back.endsOn, DateTime.utc(2026, 11, 30));
      expect((back.usageLimit, back.usedCount), (200, 12));
    });
  });

  group('orders', () {
    test(
      'keep each saving, and send the coupon only when it applied',
      () async {
        final store = MemoryStore();
        final orders = await testOrders(store);
        final offer = DiscountOffer(
          code: 'BIG500',
          title: 'Big',
          type: DiscountType.flat,
          value: 5000,
          minSubtotal: const Money.rupees(500),
        );
        final cart =
            CartController(
                MemoryStore(),
                offerLookup: (_) => offer,
                promotionSource: () => [
                  _snackBox(),
                  _special('snack', 2000, ['spring_roll']),
                ],
                clock: () => _now,
              )
              ..addCombo(_snackBox().comboView(_menu)!)
              ..add(dish('spring_roll'))
              ..applyOffer('BIG500');
        // ₹240 + ₹140 = ₹380 − ₹41 − ₹28 = ₹311: below the coupon's ₹500.
        final order = await orders.placeOrder(cart: cart, tableNumber: 5);

        final combo = order.lines.firstWhere((l) => l.isCombo);
        expect(combo.comboId, 'combo_snack_box');
        expect(combo.comboItems.map((p) => (p.itemId, p.quantity)), [
          ('samosa', 2),
          ('french_fries', 1),
        ]);
        expect(combo.discount, const Money(4100));
        final roll = order.lines.firstWhere((l) => l.itemId == 'spring_roll');
        expect(roll.discount, const Money(2800));
        expect(roll.promotionId, 'snack');
        expect(order.bill.discount, const Money(6900));
        expect(order.bill.discounts, hasLength(2));

        // Stored history keeps all of it.
        final reloaded = await testOrders(store);
        final stored = reloaded.byId(order.id)!;
        expect(stored.bill.discounts.map((d) => d.ref), [
          'combo_snack_box',
          'snack',
        ]);
        expect(
          stored.lines.firstWhere((l) => l.isCombo).comboItems,
          hasLength(2),
        );
      },
    );

    test('bills from before itemised discounts still show one line', () {
      final bill = BillBreakdown.fromJson({
        'subtotal': 50000,
        'discount': 5000,
        'discountLabel': 'Offer WELCOME10',
        'tax': 2250,
        'total': 47250,
        'taxRate': 500,
      });
      expect(bill.discounts, isEmpty);
      expect(bill.discountLines.single.label, 'Offer WELCOME10');
      expect(bill.discountLines.single.amount, const Money(5000));
    });
  });

  group('managing offers', () {
    Future<CatalogController> catalog(StaffRole role) async {
      final catalog = CatalogController(
        DemoMenuRepository(latency: Duration.zero, store: MemoryStore()),
        MemoryStore(),
        guard: FakeGuard(role),
        clock: () => _now,
      );
      await catalog.load();
      return catalog;
    }

    test('is for staff allowed to manage offers', () async {
      final waiter = await catalog(StaffRole.waiter);
      await expectLater(
        waiter.savePromotion(_snackBox()),
        throwsA(isA<PermissionDeniedException>()),
      );
      final manager = await catalog(StaffRole.manager);
      await manager.savePromotion(_snackBox());
      expect(manager.promotions.single.id, 'combo_snack_box');
      expect(manager.liveCombos.single.saving, const Money(4100));
    });

    test('checks the same rules as the server', () async {
      final owner = await catalog(StaffRole.owner);
      expect(
        owner.validatePromotion(_snackBox(price: const Money(24000))),
        contains('less than its dishes'),
      );
      expect(
        owner.validatePromotion(
          _snackBox().copyWith(items: [const PromotionItem('samosa')]),
        ),
        contains('at least two'),
      );
      expect(
        owner.validatePromotion(_special('x', 10001, ['samosa'])),
        contains('1% to 100%'),
      );
      expect(
        owner.validatePromotion(
          _special(
            'x',
            1000,
            ['samosa'],
            startsOn: _today,
            endsOn: _today.subtract(const Duration(days: 1)),
          ),
        ),
        contains('last day'),
      );
      expect(
        owner.validatePromotion(_special('x', 1000, ['no_such_dish'])),
        contains('no longer on the menu'),
      );
      expect(owner.validatePromotion(_special('x', 1000, ['samosa'])), isNull);
      // New ids never collide with a dish (a combo line uses its id).
      expect(
        owner.newPromotionId('Samosa', PromotionKind.combo),
        'combo_samosa',
      );
    });

    test('promotions keep everything through JSON', () {
      final combo = _snackBox().copyWith(
        startsOn: DateTime.utc(2026, 11),
        usageLimit: 50,
        usedCount: 7,
      );
      final back = Promotion.fromJson(
        jsonDecode(jsonEncode(combo.toJson())) as Map<String, dynamic>,
      );
      expect(back.kind, PromotionKind.combo);
      expect(back.comboPrice, const Money(19900));
      expect(back.items, combo.items);
      expect(back.startsOn, DateTime.utc(2026, 11));
      expect((back.usageLimit, back.usedCount), (50, 7));
      expect(_special('s', 1500, ['samosa']).badge, '15% OFF');
    });
  });
}
