import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/staff.dart';
import '../repositories/staff_repository.dart';
import '../storage/key_value_store.dart';
import '../utils/restaurant_time.dart';

enum AuthError {
  invalidInput('Enter your email and password.'),
  invalidCredentials('Incorrect email or password.'),
  inactive('This account has been deactivated. Contact the restaurant owner.'),
  lockedOut('Too many attempts. Try again in a minute.'),
  unavailable('Sign-in is unavailable right now. Please try again.');

  const AuthError(this.message);

  final String message;
}

class AuthException implements Exception {
  const AuthException(this.error);

  final AuthError error;

  @override
  String toString() => 'AuthException(${error.name})';
}

/// Salted, iterated SHA-256. A production backend should use a dedicated
/// password hash (Argon2, bcrypt or scrypt) server-side.
abstract final class PasswordHasher {
  static const iterations = 4000;

  static String newSalt() => Ids.random(24);

  static String hash(String password, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$password')).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert([...digest, ...utf8.encode(salt)]).bytes;
    }
    return base64Encode(digest);
  }

  /// Comparison that does not stop at the first different character.
  static bool matches(String password, String salt, String expectedHash) {
    final actual = hash(password, salt);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Minimum strength for new passwords.
  static String? validateNew(String password) {
    if (password.length < 8) return 'Use at least 8 characters.';
    if (!password.contains(RegExp(r'[A-Za-z]')) ||
        !password.contains(RegExp(r'[0-9]'))) {
      return 'Use letters and numbers.';
    }
    return null;
  }
}

/// Staff sign-in. In production this is the restaurant backend (it issues
/// short-lived tokens and checks the role on every request); the demo
/// implementation verifies against local accounts.
abstract interface class AuthService {
  bool get isDemo;

  Future<({StaffAccount staff, AdminSession session})> signIn(
    String email,
    String password,
  );

  /// The saved session if it is still valid. A server-backed implementation
  /// throws when it cannot reach the server, so the app can offer a retry
  /// rather than a sign-in that is not needed.
  Future<({StaffAccount staff, AdminSession session})?> restore();

  Future<void> signOut();
}

/// Demo-only accounts, shown on the demo login screen. They exist only in
/// the offline demo build; never ship real credentials in an app.
abstract final class DemoCredentials {
  static const password = 'Demo@1234';

  static const accounts = [
    (email: 'owner@dineqr.demo', name: 'Demo Owner', role: StaffRole.owner),
    (
      email: 'manager@dineqr.demo',
      name: 'Demo Manager',
      role: StaffRole.manager,
    ),
    (
      email: 'cashier@dineqr.demo',
      name: 'Demo Cashier',
      role: StaffRole.cashier,
    ),
    (
      email: 'kitchen@dineqr.demo',
      name: 'Demo Kitchen',
      role: StaffRole.kitchen,
    ),
    (email: 'service@dineqr.demo', name: 'Demo Server', role: StaffRole.waiter),
    (
      email: 'accounts@dineqr.demo',
      name: 'Demo Accountant',
      role: StaffRole.accountant,
    ),
  ];

  /// Fresh demo accounts with hashed passwords.
  static List<StaffAccount> seedAccounts(DateTime now) => [
    for (final (index, account) in accounts.indexed)
      () {
        final salt = PasswordHasher.newSalt();
        return StaffAccount(
          id: 'STF${(index + 1).toString().padLeft(3, '0')}',
          name: account.name,
          email: account.email,
          role: account.role,
          passwordHash: PasswordHasher.hash(password, salt),
          salt: salt,
          createdAt: now,
        );
      }(),
  ];
}

class DemoAuthService implements AuthService {
  DemoAuthService(
    this._staff,
    this._store, {
    DateTime Function()? clock,
    this.sessionLength = const Duration(hours: 8),
    this.maxAttempts = 5,
    this.lockout = const Duration(minutes: 1),
  }) : _clock = clock ?? DateTime.now;

  final StaffRepository _staff;
  final KeyValueStore _store;
  final DateTime Function() _clock;
  final Duration sessionLength;
  final int maxAttempts;
  final Duration lockout;

  final Map<String, ({int failures, DateTime? lockedUntil})> _attempts = {};

  @override
  bool get isDemo => true;

  @override
  Future<({StaffAccount staff, AdminSession session})> signIn(
    String email,
    String password,
  ) async {
    final key = email.trim().toLowerCase();
    if (key.isEmpty || password.isEmpty) {
      throw const AuthException(AuthError.invalidInput);
    }
    final now = _clock();
    final attempt = _attempts[key];
    final lockedUntil = attempt?.lockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      throw const AuthException(AuthError.lockedOut);
    }
    final accounts = await _staff.fetchStaff();
    final account = accounts.where((a) => a.email == key).firstOrNull;
    var ok = false;
    if (account != null) {
      ok = PasswordHasher.matches(password, account.salt, account.passwordHash);
    } else {
      // Hash anyway so response time does not reveal which emails exist.
      PasswordHasher.hash(password, 'timing-guard');
    }
    if (!ok || account == null) {
      final failures = (attempt?.failures ?? 0) + 1;
      _attempts[key] = (
        failures: failures >= maxAttempts ? 0 : failures,
        lockedUntil: failures >= maxAttempts ? now.add(lockout) : null,
      );
      throw AuthException(
        failures >= maxAttempts
            ? AuthError.lockedOut
            : AuthError.invalidCredentials,
      );
    }
    if (!account.isActive) throw const AuthException(AuthError.inactive);
    _attempts.remove(key);
    final updated = account.copyWith(lastLoginAt: now);
    await _staff.saveStaff(updated);
    final session = AdminSession(
      staffId: account.id,
      issuedAt: now,
      expiresAt: now.add(sessionLength),
    );
    await _store.write(StorageKeys.adminSession, jsonEncode(session.toJson()));
    return (staff: updated, session: session);
  }

  @override
  Future<({StaffAccount staff, AdminSession session})?> restore() async {
    final raw = _store.read(StorageKeys.adminSession);
    if (raw == null) return null;
    try {
      final session = AdminSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (session.isExpiredAt(_clock())) {
        await signOut();
        return null;
      }
      final accounts = await _staff.fetchStaff();
      final staff = accounts.where((a) => a.id == session.staffId).firstOrNull;
      if (staff == null || !staff.isActive) {
        await signOut();
        return null;
      }
      return (staff: staff, session: session);
    } on Object {
      await signOut();
      return null;
    }
  }

  @override
  Future<void> signOut() => _store.delete(StorageKeys.adminSession);
}

/// Used when no staff sign-in service is configured (a production build
/// without its backend): every sign-in is refused.
class UnavailableAuthService implements AuthService {
  const UnavailableAuthService();

  @override
  bool get isDemo => false;

  @override
  Future<({StaffAccount staff, AdminSession session})> signIn(
    String email,
    String password,
  ) async => throw const AuthException(AuthError.unavailable);

  @override
  Future<({StaffAccount staff, AdminSession session})?> restore() async => null;

  @override
  Future<void> signOut() async {}
}
