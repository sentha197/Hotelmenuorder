import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/modules/dashboard/dashboard_screen.dart';
import 'package:dineqr_admin/modules/legal/legal_editor_screen.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// Stands in for the server's document stored and acceptance records,
/// with its rules: one published version per kind, drafts editable,
/// published text locked.
class _Server implements LegalAdminRepository {
  final stored = <LegalDocumentVersion>[
    LegalDocumentVersion(
      id: 1,
      kind: LegalDocumentKind.terms,
      version: 1,
      title: 'Terms & Conditions',
      body: '## 1. Acceptance\n\nBy ordering you accept these terms.',
      status: LegalDocumentStatus.published,
      publishedAt: DateTime(2026, 11, 1, 9),
      publishedBy: 'DineQR',
      acceptances: 2,
    ),
    LegalDocumentVersion(
      id: 2,
      kind: LegalDocumentKind.privacy,
      version: 1,
      title: 'Privacy Policy',
      body: '## 1. What we collect\n\nOnly what your order needs.',
      status: LegalDocumentStatus.published,
      publishedAt: DateTime(2026, 11, 1, 9),
      acceptances: 2,
    ),
  ];
  final records = [
    LegalAcceptanceRecord(
      id: 1,
      hotelId: 1,
      customerId: '6f1c2d3e-0000-4000-8000-000000000001',
      tableNumber: 5,
      kind: LegalDocumentKind.terms,
      version: 1,
      title: 'Terms & Conditions',
      accepted: true,
      acceptedAt: DateTime(2026, 11, 2, 19, 30),
    ),
    LegalAcceptanceRecord(
      id: 2,
      hotelId: 1,
      customerId: '6f1c2d3e-0000-4000-8000-000000000001',
      tableNumber: 5,
      kind: LegalDocumentKind.privacy,
      version: 1,
      title: 'Privacy Policy',
      accepted: true,
      acceptedAt: DateTime(2026, 11, 2, 19, 30),
    ),
    LegalAcceptanceRecord(
      id: 3,
      hotelId: 1,
      customerId: 'a9b8c7d6-0000-4000-8000-000000000002',
      kind: LegalDocumentKind.terms,
      version: 1,
      title: 'Terms & Conditions',
      accepted: true,
      acceptedAt: DateTime(2026, 11, 3, 12, 5),
    ),
  ];
  final history = <({LegalDocumentKind? kind, String? customer})>[];

  @override
  bool get isAvailable => true;

  @override
  Future<List<LegalDocumentVersion>> versions() async => [...stored];

  LegalDocumentVersion _with(
    LegalDocumentVersion v, {
    LegalDocumentDraft? draft,
    LegalDocumentStatus? status,
  }) => LegalDocumentVersion(
    id: v.id,
    kind: v.kind,
    version: v.version,
    title: draft?.title ?? v.title,
    body: draft?.body ?? v.body,
    changeSummary: draft?.changeSummary ?? v.changeSummary,
    requiresReacceptance: draft?.requiresReacceptance ?? v.requiresReacceptance,
    status: status ?? v.status,
    publishedAt: status == LegalDocumentStatus.published
        ? DateTime(2026, 11, 8, 10)
        : v.publishedAt,
    retiredAt: status == LegalDocumentStatus.retired
        ? DateTime(2026, 11, 8, 10)
        : v.retiredAt,
    acceptances: v.acceptances,
  );

  void _replace(LegalDocumentVersion v) =>
      stored[stored.indexWhere((x) => x.id == v.id)] = v;

  @override
  Future<LegalDocumentVersion> create(LegalDocumentDraft draft) async {
    final next =
        stored
            .where((v) => v.kind == draft.kind)
            .fold(0, (m, v) => v.version > m ? v.version : m) +
        1;
    final created = _with(
      LegalDocumentVersion(
        id: stored.length + 1,
        kind: draft.kind,
        version: next,
        title: '',
        body: '',
        status: LegalDocumentStatus.draft,
      ),
      draft: draft,
    );
    stored.add(created);
    return created;
  }

  @override
  Future<LegalDocumentVersion> update(int id, LegalDocumentDraft draft) async {
    final v = stored.firstWhere((x) => x.id == id);
    if (!v.isDraft) throw const ValidationException('Locked.');
    final updated = _with(v, draft: draft);
    _replace(updated);
    return updated;
  }

  @override
  Future<void> delete(int id) async => stored.removeWhere((x) => x.id == id);

  @override
  Future<LegalDocumentVersion> publish(int id) async {
    final v = stored.firstWhere((x) => x.id == id);
    for (final old in [...stored]) {
      if (old.kind == v.kind && old.isPublished) {
        _replace(_with(old, status: LegalDocumentStatus.retired));
      }
    }
    final published = _with(v, status: LegalDocumentStatus.published);
    _replace(published);
    return published;
  }

  @override
  Future<LegalDocumentVersion> unpublish(int id) async {
    final retired = _with(
      stored.firstWhere((x) => x.id == id),
      status: LegalDocumentStatus.retired,
    );
    _replace(retired);
    return retired;
  }

  @override
  Future<List<LegalAcceptanceRecord>> acceptances({
    LegalDocumentKind? kind,
    int? version,
    String? customerId,
    int limit = 300,
  }) async {
    history.add((kind: kind, customer: customerId));
    return [
      for (final r in records.reversed)
        if ((kind == null || r.kind == kind) &&
            (version == null || r.version == version) &&
            (customerId == null || r.customerId == customerId))
          r,
    ];
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(400, 900) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final deps = await createAdminDependencies(legalRepository: server);
  await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
  await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
  await settle(tester, 800);
  Provider.of<AdminShellController>(
    tester.element(find.byType(DashboardScreen)),
    listen: false,
  ).open(AdminModule.legal);
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  testWidgets('the owner writes and publishes a new Terms version', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    expect(find.text('Terms & Privacy'), findsWidgets);
    expect(find.text('Published · version 1'), findsOneWidget);
    expect(find.textContaining('accepted by 2 guests'), findsOneWidget);

    // A new version starts from the published text.
    await _tap(tester, find.text('New version'));
    expect(find.byType(LegalEditorScreen), findsOneWidget);
    expect(
      find.text('## 1. Acceptance\n\nBy ordering you accept these terms.'),
      findsOneWidget,
    );
    final body = find.widgetWithText(TextField, 'Full text');
    await tester.enterText(
      body,
      '## 1. Acceptance\n\nBy ordering you accept these terms.\n\n'
      '## 2. Refunds\n\n- Online payments are refunded to the original method.',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What changed (shown to guests)'),
      'New section on refunds',
    );
    await tester.pump();

    // Preview shows it as guests will read it.
    await _tap(tester, find.text('Preview'));
    expect(find.text('2. Refunds'), findsOneWidget);

    await tester.tap(find.text('Save draft'));
    await settle(tester, 800);
    final draft = server.stored.last;
    expect(draft.version, 2);
    expect(draft.isDraft, isTrue);
    expect(draft.changeSummary, 'New section on refunds');
    expect(draft.requiresReacceptance, isTrue);
    expect(find.text('Version 2 · draft'), findsOneWidget);

    // Publishing asks first and says guests must accept it again.
    await _tap(tester, find.text('Publish'));
    expect(find.textContaining('every guest must accept it'), findsOneWidget);
    await tester.tap(find.text('Publish').last);
    await settle(tester, 800);
    expect(
      server.stored.firstWhere((v) => v.id == draft.id).isPublished,
      isTrue,
    );
    expect(find.text('Published · version 2'), findsOneWidget);
    expect(find.text('Earlier versions'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);
  });

  testWidgets('unpublishing warns that guests are no longer asked', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);
    await _tap(tester, find.text('Privacy Policy').first);
    await _tap(tester, find.text('Unpublish'));
    expect(find.textContaining('will not be asked to accept'), findsOneWidget);
    await tester.tap(find.text('Unpublish').last);
    await settle(tester, 800);
    expect(
      find.textContaining('No Privacy Policy is published'),
      findsOneWidget,
    );
  });

  testWidgets('the acceptance history shows who accepted what and when', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);
    await _tap(tester, find.text('Acceptance history'));
    expect(find.text('3 records'), findsOneWidget);
    expect(find.text('Terms & Conditions · version 1'), findsNWidgets(2));
    expect(find.textContaining('Table 05 · guest 6f1c2d3e'), findsNWidgets(2));
    expect(find.textContaining('Takeaway · guest a9b8c7d6'), findsOneWidget);

    // One guest's records.
    await _tap(tester, find.textContaining('Takeaway · guest a9b8c7d6'));
    expect(
      server.history.last.customer,
      'a9b8c7d6-0000-4000-8000-000000000002',
    );
    expect(find.text('1 record'), findsOneWidget);
    expect(find.text('Guest a9b8c7d6'), findsOneWidget);

    // By document.
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    await _tap(tester, find.text('Privacy Policy').last);
    expect(server.history.last.kind, LegalDocumentKind.privacy);
    expect(find.text('1 record'), findsOneWidget);
  });
}
