import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Where the DineQR API lives. Set at build time, per environment:
///
///     flutter run --dart-define=DINEQR_API_URL=http://10.0.2.2:5264
///
/// (Android emulator → host machine), `http://<computer LAN IP>:5264` for a
/// phone on the same Wi-Fi, `http://localhost:5264` for web or desktop on
/// the same computer. Without it, a debug build uses the local development
/// API ([localDevelopmentUrl]), so a plain `flutter run` works, and a
/// profile or release build uses the deployed API ([productionUrl]), so a
/// plain `flutter build apk` works. The apps never talk to PostgreSQL
/// directly.
class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 20),
  });

  static const _environmentUrl = String.fromEnvironment('DINEQR_API_URL');

  /// The API URL given with `--dart-define`. Without one, debug builds use
  /// [localDevelopmentUrl] and profile and release builds [productionUrl].
  /// A define that cannot work is rejected (see [issueFromEnvironment])
  /// rather than failing later on every request.
  static ApiConfig? fromEnvironment() => _resolve().config;

  /// Why [fromEnvironment] has no usable URL, or null when it has one. The
  /// apps show this at start-up instead of a bare "not connected".
  static ApiConfigIssue? issueFromEnvironment() => _resolve().issue;

  /// Hosts that mean "this device", which on Android is never the computer
  /// running the API — not on a phone, and not on the emulator either.
  static const _loopbackHosts = {'localhost', '127.0.0.1', '::1', '0.0.0.0'};

  static ({ApiConfig? config, ApiConfigIssue? issue}) _resolve() =>
      resolveUrl(_environmentUrl, debugFallback: kDebugMode);

  /// Applies the rules above to [value], as if it came from the define.
  /// Exposed so they can be tested without rebuilding with a new define.
  @visibleForTesting
  static ({ApiConfig? config, ApiConfigIssue? issue}) resolveUrl(
    String value, {
    required bool debugFallback,
  }) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return (
        config: ApiConfig(
          baseUrl: debugFallback ? localDevelopmentUrl : productionUrl,
        ),
        issue: null,
      );
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.isAbsolute ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return (config: null, issue: ApiConfigIssue.malformed(raw));
    }
    // Checked on Android only: the iOS simulator does share the computer's
    // network, so localhost is right there.
    final onAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (onAndroid && _loopbackHosts.contains(uri.host.toLowerCase())) {
      return (config: null, issue: ApiConfigIssue.loopback(raw));
    }
    return (config: ApiConfig(baseUrl: uri), issue: null);
  }

  /// The API started with `dotnet run` on this computer (port 5264). The
  /// Android emulator reaches the host computer at 10.0.2.2; web, desktop
  /// and the iOS simulator use localhost. A phone needs `DINEQR_API_URL`.
  static Uri get localDevelopmentUrl => Uri.parse(
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:5264'
        : 'http://localhost:5264',
  );

  /// The deployed API (Render, behind HTTPS). Only the host goes here:
  /// [resolve] adds `/api/v1` and [hubUrl] `/hubs/events`.
  static final Uri productionUrl = Uri.parse(
    'https://hotelmenuorder.onrender.com',
  );

  final Uri baseUrl;
  final Duration timeout;

  Uri resolve(String path, [Map<String, String>? query]) {
    final base = baseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1$path');
    return query == null || query.isEmpty
        ? uri
        : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  /// The SignalR hub for live updates.
  Uri get hubUrl {
    final base = baseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/hubs/events');
  }
}

/// Why a build has no usable API address, phrased for the person holding
/// the device. Every case names the value to use, because the fix is always
/// a rebuild with a different `--dart-define`.
class ApiConfigIssue {
  const ApiConfigIssue(this.title, this.detail);

  /// Present but not an absolute http(s) URL with a host.
  ApiConfigIssue.malformed(String value)
    : title = 'The server address is not valid',
      detail =
          '"$value" is not a full http:// or https:// address. '
          'It needs the scheme, host and port, for example '
          'http://192.168.1.10:5264.';

  /// Points at the device itself, which can never be the API host on
  /// Android.
  ApiConfigIssue.loopback(String value)
    : title = 'The server address points at this device',
      detail =
          '"$value" means the phone itself, not the computer running the '
          'API. Use http://10.0.2.2:5264 on the Android emulator, or '
          'http://<your computer\'s LAN IP>:5264 on a real phone connected '
          'to the same Wi-Fi.';

  /// One short line, e.g. for a dialog heading.
  final String title;

  /// What to do about it.
  final String detail;
}

/// A failed API call: [status] 0 means the server was not reached.
/// [code] is the server's machine-readable reason (e.g. `tableUnavailable`)
/// and [message] is safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  const ApiException.network()
    : status = 0,
      code = 'network',
      message =
          'Cannot reach the restaurant server. Check your connection and try '
          'again.';

  const ApiException.timeout()
    : status = 0,
      code = 'timeout',
      message = 'The server took too long to answer. Please try again.';

  final int status;
  final String code;
  final String message;

  bool get isOffline => status == 0;

  bool get isUnauthorized => status == 401;

  bool get isForbidden => status == 403;

  bool get isNotFound => status == 404;

  @override
  String toString() => 'ApiException($status, $code)';
}

/// Supplies the bearer token for each request (null for public calls).
typedef TokenSource = Future<String?> Function();

/// Called after a 401: tries to renew the session and returns whether the
/// request should be retried once.
typedef SessionRenewal = Future<bool> Function();

/// JSON over HTTP for the DineQR API. Only safe, idempotent GET requests are
/// retried; anything that changes data is sent once (and carries an
/// idempotency key where the API supports it).
class ApiClient {
  ApiClient(this.config, {http.Client? client, this.token, this.renewSession})
    : _http = client ?? http.Client();

  final ApiConfig config;
  final http.Client _http;
  TokenSource? token;
  SessionRenewal? renewSession;

  Future<Object?> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query, retries: 1);

  Future<Object?> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<Object?> put(String path, Object? body) =>
      _send('PUT', path, body: body);

  Future<Object?> patch(String path, Object? body) =>
      _send('PATCH', path, body: body);

  /// Uploads [bytes] as a `multipart/form-data` field named [field].
  ///
  /// Never retried: a retry would store a second copy of the file. The
  /// content type is deliberately left to the default, because the server
  /// identifies the format from the bytes rather than trusting the client.
  Future<Object?> postFile(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    bool renewed = false,
  }) async {
    final request = http.MultipartRequest('POST', config.resolve(path))
      ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(field, bytes, filename: filename),
      );
    final bearer = await token?.call();
    if (bearer != null && bearer.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $bearer';
    }

    http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request),
      ).timeout(config.timeout);
    } on TimeoutException {
      throw const ApiException.timeout();
    } on Object catch (error) {
      if (error is ApiException) rethrow;
      _log('POST', path, 'unreachable');
      throw const ApiException.network();
    }
    _log('POST', path, '${response.statusCode}');

    if (response.statusCode == 401 && !renewed && renewSession != null) {
      if (await renewSession!()) {
        return postFile(
          path,
          field: field,
          bytes: bytes,
          filename: filename,
          renewed: true,
        );
      }
    }
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : _tryDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw _problem(response.statusCode, decoded);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    int retries = 0,
    bool renewed = false,
  }) async {
    final uri = config.resolve(path, query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final bearer = await token?.call();
    if (bearer != null && bearer.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $bearer';
    }

    http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request),
      ).timeout(config.timeout);
    } on TimeoutException {
      if (retries > 0) return _retry(method, path, body, query, retries);
      throw const ApiException.timeout();
    } on Object catch (error) {
      if (error is ApiException) rethrow;
      if (retries > 0) return _retry(method, path, body, query, retries);
      _log(method, path, 'unreachable');
      throw const ApiException.network();
    }
    // Paths and status codes only: never tokens or bodies.
    _log(method, path, '${response.statusCode}');

    if (response.statusCode == 401 && !renewed && renewSession != null) {
      if (await renewSession!()) {
        return _send(method, path, body: body, query: query, renewed: true);
      }
    }
    if (response.statusCode >= 500 && retries > 0) {
      return _retry(method, path, body, query, retries);
    }
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : _tryDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw _problem(response.statusCode, decoded);
  }

  Future<Object?> _retry(
    String method,
    String path,
    Object? body,
    Map<String, String>? query,
    int retries,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return _send(method, path, body: body, query: query, retries: retries - 1);
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// RFC 7807 problem → [ApiException] with the server's message.
  static ApiException _problem(int status, Object? body) {
    var code = switch (status) {
      401 => 'unauthorized',
      403 => 'forbidden',
      404 => 'notFound',
      409 => 'conflict',
      429 => 'tooManyRequests',
      >= 500 => 'serverError',
      _ => 'badRequest',
    };
    var message = switch (status) {
      401 => 'Your session has ended. Please sign in again.',
      403 => 'You do not have permission to do that.',
      404 => 'That could not be found. It may have been removed.',
      429 => 'Too many attempts. Please wait a moment and try again.',
      >= 500 => 'The server had a problem. Please try again.',
      _ => 'The request could not be completed.',
    };
    if (body is Map<String, dynamic>) {
      if (body['code'] is String) code = body['code'] as String;
      if (body['title'] is String && (body['title'] as String).isNotEmpty) {
        message = body['title'] as String;
      }
    }
    return ApiException(status, code, message);
  }

  void _log(String method, String path, String outcome) {
    if (kDebugMode) debugPrint('API $method $path → $outcome');
  }

  void close() => _http.close();
}

/// A fresh idempotency key (random, URL-safe).
String newIdempotencyKey() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = List.generate(
    12,
    (_) => _alphabet[_random.nextInt(_alphabet.length)],
  ).join();
  return '$now$random';
}

const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
final _random = Random.secure();
