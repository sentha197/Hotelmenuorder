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
  testWidgets('a cashier records a guest\'s cash-at-the-counter request and '
      'opens the receipt', (tester) async {
    usePhoneScreen(tester);
    final deps = await createAdminDependencies();
    final order = (await tester.runAsync(
      () => placeTestOrder(deps.orders, {'butter_chicken': 1}, table: 7),
    ))!;
    final invoice = deps.billing.forOrder(order.id)!;
    // The guest chose "Cash" on their phone.
    await tester.runAsync(
      () => deps.billing.requestCounterPayment(
        invoiceId: invoice.id,
        kind: CounterRequestKind.cash,
      ),
    );
    final amount = CurrencyFormatter.format(invoice.total);

    await deps.admin.signIn('cashier@dineqr.demo', DemoCredentials.password);
    await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
    await settle(tester, 900);
    await settle(tester, 900);

    // Bills is the cashier's landing page; the request stands out.
    expect(find.text('Guest will pay $amount in cash'), findsOneWidget);
    await tester.tap(find.textContaining('At the counter'));
    await settle(tester, 400);
    await tester.tap(find.text(invoice.billNumber));
    await settle(tester, 900);

    expect(
      find.textContaining('Nothing is paid until you record it'),
      findsOneWidget,
    );
    await tester.tap(find.text('Record').first);
    await settle(tester, 600);
    expect(find.text('Record payment'), findsWidgets);
    expect(find.textContaining('recorded as a demo payment'), findsOneWidget);
    expect(find.textContaining('chose cash at the counter'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await settle(tester, 600);

    final paid = deps.billing.byId(invoice.id)!;
    expect(paid.status, InvoiceStatus.paid);
    expect(paid.counterRequest, isNull);
    final payment = paid.payments.single;
    expect(payment.method, PaymentMethodType.cash);
    expect(payment.recordedBy, deps.admin.actor!.name);
    expect(payment.isSimulated, isTrue, reason: 'recorded in demo mode');
    expect(find.text('Demo payment of $amount recorded'), findsOneWidget);
    expect(find.text('DEMO RECEIPT'), findsOneWidget);

    await tester.tap(find.text('RECEIPT'));
    await settle(tester, 900);
    expect(find.byType(ReceiptPreviewScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings start in demo mode and live needs a gateway', (
    tester,
  ) async {
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

    final mode = find.byType(SegmentedButton<PaymentMode>);
    await tester.ensureVisible(mode);
    await settle(tester, 300);
    final segments = tester.widget<SegmentedButton<PaymentMode>>(mode);
    expect(segments.selected, {PaymentMode.demo});
    expect(
      segments.segments.firstWhere((s) => s.value == PaymentMode.live).enabled,
      isFalse,
    );
    expect(find.textContaining('Live is unavailable'), findsOneWidget);
    expect(find.text('Indian Rupee (₹ INR)'), findsOneWidget);
    expect(deps.settings.settings.paymentMode, PaymentMode.demo);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
