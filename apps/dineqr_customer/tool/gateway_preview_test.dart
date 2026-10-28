// Walks through paying a bill by UPI through the live gateway (Cashfree) at
// phone size and saves a PNG of each step, for a visual review.
// Run: flutter test tool/gateway_preview_test.dart --dart-define=OUT=<dir>
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
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/gateway');

class _Phone implements UpiLauncher {
  @override
  bool get canOpenApps => true;

  @override
  Future<List<InstalledUpiApp>> installedApps() async => [
    for (final app in UpiApp.named) InstalledUpiApp.of(app),
    const InstalledUpiApp(id: 'in.org.npci.upiapp', label: 'BHIM'),
  ];

  @override
  Future<UpiLaunchResult> open(
    Uri link, {
    InstalledUpiApp? app,
    Map<String, String> appLinks = const {},
  }) async => UpiLaunchResult.opened;
}

Future<void> _settle(WidgetTester tester, [int ms = 700]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  setUpAll(loadBrandFonts);

  testWidgets('gateway screens', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final bill = Invoice(
      id: 'INV00001',
      billNumber: 'DQ-2026-00022',
      orderId: 'OD12345',
      tableNumber: 5,
      createdAt: DateTime.now(),
      lines: const [],
      amounts: const BillBreakdown(
        subtotal: Money(18000),
        tax: Money(900),
        total: Money(18900),
        taxRateBasisPoints: 500,
      ),
      restaurant: const RestaurantSnapshot(name: 'Spice Route'),
    );
    final server = FakeUpiBackend(bill);
    final store = MemoryStore();
    await tester.runAsync(
      () => LocalSettingsRepository(store).saveSettings(
        LocalSettingsRepository.defaults.copyWith(
          paymentMode: PaymentMode.live,
        ),
      ),
    );
    final deps = await CustomerDependencies.create(
      store: store,
      config: const CustomerConfig(enableCamera: false),
      billingRepository: LocalBillingRepository(MemoryStore(), seed: [bill]),
      billingBackend: server,
      paymentGateway: ServerPaymentGateway()
        ..update(
          providerName: 'Cashfree',
          available: true,
          isSimulated: false,
          methods: {PaymentMethodType.upi},
        ),
      upiLauncher: _Phone(),
      menuLatency: Duration.zero,
      seedDemoData: false,
    );
    await tester.runAsync(deps.settings.load);
    await tester.runAsync(deps.billing.load);

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

    final page = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;

    Future<void> tap(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, 250, scrollable: page);
      }
      await tester.ensureVisible(finder);
      await _settle(tester);
      await tester.tap(finder);
      await _settle(tester);
    }

    Future<void> scrollTo(double dy) async {
      await tester.drag(page, Offset(0, -dy));
      await _settle(tester, 400);
    }

    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed(Routes.bill, arguments: bill.id);
    await _settle(tester, 900);
    await shot('bill');

    await tap(find.text('Pay Now'));
    await _settle(tester, 900);
    await shot('choose_upi');
    await scrollTo(500);
    await shot('choose_upi_apps');

    await tap(find.text('QR Payment'));
    await shot('choose_qr');
    await scrollTo(-3000);

    await tap(find.text('UPI'));
    await tap(find.byKey(const ValueKey('upi-app-googlePay')));
    await shot('waiting_google_pay');
    await scrollTo(500);
    await shot('waiting_google_pay_bottom');

    await tap(find.byKey(const ValueKey('gateway-show-qr')));
    await scrollTo(-3000);
    await shot('waiting_qr');
    await scrollTo(400);
    await shot('waiting_qr_bottom');

    server.settleGateway('PAY000001');
    await tester.pump(const Duration(seconds: 4));
    await _settle(tester, 900);
    await shot('paid');

    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = true;
  });
}
