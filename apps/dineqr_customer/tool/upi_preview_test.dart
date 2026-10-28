// Walks through paying a bill by UPI to the restaurant at phone size and
// saves a PNG of each step, for a visual review of the UPI screens.
// Run: flutter test tool/upi_preview_test.dart --dart-define=OUT=<dir>
// [--dart-define=UPI_ID=cafe@hdfcbank] (a bank's ID opens the UPI app with a
// link; a UPI app's own ID, the default, is copied into the app instead).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
import 'package:dineqr_customer/app/upi_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/upi');
const _upiId = String.fromEnvironment(
  'UPI_ID',
  defaultValue: 'spiceroute@oksbi',
);

class _Phone implements UpiLauncher {
  @override
  bool get canOpenApps => true;

  @override
  Future<Set<UpiApp>> installedApps() async => {
    UpiApp.googlePay,
    UpiApp.phonePe,
    UpiApp.paytm,
  };

  @override
  Future<UpiLaunchResult> open(Uri link) async => UpiLaunchResult.opened;
}

Future<void> _settle(WidgetTester tester, [int ms = 700]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  setUpAll(loadBrandFonts);

  testWidgets('upi screens', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // A clipboard that takes what "Copy UPI ID" copies.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final bill = Invoice(
      id: 'INV00001',
      billNumber: 'DQ-2026-00012',
      orderId: 'OD12345',
      tableNumber: 5,
      createdAt: DateTime.now(),
      lines: const [],
      amounts: const BillBreakdown(
        subtotal: Money(6000),
        tax: Money(300),
        total: Money(6300),
        taxRateBasisPoints: 500,
      ),
      restaurant: const RestaurantSnapshot(name: 'Spice Route'),
    );
    final server = FakeUpiBackend(
      bill,
      settings: const UpiSettings(
        enabled: true,
        upiId: _upiId,
        payeeName: 'Spice Route Restaurant',
        qrImageUrl: 'https://example.test/uploads/upi/qr.png',
      ),
    );
    final deps = await CustomerDependencies.create(
      store: MemoryStore(),
      config: const CustomerConfig(enableCamera: false),
      billingRepository: LocalBillingRepository(MemoryStore(), seed: [bill]),
      billingBackend: server,
      upiLauncher: _Phone(),
      menuLatency: Duration.zero,
      seedDemoData: false,
    );
    await tester.runAsync(deps.billing.load);
    await tester.runAsync(deps.billing.loadUpiSettings);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: DineQrApp(dependencies: deps),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2700));
    await _settle(tester);

    var index = 0;
    Future<void> shot(String name) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
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

    Future<void> tap(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          250,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await _settle(tester);
    }

    Future<void> scrollTo(double dy) async {
      await tester.drag(
        find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
        Offset(0, -dy),
      );
      await _settle(tester, 400);
    }

    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed(Routes.bill, arguments: bill.id);
    await _settle(tester, 900);
    await shot('bill');

    await tap(find.text('Pay Now'));
    await shot('choose_method');

    // QR Payment: no UPI app opens by itself, so the page shows as it is.
    await tap(find.text('QR Payment'));
    await tap(find.text('Pay ₹63 by QR code'));
    await shot('upi_top');
    // The whole QR code, for decoding it from the picture.
    await scrollTo(400);
    await shot('upi_qr');
    await scrollTo(300);
    await shot('upi_qr_and_details');
    await scrollTo(700);
    await shot('upi_bottom');

    // Back to the top, go to a UPI app and return, as a phone would report it.
    await scrollTo(-3000);
    await tap(
      find.text(
        const UpiSettings(upiId: _upiId).takesPaymentLinks
            ? 'Pay with UPI'
            : 'Copy UPI ID',
      ),
    );
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await _settle(tester, 900);
    await shot('back_from_upi_app');

    await tap(find.text('Yes, I\'ve paid'));
    await shot('claim_sheet');
    await tester.enterText(
      find.byKey(const ValueKey('upi-ref-field')),
      '412345678901',
    );
    await _settle(tester, 400); // let the field's label finish moving
    await shot('claim_sheet_filled');
    await tap(find.byKey(const ValueKey('upi-claim')));
    await shot('waiting');

    await server.verifyUpiPayment('PAY000001', reference: 'UTR412345678901');
    await tap(find.byKey(const ValueKey('upi-check')));
    await shot('confirmed');

    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = true;
  });
}
