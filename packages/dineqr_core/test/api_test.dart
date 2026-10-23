import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _config = ApiConfig(baseUrl: Uri.parse('http://api.test'));

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _problem(String code, String title) => {
  'status': 409,
  'title': title,
  'code': code,
};

void main() {
  group('ApiConfig', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('a debug build without DINEQR_API_URL uses the local API', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        ApiConfig.fromEnvironment()?.baseUrl,
        Uri.parse('http://10.0.2.2:5264'),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        ApiConfig.fromEnvironment()?.baseUrl,
        Uri.parse('http://localhost:5264'),
      );
    });

    /// The resolution of [value], as if it had been given to --dart-define.
    ({ApiConfig? config, ApiConfigIssue? issue}) resolve(
      String value, {
      bool debug = false,
    }) => ApiConfig.resolveUrl(value, debugFallback: debug);

    test('a release build without the define reports a missing address', () {
      final result = resolve('');
      expect(result.config, isNull);
      expect(result.issue?.title, 'No server address in this build');
      // The message has to name what to pass, or it is not actionable.
      expect(result.issue?.detail, contains('DINEQR_API_URL'));
      expect(result.issue?.detail, contains('10.0.2.2:5264'));
    });

    test('a valid absolute URL is accepted on every platform', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final result = resolve('http://192.168.31.145:5264');
        expect(result.issue, isNull, reason: '$platform');
        expect(result.config?.baseUrl.host, '192.168.31.145');
        expect(result.config?.baseUrl.port, 5264);
      }
    });

    test('an https production URL is accepted', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final result = resolve('https://api.dineqr.example');
      expect(result.issue, isNull);
      expect(result.config?.baseUrl.scheme, 'https');
    });

    test('an address that is not a full http(s) URL is refused', () {
      for (final bad in [
        'localhost:5264', // no scheme: parses, but has no host
        '192.168.31.145:5264',
        'ftp://192.168.31.145:5264',
        'not a url',
        '/api/v1',
      ]) {
        final result = resolve(bad);
        expect(result.config, isNull, reason: bad);
        expect(
          result.issue?.title,
          'The server address is not valid',
          reason: bad,
        );
        expect(result.issue?.detail, contains(bad), reason: bad);
      }
    });

    test('a loopback address is refused on Android, where it is the phone', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      for (final host in ['localhost', '127.0.0.1', '0.0.0.0']) {
        final result = resolve('http://$host:5264');
        expect(result.config, isNull, reason: host);
        expect(
          result.issue?.title,
          'The server address points at this device',
          reason: host,
        );
        expect(result.issue?.detail, contains('10.0.2.2:5264'), reason: host);
      }
    });

    test('loopback is still fine off Android (iOS simulator, desktop)', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = platform;
        final result = resolve('http://localhost:5264');
        expect(result.issue, isNull, reason: '$platform');
        expect(result.config?.baseUrl.host, 'localhost', reason: '$platform');
      }
    });

    test('10.0.2.2 is accepted on Android: it is the emulator host', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final result = resolve('http://10.0.2.2:5264');
      expect(result.issue, isNull);
      expect(result.config?.baseUrl.host, '10.0.2.2');
    });

    test('surrounding whitespace in the define is ignored', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final result = resolve('  http://10.0.2.2:5264  ');
      expect(result.issue, isNull);
      expect(result.config?.baseUrl, Uri.parse('http://10.0.2.2:5264'));
    });

    test('a resolved config builds API and hub URLs from the same host', () {
      final config = resolve('http://192.168.31.145:5264/').config!;
      expect(
        config.resolve('/menu').toString(),
        'http://192.168.31.145:5264/api/v1/menu',
      );
      expect(
        config.hubUrl.toString(),
        'http://192.168.31.145:5264/hubs/events',
      );
    });
  });

  group('ApiClient', () {
    test('problem responses keep the server code and message', () async {
      final api = ApiClient(
        _config,
        client: MockClient(
          (_) async =>
              _json(_problem('tableUnavailable', 'Table closed.'), 409),
        ),
      );
      await expectLater(
        api.post('/orders', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'tableUnavailable')
              .having((e) => e.message, 'message', 'Table closed.')
              .having((e) => e.status, 'status', 409),
        ),
      );
    });

    test('safe GETs are retried once; changes are sent once', () async {
      var gets = 0;
      var posts = 0;
      final api = ApiClient(
        _config,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return ++gets == 1 ? _json(null, 503) : _json({'ok': true});
          }
          posts++;
          return _json(null, 503);
        }),
      );
      expect(await api.get('/menu'), {'ok': true});
      expect(gets, 2);
      await expectLater(api.post('/orders', {}), throwsA(isA<ApiException>()));
      expect(posts, 1);
    });

    test('unreachable servers become a friendly offline error', () async {
      final api = ApiClient(
        _config,
        client: MockClient((_) => throw const SocketLikeException()),
      );
      await expectLater(
        api.post('/orders', {}),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
    });
  });

  group('staff sign-in', () {
    Map<String, dynamic> tokens(String access, String refresh) => {
      'accessToken': access,
      'accessTokenExpiresAt': DateTime.now()
          .add(const Duration(minutes: 15))
          .toUtc()
          .toIso8601String(),
      'refreshToken': refresh,
      'sessionExpiresAt': DateTime.now()
          .add(const Duration(hours: 8))
          .toUtc()
          .toIso8601String(),
      'staff': {
        'id': '7',
        'name': 'Asha',
        'email': 'asha@example.com',
        'role': 'cashier',
        'active': true,
        'createdAt': '2026-10-01T00:00:00Z',
        'permissions': <String>[],
      },
    };

    test('signs in, sends the token, renews it after a 401', () async {
      final seen = <String?>[];
      var refreshed = false;
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/api/v1/auth/login':
            return _json(tokens('access-1', 'refresh-1'));
          case '/api/v1/auth/refresh':
            refreshed = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['refreshToken'], 'refresh-1');
            return _json(tokens('access-2', 'refresh-2'));
          default:
            seen.add(request.headers['Authorization']);
            return request.headers['Authorization'] == 'Bearer access-1'
                ? _json(null, 401)
                : _json(<Object>[]);
        }
      });
      final storage = MemoryTokenStorage();
      final api = ApiClient(_config, client: client);
      final auth = HttpAuthService(
        _config,
        storage,
        plain: ApiClient(_config, client: client),
      )..attach(api);
      auth.keepSignedIn = true;

      final result = await auth.signIn('asha@example.com', 'Secret123');
      expect(result.staff.role, StaffRole.cashier);
      expect(result.staff.passwordHash, isEmpty);
      expect(await storage.read('dineqr.staff.refresh'), 'refresh-1');

      await api.get('/admin/orders');
      expect(refreshed, isTrue);
      expect(seen, ['Bearer access-1', 'Bearer access-2']);
      expect(await storage.read('dineqr.staff.refresh'), 'refresh-2');

      await auth.signOut();
      expect(await storage.read('dineqr.staff.refresh'), isNull);
    });

    test('server errors map to the sign-in messages', () async {
      final auth = HttpAuthService(
        _config,
        MemoryTokenStorage(),
        plain: ApiClient(
          _config,
          client: MockClient(
            (_) async => _json({
              'title': 'Incorrect email or password.',
              'code': 'invalidCredentials',
            }, 401),
          ),
        ),
      );
      await expectLater(
        auth.signIn('a@b.co', 'wrong'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.error,
            'error',
            AuthError.invalidCredentials,
          ),
        ),
      );
    });
  });

  group('orders', () {
    OrderDraft draft({String key = 'key-123456789'}) => OrderDraft(
      tableNumber: 5,
      lines: const [],
      bill: const BillBreakdown(
        subtotal: Money(35000),
        tax: Money(1750),
        total: Money(36750),
        taxRateBasisPoints: 500,
      ),
      specialInstructions: 'Less oil',
      estimatedPrepMinutes: 20,
      request: OrderRequest(
        lines: [
          {
            'itemId': 'chicken_65',
            'quantity': 1,
            'options': {
              'portion': 'full',
              'addOns': ['mint_mayo'],
            },
          },
        ],
        idempotencyKey: key,
        offerCode: 'WELCOME10',
      ),
    );

    test('orders are sent as dishes and options, never prices', () async {
      late Map<String, dynamic> sent;
      final repo = HttpOrderRepository(
        ApiClient(
          _config,
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({
              'id': 'OD12345',
              'table': 5,
              'createdAt': '2026-10-22T10:00:00Z',
              'lines': <Object>[],
              'subtotal': 35000,
              'tax': 1750,
              'total': 36750,
              'taxRate': 500,
              'status': 'placed',
              'statusTimes': {'placed': '2026-10-22T10:00:00Z'},
              'readyAt': '2026-10-22T10:20:00Z',
            }, 201);
          }),
        ),
        staff: false,
      );
      final order = await repo.submitOrder(draft());
      expect(order.id, 'OD12345');
      expect(sent['lines'], [
        {
          'itemId': 'chicken_65',
          'quantity': 1,
          'options': {
            'portion': 'full',
            'addOns': ['mint_mayo'],
          },
        },
      ]);
      expect(sent['idempotencyKey'], 'key-123456789');
      expect(sent['offerCode'], 'WELCOME10');
      expect(sent['expectedTotal'], 36750);
      expect(jsonEncode(sent), isNot(contains('unitPrice')));
      expect(sent.containsKey('tableNumber'), isFalse); // from the session
    });

    test('server refusals become checkout errors with its message', () async {
      final repo = HttpOrderRepository(
        ApiClient(
          _config,
          client: MockClient(
            (_) async => _json(
              _problem('priceChanged', 'Prices changed. Review your cart.'),
              409,
            ),
          ),
        ),
        staff: false,
      );
      await expectLater(
        repo.submitOrder(draft()),
        throwsA(
          isA<CheckoutException>()
              .having((e) => e.error, 'error', CheckoutError.failed)
              .having(
                (e) => e.message,
                'message',
                'Prices changed. Review your cart.',
              ),
        ),
      );
    });

    test('a retried checkout reuses its idempotency key', () async {
      final keys = <String>[];
      final repository = _FlakyOrders(keys);
      final orders = OrderController(repository);
      final cart = CartController(MemoryStore());
      cart.add(demoMenuItems.firstWhere((i) => i.id == 'samosa'));
      await expectLater(
        orders.placeOrder(cart: cart, tableNumber: 5),
        throwsA(isA<CheckoutException>()),
      );
      await orders.placeOrder(cart: cart, tableNumber: 5);
      expect(keys, hasLength(2));
      expect(keys.first, keys.last);
    });
  });

  test('roles that may not see a list get an empty one', () async {
    final repo = HttpStaffRepository(
      ApiClient(_config, client: MockClient((_) async => _json(null, 403))),
    );
    expect(await repo.fetchStaff(), isEmpty);
    expect(await repo.fetchAudit(), isEmpty);
  });

  test('online payments follow the server: intent, then verify', () async {
    final calls = <String>[];
    Map<String, dynamic> payment(String status) => {
      'id': 'PAY000001',
      'invoice': 'INV00001',
      'order': 'OD12345',
      'amount': 36750,
      'method': 'upi',
      'status': status,
      'provider': 'Simulator',
      'createdAt': '2026-10-22T10:00:00Z',
      'updatedAt': '2026-10-22T10:00:00Z',
      'key': 'k',
      'simulated': true,
    };
    final backend = HttpBillingBackend(
      ApiClient(
        _config,
        client: MockClient((request) async {
          calls.add(request.url.path);
          if (request.url.path.endsWith('/intents')) {
            return _json({'payment': payment('pending'), 'simulated': true});
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['simulatedOutcome'], 'failure');
          return _json({
            'payment': payment('failed'),
            'invoice': {
              'id': 'INV00001',
              'number': 'DQ-2026-00001',
              'order': 'OD12345',
              'table': 5,
              'createdAt': '2026-10-22T10:00:00Z',
              'lines': <Object>[],
              'amounts': {
                'subtotal': 35000,
                'tax': 1750,
                'total': 36750,
                'taxRate': 500,
              },
              'payments': [payment('failed')],
            },
          });
        }),
      ),
    );
    final (result, invoice) = await backend.payOnline(
      invoiceId: 'INV00001',
      amount: const Money(36750),
      method: PaymentMethodType.upi,
      idempotencyKey: 'pay-key-1234',
      outcome: SimulatedOutcome.failure,
    );
    expect(calls, [
      '/api/v1/payments/intents',
      '/api/v1/payments/PAY000001/confirm',
    ]);
    expect(result.status, PaymentStatus.failed);
    expect(invoice.amountPaid, Money.zero);
  });

  test('a guest session survives a restart until it expires', () async {
    final store = MemoryStore();
    final api = ApiClient(
      _config,
      client: MockClient(
        (_) async => _json({
          'guestToken': 'guest-token',
          'tableNumber': 5,
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 4))
              .toUtc()
              .toIso8601String(),
        }),
      ),
    );
    final session = GuestSession(api, store);
    expect(await session.start('DINEQR:TABLE:05'), 5);
    final restored = GuestSession(ApiClient(_config), store);
    expect(restored.table, 5);
    expect(await restored.token(), 'guest-token');
  });
}

/// Fails the first submission (as a timeout would), then succeeds,
/// recording the idempotency key of each attempt.
class _FlakyOrders extends LocalOrderRepository {
  _FlakyOrders(this.keys)
    : super(MemoryStore(), latency: Duration.zero, seedDemoOrders: false);

  final List<String> keys;

  @override
  Future<RestaurantOrder> submitOrder(OrderDraft draft) {
    keys.add(draft.request!.idempotencyKey);
    if (keys.length == 1) throw const ApiException.timeout();
    return super.submitOrder(draft);
  }
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
