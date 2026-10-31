import 'dart:async';
import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _config = ApiConfig(baseUrl: Uri.parse('http://api.test'));

/// The server's answers to the guest's network check, in turn.
class _FakeChecker implements NetworkAccessChecker {
  NetworkAccessResult answer = NetworkAccessResult.allowed;
  Object? error;
  int calls = 0;

  @override
  Future<NetworkAccessResult> check() async {
    calls++;
    if (error case final Object e) throw e;
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChecker server;
  late DineInWifi wifi;
  int? table;
  late StreamController<bool> network;
  late DineInAccessController access;

  setUp(() {
    server = _FakeChecker();
    wifi = const DineInWifi(enabled: true, ssid: 'DineQR Guest');
    table = 7;
    network = StreamController<bool>();
    access = DineInAccessController(
      checker: server,
      wifi: () => wifi,
      table: () => table,
      connectivity: network.stream,
      pollEvery: null,
      observeLifecycle: false,
    );
  });

  tearDown(() async {
    access.dispose();
    await network.close();
  });

  group('dine-in access', () {
    test(
      'is locked until the server confirms the restaurant network',
      () async {
        expect(access.isRequired, isTrue);
        expect(access.isLocked, isTrue);

        await access.verify();

        expect(access.state, DineInAccess.allowed);
        expect(access.isLocked, isFalse);
        expect(access.ssid, 'DineQR Guest');
      },
    );

    test('locks when the server sees another network, and reopens on '
        'the restaurant one', () async {
      await access.verify();

      // A request (say, placing an order) was refused.
      access.reportBlocked();
      expect(access.state, DineInAccess.blocked);
      expect(access.isLocked, isTrue);

      // Mobile data: still another network.
      server.answer = NetworkAccessResult.blocked;
      await access.verify();
      expect(access.isLocked, isTrue);

      // Back on the restaurant Wi-Fi.
      server.answer = NetworkAccessResult.allowed;
      await access.verify();
      expect(access.isLocked, isFalse);
    });

    test(
      'a lost connection locks at once; a new one is checked again',
      () async {
        await access.verify();
        final before = server.calls;

        network.add(false);
        await pumpEventQueue();
        expect(access.isOffline, isTrue);
        expect(access.isLocked, isTrue);

        // Connected again, but on mobile data: the server decides.
        server.answer = NetworkAccessResult.blocked;
        network.add(true);
        await pumpEventQueue();
        expect(server.calls, before + 1);
        expect(access.isOffline, isFalse);
        expect(access.isLocked, isTrue);
      },
    );

    test('an unreachable server proves nothing either way', () async {
      await access.verify();
      server.error = const ApiException.network();

      await access.verify();

      // Still the last known answer: not locked by a server outage alone.
      expect(access.state, DineInAccess.allowed);
      expect(access.isLocked, isFalse);
    });

    test('nothing is locked when the restriction does not apply', () async {
      // Off.
      wifi = const DineInWifi();
      expect(access.isRequired, isFalse);
      expect(access.isLocked, isFalse);

      // On, but this is takeaway and the restaurant left takeaway open.
      wifi = const DineInWifi(enabled: true);
      table = OrderTables.takeaway;
      access.contextChanged();
      expect(access.isLocked, isFalse);

      // No session yet.
      table = null;
      expect(access.isLocked, isFalse);
      expect(access.state, DineInAccess.open);
    });

    test("the server's answer wins over settings read earlier", () async {
      // The app still thinks it is off; the server refuses an order.
      wifi = const DineInWifi();
      access.reportBlocked();
      expect(access.isLocked, isTrue);

      // The app thinks it is on; the server says it no longer applies.
      wifi = const DineInWifi(enabled: true);
      server.answer = NetworkAccessResult.notRequired;
      await access.verify();
      expect(access.isRequired, isFalse);
      expect(access.isLocked, isFalse);
    });

    test('a session the server just issued counts as verified', () {
      access.sessionStarted();
      expect(access.isLocked, isFalse);
      expect(server.calls, 0);
    });

    test('a new table is checked from scratch', () async {
      await access.verify();
      table = 9;
      access.contextChanged();
      expect(access.isLocked, isTrue);
      await pumpEventQueue();
      expect(access.isLocked, isFalse);
    });
  });

  group('the guest network check over HTTP', () {
    Future<NetworkAccessResult> answer(http.Response response) =>
        HttpNetworkAccessChecker(
          ApiClient(_config, client: MockClient((_) async => response)),
        ).check();

    http.Response json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    test('maps the server answers', () async {
      expect(
        await answer(json({'required': true, 'allowed': true}, 200)),
        NetworkAccessResult.allowed,
      );
      expect(
        await answer(json({'required': false, 'allowed': true}, 200)),
        NetworkAccessResult.notRequired,
      );
      expect(
        await answer(
          json({
            'code': 'networkNotAllowed',
            'detail': DineInWifi.blockedMessage,
          }, 403),
        ),
        NetworkAccessResult.blocked,
      );
      // A server from before the restriction.
      expect(
        await answer(json({'code': 'notFound'}, 404)),
        NetworkAccessResult.notRequired,
      );
    });

    test('any call refused for the network is reported', () async {
      final seen = <String>[];
      final api = ApiClient(
        _config,
        client: MockClient(
          (_) async => json({'code': 'networkNotAllowed'}, 403),
        ),
      )..onServerError = (error) => seen.add(error.code);

      await expectLater(api.post('/orders', {}), throwsA(isA<ApiException>()));
      expect(seen, ['networkNotAllowed']);
    });

    test('settings carry the hint, never the addresses', () {
      final settings = RestaurantSettings.fromJson({
        'name': 'Cafe',
        'wifi': {'enabled': true, 'ssid': 'Cafe Guest', 'takeaway': false},
      });
      expect(settings.wifi.enabled, isTrue);
      expect(settings.wifi.ssid, 'Cafe Guest');
      expect(settings.wifi.appliesTo(5), isTrue);
      expect(settings.wifi.appliesTo(OrderTables.takeaway), isFalse);
      expect(
        RestaurantSettings.fromJson({'name': 'Old server'}).wifi.enabled,
        isFalse,
      );
    });
  });
}
