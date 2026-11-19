import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

void main() {
  testWidgets('the kitchen serves an unpaid order, then a cashier records the '
      'payment at the counter and opens the receipt', (tester) async {
    usePhoneScreen(tester);
    final deps = await createAdminDependencies();
    final order = (await tester.runAsync(
      () => placeTestOrder(deps.orders, {'butter_chicken': 1}, table: 7),
    ))!;
    final invoice = deps.billing.forOrder(order.id)!;
    final amount = CurrencyFormatter.format(invoice.total);

    // The kitchen works through the order without any payment.
    await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
    for (final status in [
      OrderStatus.accepted,
      OrderStatus.preparing,
      OrderStatus.readyToServe,
      OrderStatus.served,
    ]) {
      await tester.runAsync(() => deps.orders.updateStatus(order.id, status));
    }
    expect(deps.orders.byId(order.id)!.status, OrderStatus.served);
    expect(deps.billing.byId(invoice.id)!.status, InvoiceStatus.unpaid);
    await deps.admin.signOut();

    await deps.admin.signIn('cashier@dineqr.demo', DemoCredentials.password);
    await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
    await settle(tester, 900);
    await settle(tester, 900);

    // Bills is the cashier's landing page; the bill waits to be collected.
    expect(find.text('Payments taken at the billing counter'), findsOneWidget);
    await tester.tap(find.text('Unpaid'));
    await settle(tester, 400);
    await tester.tap(find.text(invoice.billNumber).first);
    await settle(tester, 900);

    // No online-payment tools on the bill.
    expect(find.textContaining('Reconcile'), findsNothing);
    expect(find.textContaining('Check status'), findsNothing);
    expect(find.textContaining('Confirm'), findsNothing);

    await tester.tap(find.text('Record payment').first);
    await settle(tester, 600);
    expect(find.textContaining('billing counter'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await settle(tester, 600);

    final paid = deps.billing.byId(invoice.id)!;
    expect(paid.status, InvoiceStatus.paid);
    final payment = paid.payments.single;
    expect(payment.method, PaymentMethodType.cash);
    expect(payment.provider, PaymentTransaction.counterProvider);
    expect(payment.recordedBy, deps.admin.actor!.name);
    // Staff record real money: never a demo or test payment.
    expect(payment.isSimulated, isFalse);
    expect(find.text('Payment of $amount recorded'), findsOneWidget);
    expect(find.text('RECEIPT'), findsWidgets);
    expect(find.text('DEMO RECEIPT'), findsNothing);

    await tester.tap(find.widgetWithText(SnackBarAction, 'RECEIPT'));
    await settle(tester, 900);
    expect(find.byType(ReceiptPreviewScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings have no payment configuration', (tester) async {
    tester.view.physicalSize = const Size(1280, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final deps = await createAdminDependencies();
    await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
    await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
    await settle(tester, 900);
    Provider.of<AdminShellController>(
      tester.element(find.byType(Scaffold).first),
      listen: false,
    ).open(AdminModule.settings);
    await settle(tester, 900);

    expect(find.text('Billing counter'), findsOneWidget);
    expect(find.text('Indian Rupee (₹ INR)'), findsOneWidget);
    // Nothing to configure for online payment.
    for (final text in [
      'UPI ID',
      'UPI Payment',
      'QR Code',
      'Payment gateway',
      'payment gateway',
      'Allow part payments',
      'Cashfree',
      'Verification',
    ]) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('payment-option-'),
      ),
      findsNothing,
    );
    // The restrictions are still there.
    expect(find.textContaining('Wi-Fi'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
