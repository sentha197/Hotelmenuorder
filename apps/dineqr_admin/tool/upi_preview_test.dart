// Saves a PNG of the UPI parts of the staff app: the Payment Settings card
// and the cashier's confirmation of a UPI payment.
// Run: flutter test tool/upi_preview_test.dart --dart-define=OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/app/dependencies.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/upi_admin');

void main() {
  setUpAll(loadBrandFonts);

  const sizes = {'phone': Size(390, 844), 'tablet': Size(1280, 800)};

  for (final MapEntry(key: device, value: size) in sizes.entries) {
    testWidgets('upi $device', (tester) async {
      debugDisableShadows = false;
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final invoice = Invoice(
        id: 'INV00001',
        billNumber: 'DQ-2026-00012',
        orderId: 'OD12345',
        tableNumber: 5,
        createdAt: DateTime.now(),
        lines: const [],
        amounts: const BillBreakdown(
          subtotal: Money(42857),
          tax: Money(2143),
          total: Money(45000),
          taxRateBasisPoints: 500,
        ),
        restaurant: const RestaurantSnapshot(name: 'Spice Route'),
        payments: [
          PaymentTransaction(
            id: 'PAY000001',
            invoiceId: 'INV00001',
            orderId: 'OD12345',
            amount: const Money(45000),
            method: PaymentMethodType.upi,
            status: PaymentStatus.pending,
            provider: PaymentTransaction.upiDirectProvider,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            idempotencyKey: 'key-1',
            reference: 'UTR412345678901',
            claimedAt: DateTime.now(),
          ),
        ],
      );
      final deps = await AdminDependencies.create(
        store: MemoryStore(),
        config: const AppConfig(),
        billingRepository: LocalBillingRepository(
          MemoryStore(),
          seed: [invoice],
        ),
        billingBackend: FakeUpiBackend(invoice),
        paymentSettingsRepository: FakePaymentSettingsRepository(
          stored: const UpiSettings(
            enabled: true,
            upiId: 'spiceroute@okhdfcbank',
            payeeName: 'Spice Route Restaurant',
            qrImageUrl: 'https://example.test/uploads/upi/qr.png',
          ),
        ),
        menuLatency: Duration.zero,
        orderLatency: Duration.zero,
        seedDemoData: false,
      );
      await tester.runAsync(deps.billing.load);
      await tester.runAsync(deps.paymentSettings.load);
      await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: DineQrAdminApp(dependencies: deps),
        ),
      );
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
          File('$_out/${device}_${number}_$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> wait(int ms) async {
        await tester.pump();
        for (var t = 0; t < ms; t += 16) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<void> scrollTo(Finder finder) async {
        await tester.ensureVisible(finder);
        await wait(400);
      }

      await wait(1200);
      final shell = Provider.of<AdminShellController>(
        tester.element(find.byType(Scaffold).first),
        listen: false,
      );

      // ---- Settings: the card with a saved QR, then unsaved edits.
      shell.open(AdminModule.settings);
      await wait(900);
      await scrollTo(find.text('Payment Settings'));
      await shot('settings_payment_card');
      await scrollTo(find.byKey(const ValueKey('upi-save')));
      await shot('settings_payment_card_bottom');
      await tester.enterText(
        find.byKey(const ValueKey('upi-name')),
        'Spice Route Restaurant & Bar',
      );
      await wait(400);
      await scrollTo(find.text('Payment Settings'));
      await shot('settings_payment_card_unsaved');

      // ---- Bills: a UPI payment waiting for the cashier, then the dialog.
      shell.open(AdminModule.bills);
      await wait(900);
      await tester.tap(find.text('DQ-2026-00012').first);
      await wait(900);
      await shot('bill_awaiting_verification');
      await scrollTo(find.byKey(const ValueKey('confirm-PAY000001')));
      await tester.tap(find.byKey(const ValueKey('confirm-PAY000001')));
      await wait(700);
      await shot('confirm_dialog');
      await tester.tap(find.byKey(const ValueKey('upi-confirm')));
      await wait(500);
      await shot('confirm_dialog_unchecked');

      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
    });
  }
}
