import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gateway whose collect call fails without an answer (e.g. the app was
/// closed or the network dropped mid-payment).
class InterruptedGateway extends SimulatedPaymentGateway {
  InterruptedGateway() : super(processingTime: Duration.zero);

  @override
  Future<PaymentResult> collect(
    PaymentRequest request, {
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) async => throw StateError('connection lost');
}

void main() {
  late MemoryStore store;
  late FakeGuard guard;
  late AuditLog audit;
  late OrderController orders;
  late BillingController billing;
  late RestaurantSettings settings;

  BillingController createBilling(PaymentGateway gateway) => BillingController(
    LocalBillingRepository(store),
    gateway,
    guard: guard,
    audit: audit,
    settings: () => settings,
  );

  setUp(() async {
    store = MemoryStore();
    guard = FakeGuard(StaffRole.owner);
    audit = AuditLog(LocalStaffRepository(store, seed: () => []))
      ..guard = guard;
    settings = const RestaurantSettings();
    orders = await testOrders(store);
    billing = createBilling(
      SimulatedPaymentGateway(processingTime: Duration.zero),
    );
  });

  Future<Invoice> billFor(Map<String, int> items) async {
    final order = await placeTestOrder(orders, items);
    return billing.createForOrder(order);
  }

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
      await billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.upi,
      );
      final paid = billing.byId(invoice.id)!;
      final copy = Invoice.fromJson(
        jsonDecode(jsonEncode(paid.toJson())) as Map<String, dynamic>,
      );
      expect(copy.total, paid.total);
      expect(copy.amountPaid, paid.amountPaid);
      expect(copy.status, InvoiceStatus.paid);
      expect(copy.payments.single.reference, paid.payments.single.reference);
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

  group('online payments', () {
    test(
      'a full payment marks the bill paid with a simulated reference',
      () async {
        final invoice = await billFor({'chicken_65': 1});
        final payment = await billing.payOnline(
          invoiceId: invoice.id,
          amount: invoice.outstanding,
          method: PaymentMethodType.upi,
        );
        expect(payment.status, PaymentStatus.succeeded);
        expect(payment.isSimulated, isTrue);
        expect(payment.reference, startsWith('DEMO-'));
        final paid = billing.byId(invoice.id)!;
        expect(paid.status, InvoiceStatus.paid);
        expect(paid.amountPaid, invoice.total);
        expect(paid.outstanding, Money.zero);
        expect(
          billing.validateAmount(paid, const Money(100)),
          'This bill is already paid.',
        );
      },
    );

    test(
      'partial payments leave a balance and overpayment is refused',
      () async {
        final invoice = await billFor({'chicken_65': 2});
        const part = Money(10000);
        await billing.payOnline(
          invoiceId: invoice.id,
          amount: part,
          method: PaymentMethodType.card,
        );
        var bill = billing.byId(invoice.id)!;
        expect(bill.status, InvoiceStatus.partiallyPaid);
        expect(bill.outstanding, invoice.total - part);

        await expectLater(
          billing.payOnline(
            invoiceId: invoice.id,
            amount: bill.outstanding + const Money(1),
            method: PaymentMethodType.card,
          ),
          throwsA(isA<PaymentException>()),
        );

        await billing.payOnline(
          invoiceId: invoice.id,
          amount: bill.outstanding,
          method: PaymentMethodType.wallet,
        );
        bill = billing.byId(invoice.id)!;
        expect(bill.status, InvoiceStatus.paid);
        expect(bill.amountPaid, invoice.total);
        expect(bill.methodsLabel, contains('+'));
      },
    );

    test(
      'part payments are refused when the restaurant does not allow them',
      () async {
        settings = settings.copyWith(allowPartialPayments: false);
        final invoice = await billFor({'chicken_65': 2});
        expect(
          billing.validateAmount(
            invoice,
            const Money(100),
            allowPartial: false,
          ),
          startsWith('Please pay the full'),
        );
        await expectLater(
          billing.payOnline(
            invoiceId: invoice.id,
            amount: const Money(100),
            method: PaymentMethodType.upi,
          ),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test('failed and cancelled payments do not change the balance', () async {
      final invoice = await billFor({'masala_dosa': 2});
      final failed = await billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.netBanking,
        outcome: SimulatedOutcome.failure,
      );
      expect(failed.status, PaymentStatus.failed);
      expect(billing.byId(invoice.id)!.status, InvoiceStatus.failed);
      expect(billing.byId(invoice.id)!.outstanding, invoice.total);

      final cancelled = await billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.upi,
        outcome: SimulatedOutcome.cancel,
      );
      expect(cancelled.status, PaymentStatus.cancelled);
      final bill = billing.byId(invoice.id)!;
      expect(bill.amountPaid, Money.zero);
      expect(bill.outstanding, invoice.total);

      // A retry can still succeed.
      await billing.payOnline(
        invoiceId: invoice.id,
        amount: bill.outstanding,
        method: PaymentMethodType.upi,
      );
      expect(billing.byId(invoice.id)!.status, InvoiceStatus.paid);
    });

    test('a second payment cannot start while one is in progress', () async {
      billing = createBilling(
        SimulatedPaymentGateway(
          processingTime: const Duration(milliseconds: 50),
        ),
      );
      final invoice = await billFor({'masala_dosa': 1});
      final first = billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.upi,
      );
      expect(billing.isProcessing(invoice.id), isTrue);
      await expectLater(
        billing.payOnline(
          invoiceId: invoice.id,
          amount: invoice.outstanding,
          method: PaymentMethodType.upi,
        ),
        throwsA(isA<PaymentException>()),
      );
      await first;
      final bill = billing.byId(invoice.id)!;
      expect(bill.payments, hasLength(1));
      expect(bill.amountPaid, invoice.total);
    });

    test(
      'an interrupted payment stays pending and is never counted as paid',
      () async {
        billing = createBilling(InterruptedGateway());
        final invoice = await billFor({'masala_dosa': 1});
        await expectLater(
          billing.payOnline(
            invoiceId: invoice.id,
            amount: invoice.outstanding,
            method: PaymentMethodType.upi,
          ),
          throwsA(isA<PaymentException>()),
        );
        var bill = billing.byId(invoice.id)!;
        expect(bill.status, InvoiceStatus.pending);
        expect(bill.amountPaid, Money.zero);
        expect(bill.payableNow, Money.zero);
        expect(
          billing.validateAmount(bill, invoice.total),
          'A payment for this bill is still being confirmed.',
        );

        // The provider has no record of it, so it resolves as failed.
        await billing.checkPending(invoice.id);
        bill = billing.byId(invoice.id)!;
        expect(bill.hasPendingPayment, isFalse);
        expect(bill.payments.single.status, PaymentStatus.failed);
        expect(bill.outstanding, invoice.total);
      },
    );

    test('pending payments are resolved again when bills are loaded', () async {
      billing = createBilling(InterruptedGateway());
      final invoice = await billFor({'masala_dosa': 1});
      await expectLater(
        billing.payOnline(
          invoiceId: invoice.id,
          amount: invoice.outstanding,
          method: PaymentMethodType.upi,
        ),
        throwsA(isA<PaymentException>()),
      );
      final reloaded = createBilling(
        SimulatedPaymentGateway(processingTime: Duration.zero),
      );
      await reloaded.load();
      expect(reloaded.byId(invoice.id)!.hasPendingPayment, isFalse);
    });

    test(
      'the simulator replays a request with the same idempotency key',
      () async {
        final gateway = SimulatedPaymentGateway(processingTime: Duration.zero);
        const request = PaymentRequest(
          invoiceId: 'INV1',
          orderId: 'OD1',
          amount: Money(5000),
          method: PaymentMethodType.upi,
          idempotencyKey: 'same-key',
        );
        final first = await gateway.collect(request);
        final again = await gateway.collect(
          request,
          outcome: SimulatedOutcome.failure,
        );
        expect(again.status, first.status);
        expect(again.reference, first.reference);
      },
    );

    test('methods are limited to those the provider supports', () async {
      // Live mode without a real gateway: no online payment, only the
      // counter.
      settings = settings.copyWith(paymentMode: PaymentMode.live);
      billing = createBilling(const UnavailablePaymentGateway());
      expect(billing.onlinePaymentsAvailable, isFalse);
      expect(billing.liveAvailable, isFalse);
      expect(billing.paymentOptions, [
        PaymentOption.cash,
        PaymentOption.payAtCounter,
      ]);
      final invoice = await billFor({'masala_dosa': 1});
      await expectLater(
        billing.payOnline(
          invoiceId: invoice.id,
          amount: invoice.outstanding,
          method: PaymentMethodType.upi,
        ),
        throwsA(isA<PaymentException>()),
      );
    });
  });

  group('counter payments and refunds', () {
    test('only roles that collect payments can record them', () async {
      final invoice = await billFor({'chicken_65': 1});
      guard.actor = staffWith(StaffRole.kitchen);
      await expectLater(
        billing.recordCounterPayment(
          invoiceId: invoice.id,
          amount: invoice.outstanding,
          method: PaymentMethodType.cash,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      guard.actor = null;
      await expectLater(
        billing.recordCounterPayment(
          invoiceId: invoice.id,
          amount: invoice.outstanding,
          method: PaymentMethodType.cash,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      guard.actor = staffWith(StaffRole.cashier);
      final payment = await billing.recordCounterPayment(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.cash,
      );
      expect(payment.recordedBy, 'Test Cashier');
      // Recorded while the restaurant is in demo mode.
      expect(payment.isSimulated, isTrue);
      expect(billing.byId(invoice.id)!.status, InvoiceStatus.paid);
      final events = await audit.events();
      expect(events.first.action, 'payment.record');
      expect(events.first.actorRole, StaffRole.cashier.label);
    });

    test('refunds are limited, audited and never reopen the balance', () async {
      final invoice = await billFor({'chicken_65': 2});
      final payment = await billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.upi,
      );

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
      expect(refund.isSimulated, isTrue);
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
      expect(events.first.summary, startsWith('Simulated refund'));
    });
  });

  group('payment modes and options', () {
    test('demo mode offers every option and labels payments as demo', () async {
      expect(billing.paymentMode, PaymentMode.demo);
      expect(billing.isSimulated, isTrue);
      expect(billing.paymentOptions, PaymentOption.values);
      final invoice = await billFor({'masala_dosa': 1});
      final payment = await billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentOption.scanAndPay.method!,
        methodDetail: PaymentOption.scanAndPay.detail,
      );
      expect(payment.isSimulated, isTrue);
      expect(payment.mode, PaymentMode.demo);
      expect(payment.methodLabel, 'UPI · Scan & Pay');
      expect(payment.currency, 'INR');
      final copy = PaymentTransaction.fromJson(
        jsonDecode(jsonEncode(payment.toJson())) as Map<String, dynamic>,
      );
      expect(copy.methodDetail, 'Scan & Pay');
      expect(billing.byId(invoice.id)!.hasDemoPayments, isTrue);
    });

    test('live mode never takes payments through the simulator', () async {
      settings = settings.copyWith(paymentMode: PaymentMode.live);
      // The offline demo's simulator is not a live gateway.
      expect(billing.liveAvailable, isFalse);
      expect(billing.isSimulated, isFalse);
      expect(billing.onlinePaymentsAvailable, isFalse);
      final invoice = await billFor({'chicken_65': 1});
      final counter = await billing.recordCounterPayment(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.cash,
      );
      expect(counter.isSimulated, isFalse);
      expect(billing.byId(invoice.id)!.demoNotice, isNull);
    });

    test('UPI and Scan & Pay are offered only for rupee bills', () {
      settings = settings.copyWith(currencyCode: 'USD');
      expect(billing.paymentOptions, isNot(contains(PaymentOption.upi)));
      expect(billing.paymentOptions, isNot(contains(PaymentOption.scanAndPay)));
      expect(billing.paymentOptions, contains(PaymentOption.card));
    });

    test('a retried attempt with the same key is charged once', () async {
      final invoice = await billFor({'paneer_tikka': 1});
      Future<PaymentTransaction> attempt() => billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.card,
        idempotencyKey: 'retry-key-0001',
      );
      final first = await attempt();
      final again = await attempt();
      expect(again.id, first.id);
      final bill = billing.byId(invoice.id)!;
      expect(bill.payments, hasLength(1));
      expect(bill.amountPaid, invoice.total);
    });
  });

  group('counter requests', () {
    test('a request moves no money until staff record the payment', () async {
      final invoice = await billFor({'butter_chicken': 1});
      final requested = await billing.requestCounterPayment(
        invoiceId: invoice.id,
        kind: CounterRequestKind.cash,
      );
      expect(requested.openCounterRequest!.kind, CounterRequestKind.cash);
      expect(requested.openCounterRequest!.amount, invoice.total);
      expect(requested.status, InvoiceStatus.unpaid);
      expect(requested.amountPaid, Money.zero);
      expect(requested.payments, isEmpty);

      await billing.recordCounterPayment(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.cash,
      );
      final paid = billing.byId(invoice.id)!;
      expect(paid.status, InvoiceStatus.paid);
      expect(paid.counterRequest, isNull);
    });

    test('a request is limited to the balance and can be withdrawn', () async {
      final invoice = await billFor({'masala_dosa': 2});
      await expectLater(
        billing.requestCounterPayment(
          invoiceId: invoice.id,
          kind: CounterRequestKind.counter,
          amount: invoice.total + const Money(1),
        ),
        throwsA(isA<PaymentException>()),
      );
      await billing.requestCounterPayment(
        invoiceId: invoice.id,
        kind: CounterRequestKind.counter,
        amount: const Money(5000),
      );
      expect(billing.byId(invoice.id)!.openCounterRequest!.amount.paise, 5000);
      await billing.cancelCounterRequest(invoice.id);
      expect(billing.byId(invoice.id)!.counterRequest, isNull);
    });

    test('paying the whole balance online ends the request', () async {
      final invoice = await billFor({'masala_dosa': 1});
      await billing.requestCounterPayment(
        invoiceId: invoice.id,
        kind: CounterRequestKind.counter,
      );
      await billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.wallet,
      );
      expect(billing.byId(invoice.id)!.counterRequest, isNull);
    });
  });

  group('split payments', () {
    const due = Money(10000);
    final all = PaymentOption.values.toSet();
    String? check(List<SplitPart> parts, {bool partial = true}) =>
        SplitPlan.validate(
          parts,
          payable: due,
          available: all,
          allowPartial: partial,
        );

    test('parts must cover the balance exactly, without exceeding it', () {
      const card = PaymentOption.card;
      const cash = PaymentOption.cash;
      expect(
        check(const [
          SplitPart(card, Money(4000)),
          SplitPart(cash, Money(6000)),
        ]),
        isNull,
      );
      expect(
        check(const [
          SplitPart(card, Money(4000)),
          SplitPart(cash, Money(7000)),
        ]),
        contains('more than'),
      );
      expect(
        check(const [
          SplitPart(card, Money(4000)),
          SplitPart(cash, Money(5000)),
        ]),
        contains('unassigned'),
      );
      expect(check(const [SplitPart(card, due)]), contains('at least two'));
      expect(
        check(const [SplitPart(card, Money(0)), SplitPart(cash, due)]),
        contains('needs an amount'),
      );
      expect(
        check(const [
          SplitPart(PaymentOption.payAtCounter, Money(4000)),
          SplitPart(cash, Money(6000)),
        ]),
        contains('one way to pay at the counter'),
      );
      expect(
        check(const [
          SplitPart(card, Money(4000)),
          SplitPart(cash, Money(6000)),
        ], partial: false),
        contains('full amount'),
      );
      expect(
        SplitPlan.validate(
          const [SplitPart(card, Money(4000)), SplitPart(cash, Money(6000))],
          payable: due,
          available: {cash},
          allowPartial: true,
        ),
        contains('not available'),
      );
      expect(
        SplitPlan.ordered(const [
          SplitPart(cash, Money(6000)),
          SplitPart(card, Money(4000)),
        ]).map((p) => p.option),
        [card, cash],
      );
    });

    test('a split bill is paid once: online part, then counter part', () async {
      final invoice = await billFor({'chicken_65': 2, 'butter_naan': 2});
      final online = Money(invoice.total.paise ~/ 2);
      final rest = invoice.total - online;
      await billing.payOnline(
        invoiceId: invoice.id,
        amount: online,
        method: PaymentMethodType.card,
        methodDetail: 'Credit',
      );
      expect(billing.byId(invoice.id)!.status, InvoiceStatus.partiallyPaid);
      await billing.requestCounterPayment(
        invoiceId: invoice.id,
        kind: CounterRequestKind.cash,
        amount: rest,
      );
      // A part larger than what is left is refused.
      await expectLater(
        billing.payOnline(
          invoiceId: invoice.id,
          amount: rest + const Money(1),
          method: PaymentMethodType.upi,
        ),
        throwsA(isA<PaymentException>()),
      );
      await billing.recordCounterPayment(
        invoiceId: invoice.id,
        amount: rest,
        method: PaymentMethodType.cash,
      );
      final paid = billing.byId(invoice.id)!;
      expect(paid.status, InvoiceStatus.paid);
      expect(paid.amountPaid, invoice.total);
      expect(paid.payments, hasLength(2));
      expect(paid.methodsLabel, 'Card + Cash');
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

    test('settings refuse an unsupported currency', () {
      expect(
        SettingsController.validate(
          const RestaurantSettings(currencyCode: 'XYZ'),
        ),
        'Choose a supported currency.',
      );
      final json = const RestaurantSettings(
        currencyCode: 'EUR',
        paymentMode: PaymentMode.live,
      ).toJson();
      final copy = RestaurantSettings.fromJson(json);
      expect(copy.currencyCode, 'EUR');
      expect(copy.paymentMode, PaymentMode.live);
      // Servers from before payment modes send neither key.
      final old = RestaurantSettings.fromJson({'name': 'Old server'});
      expect(old.paymentMode, PaymentMode.demo);
      expect(old.currencyCode, 'INR');
    });
  });

  group('thermal receipt encoding', () {
    test('ESC/POS text carries the bill, totals and the demo marker', () async {
      final invoice = await billFor({'chicken_65': 1, 'masala_dosa': 2});
      await billing.payOnline(
        invoiceId: invoice.id,
        amount: invoice.outstanding,
        method: PaymentMethodType.upi,
      );
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
      expect(text.toUpperCase(), contains('SIMULATED'));
      expect(const UnavailableThermalPrinter().isAvailable, isFalse);
    });
  });

  test(
    'payment status comes from payments, not from the order status',
    () async {
      final order = await placeTestOrder(orders, {'masala_dosa': 1});
      final invoice = await billing.createForOrder(order);
      for (var i = 0; i < 4; i++) {
        await orders.advanceStatus(order.id);
      }
      expect(orders.byId(order.id)!.isActive, isFalse);
      expect(billing.byId(invoice.id)!.status, InvoiceStatus.unpaid);
      expect(order, isA<RestaurantOrder>());
    },
  );
}
