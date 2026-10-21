import 'package:flutter/foundation.dart';

import '../core/utils/restaurant_time.dart';
import '../data/models/staff.dart';
import '../data/repositories/staff_repository.dart';
import '../data/services/auth_service.dart';
import 'admin_session_controller.dart';
import 'settings_controller.dart';

/// Staff accounts and roles (owner only), plus the activity log.
class StaffController extends ChangeNotifier {
  StaffController(
    this._repository,
    this._guard,
    this._audit, {
    this._onAccountChanged,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final StaffRepository _repository;
  final AccessGuard _guard;
  final AuditLog _audit;
  final void Function(StaffAccount account)? _onAccountChanged;
  final DateTime Function() _clock;

  List<StaffAccount> _staff = const [];
  List<AuditEvent> _events = const [];

  List<StaffAccount> get staff => _staff;

  List<AuditEvent> get events => _events;

  StaffAccount? byId(String id) => _staff.where((s) => s.id == id).firstOrNull;

  Future<void> load() async {
    _staff = [...await _repository.fetchStaff()]
      ..sort((a, b) => a.role.index.compareTo(b.role.index));
    notifyListeners();
  }

  /// Refreshes the activity log (needs [Permission.viewAuditLog]).
  Future<void> loadEvents() async {
    _guard.require(Permission.viewAuditLog);
    _events = await _repository.fetchAudit();
    notifyListeners();
  }

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<StaffAccount> addStaff({
    required String name,
    required String email,
    required StaffRole role,
    required String password,
  }) async {
    _guard.require(Permission.manageStaff);
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanName.length < 2 || cleanName.length > 40) {
      throw const ValidationException('Name must be 2 to 40 characters.');
    }
    if (!_email.hasMatch(cleanEmail)) {
      throw const ValidationException('Enter a valid email address.');
    }
    if (_staff.any((s) => s.email == cleanEmail)) {
      throw const ValidationException('An account with this email exists.');
    }
    final weak = PasswordHasher.validateNew(password);
    if (weak != null) throw ValidationException(weak);
    final salt = PasswordHasher.newSalt();
    final account = StaffAccount(
      id: Ids.sequential('STF', _staff.map((s) => s.id), width: 3),
      name: cleanName,
      email: cleanEmail,
      role: role,
      passwordHash: PasswordHasher.hash(password, salt),
      salt: salt,
      createdAt: _clock(),
    );
    await _repository.saveStaff(account);
    await load();
    await _audit.record(
      'staff.create',
      'Added ${account.name} as ${role.label}',
      targetId: account.id,
    );
    return account;
  }

  bool _isLastActiveOwner(StaffAccount account) =>
      account.role == StaffRole.owner &&
      account.isActive &&
      _staff.where((s) => s.role == StaffRole.owner && s.isActive).length == 1;

  Future<void> changeRole(String staffId, StaffRole role) async {
    _guard.require(Permission.manageStaff);
    final account = byId(staffId);
    if (account == null || account.role == role) return;
    if (account.id == _guard.actor?.id) {
      throw const ValidationException('You cannot change your own role.');
    }
    if (_isLastActiveOwner(account)) {
      throw const ValidationException('Keep at least one active owner.');
    }
    final updated = account.copyWith(role: role);
    await _repository.saveStaff(updated);
    await load();
    _onAccountChanged?.call(updated);
    await _audit.record(
      'staff.role',
      '${account.name}: ${account.role.label} → ${role.label}',
      targetId: staffId,
    );
  }

  Future<void> setActive(String staffId, bool active) async {
    _guard.require(Permission.manageStaff);
    final account = byId(staffId);
    if (account == null || account.isActive == active) return;
    if (account.id == _guard.actor?.id) {
      throw const ValidationException('You cannot deactivate yourself.');
    }
    if (!active && _isLastActiveOwner(account)) {
      throw const ValidationException('Keep at least one active owner.');
    }
    final updated = account.copyWith(isActive: active);
    await _repository.saveStaff(updated);
    await load();
    _onAccountChanged?.call(updated);
    await _audit.record(
      active ? 'staff.activate' : 'staff.deactivate',
      '${active ? 'Activated' : 'Deactivated'} ${account.name}',
      targetId: staffId,
    );
  }

  Future<void> resetPassword(String staffId, String password) async {
    _guard.require(Permission.manageStaff);
    final account = byId(staffId);
    if (account == null) return;
    final weak = PasswordHasher.validateNew(password);
    if (weak != null) throw ValidationException(weak);
    final salt = PasswordHasher.newSalt();
    await _repository.saveStaff(
      account.copyWith(
        passwordHash: PasswordHasher.hash(password, salt),
        salt: salt,
      ),
    );
    await load();
    await _audit.record(
      'staff.password',
      'Reset the password of ${account.name}',
      targetId: staffId,
    );
  }

  /// Restores the demo accounts and clears the activity log.
  Future<void> resetDemo() async {
    await _repository.reset();
    await load();
    _events = const [];
    notifyListeners();
  }
}
