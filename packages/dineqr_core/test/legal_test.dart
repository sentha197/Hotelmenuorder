import 'dart:convert';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _config = ApiConfig(baseUrl: Uri.parse('http://api.test'));

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _item(
  String kind,
  int version, {
  bool required = true,
  int? accepted,
}) => {
  'kind': kind,
  'version': version,
  'title': kind == 'terms' ? 'Terms & Conditions' : 'Privacy Policy',
  'changeSummary': '',
  'publishedAt': '2026-11-01T10:00:00Z',
  'required': required,
  'acceptedVersion': accepted,
  'acceptedAt': accepted == null ? null : '2026-11-02T10:00:00Z',
};

void main() {
  group('LegalText', () {
    test('reads headings, paragraphs, bullets and bold text', () {
      final blocks = LegalText.parse(
        '## 1. Scope\n\nFirst line\ncontinues here.\n\n'
        '- **Orders:** what you order\n* second\n\nLast.',
      );
      expect(blocks, hasLength(5));
      expect(blocks[0], isA<LegalHeading>());
      expect(blocks[0].text, '1. Scope');
      expect(blocks[1], isA<LegalParagraph>());
      expect(blocks[1].text, 'First line continues here.');
      expect(blocks[2], isA<LegalBullet>());
      expect(blocks[2].spans, const [
        LegalSpan('Orders:', bold: true),
        LegalSpan(' what you order'),
      ]);
      expect(blocks[3].text, 'second');
      expect(blocks[4].text, 'Last.');
    });

    test('anything else stays plain text', () {
      final blocks = LegalText.parse('<script>x</script> [link](http://x)');
      expect(blocks.single.text, '<script>x</script> [link](http://x)');
    });
  });

  group('HttpLegalRepository', () {
    test('reads the published documents and the guest status', () async {
      final api = ApiClient(
        _config,
        client: MockClient((request) async {
          return switch (request.url.path) {
            '/api/v1/legal/documents' => _json([
              {
                'kind': 'terms',
                'version': 3,
                'title': 'Terms & Conditions',
                'body': '## Hello',
                'changeSummary': 'New payment section',
                'publishedAt': '2026-11-01T10:00:00Z',
              },
              // A kind this app does not know is skipped.
              {'kind': 'cookies', 'version': 1, 'title': 'x', 'body': 'y'},
            ]),
            '/api/v1/guest/legal' => _json({
              'canOrder': false,
              'documents': [
                _item('terms', 3, accepted: 2),
                _item('privacy', 1, required: false, accepted: 1),
              ],
            }),
            _ => _json(null, 404),
          };
        }),
      );
      final repository = HttpLegalRepository(api);
      final documents = await repository.published();
      expect(documents.single.kind, LegalDocumentKind.terms);
      expect(documents.single.version, 3);
      expect(documents.single.changeSummary, 'New payment section');

      final status = await repository.status();
      expect(status.canOrder, isFalse);
      expect(status.pending.single.kind, LegalDocumentKind.terms);
      expect(status.of(LegalDocumentKind.terms)!.isUpdate, isTrue);
      expect(status.of(LegalDocumentKind.privacy)!.required, isFalse);
    });

    test('sends the kind and version of each accepted document', () async {
      Object? sent;
      final api = ApiClient(
        _config,
        client: MockClient((request) async {
          sent = jsonDecode(request.body);
          return _json({
            'canOrder': true,
            'documents': [
              _item('terms', 3, required: false, accepted: 3),
              _item('privacy', 2, required: false, accepted: 2),
            ],
          });
        }),
      );
      final status = await HttpLegalRepository(api).accept([
        LegalRequirement.fromJson(_item('terms', 3)),
        LegalRequirement.fromJson(_item('privacy', 2)),
      ]);
      expect(status.canOrder, isTrue);
      expect(sent, {
        'documents': [
          {'kind': 'terms', 'version': 3},
          {'kind': 'privacy', 'version': 2},
        ],
      });
    });

    test('a server from before the documents asks for nothing', () async {
      final api = ApiClient(
        _config,
        client: MockClient((_) async => _json(null, 404)),
      );
      final repository = HttpLegalRepository(api);
      expect(await repository.published(), isEmpty);
      expect((await repository.status()).canOrder, isTrue);
    });
  });

  group('LegalController', () {
    test('a version replaced while reading is reloaded and reported', () async {
      var version = 3;
      final api = ApiClient(
        _config,
        client: MockClient((request) async {
          if (request.method == 'POST') {
            version = 4;
            return _json({
              'status': 409,
              'title': 'The Terms & Conditions has just been updated.',
              'code': 'legalVersionChanged',
            }, 409);
          }
          return switch (request.url.path) {
            '/api/v1/legal/documents' => _json([
              {
                'kind': 'terms',
                'version': version,
                'title': 'Terms & Conditions',
                'body': 'Text',
              },
            ]),
            _ => _json({
              'canOrder': false,
              'documents': [_item('terms', version)],
            }),
          };
        }),
      );
      final controller = LegalController(HttpLegalRepository(api));
      await controller.loadDocuments();
      final status = await controller.refreshStatus();
      expect(status!.pending.single.version, 3);

      await expectLater(
        controller.accept(status.pending),
        throwsA(
          isA<LegalAcceptanceException>().having(
            (e) => e.versionChanged,
            'versionChanged',
            isTrue,
          ),
        ),
      );
      expect(controller.status!.pending.single.version, 4);
      expect(controller.document(LegalDocumentKind.terms)!.version, 4);
      expect(controller.isAccepting, isFalse);
    });

    test('the offline demo has nothing to accept', () async {
      final controller = LegalController(const UnavailableLegalRepository());
      expect(controller.isAvailable, isFalse);
      expect((await controller.refreshStatus())!.canOrder, isTrue);
      await controller.loadDocuments();
      expect(controller.documents, isEmpty);
    });
  });
}
