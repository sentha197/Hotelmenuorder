import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/features/offers/offer_widgets.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart'
    show createDependencies, scanDemoTable, settle, usePhoneScreen;

MenuItem dish(String id) => demoMenuItems.firstWhere((item) => item.id == id);

/// 20% off samosas, and 2 samosas with fries (₹240 separately) for ₹199,
/// as the admin app would have saved them in the offline demo.
Future<MemoryStore> storeWithOffers() async {
  final store = MemoryStore();
  await store.write(
    StorageKeys.promotions,
    jsonEncode([
      const Promotion(
        id: 'special_snack_hour',
        kind: PromotionKind.special,
        title: 'Snack hour',
        discountValue: 2000,
        items: [PromotionItem('samosa')],
      ).toJson(),
      const Promotion(
        id: 'combo_snack_box',
        kind: PromotionKind.combo,
        title: 'Snack box',
        comboPrice: Money(19900),
        sortOrder: 1,
        items: [
          PromotionItem('samosa', quantity: 2),
          PromotionItem('french_fries'),
        ],
      ).toJson(),
    ]),
  );
  return store;
}

void main() {
  testWidgets('guests see offers and combos, and the cart prices them', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final deps = await createDependencies(store: await storeWithOffers());
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await scanDemoTable(tester, 'Table 12');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);

    // Home: a banner for the special offer and a card for the combo, with
    // its price against the dishes bought separately.
    expect(find.text('SPECIAL OFFER'), findsWidgets);
    expect(find.text('Combo Deals'), findsOneWidget);
    final card = find.byType(ComboCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Snack box')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(OfferPrice)),
      findsOneWidget,
    );
    expect(find.text('SAVE ₹41'), findsOneWidget);

    // Add the combo from its card.
    final add = find.descendant(of: card, matching: find.text('Add'));
    // Centred, clear of the bottom navigation bar.
    await Scrollable.ensureVisible(tester.element(add), alignment: 0.5);
    await settle(tester, 300);
    await tester.tap(add);
    await settle(tester, 400);
    expect(deps.cart.quantityOfCombo('combo_snack_box'), 1);
    await tester.tap(find.text('VIEW CART'));
    await settle(tester, 700);

    // Two samosas on their own get the special offer.
    deps.cart.add(dish('samosa'), quantity: 2);
    await settle(tester, 400);
    expect(find.text('COMBO SAVES ₹41'), findsOneWidget);
    expect(find.text('SNACK HOUR · −₹24'), findsOneWidget);
    expect(find.text('2 × Punjabi Samosa · French Fries'), findsOneWidget);

    // The bill lists each saving.
    final bill = deps.cart.bill;
    expect(bill.subtotal, const Money(24000 + 12000));
    expect(bill.discount, const Money(4100 + 2400));
    expect(bill.discounts.map((d) => d.label), ['Snack box', 'Snack hour']);
    expect(
      find.descendant(
        of: find.byType(BillSummary),
        matching: find.text('Snack hour'),
      ),
      findsOneWidget,
    );

    // The order keeps what each line saved and what is in the combo.
    // The demo "kitchen" takes a moment: pump while the order is placed.
    final placing = deps.orders.placeOrder(cart: deps.cart, tableNumber: 12);
    await settle(tester, 800);
    final order = await placing;
    expect(order.bill.total, bill.total);
    final combo = order.lines.firstWhere((line) => line.isCombo);
    expect(combo.comboItems.map((part) => part.itemId), [
      'samosa',
      'french_fries',
    ]);
    expect(combo.discount, const Money(4100));
    expect(
      order.lines.firstWhere((line) => !line.isCombo).discountLabel,
      'Snack hour',
    );
    await settle(tester, 1500);
  });

  testWidgets('dish cards show the offer price and badge', (tester) async {
    usePhoneScreen(tester);
    final deps = await createDependencies(store: await storeWithOffers());
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await scanDemoTable(tester, 'Table 12');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);

    await tester.tap(find.text('Starters'));
    await settle(tester, 800);
    // ₹60 less 20% is ₹48; the full price is struck through beside it.
    expect(find.text('20% OFF'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is OfferPrice &&
            widget.price == const Money(4800) &&
            widget.original == const Money(6000),
      ),
      findsWidgets,
    );
    expect(find.text('₹48'), findsWidgets);
    expect(find.text('₹60'), findsWidgets);
  });
}
