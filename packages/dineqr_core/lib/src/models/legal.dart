/// The restaurant's Terms & Conditions and Privacy Policy, as published by
/// staff on the server. The apps never hold the text themselves: they show
/// what the server sends.
enum LegalDocumentKind {
  terms('Terms & Conditions', 'accept'),
  privacy('Privacy Policy', 'acknowledge');

  const LegalDocumentKind(this.label, this.verb);

  final String label;

  /// What a guest does with it: accepts the Terms, acknowledges the Privacy
  /// Policy (it informs; the guest confirms they have read it).
  final String verb;

  static LegalDocumentKind? tryParse(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// A published document, placeholders already filled in by the server.
class LegalDocument {
  const LegalDocument({
    required this.kind,
    required this.version,
    required this.title,
    required this.body,
    this.changeSummary = '',
    this.publishedAt,
  });

  factory LegalDocument.fromJson(Map<String, dynamic> json) => LegalDocument(
    kind: LegalDocumentKind.tryParse(json['kind'] as String?)!,
    version: json['version'] as int,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    changeSummary: json['changeSummary'] as String? ?? '',
    publishedAt: _date(json['publishedAt']),
  );

  final LegalDocumentKind kind;
  final int version;
  final String title;

  /// Simple Markdown: see [LegalText].
  final String body;
  final String changeSummary;
  final DateTime? publishedAt;
}

/// One document in a guest's status: the version to accept now and what
/// this guest session has accepted.
class LegalRequirement {
  const LegalRequirement({
    required this.kind,
    required this.version,
    required this.title,
    required this.required,
    this.changeSummary = '',
    this.publishedAt,
    this.acceptedVersion,
    this.acceptedAt,
  });

  factory LegalRequirement.fromJson(Map<String, dynamic> json) =>
      LegalRequirement(
        kind: LegalDocumentKind.tryParse(json['kind'] as String?)!,
        version: json['version'] as int,
        title: json['title'] as String? ?? '',
        required: json['required'] as bool? ?? true,
        changeSummary: json['changeSummary'] as String? ?? '',
        publishedAt: _date(json['publishedAt']),
        acceptedVersion: json['acceptedVersion'] as int?,
        acceptedAt: _date(json['acceptedAt']),
      );

  final LegalDocumentKind kind;
  final int version;
  final String title;

  /// The guest must accept [version] before ordering.
  final bool required;
  final String changeSummary;
  final DateTime? publishedAt;
  final int? acceptedVersion;
  final DateTime? acceptedAt;

  /// The guest accepted an earlier version and this one changed materially.
  bool get isUpdate => required && acceptedVersion != null;
}

/// What a guest session has accepted and still has to.
class LegalStatus {
  const LegalStatus({required this.canOrder, this.documents = const []});

  factory LegalStatus.fromJson(Map<String, dynamic> json) => LegalStatus(
    canOrder: json['canOrder'] as bool? ?? false,
    documents: [
      for (final item in (json['documents'] as List? ?? const []))
        if (LegalDocumentKind.tryParse(
              (item as Map<String, dynamic>)['kind'] as String?,
            ) !=
            null)
          LegalRequirement.fromJson(item),
    ],
  );

  /// Nothing to accept (no documents published, or no server).
  static const none = LegalStatus(canOrder: true);

  final bool canOrder;
  final List<LegalRequirement> documents;

  List<LegalRequirement> get pending => [
    for (final d in documents)
      if (d.required) d,
  ];

  LegalRequirement? of(LegalDocumentKind kind) {
    for (final d in documents) {
      if (d.kind == kind) return d;
    }
    return null;
  }
}

enum LegalDocumentStatus {
  draft('Draft'),
  published('Published'),
  retired('Retired');

  const LegalDocumentStatus(this.label);

  final String label;

  static LegalDocumentStatus parse(String? name) => values.firstWhere(
    (s) => s.name == name,
    orElse: () => LegalDocumentStatus.retired,
  );
}

/// A document version as staff manage it (raw text, placeholders unfilled).
class LegalDocumentVersion {
  const LegalDocumentVersion({
    required this.id,
    required this.kind,
    required this.version,
    required this.title,
    required this.body,
    required this.status,
    this.changeSummary = '',
    this.requiresReacceptance = true,
    this.createdAt,
    this.createdBy = '',
    this.updatedAt,
    this.updatedBy = '',
    this.publishedAt,
    this.publishedBy = '',
    this.retiredAt,
    this.acceptances = 0,
  });

  factory LegalDocumentVersion.fromJson(Map<String, dynamic> json) =>
      LegalDocumentVersion(
        id: json['id'] as int,
        kind: LegalDocumentKind.tryParse(json['kind'] as String?)!,
        version: json['version'] as int,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        status: LegalDocumentStatus.parse(json['status'] as String?),
        changeSummary: json['changeSummary'] as String? ?? '',
        requiresReacceptance: json['requiresReacceptance'] as bool? ?? true,
        createdAt: _date(json['createdAt']),
        createdBy: json['createdBy'] as String? ?? '',
        updatedAt: _date(json['updatedAt']),
        updatedBy: json['updatedBy'] as String? ?? '',
        publishedAt: _date(json['publishedAt']),
        publishedBy: json['publishedBy'] as String? ?? '',
        retiredAt: _date(json['retiredAt']),
        acceptances: json['acceptances'] as int? ?? 0,
      );

  final int id;
  final LegalDocumentKind kind;
  final int version;
  final String title;
  final String body;
  final LegalDocumentStatus status;
  final String changeSummary;

  /// A material change: guests who accepted earlier versions accept again.
  final bool requiresReacceptance;
  final DateTime? createdAt;
  final String createdBy;
  final DateTime? updatedAt;
  final String updatedBy;
  final DateTime? publishedAt;
  final String publishedBy;
  final DateTime? retiredAt;

  /// How many guest sessions accepted this version.
  final int acceptances;

  bool get isDraft => status == LegalDocumentStatus.draft;
  bool get isPublished => status == LegalDocumentStatus.published;
}

/// What staff write for a new version or a draft.
class LegalDocumentDraft {
  const LegalDocumentDraft({
    required this.kind,
    required this.title,
    required this.body,
    this.changeSummary = '',
    this.requiresReacceptance = true,
  });

  final LegalDocumentKind kind;
  final String title;
  final String body;
  final String changeSummary;
  final bool requiresReacceptance;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'title': title,
    'body': body,
    'changeSummary': changeSummary,
    'requiresReacceptance': requiresReacceptance,
  };
}

/// One acceptance record: a guest session (the customer; guests have no
/// accounts) accepted a document version at a time.
class LegalAcceptanceRecord {
  const LegalAcceptanceRecord({
    required this.id,
    required this.hotelId,
    required this.customerId,
    required this.kind,
    required this.version,
    required this.title,
    required this.accepted,
    required this.acceptedAt,
    this.tableNumber,
  });

  factory LegalAcceptanceRecord.fromJson(Map<String, dynamic> json) =>
      LegalAcceptanceRecord(
        id: json['id'] as int,
        hotelId: json['hotelId'] as int? ?? 1,
        customerId: json['customerId'] as String? ?? '',
        tableNumber: json['tableNumber'] as int?,
        kind: LegalDocumentKind.tryParse(json['kind'] as String?)!,
        version: json['version'] as int,
        title: json['title'] as String? ?? '',
        accepted: json['accepted'] as bool? ?? true,
        acceptedAt: _date(json['acceptedAt']) ?? DateTime(2000),
      );

  final int id;
  final int hotelId;

  /// The guest session's id.
  final String customerId;

  /// Null for takeaway.
  final int? tableNumber;
  final LegalDocumentKind kind;
  final int version;
  final String title;
  final bool accepted;
  final DateTime acceptedAt;

  /// The first block of the session id, enough to tell guests apart.
  String get shortCustomerId =>
      customerId.length > 8 ? customerId.substring(0, 8) : customerId;
}
