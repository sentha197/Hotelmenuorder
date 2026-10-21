import '../models/staff.dart';
import '../storage/key_value_store.dart';

/// Staff accounts and the audit trail. A production backend owns both: it
/// stores credentials, enforces roles on every request and keeps an
/// append-only audit log.
abstract interface class StaffRepository {
  Future<List<StaffAccount>> fetchStaff();

  Future<void> saveStaff(StaffAccount account);

  Future<List<AuditEvent>> fetchAudit();

  Future<void> appendAudit(AuditEvent event);

  Future<void> reset();
}

class LocalStaffRepository implements StaffRepository {
  LocalStaffRepository(KeyValueStore store, {required this.seed})
    : _staff = JsonListStore(
        store,
        StorageKeys.staff,
        StaffAccount.fromJson,
        (s) => s.toJson(),
      ),
      _audit = JsonListStore(
        store,
        StorageKeys.audit,
        AuditEvent.fromJson,
        (e) => e.toJson(),
      );

  /// Keep the most recent events only (demo storage is small).
  static const maxAuditEvents = 500;

  final JsonListStore<StaffAccount> _staff;
  final JsonListStore<AuditEvent> _audit;

  /// Accounts of a fresh install.
  final List<StaffAccount> Function() seed;

  List<StaffAccount>? _accounts;
  List<AuditEvent>? _events;

  List<StaffAccount> get _allStaff => _accounts ??= _staff.read() ?? seed();

  @override
  Future<List<StaffAccount>> fetchStaff() async => List.unmodifiable(_allStaff);

  @override
  Future<void> saveStaff(StaffAccount account) async {
    final exists = _allStaff.any((s) => s.id == account.id);
    _accounts = exists
        ? [for (final s in _allStaff) s.id == account.id ? account : s]
        : [..._allStaff, account];
    await _staff.write(_accounts!);
  }

  @override
  Future<List<AuditEvent>> fetchAudit() async =>
      List.unmodifiable(_events ??= _audit.read() ?? []);

  @override
  Future<void> appendAudit(AuditEvent event) async {
    final events = [event, ...(_events ??= _audit.read() ?? [])];
    _events = events.length > maxAuditEvents
        ? events.sublist(0, maxAuditEvents)
        : events;
    await _audit.write(_events!);
  }

  @override
  Future<void> reset() async {
    _accounts = null;
    _events = null;
    await _staff.clear();
    await _audit.clear();
  }
}
