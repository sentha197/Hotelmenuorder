import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../models/geofence.dart';
import '../repositories/geofence_repository.dart';

/// Where the guest stands with the GPS ordering area.
enum LocationAccess {
  /// The area does not cover this session (it is off, there is no session,
  /// or it is a takeaway order the restaurant left out).
  open,

  /// Not checked yet.
  checking,

  /// The server measured the guest inside the area.
  allowed,

  /// The server measured the guest outside it.
  outside,

  /// The guest refused location permission (it can be asked again).
  permissionDenied,

  /// Refused for good: only the phone's settings can allow it.
  permissionDeniedForever,

  /// Location (GPS) is off on the device.
  serviceDisabled,

  /// The device gave no position, or one the server cannot use (too
  /// imprecise, out of date, simulated).
  unavailable,
}

/// The guest app's side of the GPS ordering area. Independent of the
/// dine-in Wi-Fi restriction ([DineInAccessController]): each has its own
/// lock, and an order must pass both on the server.
///
/// The server decides: it measures the distance from the position sent with
/// each order. This controller asks the device for its position and the
/// server whether that is inside, so the guest sees why ordering stopped. It
/// checks when the session or settings change, when the app resumes, and
/// before an order ([positionForOrder]).
class LocationAccessController extends ChangeNotifier {
  LocationAccessController({
    required this._checker,
    required this._provider,
    required this._area,
    required this._table,
    bool observeLifecycle = true,
  }) {
    if (observeLifecycle) {
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(verify()));
    }
  }

  final GuestLocationChecker? _checker;
  final LocationProvider _provider;
  final DineInLocation Function() _area;
  final int? Function() _table;
  AppLifecycleListener? _lifecycle;

  LocationAccess _state = LocationAccess.checking;
  String? _message;
  bool _busy = false;
  Future<GuestPosition?>? _pending;

  /// The server's own view, which wins over settings read earlier.
  bool? _serverRequires;
  int? _checkedTable;

  /// Whether the area covers the current session.
  bool get isRequired {
    final table = _table();
    if (_checker == null || table == null) return false;
    if (table != _checkedTable) return _area().appliesTo(table);
    return _serverRequires ?? _area().appliesTo(table);
  }

  LocationAccess get state => isRequired ? _state : LocationAccess.open;

  /// Whether ordering must be locked.
  bool get isLocked => isRequired && _state != LocationAccess.allowed;

  bool get isChecking => _busy;

  /// The server's explanation when it refused the position.
  String? get message => _message;

  /// The radius guests are told about.
  int get radius => _area().radius;

  /// The session or the restaurant's settings changed.
  void contextChanged() {
    if (_table() != _checkedTable) {
      _serverRequires = null;
      _state = LocationAccess.checking;
      _message = null;
    }
    notifyListeners();
    if (isRequired) unawaited(verify());
  }

  /// An order was refused by the GPS check (the server's [code] and
  /// [message]).
  void reportRefused(String code, String message) {
    _checkedTable = _table();
    _serverRequires = true;
    _apply(code, message);
    notifyListeners();
  }

  /// Opens the phone's settings for the current problem (permission refused
  /// for good, or location off).
  Future<bool> openSettings() => switch (_state) {
    LocationAccess.permissionDeniedForever => _provider.openSettings(
      LocationFailure.permissionDeniedForever,
    ),
    LocationAccess.serviceDisabled => _provider.openSettings(
      LocationFailure.serviceDisabled,
    ),
    _ => Future.value(false),
  };

  /// Measures the position and asks the server. Concurrent calls share one
  /// check. Returns the position when the server accepted it.
  Future<GuestPosition?> verify() =>
      _pending ??= _verify().whenComplete(() => _pending = null);

  /// A fresh position for an order: null when the area does not apply (the
  /// order is sent without one). Throws [LocationRefusedException] when the
  /// guest cannot order from where they are, so checkout stops before the
  /// request; the server checks the position sent with the order again.
  Future<GuestPosition?> positionForOrder() async {
    if (!isRequired) return null;
    final position = await verify();
    if (position == null) {
      if (!isRequired) return null;
      throw LocationRefusedException(_message ?? _describe(_state));
    }
    return position;
  }

  Future<GuestPosition?> _verify() async {
    final checker = _checker;
    final table = _table();
    if (checker == null || table == null || !isRequired) {
      notifyListeners();
      return null;
    }
    _busy = true;
    notifyListeners();
    GuestPosition? position;
    try {
      final reading = await _provider.current();
      position = reading.position;
      if (position == null) {
        _checkedTable = table;
        _state = switch (reading.failure!) {
          LocationFailure.permissionDenied => LocationAccess.permissionDenied,
          LocationFailure.permissionDeniedForever =>
            LocationAccess.permissionDeniedForever,
          LocationFailure.serviceDisabled => LocationAccess.serviceDisabled,
          LocationFailure.unavailable => LocationAccess.unavailable,
        };
        _message = null;
        // Ask the server too: it may have switched the area off meanwhile.
        final result = await checker.check(null);
        _serverRequires = result.required;
        return null;
      }
      final result = await checker.check(position);
      _checkedTable = table;
      _serverRequires = result.required;
      if (!result.required) {
        _state = LocationAccess.open;
        _message = null;
        return null;
      }
      if (result.allowed) {
        _state = LocationAccess.allowed;
        _message = null;
        return position;
      }
      _apply(result.code ?? DineInLocation.outsideCode, result.message);
      return null;
    } on ApiException catch (error) {
      // No answer from the server proves nothing either way: keep what is
      // known, and let an order carry the position so the server decides.
      debugPrint('Location check failed: ${error.code}');
      return position;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _apply(String code, String? message) {
    _state = code == DineInLocation.outsideCode
        ? LocationAccess.outside
        : code == 'locationRequired'
        ? LocationAccess.permissionDenied
        : LocationAccess.unavailable;
    _message = message;
  }

  static String _describe(LocationAccess state) => switch (state) {
    LocationAccess.outside => DineInLocation.outsideMessage,
    LocationAccess.permissionDenied || LocationAccess.permissionDeniedForever =>
      'Allow DineQR to use your location to order at this restaurant.',
    LocationAccess.serviceDisabled =>
      'Turn on location (GPS) on your phone to order at this restaurant.',
    _ => 'Your location could not be checked. Please try again.',
  };

  /// What the lock says for the current state.
  String get explanation => _message ?? _describe(state);

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }
}

/// Checkout stopped: the guest cannot order from where they are.
class LocationRefusedException implements Exception {
  const LocationRefusedException(this.message);

  final String message;

  @override
  String toString() => 'LocationRefusedException($message)';
}
