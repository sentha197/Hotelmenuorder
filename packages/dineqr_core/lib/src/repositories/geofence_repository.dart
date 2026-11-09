import 'dart:async';

import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import '../models/geofence.dart';

/// Why the device gave no position.
enum LocationFailure {
  /// The guest refused the permission (it can be asked again).
  permissionDenied,

  /// Refused for good: only the phone's settings can allow it now.
  permissionDeniedForever,

  /// Location (GPS) is switched off on the device.
  serviceDisabled,

  /// No fix in time, or the platform has no location at all.
  unavailable,
}

/// A position, or why there is none.
class LocationReading {
  const LocationReading.position(GuestPosition this.position) : failure = null;

  const LocationReading.failed(LocationFailure this.failure) : position = null;

  final GuestPosition? position;
  final LocationFailure? failure;
}

/// The device's location.
abstract interface class LocationProvider {
  /// Asks for permission when needed, then for a fresh, precise position.
  Future<LocationReading> current();

  /// Opens the phone's app settings (after a permanent refusal) or its
  /// location settings (GPS off). False where that is not possible.
  Future<bool> openSettings(LocationFailure failure);
}

/// [LocationProvider] on the device's GPS (Android, iOS and browsers).
class GeolocatorLocationProvider implements LocationProvider {
  const GeolocatorLocationProvider({
    this.timeLimit = const Duration(seconds: 15),
  });

  static GeolocatorPlatform get _geo => GeolocatorPlatform.instance;

  final Duration timeLimit;

  @override
  Future<LocationReading> current() async {
    try {
      if (!await _geo.isLocationServiceEnabled()) {
        return const LocationReading.failed(LocationFailure.serviceDisabled);
      }
      var permission = await _geo.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _geo.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const LocationReading.failed(LocationFailure.permissionDenied);
        case LocationPermission.deniedForever:
          return const LocationReading.failed(
            LocationFailure.permissionDeniedForever,
          );
        case LocationPermission.unableToDetermine:
          return const LocationReading.failed(LocationFailure.unavailable);
        case LocationPermission.whileInUse || LocationPermission.always:
          break;
      }
      final position = await _geo.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: timeLimit,
        ),
      );
      return LocationReading.position(
        GuestPosition(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          // The device's own time of the fix: an old cached fix is refused.
          capturedAt: position.timestamp,
          mocked: position.isMocked,
        ),
      );
    } on LocationServiceDisabledException {
      return const LocationReading.failed(LocationFailure.serviceDisabled);
    } on PermissionDeniedException {
      return const LocationReading.failed(LocationFailure.permissionDenied);
    } on TimeoutException {
      return const LocationReading.failed(LocationFailure.unavailable);
    } on Object {
      // A platform without location, or an unexpected plugin error.
      return const LocationReading.failed(LocationFailure.unavailable);
    }
  }

  @override
  Future<bool> openSettings(LocationFailure failure) async {
    try {
      return failure == LocationFailure.serviceDisabled
          ? await _geo.openLocationSettings()
          : await _geo.openAppSettings();
    } on Object {
      return false;
    }
  }
}

/// What the server answered to a guest's position.
class LocationCheckResult {
  const LocationCheckResult({
    required this.required,
    required this.allowed,
    this.code,
    this.message,
    this.distance,
  });

  static const notRequired = LocationCheckResult(
    required: false,
    allowed: true,
  );

  /// The area covers this session.
  final bool required;
  final bool allowed;

  /// The server's reason when refused (e.g. `outsideRestaurantArea`).
  final String? code;
  final String? message;

  /// Metres from the restaurant, when inside.
  final double? distance;
}

/// The guest app's check with the server (`POST /guest/location-check`).
abstract interface class GuestLocationChecker {
  /// [position] null when the device has none. Throws [ApiException] when
  /// the server cannot be asked.
  Future<LocationCheckResult> check(GuestPosition? position);
}

/// The ordering area as staff manage it.
abstract interface class GeofenceSettingsRepository {
  /// False when this build has no server to enforce it.
  bool get isAvailable;

  Future<GeofenceSettings> fetch();

  Future<GeofenceSettings> save(GeofenceSettings settings);
}

/// Used where there is no server (the offline demo).
class UnavailableGeofenceSettingsRepository
    implements GeofenceSettingsRepository {
  const UnavailableGeofenceSettingsRepository();

  @override
  bool get isAvailable => false;

  @override
  Future<GeofenceSettings> fetch() async => const GeofenceSettings();

  @override
  Future<GeofenceSettings> save(GeofenceSettings settings) => throw StateError(
    'The GPS ordering restriction needs the restaurant server: only the '
    'server can check where a guest orders from.',
  );
}
