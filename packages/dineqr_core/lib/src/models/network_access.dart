import 'order_type.dart';

/// What guests are told about the dine-in Wi-Fi restriction: whether it is
/// on and the Wi-Fi's name (a hint for which network to join). The
/// restaurant's authorised addresses are never sent to guests.
///
/// The server decides access from the public address a request comes from;
/// nothing the app knows about its own network (the Wi-Fi name, the
/// connection type) ever grants it.
class DineInWifi {
  const DineInWifi({
    this.enabled = false,
    this.ssid = '',
    this.takeaway = false,
  });

  factory DineInWifi.fromJson(Map<String, dynamic>? json) => json == null
      ? off
      : DineInWifi(
          enabled: json['enabled'] as bool? ?? false,
          ssid: json['ssid'] as String? ?? '',
          takeaway: json['takeaway'] as bool? ?? false,
        );

  static const off = DineInWifi();

  /// The message shown while access is blocked (the server's wording too).
  static const blockedMessage =
      "Please connect to the restaurant's Wi-Fi to access the DineQR menu and "
      'place your order.';

  /// The server's error code for a request from another network.
  static const blockedCode = 'networkNotAllowed';

  final bool enabled;

  /// The Wi-Fi's name, as a hint ('' when the restaurant gave none).
  final String ssid;

  /// Whether takeaway guests are held to it too.
  final bool takeaway;

  /// Whether the restriction covers a session for [table].
  bool appliesTo(int table) =>
      enabled && (!OrderTables.isTakeaway(table) || takeaway);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'ssid': ssid,
    'takeaway': takeaway,
  };
}

/// One network the restaurant authorised: an address, a range, or a
/// dynamic-DNS hostname ([resolved]: its current addresses).
class AuthorizedNetwork {
  const AuthorizedNetwork({
    required this.value,
    this.label = '',
    this.resolved = const [],
  });

  factory AuthorizedNetwork.fromJson(Map<String, dynamic> json) =>
      AuthorizedNetwork(
        value: json['value'] as String,
        label: json['label'] as String? ?? '',
        resolved: [
          for (final a in json['resolved'] as List? ?? const []) a as String,
        ],
      );

  final String value;
  final String label;
  final List<String> resolved;

  /// A hostname rather than an address or range.
  bool get isHost => !value.contains(':') && RegExp('[a-z]').hasMatch(value);

  Map<String, dynamic> toJson() => {
    'value': value,
    if (label.isNotEmpty) 'label': label,
  };
}

/// What the server sees for the staff device's own request: the [address]
/// it would check, whether that is authorised, and the proxy headers that
/// came with it. [consistent] is false when an edge header names another
/// client address, i.e. the deployment reports a proxy's address and the
/// restriction would not work.
class NetworkCheck {
  const NetworkCheck({
    required this.address,
    required this.source,
    required this.matches,
    this.matchedBy,
    this.isPrivate = false,
    this.sharedCarrier = false,
    this.consistent = true,
    this.headers = const {},
    this.suggestedEntry,
  });

  factory NetworkCheck.fromJson(Map<String, dynamic> json) => NetworkCheck(
    address: json['address'] as String?,
    source: json['source'] as String? ?? '',
    matches: json['matches'] as bool? ?? false,
    matchedBy: json['matchedBy'] as String?,
    isPrivate: json['private'] as bool? ?? false,
    sharedCarrier: json['sharedCarrier'] as bool? ?? false,
    consistent: json['consistent'] as bool? ?? true,
    headers: {
      for (final MapEntry(:key, :value)
          in (json['headers'] as Map? ?? const {}).entries)
        key as String: value as String,
    },
    suggestedEntry: json['suggestedEntry'] as String?,
  );

  final String? address;
  final String source;
  final bool matches;
  final String? matchedBy;
  final bool isPrivate;
  final bool sharedCarrier;
  final bool consistent;
  final Map<String, String> headers;
  final String? suggestedEntry;
}

/// The restriction as staff manage it (Settings, owner).
class NetworkAccessSettings {
  const NetworkAccessSettings({
    this.enabled = false,
    this.ssid = '',
    this.restrictTakeaway = false,
    this.networks = const [],
    this.you,
  });

  factory NetworkAccessSettings.fromJson(Map<String, dynamic> json) =>
      NetworkAccessSettings(
        enabled: json['enabled'] as bool? ?? false,
        ssid: json['ssid'] as String? ?? '',
        restrictTakeaway: json['restrictTakeaway'] as bool? ?? false,
        networks: [
          for (final n in json['networks'] as List? ?? const [])
            AuthorizedNetwork.fromJson(n as Map<String, dynamic>),
        ],
        you: json['you'] == null
            ? null
            : NetworkCheck.fromJson(json['you'] as Map<String, dynamic>),
      );

  final bool enabled;
  final String ssid;
  final bool restrictTakeaway;
  final List<AuthorizedNetwork> networks;

  /// What the server saw for this device when they were read.
  final NetworkCheck? you;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'ssid': ssid,
    'restrictTakeaway': restrictTakeaway,
    'networks': [for (final n in networks) n.toJson()],
  };
}
