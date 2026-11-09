import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';

import 'admin_session_controller.dart';

/// Terms & Conditions and Privacy Policy as staff manage them: every
/// version (drafts, the published one, retired ones), publishing, and the
/// guests' acceptance history. The server enforces who may do what; this
/// only mirrors it so the screens can hide what a role cannot do.
class LegalAdminController extends ChangeNotifier {
  LegalAdminController(this._repository, this._admin);

  final LegalAdminRepository _repository;
  final AdminSessionController _admin;

  /// False without a server (the offline demo).
  bool get isAvailable => _repository.isAvailable;

  /// Writing, publishing and unpublishing versions.
  bool get canEdit => _admin.can(Permission.manageSettings);

  /// Reading versions and the acceptance history (the server also lets
  /// those who read the activity log see it).
  bool get canView => canEdit || _admin.can(Permission.viewAuditLog);

  List<LegalDocumentVersion> _versions = const [];
  List<LegalAcceptanceRecord> _acceptances = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<LegalDocumentVersion> get versions => _versions;
  List<LegalAcceptanceRecord> get acceptances => _acceptances;
  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  String? get error => _error;

  /// Every version of [kind], newest first.
  List<LegalDocumentVersion> versionsOf(LegalDocumentKind kind) => [
    for (final v in _versions)
      if (v.kind == kind) v,
  ]..sort((a, b) => b.version.compareTo(a.version));

  LegalDocumentVersion? publishedOf(LegalDocumentKind kind) {
    for (final v in _versions) {
      if (v.kind == kind && v.isPublished) return v;
    }
    return null;
  }

  /// The version a new draft starts from: the published one, else the
  /// newest.
  LegalDocumentVersion? baseFor(LegalDocumentKind kind) {
    final all = versionsOf(kind);
    return publishedOf(kind) ?? (all.isEmpty ? null : all.first);
  }

  /// Versions and the latest acceptances. Quietly does nothing without a
  /// server or the permission.
  Future<void> load() async {
    if (!isAvailable || !_admin.isSignedIn || !canView) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.versions(),
        _repository.acceptances(),
      ]);
      _versions = results[0] as List<LegalDocumentVersion>;
      _acceptances = results[1] as List<LegalAcceptanceRecord>;
      _loaded = true;
    } on ValidationException catch (error) {
      _error = error.message;
    } on ApiException catch (error) {
      _error = error.isOffline
          ? 'You are offline. Check the connection and try again.'
          : error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The acceptance history, filtered (all of it with no filters).
  Future<List<LegalAcceptanceRecord>> history({
    LegalDocumentKind? kind,
    int? version,
    String? customerId,
  }) => _repository.acceptances(
    kind: kind,
    version: version,
    customerId: customerId,
    limit: 1000,
  );

  Future<T> _change<T>(Future<T> Function() action) async {
    if (!canEdit) {
      throw const PermissionDeniedException(Permission.manageSettings);
    }
    final result = await action();
    _versions = await _repository.versions();
    notifyListeners();
    return result;
  }

  Future<LegalDocumentVersion> create(LegalDocumentDraft draft) =>
      _change(() => _repository.create(draft));

  Future<LegalDocumentVersion> update(int id, LegalDocumentDraft draft) =>
      _change(() => _repository.update(id, draft));

  Future<void> delete(int id) => _change(() => _repository.delete(id));

  Future<LegalDocumentVersion> publish(int id) =>
      _change(() => _repository.publish(id));

  Future<LegalDocumentVersion> unpublish(int id) =>
      _change(() => _repository.unpublish(id));
}
