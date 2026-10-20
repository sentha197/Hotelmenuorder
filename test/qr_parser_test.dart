import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/features/qr_scanner/table_qr_parser.dart';

int? tableOf(String? raw) => switch (TableQrParser.parse(raw)) {
  ValidTableQr(:final tableNumber) => tableNumber,
  InvalidTableQr() => null,
};

TableQrError? errorOf(String? raw) => switch (TableQrParser.parse(raw)) {
  ValidTableQr() => null,
  InvalidTableQr(:final error) => error,
};

void main() {
  group('TableQrParser', () {
    test('accepts the sample payloads and extracts the table number', () {
      expect(tableOf('DINEQR:TABLE:05'), 5);
      expect(tableOf('DINEQR:TABLE:12'), 12);
    });

    test('keeps accepting codes printed before the DineQR rename', () {
      expect(tableOf('BITEANDDINE:TABLE:05'), 5);
      expect(tableOf('biteanddine:table:30'), 30);
    });

    test('tolerates surrounding whitespace and prefix casing', () {
      expect(tableOf('  dineqr:table:7 \n'), 7);
      expect(tableOf('DineQR:Table:30'), 30);
    });

    test('rejects empty content', () {
      expect(errorOf(null), TableQrError.empty);
      expect(errorOf(''), TableQrError.empty);
      expect(errorOf('   '), TableQrError.empty);
    });

    test('rejects codes that are not table codes', () {
      for (final raw in [
        'https://example.com/menu',
        'DINEQR:MENU:05',
        'DINEQR:TABLE:',
        'DINEQR:TABLE:5a',
        'DINEQR:TABLE:-3',
        'DINEQR:TABLE:1234',
        'BITEANDDINE:TABLE:5a',
        'TABLE:05',
      ]) {
        expect(errorOf(raw), TableQrError.unrecognized, reason: raw);
      }
    });

    test('rejects tables outside the restaurant range', () {
      expect(errorOf('DINEQR:TABLE:00'), TableQrError.invalidTable);
      expect(errorOf('DINEQR:TABLE:31'), TableQrError.invalidTable);
      expect(errorOf('DINEQR:TABLE:99'), TableQrError.invalidTable);
      expect(errorOf('BITEANDDINE:TABLE:99'), TableQrError.invalidTable);
    });

    test('payloadFor produces parseable, zero-padded payloads', () {
      expect(TableQrParser.payloadFor(5), 'DINEQR:TABLE:05');
      for (var table = 1; table <= TableQrParser.maxTable; table++) {
        expect(tableOf(TableQrParser.payloadFor(table)), table);
      }
    });
  });
}
