import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _config = ApiConfig(baseUrl: Uri.parse('http://api.test'));

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

MenuItem _dish(String id) => demoMenuItems.firstWhere((item) => item.id == id);

/// The shared services on local (demo) data, as the offline demo runs them.
Future<DineQrServices> _localServices(MemoryStore store) =>
    DineQrServices.create(
      store: store,
      menuLatency: Duration.zero,
      orderLatency: Duration.zero,
      seedDemoData: false,
    );

Future<void> _saveLocalSettings(MemoryStore store, RestaurantSettings value) =>
    store.write(StorageKeys.settings, jsonEncode(value.toJson()));

Map<String, dynamic> _orderJson({int table = 0}) => {
  'id': 'OD12345',
  'table': table,
  'type': table == 0 ? 'takeaway' : 'dineIn',
  'createdAt': '2026-10-22T10:00:00Z',
  'lines': <Object>[],
  'subtotal': 35000,
  'tax': 1750,
  'total': 36750,
  'taxRate': 500,
  'status': 'placed',
  'statusTimes': {'placed': '2026-10-22T10:00:00Z'},
  'readyAt': '2026-10-22T10:20:00Z',
};

OrderDraft _draft({required int table}) => OrderDraft(
  tableNumber: table,
  lines: const [],
  bill: const BillBreakdown(
    subtotal: Money(35000),
    tax: Money(1750),
    total: Money(36750),
    taxRateBasisPoints: 500,
  ),
  specialInstructions: '',
  estimatedPrepMinutes: 20,
  request: const OrderRequest(
    lines: [
      {'itemId': 'chicken_65', 'quantity': 1},
    ],
    idempotencyKey: 'key-123456789',
  ),
);

void main() {
  group('takeaway checkout', () {
    test('places a takeaway order while the restaurant takes them', () async {
      final services = await _localServices(MemoryStore());
      expect(services.settings.settings.takeawayOrdersEnabled, isTrue);
      expect(services.settings.isOrderable(OrderTables.takeaway), isTrue);
      final cart = CartController(MemoryStore())
        ..add(_dish('chicken_65'), quantity: 2);
      final shown = cart.bill.total;

      final order = await services.orders.placeOrder(
        cart: cart,
        tableNumber: OrderTables.takeaway,
      );

      expect(order.isTakeaway, isTrue);
      expect(order.type, OrderType.takeaway);
      expect(order.tableLabel, 'Takeaway');
      expect(order.bill.total, shown);
      expect(cart.isEmpty, isTrue, reason: 'cleared once the order exists');
      final bill = services.billing.forOrder(order.id)!;
      expect(bill.isTakeaway, isTrue);
      expect(bill.tableLabel, 'Takeaway');
      expect(bill.total, shown);
    });

    test(
      'is refused with the takeaway reason while takeaway is closed',
      () async {
        final store = MemoryStore();
        await _saveLocalSettings(
          store,
          LocalSettingsRepository.defaults.copyWith(
            takeawayOrdersEnabled: false,
          ),
        );
        final services = await _localServices(store);
        final cart = CartController(MemoryStore())..add(_dish('samosa'));

        await expectLater(
          services.orders.placeOrder(
            cart: cart,
            tableNumber: OrderTables.takeaway,
          ),
          throwsA(
            isA<CheckoutException>()
                .having(
                  (e) => e.error,
                  'error',
                  CheckoutError.takeawayUnavailable,
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('Takeaway orders'),
                ),
          ),
        );
        expect(cart.isEmpty, isFalse, reason: 'nothing is lost');
      },
    );

    test('dine-in still needs an active table', () async {
      final services = await _localServices(MemoryStore());
      final cart = CartController(MemoryStore())..add(_dish('samosa'));
      await expectLater(
        services.orders.placeOrder(cart: cart, tableNumber: 99),
        throwsA(
          isA<CheckoutException>().having(
            (e) => e.error,
            'error',
            CheckoutError.tableUnavailable,
          ),
        ),
      );
      final order = await services.orders.placeOrder(
        cart: cart,
        tableNumber: 5,
      );
      expect(order.isTakeaway, isFalse);
      expect(order.tableLabel, 'Table 05');
    });
  });

  group('takeaway setting', () {
    test('reads the old "parcel" key from servers before the rename', () {
      expect(
        RestaurantSettings.fromJson({'parcel': true}).takeawayOrdersEnabled,
        isTrue,
      );
      expect(
        RestaurantSettings.fromJson({
          'takeaway': false,
          'parcel': true,
        }).takeawayOrdersEnabled,
        isFalse,
        reason: 'the new key wins',
      );
      expect(
        const RestaurantSettings().takeawayOrdersEnabled,
        isFalse,
        reason: 'closed until an owner opens it',
      );
    });

    test('is written under both names, so no server switches it off', () {
      final json = const RestaurantSettings(
        takeawayOrdersEnabled: true,
      ).toJson();
      expect(json['takeaway'], isTrue);
      expect(json['parcel'], isTrue);
    });
  });

  group('takeaway over HTTP', () {
    test('guests send the type and no table: the session decides', () async {
      late Map<String, dynamic> sent;
      final repo = HttpOrderRepository(
        ApiClient(
          _config,
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            expect(request.url.path, '/api/v1/orders');
            return _json(_orderJson(), 201);
          }),
        ),
        staff: false,
      );
      final order = await repo.submitOrder(_draft(table: OrderTables.takeaway));
      expect(order.isTakeaway, isTrue);
      expect(sent['orderType'], 'takeaway');
      expect(sent.containsKey('tableNumber'), isFalse);
    });

    test('staff send the type and table 0, which every server reads', () async {
      final sent = <Map<String, dynamic>>[];
      final repo = HttpOrderRepository(
        ApiClient(
          _config,
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            sent.add(body);
            expect(request.url.path, '/api/v1/admin/orders');
            return _json(_orderJson(table: body['tableNumber'] as int), 201);
          }),
        ),
        staff: true,
      );
      await repo.submitOrder(_draft(table: OrderTables.takeaway));
      await repo.submitOrder(_draft(table: 5));
      expect(sent.first['orderType'], 'takeaway');
      expect(sent.first['tableNumber'], 0);
      expect(sent.last['orderType'], 'dineIn');
      expect(sent.last['tableNumber'], 5);
    });

    Future<CheckoutException> refusal(
      String code, {
      int status = 409,
      bool staff = false,
    }) async {
      final repo = HttpOrderRepository(
        ApiClient(
          _config,
          client: MockClient(
            (_) async => _json({
              'status': status,
              'title': 'Server says no',
              'code': code,
            }, status),
          ),
        ),
        staff: staff,
      );
      try {
        await repo.submitOrder(_draft(table: OrderTables.takeaway));
      } on CheckoutException catch (error) {
        return error;
      }
      fail('Expected a CheckoutException for $code');
    }

    test('server refusals keep their own reason and wording', () async {
      for (final code in ['takeawayUnavailable', 'parcelUnavailable']) {
        final error = await refusal(code);
        expect(error.error, CheckoutError.takeawayUnavailable, reason: code);
        expect(error.message, CheckoutError.takeawayUnavailable.message);
      }
      final mismatch = await refusal('orderTypeMismatch');
      expect(mismatch.error, CheckoutError.sessionExpired);
      // Anything else keeps the server's explanation.
      final other = await refusal('priceChanged');
      expect(other.error, CheckoutError.failed);
      expect(other.message, 'Server says no');
    });

    test('an expired guest session asks for a new scan', () async {
      final error = await refusal('unauthorized', status: 401);
      expect(error.error, CheckoutError.sessionExpired);
      expect(error.message, contains('Scan the QR code again'));
    });

    test('an expired staff session ends the sign-in instead', () async {
      final repo = HttpOrderRepository(
        ApiClient(_config, client: MockClient((_) async => _json(null, 401))),
        staff: true,
      );
      await expectLater(
        repo.submitOrder(_draft(table: OrderTables.takeaway)),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('start-up', () {
    test('creating the services with a server makes no request', () async {
      final calls = <String>[];
      final backend = DineQrBackend.guest(
        _config,
        MemoryStore(),
        client: MockClient((request) async {
          calls.add(request.url.path);
          return _json(null, 500);
        }),
      );
      final services = await DineQrServices.create(
        store: MemoryStore(),
        config: const AppConfig(demoMode: false),
        menuRepository: backend.menu,
        orderRepository: backend.orders,
        billingRepository: backend.billing,
        settingsRepository: backend.settings,
        paymentGateway: backend.payments,
        billingBackend: backend.billingBackend,
      );
      expect(calls, isEmpty);
      expect(services.orders.orders, isEmpty);
    });

    test(
      'staff screens use public data, without a 401, before sign-in',
      () async {
        final calls = <String>[];
        final backend = DineQrBackend.staff(
          _config,
          MemoryTokenStorage(),
          client: MockClient((request) async {
            calls.add(request.url.path);
            return switch (request.url.path) {
              '/api/v1/settings' => _json({'name': 'Spice Route'}),
              '/api/v1/tables' => _json([
                {'number': 1, 'active': true},
              ]),
              _ => _json(null, 401),
            };
          }),
        );
        expect(backend.auth!.hasSession, isFalse);
        final settings = await backend.settings.fetchSettings();
        final tables = await backend.settings.fetchTables();
        expect(settings.name, 'Spice Route');
        expect(tables.single.number, 1);
        expect(calls, ['/api/v1/settings', '/api/v1/tables']);
      },
    );

    test('the payment provider is read in the background', () async {
      var requests = 0;
      final backend = DineQrBackend.guest(
        _config,
        MemoryStore(),
        client: MockClient((request) async {
          requests++;
          return _json({
            'provider': 'Simulator',
            'available': true,
            'simulated': true,
          });
        }),
      );
      final billing = BillingController(
        LocalBillingRepository(MemoryStore()),
        backend.payments,
      );
      var notified = 0;
      billing.addListener(() => notified++);
      expect(backend.payments.isLoaded, isFalse);
      expect(billing.gateway.supportedMethods, isEmpty);

      await Future.wait([
        backend.loadPaymentConfig(),
        backend.loadPaymentConfig(),
      ]);
      expect(requests, 1, reason: 'concurrent reads share one request');
      expect(backend.payments.isLoaded, isTrue);
      expect(billing.isSimulated, isTrue);
      expect(billing.gateway.supportedMethods, isNotEmpty);
      expect(notified, 1, reason: 'payment screens rebuild');
    });

    test('a saved staff session survives an unreachable server', () async {
      final storage = MemoryTokenStorage();
      await storage.write('dineqr.staff.refresh', 'saved-refresh');
      final offline = HttpAuthService(
        _config,
        storage,
        plain: ApiClient(
          _config,
          client: MockClient((_) async => throw const SocketLikeError()),
        ),
      );
      await expectLater(
        offline.restore(),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
      expect(await storage.read('dineqr.staff.refresh'), 'saved-refresh');

      final refused = HttpAuthService(
        _config,
        storage,
        plain: ApiClient(
          _config,
          client: MockClient((_) async => _json({'code': 'sessionEnded'}, 401)),
        ),
      );
      expect(await refused.restore(), isNull);
      expect(await storage.read('dineqr.staff.refresh'), isNull);
    });

    test(
      'a server from before the rename gets the old takeaway code',
      () async {
        final sent = <String>[];
        final api = ApiClient(
          _config,
          client: MockClient((request) async {
            final payload =
                (jsonDecode(request.body) as Map<String, dynamic>)['qrPayload']
                    as String;
            sent.add(payload);
            // An API from before the rename knows only the old code.
            if (payload != 'DINEQR:PARCEL') {
              return _json({
                'status': 400,
                'title': 'This is not a DineQR code.',
                'code': 'unrecognized',
              }, 400);
            }
            return _json({
              'guestToken': 'guest-token',
              'tableNumber': 0,
              'expiresAt': DateTime.now()
                  .add(const Duration(hours: 4))
                  .toUtc()
                  .toIso8601String(),
            });
          }),
        );
        final session = GuestSession(api, MemoryStore());
        expect(
          await session.start(TableQrParser.takeawayPayload),
          OrderTables.takeaway,
        );
        expect(sent, ['DINEQR:TAKEAWAY', 'DINEQR:PARCEL']);

        // Any other refused code is reported as it is, with no second try.
        await expectLater(
          session.start('DINEQR:MENU:05'),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'unrecognized'),
          ),
        );
        expect(sent.last, 'DINEQR:MENU:05');
        expect(sent, hasLength(3));
      },
    );

    test('the admin warm-up request keeps nothing', () async {
      final calls = <String>[];
      final backend = DineQrBackend.staff(
        _config,
        MemoryTokenStorage(),
        client: MockClient((request) async {
          calls.add(request.url.path);
          return _json({'name': 'Public view'});
        }),
      );
      final settings = SettingsController(
        backend.settings,
        const GuestAccess(),
        null,
      );
      await backend.warmUp();
      expect(calls, ['/api/v1/settings']);
      expect(settings.settings.name, isNot('Public view'));
      // An unreachable server is not an error for anyone.
      final offline = DineQrBackend.staff(
        _config,
        MemoryTokenStorage(),
        client: MockClient((_) async => throw const SocketLikeError()),
      );
      await offline.warmUp();
    });
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
