import 'order_type.dart';

/// What guests are told about the restaurant's GPS ordering area: whether
/// they must share their location to order, and the radius. The server
/// keeps the restaurant's coordinates and measures the distance itself.
class DineInLocation {
  const DineInLocation({
    this.enabled = false,
    this.radius = 0,
    this.takeaway = false,
  });

  factory DineInLocation.fromJson(Map<String, dynamic>? json) => json == null
      ? off
      : DineInLocation(
          enabled: json['enabled'] as bool? ?? false,
          radius: json['radius'] as int? ?? 0,
          takeaway: json['takeaway'] as bool? ?? false,
        );

  static const off = DineInLocation();

  /// Shown while the guest is outside the area (the server's wording too).
  static const outsideMessage =
      "You are outside the restaurant's permitted location. Please move "
      'closer to the restaurant to place your order.';

  /// The server's error codes for a refused position.
  static const outsideCode = 'outsideRestaurantArea';
  static const codes = {
    outsideCode,
    'locationRequired',
    'locationInvalid',
    'locationInaccurate',
    'locationStale',
    'mockLocation',
  };

  final bool enabled;

  /// Metres from the restaurant.
  final int radius;

  /// Whether takeaway guests are held to it too.
  final bool takeaway;

  /// Whether the area covers a session for [table].
  bool appliesTo(int table) =>
      enabled && (!OrderTables.isTakeaway(table) || takeaway);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'radius': radius,
    'takeaway': takeaway,
  };
}

/// A position as the device reported it, sent with the location check and
/// with the order. Never stored by the app or the server.
class GuestPosition {
  const GuestPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
    this.mocked = false,
  });

  final double latitude;
  final double longitude;

  /// The device's own uncertainty, in metres.
  final double accuracy;
  final DateTime capturedAt;

  /// The device says a mock-location app supplied it (Android).
  final bool mocked;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'mocked': mocked,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };
}

/// The ordering area as staff manage it.
class GeofenceSettings {
  const GeofenceSettings({
    this.restaurantId = 1,
    this.restaurantName = '',
    this.configured = false,
    this.enabled = false,
    this.latitude,
    this.longitude,
    this.radius = 50,
    this.takeaway = false,
    this.createdAt,
    this.updatedAt,
    this.updatedBy = '',
  });

  factory GeofenceSettings.fromJson(Map<String, dynamic> json) =>
      GeofenceSettings(
        restaurantId: json['restaurantId'] as int? ?? 1,
        restaurantName: json['restaurantName'] as String? ?? '',
        configured: json['configured'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? false,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        radius: json['radius'] as int? ?? 50,
        takeaway: json['takeaway'] as bool? ?? false,
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        updatedBy: json['updatedBy'] as String? ?? '',
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// The radii offered as quick choices; any value from [minRadius] to
  /// [maxRadius] can be saved as a custom radius.
  static const presets = [20, 30, 50, 100];
  static const minRadius = 10;
  static const maxRadius = 1000;

  final int restaurantId;
  final String restaurantName;

  /// A location has been saved.
  final bool configured;
  final bool enabled;
  final double? latitude;
  final double? longitude;
  final int radius;
  final bool takeaway;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String updatedBy;

  bool get hasLocation => latitude != null && longitude != null;

  static bool isValidPoint(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude == 0 && longitude == 0);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'takeaway': takeaway,
  };

  GeofenceSettings copyWith({
    bool? enabled,
    double? latitude,
    double? longitude,
    int? radius,
    bool? takeaway,
  }) => GeofenceSettings(
    restaurantId: restaurantId,
    restaurantName: restaurantName,
    configured: configured,
    enabled: enabled ?? this.enabled,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    radius: radius ?? this.radius,
    takeaway: takeaway ?? this.takeaway,
    createdAt: createdAt,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );
}
