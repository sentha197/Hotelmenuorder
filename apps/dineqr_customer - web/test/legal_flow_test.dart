import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:dineqr_customer/app/dependencies.dart';
import 'package:dineqr_customer/app/routes.dart';
import 'package:dineqr_customer/features/legal/legal_document_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show scanDemoTable, settle, usePhoneScreen;

/// Stands in for the server's documents and acceptance records: it keeps
/// what the guest accepted and answers as the API does.
class _Server implements LegalRepository {
  int termsVersion = 2;
  int privacyVersion = 1;
  final accepted = <LegalDocumentKind, int>{};
  final calls = <List<String>>[];

  /// Answer `legalVersionChanged` to the next accept, as when staff
  /// publish a new version while the guest is reading.
  bool replaceTermsOnAccept = false;

  @override
  bool get isAvailable => true;

  int _version(LegalDocumentKind kind) =>
      kind == LegalDocumentKind.terms ? termsVersion : privacyVersion;

  @override
  Future<List<LegalDocument>> published() async => [
    for (final kind in LegalDocumentKind.values)
      LegalDocument(
        kind: kind,
        version: _version(kind),
        title: kind.label,
        body:
            '## 1. Section about ${kind.name}\n\nText of version '
            '${_version(kind)}.\n\n- A bullet point',
        changeSummary: kind == LegalDocumentKind.terms ? 'New refunds' : '',
        publishedAt: DateTime(2026, 11, 1),
      ),
  ];

  @override
  Future<LegalStatus> status() async {
    final documents = [
      for (final kind in LegalDocumentKind.values)
        LegalRequirement(
          kind: kind,
          version: _version(kind),
          title: kind.label,
          required: (accepted[kind] ?? 0) < _version(kind),
          acceptedVersion: accepted[kind],
          changeSummary: kind == LegalDocumentKind.terms ? 'New refunds' : '',
        ),
    ];
    return LegalStatus(
      canOrder: documents.every((d) => !d.required),
      documents: documents,
    );
  }

  @override
  Future<LegalStatus> accept(List<LegalRequirement> documents) async {
    calls.add([for (final d in documents) '${d.kind.name}:${d.version}']);
    if (replaceTermsOnAccept) {
      replaceTermsOnAccept = false;
      termsVersion++;
      throw const ApiException(
        409,
        'legalVersionChanged',
        'The Terms & Conditions has just been updated. Please read the '
            'current version.',
      );
    }
    for (final d in documents) {
      if (d.version != _version(d.kind)) {
        throw const ApiException(409, 'legalVersionChanged', 'Changed.');
      }
      accepted[d.kind] = d.version;
    }
    return status();
  }
}

Future<CustomerDependencies> _dependencies(_Server server) =>
    CustomerDependencies.create(
      store: MemoryStore(),
      config: const CustomerConfig(enableCamera: false),
      menuLatency: Duration.zero,
      orderLatency: const Duration(milliseconds: 300),
      paymentTime: const Duration(milliseconds: 300),
      seedDemoData: false,
      legalRepository: server,
    );

/// Scans Table 12, puts one dish in the cart and opens the order summary.
Future<void> _toSummary(WidgetTester tester, CustomerDependencies deps) async {
  await scanDemoTable(tester, 'Table 12');
  expect(find.text('Terms & Conditions'), findsOneWidget);
  expect(find.text('Privacy Policy'), findsOneWidget);
  await tester.tap(find.text('Start Ordering'));
  await settle(tester, 800);
  deps.cart.quickAdd(deps.catalog.allItems.first);
  deps.navigatorKey.currentState!.pushNamed(Routes.summary);
  await settle(tester, 800);
  expect(find.text('Order Summary'), findsOneWidget);
}

Finder _placeOrder() => find.textContaining('Place Order ·');

bool _enabled(WidgetTester tester) =>
    tester
        .widget<PrimaryButton>(
          find.ancestor(
            of: _placeOrder(),
            matching: find.byType(PrimaryButton),
          ),
        )
        .onPressed !=
    null;

Future<void> _tick(WidgetTester tester, String statement) async {
  final box = find.text(statement);
  await tester.ensureVisible(box);
  await tester.tap(box);
  await tester.pump();
}

const _terms = 'I have read and accept the Terms & Conditions.';
const _privacy = 'I have read and acknowledge the Privacy Policy.';

void main() {
  testWidgets('a guest accepts both documents before their first order', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final server = _Server();
    final deps = await _dependencies(server);
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await _toSummary(tester, deps);

    // Nothing is ticked in advance, and the order cannot be placed.
    expect(find.text('Before you order'), findsOneWidget);
    expect(find.text(_terms), findsOneWidget);
    expect(find.text(_privacy), findsOneWidget);
    expect(find.text('Tick both boxes above to place your order.'), findsOne);
    expect(_enabled(tester), isFalse);

    await _tick(tester, _terms);
    expect(_enabled(tester), isFalse);
    await _tick(tester, _privacy);
    expect(_enabled(tester), isTrue);

    // The full document opens from its link, as the server published it.
    final read = find.text('Read the Terms & Conditions (v2)');
    await tester.ensureVisible(read);
    await tester.tap(read);
    await settle(tester, 800);
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.text('1. Section about terms'), findsOneWidget);
    expect(find.text('Version 2 · Effective 1 Nov 2026'), findsOneWidget);
    expect(find.text('What changed: New refunds'), findsOneWidget);
    deps.navigatorKey.currentState!.pop();
    await settle(tester, 800);

    // Placing the order records both acceptances first.
    await tester.ensureVisible(_placeOrder());
    await tester.tap(_placeOrder());
    await settle(tester, 400);
    await settle(tester, 1200);
    expect(server.calls, [
      ['terms:2', 'privacy:1'],
    ]);
    expect(find.text('Order Placed\nSuccessfully!'), findsOneWidget);
    expect(deps.legal.status!.canOrder, isTrue);

    // Their next order in the same session asks for nothing.
    deps.cart.quickAdd(deps.catalog.allItems.first);
    deps.navigatorKey.currentState!.pushNamed(Routes.summary);
    await settle(tester, 800);
    expect(find.text(_terms), findsNothing);
    expect(_enabled(tester), isTrue);
    expect(find.text('Your order is placed under our'), findsOneWidget);
  });

  testWidgets('a document updated while reading must be read again', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final server = _Server()..replaceTermsOnAccept = true;
    final deps = await _dependencies(server);
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await _toSummary(tester, deps);

    await _tick(tester, _terms);
    await _tick(tester, _privacy);
    await tester.ensureVisible(_placeOrder());
    await tester.tap(_placeOrder());
    await settle(tester, 600);

    // No order; the boxes are cleared and the new version is offered.
    expect(deps.orders.orders, isEmpty);
    expect(find.textContaining('has just been updated'), findsOneWidget);
    expect(find.text('Read the Terms & Conditions (v3)'), findsOneWidget);
    expect(_enabled(tester), isFalse);

    await _tick(tester, _terms);
    await _tick(tester, _privacy);
    await tester.ensureVisible(_placeOrder());
    await tester.tap(_placeOrder());
    await settle(tester, 400);
    await settle(tester, 1200);
    expect(server.calls.last, ['terms:3', 'privacy:1']);
    expect(find.text('Order Placed\nSuccessfully!'), findsOneWidget);
  });

  testWidgets('a material update asks a returning guest again', (tester) async {
    usePhoneScreen(tester);
    final server = _Server()
      ..accepted[LegalDocumentKind.terms] = 1
      ..accepted[LegalDocumentKind.privacy] = 1;
    final deps = await _dependencies(server);
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await _toSummary(tester, deps);

    // Only the updated Terms, with what changed.
    expect(find.text('We have updated our terms'), findsOneWidget);
    expect(find.text(_terms), findsOneWidget);
    expect(find.text(_privacy), findsNothing);
    expect(find.text('What changed: New refunds'), findsOneWidget);
    expect(find.text('Tick the box above to place your order.'), findsOne);
    await _tick(tester, _terms);
    expect(_enabled(tester), isTrue);
  });

  testWidgets('the offline demo asks for nothing and says why', (tester) async {
    usePhoneScreen(tester);
    final deps = await CustomerDependencies.create(
      store: MemoryStore(),
      config: const CustomerConfig(enableCamera: false),
      menuLatency: Duration.zero,
      orderLatency: const Duration(milliseconds: 300),
      seedDemoData: false,
    );
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await scanDemoTable(tester, 'Table 12');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 800);
    deps.cart.quickAdd(deps.catalog.allItems.first);
    deps.navigatorKey.currentState!.pushNamed(Routes.summary);
    await settle(tester, 800);
    expect(find.text(_terms), findsNothing);
    expect(_enabled(tester), isTrue);

    deps.navigatorKey.currentState!.pushNamed(
      Routes.legal,
      arguments: LegalDocumentKind.privacy,
    );
    await settle(tester, 800);
    expect(find.text('Not published'), findsOneWidget);
  });
}
