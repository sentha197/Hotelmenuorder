import 'package:flutter/foundation.dart';

import '../models/network_access.dart';
import '../models/staff.dart';
import '../repositories/network_access_repository.dart';
import 'access.dart';
import 'settings_controller.dart';

/// The dine-in Wi-Fi restriction as the owner manages it: the switch, the
/// Wi-Fi name guests are shown, and the restaurant's public networks. The
/// server validates and authorises every save (and decides access); the
/// checks here only save a round trip.
class NetworkAccessSettingsController extends ChangeNotifier {
  NetworkAccessSettingsController(this._repository, this._guard);

  final NetworkAccessSettingsRepository _repository;
  final AccessGuard _guard;

  NetworkAccessSettings _settings = const NetworkAccessSettings();
  bool _loaded = false;

  static const maxNetworks = 20;

  /// Whether this build has a server to enforce it (not the offline demo).
  bool get isAvailable => _repository.isAvailable;

  NetworkAccessSettings get settings => _settings;

  /// What the server saw for this device at the last read.
  NetworkCheck? get you => _settings.you;

  bool get isLoaded => _loaded;

  /// Reads the settings and what the server sees for this device. Only for
  /// staff who may change settings (the server refuses anyone else).
  Future<void> load() async {
    if (!isAvailable || !_guard.can(Permission.manageSettings)) return;
    _settings = await _repository.fetch();
    _loaded = true;
    notifyListeners();
  }

  /// Validates and saves [next] (the full network list).
  Future<void> save(NetworkAccessSettings next) async {
    _guard.require(Permission.manageSettings);
    final ssid = next.ssid.trim();
    if (ssid.length > 32) {
      throw const ValidationException('A Wi-Fi name is at most 32 characters.');
    }
    final networks = [
      for (final n in next.networks)
        if (n.value.trim().isNotEmpty)
          AuthorizedNetwork(value: n.value.trim(), label: n.label.trim()),
    ];
    if (networks.length > maxNetworks) {
      throw const ValidationException('List at most 20 networks.');
    }
    if (next.enabled && networks.isEmpty) {
      throw const ValidationException(
        "Add the restaurant's network before switching the restriction on, "
        'or no guest could order.',
      );
    }
    _settings = await _repository.save(
      NetworkAccessSettings(
        enabled: next.enabled,
        ssid: ssid,
        restrictTakeaway: next.restrictTakeaway,
        networks: networks,
      ),
    );
    _loaded = true;
    notifyListeners();
  }
}
