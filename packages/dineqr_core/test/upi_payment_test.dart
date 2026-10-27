import 'dart:async';
import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _config = ApiConfig(baseUrl: Uri.parse('http://api.test'));

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Invoice _invoice({
  String id = 'INV00001',
  String number = 'DQ-2026-00012',
  Money total = const Money(45000),
  List<PaymentTransaction> payments = const [],
}) => Invoice(
  id: id,
  billNumber: number,
  orderId: 'OD12345',
  tableNumber: 5,
  createdAt: DateTime.utc(2026, 10, 25, 7),
  lines: const [],
  amounts: BillBreakdown(
    subtotal: total,
    tax: Money.zero,
    total: total,
    taxRateBasisPoints: 0,
  ),
  restaurant: const RestaurantSnapshot(name: 'Test Cafe'),
  payments: payments,
);

PaymentTransaction _payment({
  String id = 'PAY000001',
  Money amount = const Money(45000),
  PaymentStatus status = PaymentStatus.pending,
  DateTime? claimedAt,
  String reference = '',
  String provider = PaymentTransaction.upiDirectProvider,
}) => PaymentTransaction(
  id: id,
  invoiceId: 'INV00001',
  orderId: 'OD12345',
  amount: amount,
  method: PaymentMethodType.upi,
  status: status,
  provider: provider,
  createdAt: DateTime.utc(2026, 10, 25, 7, 1),
  updatedAt: DateTime.utc(2026, 10, 25, 7, 1),
  idempotencyKey: 'key-$id',
  reference: reference,
  claimedAt: claimedAt,
);

const _settings = UpiSettings(
  enabled: true,
  upiId: 'cafe@okhdfcbank',
  payeeName: 'Test Cafe',
);

void main() {
  group('UpiSettings', () {
    test('accepts well-formed UPI IDs and normalises them', () {
      for (final id in [
        'cafe@okhdfcbank',
        'cafe.owner@oksbi',
        'cafe_owner-1@ybl',
        '9876543210@paytm',
        'ab@upi',
      ]) {
        expect(
          UpiSettings.isValidId(UpiSettings.normalizeId(id)),
          isTrue,
          reason: id,
        );
      }
      expect(
        UpiSettings.normalizeId('  Cafe.Owner@OkHDFCBank '),
        'cafe.owner@okhdfcbank',
      );
    });

    test('rejects malformed UPI IDs', () {
      for (final id in [
        '',
        'no-at-sign',
        '@okhdfcbank',
        'cafe@',
        'ca fe@okhdfcbank',
        'cafe@b',
        'cafe@bank@x',
        'c@okhdfcbank',
        'cafe@123bank',
        'café@okhdfcbank',
        'cafe@okhdfcbank.com',
      ]) {
        expect(UpiSettings.isValidId(id), isFalse, reason: id);
      }
    });

    test(
      'names are 2 to 60 characters without markup or control characters',
      () {
        expect(UpiSettings.isValidName('Spice Route'), isTrue);
        expect(UpiSettings.isValidName("Anna's Café & Bar"), isTrue);
        expect(UpiSettings.isValidName('A'), isFalse);
        expect(UpiSettings.isValidName('x' * 61), isFalse);
        expect(UpiSettings.isValidName('<b>Cafe</b>'), isFalse);
        expect(UpiSettings.isValidName('Cafe\nTwo'), isFalse);
      },
    );

    test('is ready only when switched on and complete', () {
      expect(_settings.isReady, isTrue);
      expect(_settings.copyWith(enabled: false).isReady, isFalse);
      expect(_settings.copyWith(upiId: 'broken').isReady, isFalse);
      expect(_settings.copyWith(payeeName: ' ').isReady, isFalse);
      expect(const UpiSettings().isReady, isFalse);
    });

    test('validate explains the first problem', () {
      expect(_settings.validate(), isNull);
      expect(
        _settings.copyWith(upiId: 'nope').validate(),
        'Enter a valid UPI ID, like name@bank.',
      );
      expect(
        _settings.copyWith(upiId: '').validate(),
        "Enter the restaurant's UPI ID to switch UPI payments on.",
      );
      expect(
        _settings.copyWith(payeeName: '').validate(),
        'Enter the name guests will see when they pay.',
      );
      expect(
        _settings.copyWith(payeeName: '<x>').validate(),
        'The name must be 2 to 60 characters.',
      );
      // Switched off, the details may be incomplete.
      expect(const UpiSettings().validate(), isNull);
      expect(_settings.copyWith(enabled: false, upiId: '').validate(), isNull);
    });

    test('survives a JSON round trip and tolerates missing keys', () {
      final copy = UpiSettings.fromJson(
        jsonDecode(
              jsonEncode(
                _settings
                    .copyWith(
                      qrImageUrl: 'https://x.test/uploads/upi/a.png',
                      verificationMode: UpiVerificationMode.automatic,
                    )
                    .toJson(),
              ),
            )
            as Map<String, dynamic>,
      );
      expect(copy.upiId, 'cafe@okhdfcbank');
      expect(copy.hasQrImage, isTrue);
      expect(copy.verificationMode, UpiVerificationMode.automatic);
      expect(UpiSettings.fromJson(const {}), const UpiSettings());
      expect(
        UpiSettings.fromJson(const {
          'verificationMode': 'weird',
        }).verificationMode,
        UpiVerificationMode.manual,
      );
    });
  });

  group('UpiPaymentLink', () {
    UpiPaymentLink link({
      UpiSettings settings = _settings,
      Money amount = const Money(45000),
      String billNumber = 'DQ-2026-00012',
      String paymentId = 'PAY000001',
    }) => UpiPaymentLink.forPayment(
      settings: settings,
      invoice: _invoice(number: billNumber),
      payment: _payment(id: paymentId, amount: amount),
    );

    test('carries the payee, exact amount, INR and a unique reference', () {
      final l = link();
      expect(
        l.uriString,
        'upi://pay?pa=cafe@okhdfcbank&pn=Test%20Cafe&am=450.00&cu=INR'
        '&tn=Bill%20DQ-2026-00012&tr=PAY000001',
      );
      final parsed = l.uri;
      expect(parsed.scheme, 'upi');
      expect(parsed.host, 'pay');
      expect(parsed.queryParameters, {
        'pa': 'cafe@okhdfcbank',
        'pn': 'Test Cafe',
        'am': '450.00',
        'cu': 'INR',
        'tn': 'Bill DQ-2026-00012',
        'tr': 'PAY000001',
      });
    });

    test('formats paise exactly, never with floating point', () {
      expect(link(amount: const Money(5)).amountText, '0.05');
      expect(link(amount: const Money(100)).amountText, '1.00');
      expect(link(amount: const Money(12345)).amountText, '123.45');
      expect(link(amount: const Money(125050)).amountText, '1250.50');
      expect(link(amount: const Money(10000000)).amountText, '100000.00');
    });

    test('encodes spaces as %20 and keeps special characters safe', () {
      final l = link(
        settings: _settings.copyWith(payeeName: "Anna's Café & Sons"),
      );
      expect(l.uriString, contains('pn=Anna\'s%20Caf%C3%A9%20%26%20Sons'));
      expect(l.uriString, isNot(contains('+')));
      expect(l.uri.queryParameters['pn'], "Anna's Café & Sons");
      // The '&' inside the name did not split the query.
      expect(
        l.uri.queryParameters.keys,
        containsAll(['pa', 'pn', 'am', 'cu', 'tn', 'tr']),
      );
    });

    test('every attempt has its own reference', () {
      expect(
        link(paymentId: 'PAY000001').uri.queryParameters['tr'],
        'PAY000001',
      );
      expect(
        link(paymentId: 'PAY000002').uri.queryParameters['tr'],
        'PAY000002',
      );
    });

    test('can be rebuilt from the payment alone', () {
      expect(link().uriString, link().uriString);
    });
  });

  group('payment records', () {
    test('a pending UPI payment says what it waits for', () {
      expect(_payment().isUpiDirect, isTrue);
      expect(_payment().statusLabel, 'Payment started');
      expect(
        _payment(claimedAt: DateTime.utc(2026)).statusLabel,
        'Pending verification',
      );
      expect(
        _payment(status: PaymentStatus.succeeded).statusLabel,
        'Successful',
      );
      expect(_payment(status: PaymentStatus.failed).statusLabel, 'Failed');
      expect(
        _payment(status: PaymentStatus.cancelled).statusLabel,
        'Cancelled',
      );
      // Other pending payments keep the generic wording.
      expect(_payment(provider: 'Simulator').statusLabel, 'Pending');
    });

    test('the claim time survives JSON', () {
      final claimed = _payment(claimedAt: DateTime.utc(2026, 10, 25, 7, 5));
      final copy = PaymentTransaction.fromJson(
        jsonDecode(jsonEncode(claimed.toJson())) as Map<String, dynamic>,
      );
      expect(copy.isClaimed, isTrue);
      expect(copy.claimedAt, DateTime.utc(2026, 10, 25, 7, 5));
      expect(_payment().toJson().containsKey('claimed'), isFalse);
      expect(copy.copyWith(status: PaymentStatus.succeeded).isClaimed, isTrue);
    });

    test('a claimed payment does not pay the bill', () {
      final bill = _invoice(
        payments: [_payment(claimedAt: DateTime.utc(2026))],
      );
      expect(bill.status, InvoiceStatus.pending);
      expect(bill.status.label, 'Pending verification');
      expect(bill.amountPaid, Money.zero);
      expect(bill.outstanding, const Money(45000));
      expect(bill.payableNow, Money.zero);
    });

    test('a confirmed payment pays it, a rejected one reopens it', () {
      final paid = _invoice(
        payments: [_payment(status: PaymentStatus.succeeded)],
      );
      expect(paid.status, InvoiceStatus.paid);
      expect(paid.outstanding, Money.zero);

      final rejected = _invoice(
        payments: [_payment(status: PaymentStatus.failed)],
      );
      expect(rejected.status, InvoiceStatus.failed);
      expect(rejected.payableNow, const Money(45000));

      final cancelled = _invoice(
        payments: [_payment(status: PaymentStatus.cancelled)],
      );
      expect(cancelled.status, InvoiceStatus.unpaid);
      expect(cancelled.payableNow, const Money(45000));
    });

    test('a part payment leaves the rest to pay', () {
      final bill = _invoice(
        payments: [
          _payment(
            id: 'PAY000001',
            amount: const Money(20000),
            status: PaymentStatus.succeeded,
          ),
          _payment(id: 'PAY000002', amount: const Money(10000)),
        ],
      );
      expect(bill.amountPaid, const Money(20000));
      expect(bill.outstanding, const Money(25000));
      expect(bill.payableNow, const Money(15000));
    });
  });

  group('BillingController (UPI to the restaurant)', () {
    late FakeUpiBackend server;
    late BillingController billing;

    BillingController create(FakeUpiBackend backend, {StaffRole? role}) =>
        BillingController(
          LocalBillingRepository(MemoryStore()),
          const UnavailablePaymentGateway(),
          guard: role == null ? const GuestAccess() : FakeGuard(role),
          backend: backend,
          settings: () => const RestaurantSettings(),
        );

    Future<void> open() async {
      final order = await placeTestOrder(await testOrders(MemoryStore()), {
        'chicken_65': 1,
      });
      await billing.createForOrder(order);
    }

    setUp(() async {
      server = FakeUpiBackend(_invoice());
      billing = create(server);
      await open();
    });

    test('UPI is offered only after the server reports it set up', () async {
      expect(billing.upiDirectAvailable, isFalse);
      expect(billing.guestMethods, isEmpty);
      expect(billing.onlinePaymentsAvailable, isFalse);

      await billing.loadUpiSettings();
      expect(billing.upiDirectAvailable, isTrue);
      expect(billing.guestMethods, [PaymentMethodType.upi]);
      expect(billing.isDirectUpi(PaymentMethodType.upi), isTrue);
      expect(billing.isDirectUpi(PaymentMethodType.card), isFalse);
      expect(billing.onlinePaymentsAvailable, isTrue);

      server.settings = _settings.copyWith(enabled: false);
      await billing.loadUpiSettings();
      expect(billing.upiDirectAvailable, isFalse);
      expect(billing.guestMethods, isEmpty);
    });

    test('a failed read keeps what was known', () async {
      await billing.loadUpiSettings();
      expect(billing.upiDirectAvailable, isTrue);

      // The server cannot be reached later: UPI stays offered as before.
      server.failSettings = true;
      await billing.loadUpiSettings();
      expect(billing.upiDirectAvailable, isTrue);

      // If it was never read, UPI is simply not offered.
      final fresh = create(server);
      await fresh.loadUpiSettings();
      expect(fresh.upiDirectAvailable, isFalse);
    });

    test('without a server there is no direct UPI at all', () async {
      final local = BillingController(
        LocalBillingRepository(MemoryStore()),
        const UnavailablePaymentGateway(),
      );
      await local.loadUpiSettings();
      expect(local.upiDirectAvailable, isFalse);
      expect(local.guestMethods, isEmpty);
      await expectLater(
        local.claimUpiPayment('PAY000001'),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            contains('need the restaurant server'),
          ),
        ),
      );
    });

    test('UPI cannot start when the restaurant has not set it up', () async {
      // Never read from the server (or switched off): nothing is sent.
      await expectLater(
        billing.startUpiPayment(
          invoiceId: 'INV00001',
          amount: const Money(45000),
        ),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            contains('Please pay at the counter'),
          ),
        ),
      );
      expect(server.calls.where((c) => c.startsWith('start')), isEmpty);
    });

    test(
      'starting a payment reserves the amount without paying the bill',
      () async {
        await billing.loadUpiSettings();
        final payment = await billing.startUpiPayment(
          invoiceId: 'INV00001',
          amount: const Money(45000),
        );
        expect(payment.status, PaymentStatus.pending);
        expect(payment.isUpiDirect, isTrue);
        final bill = billing.byId('INV00001')!;
        expect(bill.status, InvoiceStatus.pending);
        expect(bill.amountPaid, Money.zero);
        expect(bill.payableNow, Money.zero);
        expect(server.calls.where((c) => c.startsWith('start')), [
          'start:45000',
        ]);
      },
    );

    test('amounts that cannot be paid never reach the server', () async {
      await billing.loadUpiSettings();
      for (final paise in [0, -1, 45001]) {
        await expectLater(
          billing.startUpiPayment(invoiceId: 'INV00001', amount: Money(paise)),
          throwsA(isA<PaymentException>()),
          reason: '$paise',
        );
      }
      expect(server.calls.where((c) => c.startsWith('start')), isEmpty);
    });

    test('a part payment is for exactly what is chosen', () async {
      await billing.loadUpiSettings();
      final payment = await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(15000),
      );
      expect(payment.amount, const Money(15000));
      expect(billing.byId('INV00001')!.payableNow, const Money(30000));
    });

    test('a second tap while one is starting sends nothing more', () async {
      await billing.loadUpiSettings();
      server.holdStart = Completer<void>();
      final first = billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      await expectLater(
        billing.startUpiPayment(
          invoiceId: 'INV00001',
          amount: const Money(45000),
        ),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            'A payment for this bill is in progress.',
          ),
        ),
      );
      expect(billing.isProcessing('INV00001'), isTrue);
      server.holdStart!.complete();
      await first;
      expect(billing.isProcessing('INV00001'), isFalse);
      expect(server.calls.where((c) => c.startsWith('start')), hasLength(1));
    });

    test('no second payment starts while one is waiting', () async {
      await billing.loadUpiSettings();
      await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      await expectLater(
        billing.startUpiPayment(
          invoiceId: 'INV00001',
          amount: const Money(100),
        ),
        throwsA(isA<PaymentException>()),
      );
      expect(server.calls.where((c) => c.startsWith('start')), hasLength(1));
    });

    test(
      'the provider UPI route is closed once UPI goes to the restaurant',
      () async {
        await billing.loadUpiSettings();
        await expectLater(
          billing.payOnline(
            invoiceId: 'INV00001',
            amount: const Money(45000),
            method: PaymentMethodType.upi,
          ),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test('claiming flags the payment but the bill stays unpaid', () async {
      await billing.loadUpiSettings();
      final started = await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      final claimed = await billing.claimUpiPayment(
        started.id,
        reference: ' 412345678901 ',
      );
      expect(claimed.isClaimed, isTrue);
      expect(claimed.status, PaymentStatus.pending);
      expect(server.calls, contains('claim:PAY000001:412345678901'));
      final bill = billing.byId('INV00001')!;
      expect(bill.amountPaid, Money.zero);
      expect(bill.status, InvoiceStatus.pending);
      expect(bill.outstanding, const Money(45000));
    });

    test('a guest can cancel and then start again', () async {
      await billing.loadUpiSettings();
      final started = await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      final cancelled = await billing.cancelUpiPayment(started.id);
      expect(cancelled.status, PaymentStatus.cancelled);
      expect(billing.byId('INV00001')!.payableNow, const Money(45000));
      await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      expect(server.calls.where((c) => c.startsWith('start')), hasLength(2));
    });

    test('only cashiers, managers and owners can confirm or reject', () async {
      await billing.loadUpiSettings();
      final started = await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      // Guests have no staff role at all.
      await expectLater(
        () => billing.verifyUpiPayment(started.id, reference: '412345678901'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        () => billing.rejectUpiPayment(started.id),
        throwsA(isA<PermissionDeniedException>()),
      );
      for (final role in [
        StaffRole.kitchen,
        StaffRole.waiter,
        StaffRole.accountant,
      ]) {
        final staff = create(server, role: role);
        await expectLater(
          () => staff.verifyUpiPayment(started.id, reference: '412345678901'),
          throwsA(isA<PermissionDeniedException>()),
          reason: '$role',
        );
      }
      expect(server.calls.where((c) => c.startsWith('verify')), isEmpty);
    });

    test(
      'a cashier confirms with the bank reference and the bill is paid',
      () async {
        await billing.loadUpiSettings();
        final started = await billing.startUpiPayment(
          invoiceId: 'INV00001',
          amount: const Money(45000),
        );
        final cashier = create(server, role: StaffRole.cashier);
        await expectLater(
          () => cashier.verifyUpiPayment(started.id, reference: '  '),
          throwsA(isA<PaymentException>()),
        );
        expect(server.calls.where((c) => c.startsWith('verify')), isEmpty);

        await cashier.createForOrder(
          await placeTestOrder(await testOrders(MemoryStore()), {
            'chicken_65': 1,
          }),
        );
        final done = await cashier.verifyUpiPayment(
          started.id,
          reference: ' 412345678901 ',
        );
        expect(done.status, PaymentStatus.succeeded);
        expect(done.reference, '412345678901');
        final bill = cashier.byId('INV00001')!;
        expect(bill.status, InvoiceStatus.paid);
        expect(bill.outstanding, Money.zero);
      },
    );

    test('a cashier can reject and the balance opens again', () async {
      await billing.loadUpiSettings();
      final started = await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      final cashier = create(server, role: StaffRole.cashier);
      await cashier.createForOrder(
        await placeTestOrder(await testOrders(MemoryStore()), {
          'chicken_65': 1,
        }),
      );
      final rejected = await cashier.rejectUpiPayment(
        started.id,
        reason: ' Not in the statement ',
      );
      expect(rejected.status, PaymentStatus.failed);
      expect(server.calls, contains('reject:PAY000001:Not in the statement'));
      final bill = cashier.byId('INV00001')!;
      expect(bill.status, InvoiceStatus.failed);
      expect(bill.payableNow, const Money(45000));
    });

    test('checking a pending payment asks the server, not the app', () async {
      await billing.loadUpiSettings();
      final started = await billing.startUpiPayment(
        invoiceId: 'INV00001',
        amount: const Money(45000),
      );
      await billing.checkPending('INV00001');
      expect(server.calls, contains('refresh:${started.id}'));
      expect(billing.byId('INV00001')!.status, InvoiceStatus.pending);
    });
  });

  group('HTTP: UPI to the restaurant', () {
    Map<String, dynamic> paymentJson(
      String status, {
      String? claimed,
      String ref = '',
    }) => {
      'id': 'PAY000001',
      'invoice': 'INV00001',
      'order': 'OD12345',
      'amount': 45000,
      'method': 'upi',
      'status': status,
      'provider': 'UPI direct',
      'createdAt': '2026-10-25T07:00:00Z',
      'updatedAt': '2026-10-25T07:00:00Z',
      'key': 'k',
      'ref': ref,
      'claimed': ?claimed,
    };

    Map<String, dynamic> invoiceJson(String status) => {
      'id': 'INV00001',
      'number': 'DQ-2026-00012',
      'order': 'OD12345',
      'table': 5,
      'createdAt': '2026-10-25T07:00:00Z',
      'lines': <Object>[],
      'amounts': {'subtotal': 45000, 'tax': 0, 'total': 45000, 'taxRate': 0},
      'payments': [paymentJson(status)],
    };

    HttpBillingBackend backend(
      Future<http.Response> Function(http.Request request) handler,
    ) => HttpBillingBackend(ApiClient(_config, client: MockClient(handler)));

    test('the payee is read from the guest endpoint', () async {
      late http.Request seen;
      final upi = await backend((request) async {
        seen = request;
        return _json({
          'enabled': true,
          'upiId': 'cafe@okhdfcbank',
          'payeeName': 'Test Cafe',
          'qrImage': '',
          'verificationMode': 'manual',
        });
      }).upiSettings();
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/payments/upi');
      expect(upi.isReady, isTrue);
      expect(upi.upiId, 'cafe@okhdfcbank');
    });

    test(
      'starting sends the invoice, exact paise and an idempotency key',
      () async {
        late Map<String, dynamic> sent;
        final (payment, invoice) =
            await backend((request) async {
              expect(request.url.path, '/api/v1/payments/upi');
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return _json({
                'payment': paymentJson('pending'),
                'invoice': invoiceJson('pending'),
              });
            }).startUpiPayment(
              invoiceId: 'INV00001',
              amount: const Money(45000),
              idempotencyKey: 'attempt-1234',
            );
        expect(sent, {
          'invoiceId': 'INV00001',
          'amount': 45000,
          'idempotencyKey': 'attempt-1234',
        });
        expect(payment.status, PaymentStatus.pending);
        expect(invoice.amountPaid, Money.zero);
      },
    );

    test('claim, cancel, verify and reject use their own endpoints', () async {
      final seen = <String>[];
      final b = backend((request) async {
        seen.add(
          '${request.method} ${request.url.path}'
          '${request.body.isEmpty ? '' : ' ${request.body}'}',
        );
        return _json({
          'payment': paymentJson('pending', claimed: '2026-10-25T07:05:00Z'),
          'invoice': invoiceJson('pending'),
        });
      });
      final (claimed, _) = await b.claimUpiPayment(
        'PAY000001',
        reference: '412345678901',
      );
      await b.claimUpiPayment('PAY000001');
      await b.cancelUpiPayment('PAY000001');
      await b.verifyUpiPayment('PAY000001', reference: '412345678901');
      await b.rejectUpiPayment('PAY000001', reason: 'Not received');
      await b.rejectUpiPayment('PAY000001');
      expect(claimed.isClaimed, isTrue);
      expect(seen, [
        'POST /api/v1/payments/PAY000001/upi/claim {"reference":"412345678901"}',
        'POST /api/v1/payments/PAY000001/upi/claim {}',
        'POST /api/v1/payments/PAY000001/cancel',
        'POST /api/v1/admin/payments/PAY000001/verify {"reference":"412345678901"}',
        'POST /api/v1/admin/payments/PAY000001/reject {"reason":"Not received"}',
        'POST /api/v1/admin/payments/PAY000001/reject {}',
      ]);
    });

    test('server refusals keep their wording', () async {
      final b = backend(
        (_) async => _json({
          'status': 409,
          'title':
              'That UPI transaction ID is already recorded on another payment.',
          'code': 'duplicateReference',
        }, 409),
      );
      await expectLater(
        b.verifyUpiPayment('PAY000001', reference: '412345678901'),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            'That UPI transaction ID is already recorded on another payment.',
          ),
        ),
      );
    });

    test('a lost session is reported as such', () async {
      final b = backend((_) async => _json(null, 401));
      await expectLater(
        b.cancelUpiPayment('PAY000001'),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('HTTP: payment settings', () {
    HttpPaymentSettingsRepository repository(
      Future<http.Response> Function(http.Request request) handler,
    ) => HttpPaymentSettingsRepository(
      ApiClient(_config, client: MockClient(handler)),
    );

    final saved = {
      'enabled': true,
      'upiId': 'cafe@okhdfcbank',
      'payeeName': 'Test Cafe',
      'qrImage': 'https://x.test/uploads/upi/a.png',
      'verificationMode': 'manual',
      'automaticVerificationAvailable': false,
      'ready': true,
    };

    test('reads and saves the settings', () async {
      final seen = <String>[];
      final repo = repository((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.method == 'PUT') {
          expect(jsonDecode(request.body), {
            'enabled': true,
            'upiId': 'cafe@okhdfcbank',
            'payeeName': 'Test Cafe',
            'qrImage': '',
            'verificationMode': 'manual',
          });
        }
        return _json(saved);
      });
      final read = await repo.fetch();
      expect(read.upi.isReady, isTrue);
      expect(read.upi.qrImageUrl, 'https://x.test/uploads/upi/a.png');
      expect(read.automaticVerificationAvailable, isFalse);
      await repo.save(_settings);
      expect(seen, [
        'GET /api/v1/admin/payments/settings',
        'PUT /api/v1/admin/payments/settings',
      ]);
    });

    test('server validation messages reach the form', () async {
      final repo = repository(
        (_) async => _json({
          'status': 400,
          'title': 'Enter a valid UPI ID, like name@bank.',
          'code': 'validation',
        }, 400),
      );
      await expectLater(
        repo.save(_settings),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Enter a valid UPI ID, like name@bank.',
          ),
        ),
      );
    });

    test('an older server and an unmigrated database are explained', () async {
      // The route does not exist: the server runs an older API.
      await expectLater(
        repository(
          (_) async => _json({'status': 404, 'title': 'Not Found'}, 404),
        ).fetch(),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            HttpPaymentSettingsRepository.serverTooOld,
          ),
        ),
      );
      // The route exists but fails (e.g. the migration was not applied).
      await expectLater(
        repository((_) async => _json(null, 500)).fetch(),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            HttpPaymentSettingsRepository.serverNotMigrated,
          ),
        ),
      );
    });

    test('uploads the QR picture as a file and returns its address', () async {
      late http.BaseRequest seen;
      final repo = HttpPaymentSettingsRepository(
        ApiClient(
          _config,
          client: _StreamClient((request) async {
            seen = request;
            return _json({'url': 'https://x.test/uploads/upi/a.png'});
          }),
        ),
      );
      final url = await repo.uploadUpiQr(bytes: [1, 2, 3], filename: 'qr.png');
      expect(url, 'https://x.test/uploads/upi/a.png');
      expect(seen.url.path, '/api/v1/admin/uploads/upi-qr');
      expect(seen.method, 'POST');
    });
  });

  group('PaymentSettingsController', () {
    late FakePaymentSettingsRepository repository;

    PaymentSettingsController controller(StaffRole? role) =>
        PaymentSettingsController(
          repository,
          role == null ? const GuestAccess() : FakeGuard(role),
        );

    setUp(() => repository = FakePaymentSettingsRepository());

    test('loads what the server holds', () async {
      repository.stored = _settings.copyWith(
        qrImageUrl: 'https://x.test/a.png',
      );
      final c = controller(StaffRole.owner);
      expect(c.isLoaded, isFalse);
      await c.load();
      expect(c.isLoaded, isTrue);
      expect(c.upi.upiId, 'cafe@okhdfcbank');
      expect(c.upi.hasQrImage, isTrue);
      expect(c.automaticVerificationAvailable, isFalse);
    });

    test(
      'saves trimmed, lower-cased details and shows the server version',
      () async {
        final c = controller(StaffRole.owner);
        await c.load();
        await c.save(
          _settings.copyWith(
            upiId: '  Cafe@OkHDFCBank ',
            payeeName: ' Spice Route ',
          ),
        );
        expect(repository.saves.single.upiId, 'cafe@okhdfcbank');
        expect(repository.saves.single.payeeName, 'Spice Route');
        expect(c.upi.upiId, 'cafe@okhdfcbank');
      },
    );

    test('invalid details are refused before any request', () async {
      final c = controller(StaffRole.owner);
      await expectLater(
        c.save(_settings.copyWith(upiId: 'broken')),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        c.save(_settings.copyWith(payeeName: '')),
        throwsA(isA<ValidationException>()),
      );
      expect(repository.saves, isEmpty);
    });

    test(
      'automatic verification is refused without a connected provider',
      () async {
        final c = controller(StaffRole.owner);
        await c.load();
        await expectLater(
          c.save(
            _settings.copyWith(verificationMode: UpiVerificationMode.automatic),
          ),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              PaymentSettingsController.automaticUnavailableMessage,
            ),
          ),
        );
        expect(repository.saves, isEmpty);

        repository.automaticAvailable = true;
        await c.load();
        expect(c.automaticVerificationAvailable, isTrue);
        await c.save(
          _settings.copyWith(verificationMode: UpiVerificationMode.automatic),
        );
        expect(c.upi.verificationMode, UpiVerificationMode.automatic);
      },
    );

    test('only the owner may save', () async {
      for (final role in [
        null,
        StaffRole.manager,
        StaffRole.cashier,
        StaffRole.accountant,
      ]) {
        await expectLater(
          controller(role).save(_settings),
          throwsA(isA<PermissionDeniedException>()),
          reason: '$role',
        );
        await expectLater(
          controller(role).uploadQr([0xFF, 0xD8, 0xFF, 0xE0]),
          throwsA(isA<PermissionDeniedException>()),
          reason: '$role',
        );
      }
      expect(repository.saves, isEmpty);
      expect(repository.uploads, isEmpty);
    });

    test('a QR picture is checked before it is uploaded', () async {
      final c = controller(StaffRole.owner);
      const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
      expect(c.canUploadQr, isTrue);
      expect(await c.uploadQr(png), 'https://x.test/uploads/upi/new.png');
      expect(repository.uploads.single, endsWith('.png'));

      for (final bad in [
        <int>[],
        [0x47, 0x49, 0x46, 0x38, 1, 2],
        [0x25, 0x50, 0x44, 0x46, 1, 2],
        List<int>.filled(DishImageUploader.maxBytes + 1, 0xFF),
      ]) {
        await expectLater(c.uploadQr(bad), throwsA(isA<ValidationException>()));
      }
      expect(repository.uploads, hasLength(1));
    });

    test('the offline demo has no payment settings', () async {
      const unavailable = UnavailablePaymentSettingsRepository();
      final c = PaymentSettingsController(
        unavailable,
        FakeGuard(StaffRole.owner),
      );
      expect(c.isAvailable, isFalse);
      expect(c.canUploadQr, isFalse);
      await c.load();
      expect(c.upi.isReady, isFalse);
      await expectLater(c.save(_settings), throwsA(isA<StateError>()));
      await expectLater(c.uploadQr([1]), throwsA(isA<ValidationException>()));
    });
  });
}

/// Answers multipart (streamed) requests too, which [MockClient] only does
/// through its stream constructor.
class _StreamClient extends http.BaseClient {
  _StreamClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
