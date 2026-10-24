import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

int? tableOf(String? raw) => switch (TableQrParser.parse(raw)) {
  ValidTableQr(:final tableNumber) => tableNumber,
  ValidTakeawayQr() => OrderTables.takeaway,
  InvalidTableQr() => null,
};

TableQrError? errorOf(String? raw, {bool takeawayEnabled = false}) =>
    switch (TableQrParser.parse(raw, takeawayEnabled: takeawayEnabled)) {
      ValidTableQr() || ValidTakeawayQr() => null,
      InvalidTableQr(:final error) => error,
    };

bool isTakeaway(String? raw, {bool takeawayEnabled = true}) =>
    TableQrParser.parse(raw, takeawayEnabled: takeawayEnabled)
        is ValidTakeawayQr;

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

  group('takeaway QR', () {
    test('is accepted when the restaurant takes takeaway orders', () {
      expect(isTakeaway('DINEQR:TAKEAWAY'), isTrue);
      expect(isTakeaway('  dineqr:takeaway \n'), isTrue);
    });

    test('keeps accepting codes printed while it was called parcel', () {
      expect(isTakeaway('DINEQR:PARCEL'), isTrue);
      expect(isTakeaway('dineqr:parcel'), isTrue);
      expect(isTakeaway('BITEANDDINE:PARCEL'), isTrue);
    });

    test('is refused while takeaway orders are switched off', () {
      expect(
        errorOf('DINEQR:TAKEAWAY'),
        TableQrError.takeawayUnavailable,
        reason: 'takeawayEnabled defaults to false',
      );
      expect(errorOf('DINEQR:PARCEL'), TableQrError.takeawayUnavailable);
      expect(isTakeaway('DINEQR:TAKEAWAY', takeawayEnabled: false), isFalse);
    });

    test('is a single fixed payload, so regenerating cannot duplicate it', () {
      expect(
        TableQrParser.payloadFor(OrderTables.takeaway),
        'DINEQR:TAKEAWAY',
      );
      expect(
        TableQrParser.payloadFor(OrderTables.takeaway),
        TableQrParser.takeawayPayload,
      );
    });

    test('carries no table, and table zero is never a dine-in code', () {
      expect(
        tableOf('DINEQR:TAKEAWAY'),
        isNull,
        reason: 'takeaway off by default',
      );
      expect(errorOf('DINEQR:TABLE:00'), TableQrError.invalidTable);
      expect(OrderTables.typeOf(OrderTables.takeaway), OrderType.takeaway);
      expect(OrderTables.typeOf(5), OrderType.dineIn);
    });

    test('near-misses are not treated as the takeaway code', () {
      for (final raw in [
        'DINEQR:TAKEAWAYS',
        'DINEQR:TAKEAWAY:1',
        'DINEQR:TAKE AWAY',
        'TAKEAWAY',
        'DINEQR:PARCELS',
        'PARCEL',
        'BITEANDDINE:TAKEAWAY',
      ]) {
        expect(
          isTakeaway(raw),
          isFalse,
          reason: '$raw must not open the takeaway flow',
        );
      }
    });

    test('labels distinguish takeaway from a table', () {
      expect(OrderTables.label(OrderTables.takeaway), 'Takeaway');
      expect(OrderTables.label(7), 'Table 07');
      expect(OrderTables.shortLabel(OrderTables.takeaway), 'Takeaway');
      expect(OrderTables.shortLabel(7), '07');
    });

    test('status labels read as collected for takeaway', () {
      expect(
        OrderStatus.readyToServe.labelFor(OrderType.takeaway),
        'Ready for Pickup',
      );
      expect(OrderStatus.served.labelFor(OrderType.takeaway), 'Collected');
      expect(OrderStatus.served.labelFor(OrderType.dineIn), 'Served at Table');
      expect(
        OrderStatus.preparing.labelFor(OrderType.takeaway),
        OrderStatus.preparing.label,
      );
    });
  });
}
