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
    expect(find.textContaining('demo payment'), findsNothing);
    expect(find.textContaining('chose cash at the counter'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await settle(tester, 600);

    final paid = deps.billing.byId(invoice.id)!;
    expect(paid.status, InvoiceStatus.paid);
    expect(paid.counterRequest, isNull);
    final payment = paid.payments.single;
    expect(payment.method, PaymentMethodType.cash);
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

  testWidgets('settings offer each payment option on its own, with no demo '
      'mode', (tester) async {
    tester.view.physicalSize = const Size(1280, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // A gateway that takes every method, so every box can be ticked.
    final store = MemoryStore();
    final deps = await createAdminDependencies(
      store: store,
      paymentGateway: FakePaymentGateway(),
    );
    await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
    await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
    await settle(tester, 900);
    Provider.of<AdminShellController>(
      tester.element(find.byType(Scaffold).first),
      listen: false,
    ).open(AdminModule.settings);
    await settle(tester, 900);

    // No Demo / Live switch and no demo wording.
    expect(find.text('Demo'), findsNothing);
    expect(find.text('Live'), findsNothing);
    expect(find.textContaining('Demo mode'), findsNothing);
    expect(find.text('UPI and QR Payment'), findsNothing);
    expect(find.text('Indian Rupee (₹ INR)'), findsOneWidget);

    // Five options, each with its own box, all on to start with.
    CheckboxListTile box(String key) => tester.widget<CheckboxListTile>(
      find.byKey(ValueKey('payment-option-$key')),
    );
    for (final key in ['upi', 'qr', 'card', 'netBanking', 'wallet']) {
      expect(box(key).value, isTrue, reason: key);
      expect(box(key).onChanged, isNotNull, reason: key);
    }
    expect(find.text('UPI Payment'), findsOneWidget);
    expect(find.text('QR Code Payment'), findsOneWidget);

    // Turning UPI off leaves QR Code on, and the other way round.
    final upi = find.byKey(const ValueKey('payment-option-upi'));
    await tester.ensureVisible(upi);
    await settle(tester, 300);
    await tester.tap(upi);
    await settle(tester, 300);
    expect(box('upi').value, isFalse);
    expect(box('qr').value, isTrue);

    final save = find.text('Save settings');
    await tester.ensureVisible(save);
    await settle(tester, 300);
    await tester.tap(save);
    await settle(tester, 900);
    expect(
      deps.settings.settings.onlineOptions,
      isNot(contains(PaymentOption.upi)),
    );
    expect(deps.settings.settings.onlineOptions, {
      PaymentOption.scanAndPay,
      PaymentOption.card,
      PaymentOption.netBanking,
      PaymentOption.wallet,
    });
    // Saved, so it is still there when the page is opened again.
    final stored = await LocalSettingsRepository(store).fetchSettings();
    expect(stored.onlineOptions, deps.settings.settings.onlineOptions);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
