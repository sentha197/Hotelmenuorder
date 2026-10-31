import '../models/network_access.dart';

/// What the server answered to a guest's network check.
enum NetworkAccessResult {
  /// The restriction is off, or does not cover this session (takeaway).
  notRequired,

  /// The request came from the restaurant's network.
  allowed,

  /// It came from another network: dine-in is locked until it passes again.
  blocked,
}

/// The guest app's check with the server (`POST /guest/network-access`). The
/// server decides from the public address the request arrives from; the app
/// sends nothing about its network.
abstract interface class NetworkAccessChecker {
  /// Throws [ApiException] when the server cannot be asked.
  Future<NetworkAccessResult> check();
}

/// The restriction as staff manage it. Only a server can enforce it, so
/// the offline demo has none.
abstract interface class NetworkAccessSettingsRepository {
  /// False when this build has no server to enforce it.
  bool get isAvailable;

  /// The settings, and what the server sees for this device.
  Future<NetworkAccessSettings> fetch();

  /// Saves [settings] (the full network list) and returns what the server
  /// stored.
  Future<NetworkAccessSettings> save(NetworkAccessSettings settings);
}

/// Used where there is no server (the offline demo).
class UnavailableNetworkAccessSettingsRepository
    implements NetworkAccessSettingsRepository {
  const UnavailableNetworkAccessSettingsRepository();

  @override
  bool get isAvailable => false;

  @override
  Future<NetworkAccessSettings> fetch() async => const NetworkAccessSettings();

  @override
  Future<NetworkAccessSettings> save(NetworkAccessSettings settings) =>
      throw StateError(
        'The dine-in Wi-Fi restriction needs the restaurant server: only the '
        'server sees which network a guest is on.',
      );
}
