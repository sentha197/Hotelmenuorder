// Walks through the app at phone size and saves a PNG of each screen.
// Run: flutter test tool/screens_preview_test.dart --dart-define=OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/app/app.dart';
import 'package:menu_order/app/dependencies.dart';
import 'package:menu_order/data/storage/key_value_store.dart';
import 'package:menu_order/features/menu/menu_widgets.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/screens');

void main() {
  setUpAll(loadBrandFonts);

  testWidgets('screens', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final storage = MemoryStore();
    final deps = await AppDependencies.create(
      store: storage,
      config: const AppConfig(enableCamera: false),
      menuLatency: Duration.zero,
      orderLatency: const Duration(milliseconds: 300),
      paymentTime: const Duration(milliseconds: 300),
    );

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: DineQrApp(dependencies: deps),
      ),
    );

    // Decode every bundled photo up front so screenshots include them.
    final context = key.currentContext!;
    await tester.runAsync(() async {
      for (final file in Directory('assets/images').listSync()) {
        final path = file.path.replaceAll(r'\', '/');
        if (!path.endsWith('.jpg') && !path.endsWith('.png')) continue;
        if (!context.mounted) return;
        await precacheImage(AssetImage(path), context);
      }
    });

    var index = 0;
    Future<void> shot(String name) async {
      // Let pending (resized) image decodes finish, then paint them.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final number = (index++).toString().padLeft(2, '0');
        File('$_out/${number}_$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> wait(int ms) async {
      // Pump frame by frame (~60 fps) so animations progress as on device.
      await tester.pump();
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // 1. Splash stages. The first frame matches the native launch screen.
    await shot('splash_first_frame');
    await tester.pump(const Duration(milliseconds: 450));
    await shot('splash_reveal');
    await tester.pump(const Duration(milliseconds: 700));
    await shot('splash_logo');
    await tester.pump(const Duration(milliseconds: 1000));
    await shot('splash_loader');

    // 2. Scanner (demo mode: no camera in tests).
    await tester.pump(const Duration(milliseconds: 600));
    await wait(900);
    await shot('scanner');
    await tester.tap(find.text('Use a demo QR code'));
    await wait(600);
    await shot('scanner_demo_sheet');
    await tester.tap(find.text('Table 12').last);
    await wait(500);
    await shot('scanner_detected');
    await wait(1600);

    // 3. Table confirmation.
    await wait(900);
    await shot('table_confirmation');
    await tester.tap(find.text('Start Ordering'));
    await wait(900);

    // 4. Home.
    await wait(800);
    await shot('home');
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -520),
    );
    await wait(600);
    await shot('home_scrolled');

    // 5. Category list.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 520),
    );
    await wait(400);
    await tester.tap(find.text('Starters'));
    await wait(1000);
    await shot('menu_starters');
    await tester.tap(find.text('Veg'));
    await wait(800);
    await shot('menu_veg');
    await tester.tap(find.byTooltip('Back'));
    await wait(800);

    // 6. Dish details.
    await tester.tap(
      find.descendant(
        of: find.byType(FoodCard),
        matching: find.text('Chicken 65'),
      ),
    );
    await wait(1000);
    await shot('dish_details');
    await tester.tap(find.text('Spicy'));
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await wait(200);
    await shot('dish_favorite_burst');
    await wait(2200);
    await tester.tap(find.text('Add to Cart'));
    await wait(300);
    await shot('dish_added');
    await wait(600);

    // 7. Cart, with a coupon saved below its minimum.
    await tester.tap(find.text('VIEW CART'));
    await wait(900);
    await shot('cart');
    await tester.tap(find.text('Apply a coupon'));
    await wait(700);
    await shot('cart_coupon_sheet');
    await tester.tap(find.text('APPLY').first);
    await wait(700);
    await shot('cart_coupon_saved');

    // 8. Summary.
    await tester.tap(find.text('Proceed to Place Order'));
    await wait(900);
    await shot('order_summary');
    await tester.tap(find.textContaining('Place Order ·'));
    await tester.pump(const Duration(milliseconds: 120));
    await shot('order_placing');
    await wait(400);

    // 9. Success.
    await wait(500);
    await shot('order_success_burst');
    await wait(1500);
    await shot('order_success');

    // Bill and simulated payment.
    await tester.tap(find.text('View Bill'));
    await wait(900);
    await shot('bill');
    await tester.tap(find.textContaining('Pay ₹').first);
    await wait(900);
    await shot('payment');
    await tester.tap(find.textContaining('Pay ₹').last);
    await tester.pump(const Duration(milliseconds: 150));
    await shot('payment_processing');
    await wait(1200);
    await shot('payment_success');
    await tester.tap(find.text('Done'));
    await wait(900);
    await shot('bill_paid');
    await tester.tap(find.byTooltip('Back'));
    await wait(800);

    // 10. Tracking.
    await tester.tap(find.text('Track Order'));
    await wait(900);
    await shot('tracking_placed');
    final vertical = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    for (var i = 0; i < 4; i++) {
      final advance = find.textContaining('Mark as');
      await tester.scrollUntilVisible(advance, 200, scrollable: vertical.last);
      await tester.pump();
      await tester.tap(advance);
      await wait(900);
      if (i == 1) await shot('tracking_preparing');
    }

    // 12. Feedback.
    await wait(900);
    await shot('feedback');
    await tester.tap(find.byKey(const ValueKey('rating-star-4')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await shot('feedback_stars_animating');
    await wait(700);
    await shot('feedback_rated');
    await tester.tap(find.text('Submit'));
    await wait(1400);
    await shot('feedback_thanks');
    await tester.tap(find.text('Done'));
    await wait(600);

    // 11. My orders.
    await tester.tap(find.byTooltip('Back'));
    await wait(800);
    await tester.tap(find.text('Orders'));
    await wait(800);
    await shot('orders_current');
    await tester.tap(find.textContaining('Past ('));
    await wait(900);
    await shot('orders_past');

    // More, bills and payment history, empty cart.
    await tester.tap(find.text('More'));
    await wait(900);
    await shot('more');
    await tester.tap(find.text('Bills & Payments'));
    await wait(900);
    await shot('payment_history');
    await tester.tap(find.byTooltip('Back'));
    await wait(800);
    await tester.tap(find.text('Cart'));
    await wait(900);
    await shot('cart_empty');

    debugDisableShadows = true;
  });
}
