import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/features/menu/menu_widgets.dart';
import 'package:dineqr_customer/features/splash/splash_screen.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<CustomerDependencies> createDependencies({MemoryStore? store}) {
  final storage = store ?? MemoryStore();
  return CustomerDependencies.create(
    store: storage,
    config: const CustomerConfig(enableCamera: false),
    menuLatency: Duration.zero,
    orderLatency: const Duration(milliseconds: 300),
    paymentTime: const Duration(milliseconds: 300),
    seedDemoData: false,
  );
}

/// Phone-sized surface (iPhone 13/14 logical size).
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

/// Splash -> scanner -> demo QR for [table] -> welcome.
Future<void> scanDemoTable(WidgetTester tester, String table) async {
  await tester.pump(const Duration(milliseconds: 2700)); // splash
  await settle(tester, 700);
  expect(find.text('Scan QR Code'), findsOneWidget);
  await tester.tap(find.text('Use a demo QR code'));
  await settle(tester, 500);
  // The sheet is on top; the scanner frame may show a demo card too.
  await tester.tap(find.text(table).last);
  await settle(tester, 1000); // success check + delay
  await settle(tester, 1000); // route transition + entrance animations
}

void main() {
  testWidgets('complete ordering flow from splash to feedback', (tester) async {
    usePhoneScreen(tester);
    final deps = await createDependencies();
    await tester.pumpWidget(DineQrApp(dependencies: deps));

    // 1. Splash. The first frame matches the native launch screen: the
    // logo at launch size with its smile in the faint starting state.
    DineQrMark mark() => tester.widget<DineQrMark>(find.byType(DineQrMark));
    expect(mark().size, SplashScreen.launchMarkWidth);
    expect(mark().smile, SplashScreen.launchSmile);
    expect(find.byType(DineQrWordmark), findsOneWidget);
    expect(find.byType(DineQrTagline), findsOneWidget);
    // The smile draws in and the QR-scanner loader appears.
    await tester.pump(const Duration(milliseconds: 1300));
    expect(mark().smile, greaterThan(SplashScreen.launchSmile));
    expect(mark().size, greaterThan(SplashScreen.launchMarkWidth));
    expect(find.byType(QrScanEmblem), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 2-3. Demo scan of Table 12, then the welcome screen.
    await scanDemoTable(tester, 'Table 12');
    expect(find.text('Welcome to'), findsOneWidget);
    expect(find.text('Table 12'), findsOneWidget);
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);
    expect(deps.session.tableNumber, 12);

    // 4. Home.
    expect(find.text('Popular Dishes'), findsOneWidget);
    expect(find.text('Table 12'), findsOneWidget);

    // 6. Dish details: customise and add to cart.
    // (The promo banner also mentions Chicken 65; open it from its card.)
    await tester.tap(
      find.descendant(
        of: find.byType(FoodCard),
        matching: find.text('Chicken 65'),
      ),
    );
    await settle(tester, 700);
    expect(find.text('Spice Level'), findsOneWidget);
    await tester.tap(find.text('Spicy'));
    await tester.pump();
    final increase = find.byIcon(Icons.add_rounded);
    await tester.scrollUntilVisible(
      increase,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(increase);
    await tester.pump();
    await tester.tap(find.text('Add to Cart'));
    await settle(tester, 400);
    expect(deps.cart.totalQuantity, 2);
    expect(deps.cart.lines.single.customization.spice, SpiceLevel.spicy);
    expect(find.text('2 × Chicken 65 added to cart'), findsOneWidget);

    // 7. Cart, via the snackbar action.
    await tester.tap(find.text('VIEW CART'));
    await settle(tester, 700);
    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Spice: Spicy · Half'), findsOneWidget);
    final instructions = find.byType(TextField);
    await tester.ensureVisible(instructions);
    await tester.enterText(instructions, 'Less oil please');
    await tester.pump();
    expect(deps.cart.specialInstructions, 'Less oil please');

    // 8. Order summary.
    await tester.tap(find.text('Proceed to Place Order'));
    await settle(tester, 700);
    expect(find.text('Order Summary'), findsOneWidget);
    expect(find.text('Less oil please'), findsOneWidget);
    expect(find.text('Place Order · ₹378'), findsOneWidget);
    await tester.tap(find.text('Place Order · ₹378'));
    await tester.pump();
    expect(deps.orders.isPlacing, isTrue);
    await settle(tester, 400);
    await settle(tester, 1200);

    // 9. Order placed (the number is drawn in two layers).
    expect(find.text('Order Placed\nSuccessfully!'), findsOneWidget);
    expect(find.byType(SuccessEmblem), findsOneWidget);
    await settle(tester, 800); // order number reveal
    expect(find.text('#OD12345'), findsWidgets);
    expect(deps.cart.isEmpty, isTrue);
    final order = deps.orders.byId('OD12345')!;
    expect(order.tableNumber, 12);
    expect(order.specialInstructions, 'Less oil please');

    // 10. Tracking, advancing through every stage.
    await tester.tap(find.text('Track Order'));
    await settle(tester, 700);
    expect(find.text('Order Tracking'), findsOneWidget);
    // Placed -> Accepted -> Preparing -> Ready -> Served.
    for (var i = 0; i < 4; i++) {
      final advance = find.textContaining('Mark as');
      await tester.scrollUntilVisible(
        advance,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(advance);
      await settle(tester, 800);
    }
    expect(deps.orders.byId('OD12345')!.status, OrderStatus.served);

    // 12. Feedback sheet opens automatically once served.
    await settle(tester, 800);
    expect(find.text('How was your food?'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await settle(tester, 300);
    expect(find.text(FeedbackError.missingRating.message), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rating-star-4')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Great food!');
    await tester.tap(find.text('Submit'));
    await settle(tester, 800);
    expect(find.text('Thank you!'), findsOneWidget);
    final rated = deps.orders.byId('OD12345')!;
    expect(rated.feedback!.rating, 4);
    expect(rated.feedback!.comment, 'Great food!');
    await tester.tap(find.text('Done'));
    await settle(tester, 500);

    // 11. Order history shows the served order under Past.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester, 700);
    await tester.tap(find.text('Orders'));
    await settle(tester, 600);
    expect(find.text('My Orders'), findsOneWidget);
    await tester.tap(find.text('Past (1)'));
    await settle(tester, 800);
    expect(find.text('Order #OD12345'), findsOneWidget);
  });

  testWidgets(
    'invalid QR codes show an error and keep the guest on the scanner',
    (tester) async {
      usePhoneScreen(tester);
      final deps = await createDependencies();
      await tester.pumpWidget(DineQrApp(dependencies: deps));
      await tester.pump(const Duration(milliseconds: 2700));
      await settle(tester, 700);

      await tester.tap(find.text('Use a demo QR code'));
      await settle(tester, 500);
      await tester.tap(find.text('Invalid code'));
      await settle(tester, 400);
      expect(find.text('This is not a DineQR code.'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(deps.session.tableNumber, isNull);

      await tester.tap(find.text('Use a demo QR code'));
      await settle(tester, 500);
      await tester.tap(find.text('Unknown table'));
      await settle(tester, 400);
      expect(
        find.text('This QR code points to a table that does not exist.'),
        findsOneWidget,
      );
      await settle(tester, 4500); // error auto-hides
    },
  );

  testWidgets('menu filters, quick add and clearing the cart', (tester) async {
    usePhoneScreen(tester);
    final semantics = tester.ensureSemantics();
    final deps = await createDependencies();
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await scanDemoTable(tester, 'Table 05');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);

    // Starters category from the home screen.
    await tester.tap(find.text('Starters'));
    await settle(tester, 800);
    expect(find.text('Chicken 65'), findsOneWidget);
    await tester.tap(find.text('Veg'));
    await settle(tester, 800);
    expect(find.text('Chicken 65'), findsNothing);
    expect(find.text('Paneer Tikka'), findsOneWidget);
    await tester.tap(find.text('Non Veg'));
    await settle(tester, 800);
    expect(find.text('Paneer Tikka'), findsNothing);
    expect(find.text('Chicken 65'), findsOneWidget);

    // Quick add from the list keeps the stepper and cart in sync.
    await tester.tap(find.bySemanticsLabel('Add Chicken 65 to cart'));
    await settle(tester, 400);
    expect(deps.cart.quantityOfItem('chicken_65'), 1);
    await tester.tap(find.bySemanticsLabel('Increase Chicken 65 quantity'));
    await tester.pump();
    expect(deps.cart.quantityOfItem('chicken_65'), 2);

    // Clear the cart with confirmation.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester, 700);
    await tester.tap(find.text('Cart'));
    await settle(tester, 600);
    await tester.tap(find.text('Clear All'));
    await settle(tester, 500);
    expect(find.text('Clear your cart?'), findsOneWidget);
    await tester.tap(find.text('Clear All').last);
    await settle(tester, 600);
    expect(deps.cart.isEmpty, isTrue);
    expect(find.text('Your cart is empty'), findsOneWidget);
    semantics.dispose();
  });
}
