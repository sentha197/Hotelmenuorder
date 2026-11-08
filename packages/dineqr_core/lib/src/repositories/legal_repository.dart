import '../models/legal.dart';

/// The guest side: the published documents and this guest session's
/// acceptances. Only a server can record an acceptance (and check it on
/// every order), so the offline demo has none.
abstract interface class LegalRepository {
  /// False when this build has no server (the offline demo).
  bool get isAvailable;

  /// The published Terms & Conditions and Privacy Policy (anyone).
  Future<List<LegalDocument>> published();

  /// What the current guest session has accepted and still must.
  Future<LegalStatus> status();

  /// Records that the guest accepted [documents] (kind and version).
  /// Throws [ApiException] `legalVersionChanged` when one was replaced
  /// meanwhile.
  Future<LegalStatus> accept(List<LegalRequirement> documents);
}

/// Staff: versions, publishing and the acceptance history.
abstract interface class LegalAdminRepository {
  bool get isAvailable;

  Future<List<LegalDocumentVersion>> versions();

  Future<LegalDocumentVersion> create(LegalDocumentDraft draft);

  Future<LegalDocumentVersion> update(int id, LegalDocumentDraft draft);

  Future<void> delete(int id);

  Future<LegalDocumentVersion> publish(int id);

  Future<LegalDocumentVersion> unpublish(int id);

  Future<List<LegalAcceptanceRecord>> acceptances({
    LegalDocumentKind? kind,
    int? version,
    String? customerId,
    int limit = 300,
  });
}

/// Where there is no server (the offline demo): nothing published, nothing
/// to accept.
class UnavailableLegalRepository
    implements LegalRepository, LegalAdminRepository {
  const UnavailableLegalRepository();

  static const _reason =
      'Terms & Conditions and the Privacy Policy are kept on the restaurant '
      'server, which this offline demo does not use.';

  @override
  bool get isAvailable => false;

  @override
  Future<List<LegalDocument>> published() async => const [];

  @override
  Future<LegalStatus> status() async => LegalStatus.none;

  @override
  Future<LegalStatus> accept(List<LegalRequirement> documents) async =>
      LegalStatus.none;

  @override
  Future<List<LegalDocumentVersion>> versions() async => const [];

  @override
  Future<LegalDocumentVersion> create(LegalDocumentDraft draft) =>
      throw StateError(_reason);

  @override
  Future<LegalDocumentVersion> update(int id, LegalDocumentDraft draft) =>
      throw StateError(_reason);

  @override
  Future<void> delete(int id) => throw StateError(_reason);

  @override
  Future<LegalDocumentVersion> publish(int id) => throw StateError(_reason);

  @override
  Future<LegalDocumentVersion> unpublish(int id) => throw StateError(_reason);

  @override
  Future<List<LegalAcceptanceRecord>> acceptances({
    LegalDocumentKind? kind,
    int? version,
    String? customerId,
    int limit = 300,
  }) async => const [];
}
