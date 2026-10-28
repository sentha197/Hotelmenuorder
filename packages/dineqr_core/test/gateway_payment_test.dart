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
  Money total = const Money(45000),
  List<PaymentTransaction> payments = const [],
}) => Invoice(
  id: 'INV00001',
  billNumber: 'DQ-2026-00012',
  orderId: 'OD12345',
  tableNumber: 5,
  createdAt: DateTime.utc(2026, 10, 28, 7),
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

/// The server's live gateway as the apps see it: Cashfree, UPI only.
ServerPaymentGateway _cashfree() => ServerPaymentGateway()
  ..update(
    providerName: 'Cashfree',
    available: true,
    isSimulated: false,
    methods: {PaymentMethodType.upi},
  );

void main() {
  group('BillingController (UPI through the gateway)', () {
    late FakeUpiBackend server;
    late BillingController billing;
    var mode = PaymentMode.live;

    BillingController create({PaymentGateway? gateway}) => BillingController(
      LocalBillingRepository(MemoryStore()),
      gateway ?? _cashfree(),
      guard: const GuestAccess(),
      backend: server,
      settings: () => RestaurantSettings(paymentMode: mode),
    );

    setUp(() async {
      mode = PaymentMode.live;
      server = FakeUpiBackend(_invoice());
      billing = create();
      await billing.createForOrder(
        await placeTestOrder(await testOrders(MemoryStore()), {
          'chicken_65': 1,
        }),
      );
    });

    test(
      'live mode offers UPI from an app or by QR, then the counter',
      () async {
        // Even with the restaurant's own UPI ID set up: the gateway needs no
        // one to confirm the money.
        await billing.loadUpiSettings();
        expect(billing.gatewayUpiAvailable, isTrue);
        expect(billing.upiDirectAvailable, isFalse);
        expect(billing.paymentOptions, [
          PaymentOption.upi,
          PaymentOption.scanAndPay,
          PaymentOption.cash,
          PaymentOption.payAtCounter,
        ]);
        expect(billing.isGatewayOption(PaymentOption.upi), isTrue);
        expect(billing.isGatewayOption(PaymentOption.scanAndPay), isTrue);
        expect(billing.isGatewayOption(PaymentOption.cash), isFalse);
        // Settled by the gateway's report, so not a part of a split.
        expect(billing.splitOptions, [
          PaymentOption.cash,
          PaymentOption.payAtCounter,
        ]);
        expect(billing.canSplit, isFalse);
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

    test('demo mode and a server without a gateway never use it', () async {
      mode = PaymentMode.demo;
      expect(billing.gatewayUpiAvailable, isFalse);
      mode = PaymentMode.live;
      final none = create(gateway: ServerPaymentGateway());
      expect(none.gatewayUpiAvailable, isFalse);
      expect(none.paymentOptions, [
        PaymentOption.cash,
        PaymentOption.payAtCounter,
      ]);
    });

    test(
      'starting holds the amount, and a retry is the same payment',
      () async {
        final payment = await billing.startGatewayUpi(
          invoiceId: 'INV00001',
          amount: const Money(45000),
          idempotencyKey: 'key-1',
          methodDetail: 'Google Pay',
        );
        expect(server.calls, ['gateway:45000:Google Pay']);
        expect(payment.isGateway, isTrue);
        expect(payment.status, PaymentStatus.pending);
        final bill = billing.byId('INV00001')!;
        expect(bill.status, InvoiceStatus.pending);
        expect(bill.amountPaid, Money.zero);
        expect(bill.payableNow, Money.zero);

        // The answer was lost; the same request again.
        final again = await billing.startGatewayUpi(
          invoiceId: 'INV00001',
          amount: const Money(45000),
          idempotencyKey: 'key-1',
        );
        expect(again.id, payment.id);
        expect(billing.byId('INV00001')!.payments, hasLength(1));
      },
    );

    test('a wrong amount is refused before anything is sent', () async {
      for (final amount in [const Money(90000), Money.zero]) {
        await expectLater(
          billing.startGatewayUpi(
            invoiceId: 'INV00001',
            amount: amount,
            idempotencyKey: 'key-${amount.paise}',
          ),
          throwsA(isA<PaymentException>()),
        );
      }
      expect(server.calls, isEmpty);
    });

    test('the bill is paid only when the gateway reports it', () async {
      final payment = await billing.startGatewayUpi(
        invoiceId: 'INV00001',
        amount: const Money(20000),
        idempotencyKey: 'key-1',
      );
      final apps = await billing.gatewayCheckout(payment.id);
      final qr = await billing.gatewayCheckout(payment.id, qr: true);
      expect(server.calls, [
        'gateway:20000:',
        'checkout:${payment.id}:apps',
        'checkout:${payment.id}:qr',
      ]);
      expect(apps.links['gpay'], startsWith('tez://upi/pay?'));
      expect(qr.qrPng, isNotNull);

      // Nothing yet: checking changes nothing.
      await billing.checkPending('INV00001');
      expect(billing.byId('INV00001')!.amountPaid, Money.zero);

      server.settleGateway(payment.id);
      await billing.checkPending('INV00001');
      final bill = billing.byId('INV00001')!;
      expect(bill.status, InvoiceStatus.partiallyPaid);
      expect(bill.amountPaid, const Money(20000));
      expect(bill.outstanding, const Money(25000));
      expect(bill.payments.single.reference, '412345678901');
    });

    test('cancelling ends the payment and frees the amount', () async {
      final payment = await billing.startGatewayUpi(
        invoiceId: 'INV00001',
        amount: const Money(45000),
        idempotencyKey: 'key-1',
      );
      final cancelled = await billing.cancelPayment(payment.id);
      expect(cancelled.status, PaymentStatus.cancelled);
      expect(billing.byId('INV00001')!.payableNow, const Money(45000));
    });
  });

  group('UpiApp and GatewayCheckout', () {
    test('each app opens the same payment with its own scheme', () {
      final link = Uri.parse(
        'upi://pay?pa=cafe@okhdfcbank&pn=Test%20Cafe&am=450.00&cu=INR',
      );
      expect(
        UpiApp.googlePay.linkFor(link).toString(),
        'tez://upi/pay?pa=cafe@okhdfcbank&pn=Test%20Cafe&am=450.00&cu=INR',
      );
      expect(
        UpiApp.phonePe.linkFor(link).toString(),
        startsWith('phonepe://pay?pa=cafe@okhdfcbank'),
      );
      expect(
        UpiApp.paytm.linkFor(link).toString(),
        startsWith('paytmmp://pay?'),
      );
      expect(UpiApp.other.linkFor(link), link);
      expect(UpiApp.named, isNot(contains(UpiApp.other)));
    });

    test('the gateway link for an app is used, else its plain link', () {
      final checkout = GatewayCheckout.fromJson({
        'links': {
          'default': 'upi://pay?pa=x@axis&am=1.00',
          'gpay': 'tez://upi/pay?pa=x@axis&am=1.00&sign=abc',
        },
        'qrImage': FakeUpiBackend.qrImage,
        'expiresAt': '2026-10-28T07:17:00Z',
      });
      expect(
        UpiApp.googlePay.linkIn(checkout).toString(),
        'tez://upi/pay?pa=x@axis&am=1.00&sign=abc',
      );
      expect(
        UpiApp.phonePe.linkIn(checkout).toString(),
        'phonepe://pay?pa=x@axis&am=1.00',
      );
      expect(checkout.qrPng, isNotNull);
      expect(checkout.expiresAt, DateTime.utc(2026, 10, 28, 7, 17));
      expect(const GatewayCheckout().qrPng, isNull);
      expect(
        const GatewayCheckout(qrImage: 'data:image/png;base64,%%').qrPng,
        isNull,
      );
      expect(UpiApp.googlePay.linkIn(const GatewayCheckout()), isNull);
    });
  });

  group('HTTP: UPI through the gateway', () {
    Map<String, dynamic> paymentJson(String status) => {
      'id': 'PAY000001',
      'invoice': 'INV00001',
      'order': 'OD12345',
      'amount': 45000,
      'method': 'upi',
      'status': status,
      'provider': 'Cashfree',
      'createdAt': '2026-10-28T07:00:00Z',
      'updatedAt': '2026-10-28T07:00:00Z',
      'key': 'key-1',
      'ref': '',
      'detail': 'Google Pay',
    };

    Map<String, dynamic> invoiceJson(String status) => {
      'id': 'INV00001',
      'number': 'DQ-2026-00012',
      'order': 'OD12345',
      'table': 5,
      'createdAt': '2026-10-28T07:00:00Z',
      'lines': <Object>[],
      'amounts': {'subtotal': 45000, 'tax': 0, 'total': 45000, 'taxRate': 0},
      'payments': [paymentJson(status)],
    };

    HttpBillingBackend backend(
      Future<http.Response> Function(http.Request request) handler,
    ) => HttpBillingBackend(ApiClient(_config, client: MockClient(handler)));

    test('starting sends a UPI intent with the exact paise and key', () async {
      late http.Request seen;
      final (payment, invoice) =
          await backend((request) async {
            seen = request;
            return _json({
              'payment': paymentJson('pending'),
              'provider': 'Cashfree',
              'simulated': false,
              'amount': 45000,
              'currency': 'INR',
              'mode': 'live',
              'invoice': invoiceJson('pending'),
            });
          }).startGatewayPayment(
            invoiceId: 'INV00001',
            amount: const Money(45000),
            idempotencyKey: 'key-1',
            methodDetail: 'Google Pay',
          );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/payments/intents');
      expect(jsonDecode(seen.body), {
        'invoiceId': 'INV00001',
        'amount': 45000,
        'method': 'upi',
        'idempotencyKey': 'key-1',
        'methodDetail': 'Google Pay',
      });
      expect(payment.isGateway, isTrue);
      expect(payment.methodLabel, 'UPI · Google Pay');
      expect(invoice.status, InvoiceStatus.pending);
    });

    test(
      'an older server without the bill in the answer is asked for it',
      () async {
        final paths = <String>[];
        final (
          _,
          invoice,
        ) = await backend((request) async {
          paths.add('${request.method} ${request.url.path}');
          return request.method == 'POST'
              ? _json({'payment': paymentJson('pending'), 'simulated': false})
              : _json({
                  'payment': paymentJson('pending'),
                  'invoice': invoiceJson('pending'),
                });
        }).startGatewayPayment(
          invoiceId: 'INV00001',
          amount: const Money(45000),
          idempotencyKey: 'key-1',
        );
        expect(paths, [
          'POST /api/v1/payments/intents',
          'GET /api/v1/payments/PAY000001',
        ]);
        expect(invoice.id, 'INV00001');
      },
    );

    test('the checkout asks for app links or the QR code', () async {
      final bodies = <Object?>[];
      final api = backend((request) async {
        expect(request.url.path, '/api/v1/payments/PAY000001/checkout');
        bodies.add(jsonDecode(request.body));
        return _json({
          'payment': paymentJson('pending'),
          'links': {
            'default': 'upi://pay?am=450.00',
            'gpay': 'tez://upi/pay?am=450.00',
          },
          'qrImage': '',
          'expiresAt': '2026-10-28T07:17:00Z',
        });
      });
      final apps = await api.gatewayCheckout('PAY000001');
      await api.gatewayCheckout('PAY000001', qr: true);
      expect(bodies, [
        {'channel': 'apps'},
        {'channel': 'qr'},
      ]);
      expect(apps.links['gpay'], 'tez://upi/pay?am=450.00');
    });

    test('a refused request reaches the guest as a message', () async {
      await expectLater(
        backend(
          (request) async => _json({
            // The server's problem details carry the message as the title.
            'code': 'gatewayUnavailable',
            'title':
                'The payment service did not respond. Please try again in a moment.',
          }, 503),
        ).gatewayCheckout('PAY000001'),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.message,
            'message',
            contains('did not respond'),
          ),
        ),
      );
    });

    test('the live gateway takes only the methods the server names', () {
      final gateway = _cashfree();
      expect(gateway.supportedMethods, {PaymentMethodType.upi});
      final older = ServerPaymentGateway()
        ..update(providerName: 'X', available: true, isSimulated: false);
      expect(older.supportedMethods, PaymentMethodType.online.toSet());
    });
  });
}
