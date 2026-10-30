import 'dart:convert';

import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/modules/dashboard/dashboard_screen.dart';
import 'package:dineqr_admin/modules/offers/offers_screen.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// A special offer on samosas and a combo, saved as the demo stores them.
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
        usageLimit: 50,
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

/// Scrolls [finder] to the middle of the screen, clear of the app bar, and
/// clears any snackbar that could cover it.
Future<void> centre(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .clearSnackBars();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the Offers section lists, pauses and creates offers', (
    tester,
  ) async {
    // A small phone, so any row that does not fit fails the test.
    tester.view.physicalSize = const Size(360, 760) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final deps = await createAdminDependencies(store: await storeWithOffers());
    await deps.admin.signIn('manager@dineqr.demo', DemoCredentials.password);
    await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
    await settle(tester, 800);

    // Managers run offers.
    final shell = Provider.of<AdminShellController>(
      tester.element(find.byType(DashboardScreen)),
      listen: false,
    );
    shell.open(AdminModule.offers);
    await settle(tester);
    expect(find.byType(OffersScreen), findsOneWidget);

    // Special offers: what it gives, where it stands, how often it was used.
    expect(find.text('Snack hour'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('20% OFF · Punjabi Samosa'), findsOneWidget);
    expect(find.textContaining('Used 0 of 50'), findsOneWidget);

    // Pausing it takes it off the guests' menus.
    await tester.tap(find.byType(Switch).first);
    await settle(tester);
    expect(deps.catalog.promotionById('special_snack_hour')!.isActive, false);
    expect(find.text('Paused'), findsOneWidget);
    expect(deps.catalog.liveSpecials, isEmpty);

    // Combos: dishes, price and saving.
    await tester.tap(find.text('Combos'));
    await settle(tester);
    expect(find.text('Snack box'), findsOneWidget);
    expect(find.textContaining('saves ₹41'), findsOneWidget);

    // A new special offer, through the editor.
    await tester.tap(find.text('Special offers'));
    await settle(tester);
    await tester.tap(find.text('New offer'));
    await settle(tester, 800);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Fries Friday',
    );
    final discount = find.widgetWithText(TextField, 'Discount per dish');
    await centre(tester, discount);
    await tester.enterText(discount, '15');
    final choose = find.text('Choose dishes');
    await centre(tester, choose);
    await tester.pump();
    await tester.tap(choose);
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'fries',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('French Fries'),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Done (1)'));
    await settle(tester);
    final create = find.text('Create special offer');
    await centre(tester, create);
    await tester.tap(create);
    await settle(tester, 800);

    final created = deps.catalog.promotions.firstWhere(
      (p) => p.title == 'Fries Friday',
    );
    expect(created.id, 'special_fries_friday');
    expect(created.discountValue, 1500);
    expect(created.items.single.itemId, 'french_fries');
    expect(
      deps.catalog.specialFor(deps.catalog.byId('french_fries')!)!.perUnit,
      const Money(1800),
    );

    // A new coupon with a usage limit.
    await tester.tap(find.text('Coupons'));
    await settle(tester);
    await tester.tap(find.text('New coupon'));
    await settle(tester);
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(TextField, 'Code'),
      ),
      'FRIDAY20',
    );
    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(TextField, 'Title'),
      ),
      'Friday treat',
    );
    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(TextField, 'Discount'),
      ),
      '20',
    );
    final limit = find.descendant(
      of: dialog,
      matching: find.widgetWithText(TextField, 'Usage limit (optional)'),
    );
    await centre(tester, limit);
    await tester.enterText(limit, '100');
    await tester.tap(find.text('Save'));
    await settle(tester);

    final coupon = deps.settings.settings.offerByCode('FRIDAY20')!;
    expect(coupon.value, 2000);
    expect(coupon.usageLimit, 100);
    expect(find.text('FRIDAY20 · Friday treat'), findsOneWidget);
    expect(find.textContaining('Used 0 of 100'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
