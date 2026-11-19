import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryStore store;
  late FakeGuard guard;
  late AuditLog audit;
  late OrderController orders;
  late BillingController billing;

  BillingController createBilling({List<Invoice> seed = const []}) =>
      BillingController(
        LocalBillingRepository(store, seed: seed),
        guard: guard,
        audit: audit,
      );

  setUp(() async {
    store = MemoryStore();
    guard = FakeGuard(StaffRole.owner);
    audit = AuditLog(LocalStaffRepository(store, seed: () => []))
      ..guard = guard;
    orders = await testOrders(store);
    billing = createBilling();
  });

  Future<Invoice> billFor(Map<String, int> items) async {
    final order = await placeTestOrder(orders, items);
    return billing.createForOrder(order);
  }

  Future<PaymentTransaction> payAtCounter(
    Invoice invoice, {
    Money? amount,
    PaymentMethodType method = PaymentMethodType.cash,
  }) => billing.recordCounterPayment(
    invoiceId: invoice.id,
    amount: amount ?? billing.byId(invoice.id)!.outstanding,
    method: method,
  );

  group('bills', () {
    test(
      'a bill copies the order pricing snapshot and is created once',
      () async {
        final order = await placeTestOrder(orders, {'chicken_65': 2});
        final invoice = await billing.createForOrder(order);
        expect(await billing.createForOrder(order), same(invoice));
        expect(billing.invoices, hasLength(1));
        expect(invoice.billNumber, matches(RegExp(r'^DQ-\d{4}-00001$')));
        expect(invoice.orderId, order.id);
        expect(invoice.tableNumber, order.tableNumber);
        expect(invoice.total, order.bill.total);
        expect(invoice.amounts.tax, order.bill.tax);
        expect(invoice.status, InvoiceStatus.unpaid);
        expect(invoice.outstanding, order.bill.total);

        final second = await billFor({'gulab_jamun': 1});
        expect(second.billNumber, endsWith('-00002'));
      },
    );

    test('bills survive a JSON round trip unchanged', () async {
      final invoice = await billFor({'masala_dosa': 1});
      await billing.recordCounterPayment(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.card,
        reference: 'TERM-42',
      );
      final paid = billing.byId(invoice.id)!;
      final copy = Invoice.fromJson(
        jsonDecode(jsonEncode(paid.toJson())) as Map<String, dynamic>,
      );
      expect(copy.total, paid.total);
      expect(copy.amountPaid, paid.amountPaid);
      expect(copy.status, InvoiceStatus.paid);
      expect(copy.payments.single.reference, 'TERM-42');
      expect(copy.payments.single.isCounter, isTrue);
    });

    test('a cancelled order voids its bill', () async {
      final order = await placeTestOrder(orders, {'masala_dosa': 1});
      final invoice = await billing.createForOrder(order);
      await billing.voidForOrder(order);
      final voided = billing.byId(invoice.id)!;
      expect(voided.status, InvoiceStatus.voided);
      expect(voided.outstanding, Money.zero);
      expect(voided.refundDue, isFalse);
      expect(
        billing.validateAmount(voided, const Money(100)),
        'This bill was cancelled.',
      );
    });
  });

  group('counter payments', () {
    test('only roles that collect payments can record them', () async {
      final invoice = await billFor({'chicken_65': 1});
      guard.actor = staffWith(StaffRole.kitchen);
      await expectLater(
        payAtCounter(invoice),
        throwsA(isA<PermissionDeniedException>()),
      );
      guard.actor = null;
      await expectLater(
        payAtCounter(invoice),
        throwsA(isA<SessionExpiredException>()),
      );
      guard.actor = staffWith(StaffRole.cashier);
      final payment = await payAtCounter(invoice);
      expect(payment.recordedBy, 'Test Cashier');
      expect(payment.provider, PaymentTransaction.counterProvider);
      // Recorded by staff: real money, never a test payment.
      expect(payment.isSimulated, isFalse);
      expect(billing.byId(invoice.id)!.status, InvoiceStatus.paid);
      final events = await audit.events();
      expect(events.first.action, 'payment.record');
      expect(events.first.actorRole, StaffRole.cashier.label);
    });

    test('the counter takes cash, card or UPI only', () async {
      expect(PaymentMethodType.counter, [
        PaymentMethodType.cash,
        PaymentMethodType.card,
        PaymentMethodType.upi,
      ]);
      final invoice = await billFor({'masala_dosa': 1});
      for (final method in [
        PaymentMethodType.netBanking,
        PaymentMethodType.wallet,
      ]) {
        await expectLater(
          payAtCounter(invoice, method: method),
          throwsA(isA<PaymentException>()),
        );
      }
      await payAtCounter(invoice, method: PaymentMethodType.upi);
      expect(billing.byId(invoice.id)!.methodsLabel, 'UPI');
    });

    test('a bill paid part by card, part in cash settles once', () async {
      final invoice = await billFor({'chicken_65': 2, 'butter_naan': 2});
      final byCard = Money(invoice.total.paise ~/ 2);
      await payAtCounter(
        invoice,
        amount: byCard,
        method: PaymentMethodType.card,
      );
      var bill = billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.partiallyPaid);
      expect(bill.outstanding, invoice.total - byCard);
      expect(
        billing.validateAmount(bill, bill.outstanding + const Money(1)),
        isNotNull,
      );

      await payAtCounter(invoice);
      bill = billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.paid);
      expect(bill.outstanding, Money.zero);
      expect(bill.methodsLabel, 'Card + Cash');
      expect(
        billing.validateAmount(bill, const Money(100)),
        'This bill is already paid.',
      );
    });
  });

  group('refunds', () {
    test('refunds are limited, audited and never reopen the balance', () async {
      final invoice = await billFor({'chicken_65': 2});
      final payment = await payAtCounter(invoice);

      guard.actor = staffWith(StaffRole.cashier);
      await expectLater(
        billing.refund(
          invoiceId: invoice.id,
          paymentId: payment.id,
          amount: const Money(100),
          reason: 'Cold food',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      guard.actor = staffWith(StaffRole.accountant);
      await expectLater(
        billing.refund(
          invoiceId: invoice.id,
          paymentId: payment.id,
          amount: payment.amount + const Money(1),
          reason: 'Too much',
        ),
        throwsA(isA<PaymentException>()),
      );
      await expectLater(
        billing.refund(
          invoiceId: invoice.id,
          paymentId: payment.id,
          amount: const Money(100),
          reason: '',
        ),
        throwsA(isA<PaymentException>()),
      );

      final refund = await billing.refund(
        invoiceId: invoice.id,
        paymentId: payment.id,
        amount: const Money(5000),
        reason: 'Dish was cold',
      );
      expect(refund.status, RefundStatus.processed);
      expect(refund.isSimulated, isFalse);
      var bill = billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.partiallyRefunded);
      expect(bill.amountPaid, invoice.total);
      expect(bill.amountRefunded, const Money(5000));
      expect(bill.netPaid, invoice.total - const Money(5000));
      expect(bill.outstanding, Money.zero);
      expect(bill.refundableOn(payment.id), payment.amount - const Money(5000));

      await billing.refund(
        invoiceId: invoice.id,
        paymentId: payment.id,
        amount: bill.refundableOn(payment.id),
        reason: 'Order mix-up',
      );
      bill = billing.byId(invoice.id)!;
      expect(bill.status, InvoiceStatus.refunded);
      expect(bill.refundableOn(payment.id), Money.zero);
      final events = await audit.events();
      expect(events.where((e) => e.action == 'payment.refund'), hasLength(2));
      expect(events.first.summary, startsWith('Refund'));
    });
  });

  group('history from before online payment was retired', () {
    Invoice historical(String provider, {Map<String, dynamic>? extra}) =>
        Invoice.fromJson({
          'id': 'INV000901',
          'number': 'DQ-2026-00901',
          'order': 'OD900',
          'table': 4,
          'createdAt': '2026-10-20T10:00:00.000Z',
          'lines': <Object>[],
          'amounts': const BillBreakdown(
            subtotal: Money(20000),
            tax: Money(1000),
            total: Money(21000),
            taxRateBasisPoints: 500,
          ).toJson(),
          'payments': [
            {
              'id': 'PAY000901',
              'invoice': 'INV000901',
              'order': 'OD900',
              'amount': 21000,
              'method': 'upi',
              'status': 'succeeded',
              'provider': provider,
              'createdAt': '2026-10-20T10:30:00.000Z',
              'updatedAt': '2026-10-20T10:31:00.000Z',
              'key': 'old-key-901',
              'ref': '512345678901',
              'claimed': '2026-10-20T10:30:30.000Z',
            },
          ],
          // A field older servers sent; ignored now.
          'counterRequest': {
            'kind': 'cash',
            'amount': 21000,
            'at': '2026-10-20T10:20:00.000Z',
          },
          ...?extra,
        });

    test('older online payments still read and count as paid', () {
      final bill = historical(PaymentTransaction.upiDirectProvider);
      expect(bill.status, InvoiceStatus.paid);
      expect(bill.outstanding, Money.zero);
      final payment = bill.payments.single;
      expect(payment.method, PaymentMethodType.upi);
      expect(payment.reference, '512345678901');
      expect(payment.isCounter, isFalse);
      expect(payment.isGateway, isFalse);
    });

    test('a UPI-direct payment can be refunded at the counter', () async {
      billing = createBilling(
        seed: [historical(PaymentTransaction.upiDirectProvider)],
      );
      await billing.load();
      final refund = await billing.refund(
        invoiceId: 'INV000901',
        paymentId: 'PAY000901',
        amount: const Money(1000),
        reason: 'Overcharged',
      );
      expect(refund.status, RefundStatus.processed);
    });

    test('a gateway payment is refunded at the gateway, not here', () async {
      billing = createBilling(seed: [historical('Cashfree')]);
      await billing.load();
      expect(billing.byId('INV000901')!.payments.single.isGateway, isTrue);
      await expectLater(
        billing.refund(
          invoiceId: 'INV000901',
          paymentId: 'PAY000901',
          amount: const Money(1000),
          reason: 'Overcharged',
        ),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            contains('Cashfree'),
          ),
        ),
      );
      expect(billing.byId('INV000901')!.refunds, isEmpty);
    });
  });

  group('currency', () {
    tearDown(() => CurrencyFormatter.configure('INR'));

    test('amounts follow the restaurant currency', () {
      expect(CurrencyFormatter.format(const Money(12345000)), '₹1,23,450');
      CurrencyFormatter.configure('USD');
      expect(CurrencyFormatter.format(const Money(123450)), r'$1,234.50');
      expect(CurrencyFormatter.symbol, r'$');
      expect(SettingsController.parseRupees(r'$12.50'), const Money(1250));
      CurrencyFormatter.configure('XYZ'); // unknown: ignored
      expect(CurrencyFormatter.code, 'USD');
    });

    test('settings refuse an unsupported currency and carry no '
        'online payment options', () {
      expect(
        SettingsController.validate(
          const RestaurantSettings(currencyCode: 'XYZ'),
        ),
        'Choose a supported currency.',
      );
      final json = const RestaurantSettings(currencyCode: 'EUR').toJson();
      expect(json.containsKey('paymentMode'), isFalse);
      expect(json.containsKey('methods'), isFalse);
      expect(json.containsKey('partial'), isFalse);
      final copy = RestaurantSettings.fromJson({
        ...json,
        // What older servers sent: ignored.
        'methods': ['upi', 'qr'],
        'partial': false,
      });
      expect(copy.currencyCode, 'EUR');
      // Servers from before currencies send no currency.
      final old = RestaurantSettings.fromJson({'name': 'Old server'});
      expect(old.currencyCode, 'INR');
    });
  });

  group('thermal receipt encoding', () {
    test('ESC/POS text carries the bill and totals', () async {
      final invoice = await billFor({'chicken_65': 1, 'masala_dosa': 2});
      await payAtCounter(invoice);
      final bytes = EscPosReceipt.encode(billing.byId(invoice.id)!);
      expect(bytes.every((b) => b < 128), isTrue, reason: 'ASCII only');
      final text = latin1.decode(bytes);
      expect(text, contains(invoice.billNumber));
      expect(text, contains('TOTAL'));
      expect(
        text,
        contains(
          CurrencyFormatter.format(invoice.total).replaceAll('₹', 'Rs.'),
        ),
      );
      // A real payment carries no test or demo marker.
      expect(text.toUpperCase(), isNot(contains('TEST PAYMENT')));
      expect(text.toUpperCase(), isNot(contains('SIMULATED')));
      expect(const UnavailableThermalPrinter().isAvailable, isFalse);
    });
  });

  test('the kitchen serves an order whose bill is still unpaid: payment '
      'status comes from payments, not from the order status', () async {
    final order = await placeTestOrder(orders, {'masala_dosa': 1});
    final invoice = await billing.createForOrder(order);
    for (var i = 0; i < 4; i++) {
      await orders.advanceStatus(order.id);
    }
    expect(orders.byId(order.id)!.status, OrderStatus.served);
    expect(billing.byId(invoice.id)!.status, InvoiceStatus.unpaid);
  });
}
