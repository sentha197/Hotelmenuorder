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

GuestPosition _at(double metresNorth, {bool mocked = false}) => GuestPosition(
  latitude: 13.0827 + metresNorth / 111195,
  longitude: 80.2707,
  accuracy: 5,
  capturedAt: DateTime.now(),
  mocked: mocked,
);

/// The device: what it reports next.
class _Device implements LocationProvider {
  LocationReading next = LocationReading.position(_at(5));
  final opened = <LocationFailure>[];

  @override
  Future<LocationReading> current() async => next;

  @override
  Future<bool> openSettings(LocationFailure failure) async {
    opened.add(failure);
    return true;
  }
}

/// The server: measures like the API (inside 20 m), or says the area is off.
class _Server implements GuestLocationChecker {
  bool enabled = true;
  final seen = <GuestPosition?>[];

  @override
  Future<LocationCheckResult> check(GuestPosition? position) async {
    seen.add(position);
    if (!enabled) return LocationCheckResult.notRequired;
    if (position == null) {
      return const LocationCheckResult(
        required: true,
        allowed: false,
        code: 'locationRequired',
        message: 'Turn on location.',
      );
    }
    final metres = (position.latitude - 13.0827) * 111195;
    return metres <= 20
        ? LocationCheckResult(required: true, allowed: true, distance: metres)
        : const LocationCheckResult(
            required: true,
            allowed: false,
            code: DineInLocation.outsideCode,
            message: DineInLocation.outsideMessage,
          );
  }
}

void main() {
  group('LocationAccessController', () {
    late _Device device;
    late _Server server;
    var area = const DineInLocation(enabled: true, radius: 20);
    int? table = 5;

    LocationAccessController controller() => LocationAccessController(
      checker: server,
      provider: device,
      area: () => area,
      table: () => table,
      observeLifecycle: false,
    );

    setUp(() {
      device = _Device();
      server = _Server();
      area = const DineInLocation(enabled: true, radius: 20);
      table = 5;
    });

    test('inside the radius ordering is open; outside it is locked', () async {
      final access = controller();
      expect(access.isLocked, isTrue); // not checked yet
      await access.verify();
      expect(access.state, LocationAccess.allowed);
      expect(access.isLocked, isFalse);

      device.next = LocationReading.position(_at(80));
      await access.verify();
      expect(access.state, LocationAccess.outside);
      expect(access.isLocked, isTrue);
      expect(access.explanation, DineInLocation.outsideMessage);
      await expectLater(
        access.positionForOrder(),
        throwsA(isA<LocationRefusedException>()),
      );

      // Back inside (e.g. after resuming the app).
      device.next = LocationReading.position(_at(3));
      final position = await access.positionForOrder();
      expect(position, isNotNull);
      expect(access.isLocked, isFalse);
    });

    test(
      'a refused permission or GPS switched off keeps ordering locked',
      () async {
        final access = controller();
        device.next = const LocationReading.failed(
          LocationFailure.permissionDenied,
        );
        await access.verify();
        expect(access.state, LocationAccess.permissionDenied);
        expect(access.isLocked, isTrue);

        device.next = const LocationReading.failed(
          LocationFailure.permissionDeniedForever,
        );
        await access.verify();
        expect(access.state, LocationAccess.permissionDeniedForever);
        await access.openSettings();

        device.next = const LocationReading.failed(
          LocationFailure.serviceDisabled,
        );
        await access.verify();
        expect(access.state, LocationAccess.serviceDisabled);
        expect(access.isLocked, isTrue);
        await access.openSettings();
        expect(device.opened, [
          LocationFailure.permissionDeniedForever,
          LocationFailure.serviceDisabled,
        ]);
        expect(access.explanation, contains('Turn on location'));
      },
    );

    test(
      'nothing is asked while the area is off or there is no session',
      () async {
        area = DineInLocation.off;
        final access = controller();
        expect(access.isLocked, isFalse);
        expect(await access.positionForOrder(), isNull);
        expect(server.seen, isEmpty);

        area = const DineInLocation(enabled: true, radius: 20);
        table = null;
        expect(access.isLocked, isFalse);

        // Takeaway is covered only when the restaurant says so.
        table = OrderTables.takeaway;
        expect(access.isRequired, isFalse);
        area = const DineInLocation(enabled: true, radius: 20, takeaway: true);
        expect(access.isRequired, isTrue);
      },
    );

    test('the server switching the area off unlocks ordering', () async {
      final access = controller();
      device.next = LocationReading.position(_at(500));
      await access.verify();
      expect(access.isLocked, isTrue);
      server.enabled = false;
      await access.verify();
      expect(access.isLocked, isFalse);
      expect(access.state, LocationAccess.open);
    });

    test('a refused order locks it with the server\'s reason', () {
      final access = controller();
      access.reportRefused('mockLocation', 'Turn off mock location apps.');
      expect(access.isLocked, isTrue);
      expect(access.state, LocationAccess.unavailable);
      expect(access.explanation, 'Turn off mock location apps.');
    });
  });

  group('HttpGuestLocationChecker', () {
    test('turns refusals into results and sends the position', () async {
      Object? sent;
      final api = ApiClient(
        _config,
        client: MockClient((request) async {
          sent = jsonDecode(request.body);
          return _json({
            'status': 403,
            'title': DineInLocation.outsideMessage,
            'code': 'outsideRestaurantArea',
          }, 403);
        }),
      );
      final result = await HttpGuestLocationChecker(api).check(_at(90));
      expect(result.required, isTrue);
      expect(result.allowed, isFalse);
      expect(result.code, DineInLocation.outsideCode);
      expect(result.message, DineInLocation.outsideMessage);
      expect(sent, containsPair('accuracy', 5.0));
      expect(sent, containsPair('mocked', false));
      expect((sent! as Map)['capturedAt'], endsWith('Z'));
    });

    test(
      'reads an accepted position, and an older server asks nothing',
      () async {
        var status = 200;
        final api = ApiClient(
          _config,
          client: MockClient(
            (_) async => status == 200
                ? _json({
                    'required': true,
                    'allowed': true,
                    'radius': 20,
                    'distance': 4.5,
                  })
                : _json(null, 404),
          ),
        );
        final ok = await HttpGuestLocationChecker(api).check(_at(4));
        expect(ok.allowed, isTrue);
        expect(ok.distance, 4.5);
        status = 404;
        expect(
          (await HttpGuestLocationChecker(api).check(null)).required,
          isFalse,
        );
      },
    );
  });

  test('settings carry whether the area is on, never the coordinates', () {
    final settings = RestaurantSettings.fromJson({
      'name': 'Test',
      'location': {'enabled': true, 'radius': 30, 'takeaway': false},
    });
    expect(settings.location.enabled, isTrue);
    expect(settings.location.radius, 30);
    expect(settings.location.appliesTo(5), isTrue);
    expect(settings.location.appliesTo(OrderTables.takeaway), isFalse);
    expect(
      RestaurantSettings.fromJson({'name': 'Old server'}).location.enabled,
      isFalse,
    );
  });

  test('admin settings round-trip and validate points', () {
    final settings = GeofenceSettings.fromJson({
      'restaurantId': 1,
      'restaurantName': 'DineQR',
      'configured': true,
      'enabled': true,
      'latitude': 13.0827,
      'longitude': 80.2707,
      'radius': 30,
      'takeaway': true,
      'updatedBy': 'Owner',
    });
    expect(settings.toJson(), {
      'enabled': true,
      'latitude': 13.0827,
      'longitude': 80.2707,
      'radius': 30,
      'takeaway': true,
    });
    expect(GeofenceSettings.isValidPoint(13.08, 80.27), isTrue);
    expect(GeofenceSettings.isValidPoint(0, 0), isFalse);
    expect(GeofenceSettings.isValidPoint(91, 0), isFalse);
    expect(GeofenceSettings.isValidPoint(10, null), isFalse);
  });
}
