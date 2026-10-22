import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

/// The signed-in staff member (admin area only).
class AdminSessionController extends ChangeNotifier implements AccessGuard {
  AdminSessionController(this._auth, this._audit, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _audit.guard = this;
  }

  final AuthService _auth;
  final AuditLog _audit;
  final DateTime Function() _clock;

  StaffAccount? _staff;
  AdminSession? _session;
  bool _busy = false;
  String? _endedReason;

  bool get isDemo => _auth.isDemo;

  bool get isBusy => _busy;

  bool get isSignedIn => _validSession;

  @override
  StaffAccount? get actor => _validSession ? _staff : null;

  AdminSession? get session => _session;

  /// Why the last session ended on its own (e.g. expiry), shown once on the
  /// login screen.
  String? takeEndedReason() {
    final reason = _endedReason;
    _endedReason = null;
    return reason;
  }

  bool get _validSession {
    final session = _session;
    return _staff != null &&
        session != null &&
        !session.isExpiredAt(_clock()) &&
        _staff!.isActive;
  }

  Future<void> restore() async {
    final restored = await _auth.restore();
    if (restored == null) return;
    _staff = restored.staff;
    _session = restored.session;
    notifyListeners();
  }

  /// Throws [AuthException] with a user-facing message.
  Future<StaffAccount> signIn(String email, String password) async {
    if (_busy) throw const AuthException(AuthError.unavailable);
    _busy = true;
    notifyListeners();
    try {
      final result = await _auth.signIn(email, password);
      _staff = result.staff;
      _session = result.session;
      _endedReason = null;
      await _audit.record('auth.sign_in', 'Signed in');
      return result.staff;
    } on AuthException catch (error) {
      if (error.error == AuthError.lockedOut) {
        await _audit.record(
          'auth.locked',
          'Sign-in locked after repeated failures for ${email.trim().toLowerCase()}',
        );
      }
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut({String? reason}) async {
    if (_staff != null && reason == null) {
      await _audit.record('auth.sign_out', 'Signed out');
    }
    _staff = null;
    _session = null;
    _endedReason = reason;
    await _auth.signOut();
    notifyListeners();
  }

  /// Applies changes to the signed-in account (role or active flag).
  void refreshActor(StaffAccount updated) {
    if (_staff?.id != updated.id) return;
    _staff = updated;
    if (!updated.isActive) {
      unawaited(signOut(reason: 'Your account was deactivated.'));
    } else {
      notifyListeners();
    }
  }

  @override
  bool can(Permission permission) => _validSession && _staff!.can(permission);

  @override
  void require(Permission permission) {
    if (!_validSession) {
      if (_session != null) {
        unawaited(
          signOut(reason: 'Your session expired. Please sign in again.'),
        );
      }
      throw const SessionExpiredException();
    }
    if (!_staff!.can(permission)) throw PermissionDeniedException(permission);
  }

  /// Ends an expired session. The admin shell calls this periodically and
  /// when the app resumes; [require] also checks on every action.
  Future<void> checkExpiry() async {
    final session = _session;
    if (session != null && session.isExpiredAt(_clock())) {
      await signOut(reason: 'Your session expired. Please sign in again.');
    }
  }
}
