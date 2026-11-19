import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'api_client.dart';

/// A change announced by the server (`orders`, `bills`, `menu`, `settings`,
/// `tables`, `inventory`, `staff`), or `connected` after (re)connecting.
/// Events only say what changed; the data is always re-read through the
/// REST API, which applies every permission check.
class RealtimeEvent {
  const RealtimeEvent(this.name, [this.data = const {}]);

  final String name;
  final Map<String, dynamic> data;
}

/// The server's SignalR hub (`/hubs/events`), with automatic reconnection.
class RealtimeClient {
  RealtimeClient(this._config, {required this.token});

  static const eventNames = [
    'orders',
    'bills',
    'menu',
    'settings',
    'tables',
    'inventory',
    'staff',
  ];

  final ApiConfig _config;

  /// The staff access token or guest token for the connection.
  final Future<String?> Function() token;

  final _events = StreamController<RealtimeEvent>.broadcast();
  HubConnection? _hub;
  Timer? _retry;
  bool _wanted = false;

  Stream<RealtimeEvent> get events => _events.stream;

  bool get isConnected => _hub?.state == HubConnectionState.Connected;

  /// Connects (again). Safe to call repeatedly, e.g. after signing in.
  Future<void> start() async {
    _wanted = true;
    _retry?.cancel();
    await _hub?.stop().catchError((Object _) {});
    if ((await token()) == null) return; // nothing to authenticate with yet
    final hub = HubConnectionBuilder()
        .withUrl(
          _config.hubUrl.toString(),
          options: HttpConnectionOptions(
            accessTokenFactory: () async => await token() ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();
    for (final name in eventNames) {
      hub.on(name, (arguments) {
        final first = arguments == null || arguments.isEmpty
            ? null
            : arguments.first;
        _events.add(
          RealtimeEvent(
            name,
            first is Map ? Map<String, dynamic>.from(first) : const {},
          ),
        );
      });
    }
    hub.onreconnected(({connectionId}) {
      _events.add(const RealtimeEvent('connected'));
    });
    hub.onclose(({error}) => _scheduleRestart());
    _hub = hub;
    try {
      await hub.start();
      _events.add(const RealtimeEvent('connected'));
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Live updates unavailable: $error');
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (!_wanted) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 15), start);
  }

  Future<void> stop() async {
    _wanted = false;
    _retry?.cancel();
    await _hub?.stop().catchError((Object _) {});
    _hub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}

/// Keeps screens current: on each event the matching data is re-read from
/// the API (bursts are merged), everything is re-read after a reconnect,
/// and while the live connection is down data is refreshed periodically.
/// Re-reads just the record an event names (its payload). Returns false when
/// the payload names nothing usable, so the whole list is re-read instead.
typedef LivePatcher = Future<bool> Function(Map<String, dynamic> data);

class LiveUpdates {
  LiveUpdates(
    this._client, {
    required this._handlers,
    this.pollEvery = const Duration(seconds: 30),
    this._patchers = const {},
  }) {
    _subscription = _client.events.listen(_onEvent);
    _poll = Timer.periodic(pollEvery, (_) {
      if (!_client.isConnected) _refresh(_handlers.keys);
    });
  }

  final RealtimeClient _client;
  final Map<String, Future<void> Function()> _handlers;
  final Map<String, LivePatcher> _patchers;
  final Duration pollEvery;

  /// At most this many records are re-read one by one; a bigger burst
  /// re-reads the whole list.
  static const maxPatches = 8;
  final _pending = <String, List<Map<String, dynamic>>>{};
  late final StreamSubscription<RealtimeEvent> _subscription;
  late final Timer _poll;
  final _dirty = <String>{};
  Timer? _debounce;

  void _onEvent(RealtimeEvent event) {
    if (event.name == 'connected') {
      _refresh(_handlers.keys);
    } else if (_patchers.containsKey(event.name) && event.data.isNotEmpty) {
      // An order or bill event names its record: re-read only that one, not
      // every order or bill of the last 90 days.
      (_pending[event.name] ??= []).add(event.data);
      _schedule();
    } else if (_handlers.containsKey(event.name)) {
      _refresh([event.name]);
    }
  }

  void _refresh(Iterable<String> names) {
    _dirty.addAll(names);
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final pending = {..._pending};
      _pending.clear();
      for (final MapEntry(key: name, value: payloads) in pending.entries) {
        if (_dirty.contains(name)) continue;
        final unique = {
          for (final p in payloads) p.toString(): p,
        }.values.toList();
        if (unique.length > maxPatches) {
          _dirty.add(name);
          continue;
        }
        for (final payload in unique) {
          var ok = false;
          try {
            ok = await _patchers[name]!(payload);
          } on Object catch (error) {
            if (kDebugMode) debugPrint('Updating one $name failed: $error');
          }
          if (!ok) {
            _dirty.add(name);
            break;
          }
        }
      }
      final names = {..._dirty};
      _dirty.clear();
      for (final name in names) {
        try {
          await _handlers[name]!();
        } on Object catch (error) {
          // The screens keep what they have; the next event or poll retries.
          if (kDebugMode) debugPrint('Refreshing $name failed: $error');
        }
      }
    });
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    _poll.cancel();
    await _subscription.cancel();
  }
}
