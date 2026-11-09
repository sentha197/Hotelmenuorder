import 'dart:async';

import 'package:web/web.dart' as web;

Future<bool>? _loading;

/// Adds the Maps JavaScript API to the page once, with [apiKey]. False when
/// it could not be loaded (no key, offline, or the key refused).
Future<bool> ensureGoogleMapsLoaded(String apiKey) {
  if (apiKey.isEmpty) return Future.value(false);
  return _loading ??= () {
    final done = Completer<bool>();
    final script = web.HTMLScriptElement()
      ..src =
          'https://maps.googleapis.com/maps/api/js?key='
          '${Uri.encodeQueryComponent(apiKey)}&loading=async'
      ..async = true;
    script.onLoad.first.then((_) => done.complete(true));
    script.onError.first.then((_) {
      _loading = null;
      done.complete(false);
    });
    web.document.head!.append(script);
    return done.future;
  }();
}
