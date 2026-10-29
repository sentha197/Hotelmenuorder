import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

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

  /// Set in backend mode: the server creates accounts, hashes passwords,
  /// enforces the owner rules and writes the audit entries.
  StaffDirectory? get _directory =>
      _repository is StaffDirectory ? _repository as StaffDirectory : null;

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

  /// The name a [StaffRole.custom] role carries (null for any other role).
  static String? _cleanTitle(StaffRole role, String? title) {
    if (role != StaffRole.custom) return null;
    final clean = (title ?? '').trim();
    if (clean.length < 2 || clean.length > StaffRole.maxTitleLength) {
      throw const ValidationException(
        'Role name must be 2 to ${StaffRole.maxTitleLength} characters.',
      );
    }
    return clean;
  }

  /// [roleTitle] names a [StaffRole.custom] role, e.g. "Officer".
  Future<StaffAccount> addStaff({
    required String name,
    required String email,
    required StaffRole role,
    String? roleTitle,
    required String password,
  }) async {
    _guard.require(Permission.manageStaff);
    final title = _cleanTitle(role, roleTitle);
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
    final directory = _directory;
    if (directory != null) {
      final created = await directory.create(
        name: cleanName,
        email: cleanEmail,
        role: role,
        roleTitle: title,
        password: password,
      );
      await load();
      return created;
    }
    final salt = PasswordHasher.newSalt();
    final account = StaffAccount(
      id: Ids.sequential('STF', _staff.map((s) => s.id), width: 3),
      name: cleanName,
      email: cleanEmail,
      role: role,
      roleTitle: title,
      passwordHash: PasswordHasher.hash(password, salt),
      salt: salt,
      createdAt: _clock(),
    );
    await _repository.saveStaff(account);
    await load();
    await _audit.record(
      'staff.create',
      'Added ${account.name} as ${account.roleLabel}',
      targetId: account.id,
    );
    return account;
  }

  bool _isLastActiveOwner(StaffAccount account) =>
      account.role == StaffRole.owner &&
      account.isActive &&
      _staff.where((s) => s.role == StaffRole.owner && s.isActive).length == 1;

  /// Moves [staffId] to [role]. Naming a custom role again (a new
  /// [roleTitle]) renames it and keeps the access the owner granted; any
  /// other change starts from the new role's own permissions.
  Future<void> changeRole(
    String staffId,
    StaffRole role, {
    String? roleTitle,
  }) async {
    _guard.require(Permission.manageStaff);
    final title = _cleanTitle(role, roleTitle);
    final account = byId(staffId);
    if (account == null) return;
    if (account.role == role && account.roleTitle == title) return;
    if (account.id == _guard.actor?.id) {
      throw const ValidationException('You cannot change your own role.');
    }
    if (account.role != role && _isLastActiveOwner(account)) {
      throw const ValidationException('Keep at least one active owner.');
    }
    final directory = _directory;
    if (directory != null) {
      final updated = await directory.update(
        staffId,
        role: role,
        roleTitle: title,
      );
      await load();
      _onAccountChanged?.call(updated);
      return;
    }
    final updated = account.copyWith(role: role, roleTitle: title);
    await _repository.saveStaff(updated);
    await load();
    _onAccountChanged?.call(updated);
    await _audit.record(
      'staff.role',
      '${account.name}: ${account.roleLabel} → ${updated.roleLabel}',
      targetId: staffId,
    );
  }

  /// Gives [staffId] exactly [permissions] instead of their role's defaults;
  /// null (or choosing what the role already allows) goes back to the
  /// defaults. Only an owner may do this, and owners keep full access.
  Future<void> changeAccess(
    String staffId,
    Set<Permission>? permissions,
  ) async {
    _guard.require(Permission.manageStaff);
    if (_guard.actor?.role != StaffRole.owner) {
      throw const ValidationException(
        'Only an owner can change what someone can access.',
      );
    }
    final account = byId(staffId);
    if (account == null) return;
    if (account.id == _guard.actor?.id) {
      throw const ValidationException('You cannot change your own access.');
    }
    if (account.role == StaffRole.owner) {
      throw const ValidationException('Owners always have full access.');
    }
    final custom =
        permissions == null || setEquals(permissions, account.role.permissions)
        ? null
        : permissions;
    if (custom == null
        ? !account.hasCustomAccess
        : setEquals(custom, account.customPermissions)) {
      return;
    }
    final directory = _directory;
    if (directory != null) {
      final updated = await directory.setAccess(staffId, custom);
      await load();
      _onAccountChanged?.call(updated);
      return;
    }
    final updated = custom == null
        ? account.copyWith(clearCustomPermissions: true)
        : account.copyWith(customPermissions: custom);
    await _repository.saveStaff(updated);
    await load();
    _onAccountChanged?.call(updated);
    final added = updated.permissions.difference(account.role.permissions);
    final removed = account.role.permissions.difference(updated.permissions);
    await _audit.record(
      'staff.access',
      custom == null
          ? '${account.name}: access reset to ${account.roleLabel} defaults'
          : '${account.name}: custom access '
                '(+${added.length} / −${removed.length} vs ${account.roleLabel})',
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
    final directory = _directory;
    if (directory != null) {
      final updated = await directory.update(staffId, active: active);
      await load();
      _onAccountChanged?.call(updated);
      return;
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
    final directory = _directory;
    if (directory != null) {
      await directory.resetPassword(staffId, password);
      return;
    }
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
