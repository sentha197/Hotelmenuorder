import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

int? tableOf(String? raw) => switch (TableQrParser.parse(raw)) {
  ValidTableQr(:final tableNumber) => tableNumber,
  ValidParcelQr() => OrderTables.parcel,
  InvalidTableQr() => null,
};

TableQrError? errorOf(String? raw, {bool parcelEnabled = false}) =>
    switch (TableQrParser.parse(raw, parcelEnabled: parcelEnabled)) {
      ValidTableQr() || ValidParcelQr() => null,
      InvalidTableQr(:final error) => error,
    };

bool isParcel(String? raw, {bool parcelEnabled = true}) =>
    TableQrParser.parse(raw, parcelEnabled: parcelEnabled) is ValidParcelQr;

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

  group('parcel QR', () {
    test('is accepted when the restaurant takes parcel orders', () {
      expect(isParcel('DINEQR:PARCEL'), isTrue);
      expect(isParcel('  dineqr:parcel \n'), isTrue);
      expect(isParcel('BITEANDDINE:PARCEL'), isTrue);
    });

    test('is refused while parcel orders are switched off', () {
      expect(
        errorOf('DINEQR:PARCEL'),
        TableQrError.parcelUnavailable,
        reason: 'parcelEnabled defaults to false',
      );
      expect(isParcel('DINEQR:PARCEL', parcelEnabled: false), isFalse);
    });

    test('is a single fixed payload, so regenerating cannot duplicate it', () {
      expect(TableQrParser.payloadFor(OrderTables.parcel), 'DINEQR:PARCEL');
      expect(
        TableQrParser.payloadFor(OrderTables.parcel),
        TableQrParser.parcelPayload,
      );
    });

    test('carries no table, and table zero is never a dine-in code', () {
      expect(tableOf('DINEQR:PARCEL'), isNull, reason: 'parcel off by default');
      expect(errorOf('DINEQR:TABLE:00'), TableQrError.invalidTable);
      expect(OrderTables.typeOf(OrderTables.parcel), OrderType.parcel);
      expect(OrderTables.typeOf(5), OrderType.dineIn);
    });

    test('near-misses are not treated as the parcel code', () {
      for (final raw in ['DINEQR:PARCELS', 'DINEQR:PARCEL:1', 'PARCEL']) {
        expect(
          isParcel(raw),
          isFalse,
          reason: '$raw must not open the parcel flow',
        );
      }
    });

    test('labels distinguish parcel from a table', () {
      expect(OrderTables.label(OrderTables.parcel), 'Parcel');
      expect(OrderTables.label(7), 'Table 07');
    });
  });
}
