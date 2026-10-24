import 'dart:async';
import 'dart:convert';

import '../models/staff.dart';
import '../qr/table_qr_parser.dart';
import '../services/auth_service.dart';
import '../storage/key_value_store.dart';
import 'api_client.dart';

/// Where long-lived tokens are kept. The admin app passes platform secure
/// storage; tests use [MemoryTokenStorage].
abstract interface class TokenStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class MemoryTokenStorage implements TokenStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// A staff account as the API returns it (never with a password hash).
StaffAccount staffFromApi(Map<String, dynamic> json) => StaffAccount(
  id: json['id'] as String,
  name: json['name'] as String,
  email: json['email'] as String,
  role: StaffRole.parse(json['role'] as String?),
  passwordHash: '',
  salt: '',
  createdAt: DateTime.parse(json['createdAt'] as String),
  isActive: json['active'] as bool? ?? true,
  lastLoginAt: json['lastLogin'] == null
      ? null
      : DateTime.parse(json['lastLogin'] as String),
);

/// Staff sign-in against the server. Access tokens are short-lived and kept
/// in memory; the refresh token is stored (in secure storage) only when the
/// staff member chose to stay signed in. [attach] makes an [ApiClient] send
/// the access token and renew it after a 401.
class HttpAuthService implements AuthService {
  HttpAuthService(
    ApiConfig config,
    this._storage, {
    ApiClient? plain,
    DateTime Function()? clock,
  }) : _plain = plain ?? ApiClient(config),
       _clock = clock ?? DateTime.now;

  static const _refreshKey = 'dineqr.staff.refresh';

  // Sign-in and refresh calls go through a client without a token, so a
  // refresh never waits on itself.
  final ApiClient _plain;
  final TokenStorage _storage;
  final DateTime Function() _clock;
  ApiClient? _api;

  String? _access;
  DateTime? _accessExpires;
  String? _refresh;
  Future<bool>? _renewing;

  /// Whether the next sign-in survives an app restart.
  bool keepSignedIn = false;

  @override
  bool get isDemo => false;

  /// Whether this app holds a staff session (staff endpoints can only be
  /// refused without one).
  bool get hasSession => _access != null || _refresh != null;

  /// Lets [api] call staff endpoints with this session.
  void attach(ApiClient api) {
    _api = api
      ..token = accessToken
      ..renewSession = renew;
  }

  @override
  Future<({StaffAccount staff, AdminSession session})> signIn(
    String email,
    String password,
  ) async {
    try {
      final json = await _plain.post('/auth/login', {
        'email': email.trim(),
        'password': password,
      });
      return await _accept(json! as Map<String, dynamic>, keepSignedIn);
    } on ApiException catch (error) {
      throw AuthException(switch (error.code) {
        'invalidInput' => AuthError.invalidInput,
        'invalidCredentials' => AuthError.invalidCredentials,
        'lockedOut' || 'tooManyRequests' => AuthError.lockedOut,
        'forbidden' => AuthError.inactive,
        _ => AuthError.unavailable,
      });
    }
  }

  /// Restores the saved session. Returns null when there is none or the
  /// server refused it (the token is then forgotten). Throws the
  /// [ApiException] when the server could not be reached, keeping the token,
  /// so the app can offer a retry instead of a sign-in it does not need.
  @override
  Future<({StaffAccount staff, AdminSession session})?> restore() async {
    final saved = await _storage.read(_refreshKey);
    if (saved == null || saved.isEmpty) return null;
    try {
      final json = await _plain.post('/auth/refresh', {'refreshToken': saved});
      return await _accept(json! as Map<String, dynamic>, true);
    } on ApiException catch (error) {
      if (error.isOffline) rethrow;
      await _clear();
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    final refresh = _refresh;
    try {
      if (refresh != null) {
        await (_api ?? _plain).post('/auth/logout', {'refreshToken': refresh});
      }
    } on ApiException {
      // Best effort: the session expires on the server anyway.
    } finally {
      await _clear();
    }
  }

  /// A valid access token, renewed shortly before it expires.
  Future<String?> accessToken() async {
    final expires = _accessExpires;
    if (_access != null &&
        expires != null &&
        _clock().isBefore(expires.subtract(const Duration(seconds: 30)))) {
      return _access;
    }
    if (_refresh == null) return _access;
    await renew();
    return _access;
  }

  /// Exchanges the refresh token for a new pair (one call at a time).
  Future<bool> renew() => _renewing ??= _renew().whenComplete(() {
    _renewing = null;
  });

  Future<bool> _renew() async {
    final refresh = _refresh;
    if (refresh == null) return false;
    try {
      final json = await _plain.post('/auth/refresh', {
        'refreshToken': refresh,
      });
      final persist = await _storage.read(_refreshKey) != null;
      await _accept(json! as Map<String, dynamic>, persist);
      return true;
    } on ApiException catch (error) {
      if (!error.isOffline) await _clear();
      return false;
    }
  }

  Future<({StaffAccount staff, AdminSession session})> _accept(
    Map<String, dynamic> json,
    bool persist,
  ) async {
    _access = json['accessToken'] as String;
    _accessExpires = DateTime.parse(json['accessTokenExpiresAt'] as String);
    _refresh = json['refreshToken'] as String;
    if (persist) {
      await _storage.write(_refreshKey, _refresh!);
    } else {
      await _storage.delete(_refreshKey);
    }
    final staff = staffFromApi(json['staff'] as Map<String, dynamic>);
    return (
      staff: staff,
      session: AdminSession(
        staffId: staff.id,
        issuedAt: _clock(),
        expiresAt: DateTime.parse(json['sessionExpiresAt'] as String),
      ),
    );
  }

  Future<void> _clear() async {
    _access = null;
    _accessExpires = null;
    _refresh = null;
    await _storage.delete(_refreshKey);
  }
}

/// The customer's table session: scanning a table QR asks the server for a
/// guest token scoped to that table (it grants no staff access). The token
/// is kept on the device until it expires, so the guest's orders and bills
/// stay reachable after a restart.
class GuestSession {
  GuestSession(this._api, this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _restore();
    _api.token = token;
  }

  static const _key = 'guest.session';

  final ApiClient _api;
  final KeyValueStore _store;
  final DateTime Function() _clock;

  String? _token;
  int? _table;
  DateTime? _expires;

  int? get table => isActive ? _table : null;

  bool get isActive =>
      _token != null && _expires != null && _clock().isBefore(_expires!);

  Future<String?> token() async => isActive ? _token : null;

  /// Validates [qrPayload] with the server and starts (or keeps) the session.
  /// Throws [ApiException] (e.g. `tableInactive`, `notFound`).
  Future<int> start(String qrPayload) async {
    Map<String, dynamic> json;
    try {
      json =
          (await _api.post('/guest/sessions', {'qrPayload': qrPayload}))!
              as Map<String, dynamic>;
    } on ApiException catch (error) {
      // A server from before takeaway was renamed knows only its old code.
      if (error.code != 'unrecognized' ||
          qrPayload != TableQrParser.takeawayPayload) {
        rethrow;
      }
      json =
          (await _api.post('/guest/sessions', {
                'qrPayload': TableQrParser.legacyTakeawayPayloads.first,
              }))!
              as Map<String, dynamic>;
    }
    _token = json['guestToken'] as String;
    _table = json['tableNumber'] as int;
    _expires = DateTime.parse(json['expiresAt'] as String);
    await _store.write(
      _key,
      jsonEncode({
        'token': _token,
        'table': _table,
        'expires': _expires!.toIso8601String(),
      }),
    );
    return _table!;
  }

  Future<void> clear() async {
    _token = null;
    _table = null;
    _expires = null;
    await _store.delete(_key);
  }

  void _restore() {
    final raw = _store.read(_key);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _token = json['token'] as String;
      _table = json['table'] as int;
      _expires = DateTime.parse(json['expires'] as String);
    } on Object {
      unawaited(_store.delete(_key));
    }
  }
}
