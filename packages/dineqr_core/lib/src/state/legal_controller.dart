import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/legal.dart';
import '../repositories/legal_repository.dart';
import 'catalog_controller.dart';

/// Why accepting failed, in words a guest can act on.
class LegalAcceptanceException implements Exception {
  const LegalAcceptanceException(this.message, {this.versionChanged = false});

  final String message;

  /// A document was updated while the guest was reading it: the new version
  /// has been loaded and must be accepted instead.
  final bool versionChanged;

  @override
  String toString() => 'LegalAcceptanceException($message)';
}

/// The guest side of the Terms & Conditions and Privacy Policy: the
/// published documents (from the server, never built into the app) and
/// what the guest's session has accepted. The server checks acceptance on
/// every order, so this only lets the app ask for it up front.
class LegalController extends ChangeNotifier {
  LegalController(this._repository);

  final LegalRepository _repository;

  /// False without a server (the offline demo): nothing to show or accept.
  bool get isAvailable => _repository.isAvailable;

  List<LegalDocument> _documents = const [];
  LoadState? _documentsState;
  String? _documentsError;
  LegalStatus? _status;
  bool _accepting = false;

  List<LegalDocument> get documents => _documents;

  /// Null until the documents were first asked for.
  LoadState? get documentsState => _documentsState;
  String? get documentsError => _documentsError;

  /// The guest session's status; null until read (or after the session
  /// changed).
  LegalStatus? get status => _status;
  bool get isAccepting => _accepting;

  LegalDocument? document(LegalDocumentKind kind) {
    for (final d in _documents) {
      if (d.kind == kind) return d;
    }
    return null;
  }

  Future<void>? _loading;

  /// Loads the published documents (again, with [force]).
  Future<void> loadDocuments({bool force = false}) {
    if (!force && _documentsState == LoadState.ready) return Future.value();
    return _loading ??= () async {
      _documentsState = LoadState.loading;
      _documentsError = null;
      notifyListeners();
      try {
        _documents = await _repository.published();
        _documentsState = LoadState.ready;
      } on ApiException catch (error) {
        _documentsState = LoadState.error;
        _documentsError = error.isOffline
            ? 'You are offline. Check your connection and try again.'
            : 'The document could not be loaded. Please try again.';
      } finally {
        _loading = null;
        notifyListeners();
      }
    }();
  }

  /// Reads what the guest session must still accept. Returns null (and
  /// keeps the last status) when the server cannot be asked; the server
  /// still checks when the order is placed.
  Future<LegalStatus?> refreshStatus() async {
    try {
      _status = await _repository.status();
      notifyListeners();
    } on ApiException catch (error) {
      debugPrint('Legal status not loaded: ${error.code}');
    }
    return _status;
  }

  /// Records that the guest accepted [documents]. When one was updated
  /// meanwhile, reloads the documents and status and throws a
  /// [LegalAcceptanceException] with `versionChanged`.
  Future<LegalStatus> accept(List<LegalRequirement> documents) async {
    if (documents.isEmpty) return _status ?? LegalStatus.none;
    _accepting = true;
    notifyListeners();
    try {
      _status = await _repository.accept(documents);
      return _status!;
    } on ApiException catch (error) {
      if (error.code == 'legalVersionChanged') {
        await Future.wait([loadDocuments(force: true), refreshStatus()]);
        throw LegalAcceptanceException(error.message, versionChanged: true);
      }
      throw LegalAcceptanceException(
        error.isOffline
            ? 'You are offline. Check your connection and try again.'
            : error.isUnauthorized
            ? 'Your ordering session has ended. Scan the QR code again to '
                  'continue.'
            : error.message,
      );
    } finally {
      _accepting = false;
      notifyListeners();
    }
  }

  /// A new (or no) guest session: its acceptances are its own.
  void sessionChanged() {
    if (_status == null) return;
    _status = null;
    notifyListeners();
  }

  /// The restaurant may have published a new version.
  Future<void> documentsChanged() async {
    if (_documentsState != null) await loadDocuments(force: true);
    if (_status != null) await refreshStatus();
  }
}
