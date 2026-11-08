import 'package:flutter/foundation.dart';

import '../models/geofence.dart';
import '../models/staff.dart';
import '../repositories/geofence_repository.dart';
import 'access.dart';
import 'settings_controller.dart';

/// The GPS ordering area as the owner manages it: the restaurant's
/// location, the radius and the switch. Separate from the dine-in Wi-Fi
/// restriction ([NetworkAccessSettingsController]). The server validates
/// and authorises every save; the checks here only save a round trip.
class GeofenceSettingsController extends ChangeNotifier {
  GeofenceSettingsController(this._repository, this._guard);

  final GeofenceSettingsRepository _repository;
  final AccessGuard _guard;

  GeofenceSettings _settings = const GeofenceSettings();
  bool _loaded = false;

  bool get isAvailable => _repository.isAvailable;

  GeofenceSettings get settings => _settings;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (!isAvailable || !_guard.can(Permission.manageSettings)) return;
    _settings = await _repository.fetch();
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(GeofenceSettings next) async {
    _guard.require(Permission.manageSettings);
    if (next.radius < GeofenceSettings.minRadius ||
        next.radius > GeofenceSettings.maxRadius) {
      throw const ValidationException(
        'Choose a radius from 10 to 1000 metres.',
      );
    }
    if (next.latitude != null || next.longitude != null) {
      if (!GeofenceSettings.isValidPoint(next.latitude, next.longitude)) {
        throw const ValidationException(
          'Enter a latitude from -90 to 90 and a longitude from -180 to 180, '
          'or pick the restaurant on the map.',
        );
      }
    } else {
      throw ValidationException(
        next.enabled
            ? "Set the restaurant's location before switching the GPS "
                  'restriction on.'
            : "Set the restaurant's location.",
      );
    }
    _settings = await _repository.save(next);
    _loaded = true;
    notifyListeners();
  }
}
