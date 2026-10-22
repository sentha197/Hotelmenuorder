import '../models/staff.dart';
import '../repositories/staff_repository.dart';
import '../utils/restaurant_time.dart';

/// Thrown when the signed-in staff member may not perform an action.
class PermissionDeniedException implements Exception {
  const PermissionDeniedException(this.permission);

  final Permission permission;

  String get message =>
      'You do not have permission to ${permission.label.toLowerCase()}.';

  @override
  String toString() => 'PermissionDeniedException(${permission.name})';
}

/// Thrown when an admin action runs without a valid session.
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  String get message => 'Your session has ended. Please sign in again.';

  @override
  String toString() => 'SessionExpiredException';
}

/// Checks permissions for privileged actions. Controllers call [require]
/// before every admin change, so hiding a button is never the only guard.
abstract interface class AccessGuard {
  StaffAccount? get actor;

  /// Throws [SessionExpiredException] or [PermissionDeniedException].
  void require(Permission permission);

  bool can(Permission permission);
}

/// Records sensitive actions with the acting staff member.
class AuditLog {
  AuditLog(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final StaffRepository _repository;
  final DateTime Function() _clock;
  AccessGuard? guard;

  Future<void> record(
    String action,
    String summary, {
    String targetId = '',
    StaffAccount? actor,
  }) {
    final who = actor ?? guard?.actor;
    return _repository.appendAudit(
      AuditEvent(
        id: 'EVT${_clock().microsecondsSinceEpoch}${Ids.random(4)}',
        at: _clock(),
        actorId: who?.id ?? 'system',
        actorName: who?.name ?? 'System',
        actorRole: who?.role.label ?? 'Automatic',
        action: action,
        summary: summary,
        targetId: targetId,
      ),
    );
  }

  Future<List<AuditEvent>> events() => _repository.fetchAudit();
}

/// Access guard for the guest app: nobody is signed in, so every
/// privileged action is refused. Guest actions (placing an order, paying a
/// bill, rating) need no permission and never consult the guard.
class GuestAccess implements AccessGuard {
  const GuestAccess();

  @override
  StaffAccount? get actor => null;

  @override
  bool can(Permission permission) => false;

  @override
  void require(Permission permission) =>
      throw PermissionDeniedException(permission);
}
