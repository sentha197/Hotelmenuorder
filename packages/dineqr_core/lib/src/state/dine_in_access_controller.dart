import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../models/network_access.dart';
import '../repositories/network_access_repository.dart';

/// Where the guest's dine-in access stands.
enum DineInAccess {
  /// The restriction does not cover this session (it is off, there is no
  /// session yet, or it is a takeaway order the restaurant left open).
  open,

  /// Not verified yet (or being re-verified after it was blocked).
  checking,

  /// The server saw the guest on the restaurant's network.
  allowed,

  /// The server saw another network, or the phone has no connection at all.
  blocked,
}

/// The guest app's side of the dine-in Wi-Fi restriction.
///
/// The server decides: it compares the public address each request comes
/// from with the restaurant's, and refuses orders and payments from
/// anywhere else. This controller only keeps the app honest about it, so a
/// guest sees why ordering stopped instead of a failed request: it locks
/// dine-in whenever the server says the guest is elsewhere, and verifies
/// again (and unlocks) when the app resumes, when the connection changes,
/// and every [pollEvery] while the restriction applies. Nothing about the
/// phone's own network (its Wi-Fi name, connection type or address) ever
/// unlocks it.
class DineInAccessController extends ChangeNotifier {
  DineInAccessController({
    required this._checker,
    required this._wifi,
    required this._table,
    Stream<bool>? connectivity,
    this.pollEvery = const Duration(seconds: 30),
    bool observeLifecycle = true,
  }) {
    _connectivity = connectivity?.listen(_connectionChanged);
    if (observeLifecycle) {
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(verify()));
    }
  }

  final NetworkAccessChecker? _checker;
  final DineInWifi Function() _wifi;
  final int? Function() _table;

  /// How often access is re-verified while the restriction applies (null:
  /// only on resume, connection changes and failed requests).
  final Duration? pollEvery;

  StreamSubscription<bool>? _connectivity;
  AppLifecycleListener? _lifecycle;
  Timer? _poll;

  DineInAccess _state = DineInAccess.checking;
  bool _offline = false;
  bool _busy = false;
  Future<void>? _pending;

  /// The server's own view, which wins over settings the app read earlier
  /// (the restaurant may have switched the restriction on or off since).
  bool? _serverRequires;
  int? _checkedTable;

  /// Whether the restriction covers the current session.
  bool get isRequired {
    final table = _table();
    if (_checker == null || table == null) return false;
    if (table != _checkedTable) return _wifi().appliesTo(table);
    return _serverRequires ?? _wifi().appliesTo(table);
  }

  DineInAccess get state => isRequired ? _state : DineInAccess.open;

  /// Whether ordering, checkout and starting payments must be locked.
  bool get isLocked =>
      isRequired && (_offline || _state != DineInAccess.allowed);

  /// Whether the phone reported no connection at all.
  bool get isOffline => isRequired && _offline;

  /// Whether a check with the server is under way.
  bool get isChecking => _busy;

  /// The restaurant's Wi-Fi name, as a hint ('' when it gave none).
  String get ssid => _wifi().ssid;

  /// The session or the restaurant's settings changed.
  void contextChanged() {
    if (_table() != _checkedTable) {
      _serverRequires = null;
      _state = DineInAccess.checking;
    }
    _schedule();
    notifyListeners();
    if (isRequired) unawaited(verify());
  }

  /// A session was just issued: on a covered table the server issues one
  /// only on the restaurant's network, so it is verified.
  void sessionStarted() {
    _checkedTable = _table();
    _serverRequires = null;
    _state = isRequired ? DineInAccess.allowed : DineInAccess.open;
    _schedule();
    notifyListeners();
  }

  /// A request was refused with `networkNotAllowed`.
  void reportBlocked() {
    _checkedTable = _table();
    _serverRequires = true;
    if (_state == DineInAccess.blocked) return;
    _state = DineInAccess.blocked;
    _schedule();
    notifyListeners();
  }

  /// Asks the server now. Concurrent calls share one request.
  Future<void> verify() =>
      _pending ??= _verify().whenComplete(() => _pending = null);

  Future<void> _verify() async {
    final checker = _checker;
    final table = _table();
    if (checker == null || table == null) {
      _schedule();
      notifyListeners();
      return;
    }
    if (!isRequired && _serverRequires == null && table == _checkedTable) {
      _schedule();
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await checker.check();
      _checkedTable = table;
      switch (result) {
        case NetworkAccessResult.notRequired:
          _serverRequires = false;
          _state = DineInAccess.open;
        case NetworkAccessResult.allowed:
          _serverRequires = true;
          _state = DineInAccess.allowed;
          _offline = false;
        case NetworkAccessResult.blocked:
          _serverRequires = true;
          _state = DineInAccess.blocked;
      }
    } on ApiException catch (error) {
      // No answer is no proof either way: keep what is known (the phone's
      // own "no connection" signal locks it separately). A refused session
      // (expired) is for the scanner to deal with.
      debugPrint('Dine-in access check failed: ${error.code}');
    } finally {
      _busy = false;
      _schedule();
      notifyListeners();
    }
  }

  void _connectionChanged(bool connected) {
    _offline = !connected;
    notifyListeners();
    if (connected && isRequired) unawaited(verify());
  }

  void _schedule() {
    final every = pollEvery;
    if (every != null && isRequired) {
      _poll ??= Timer.periodic(every, (_) => unawaited(verify()));
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_connectivity?.cancel());
    _lifecycle?.dispose();
    super.dispose();
  }
}
