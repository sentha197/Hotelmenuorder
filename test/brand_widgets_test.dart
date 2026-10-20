import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/app/app.dart';
import 'package:menu_order/core/animations/brand_effects.dart';
import 'package:menu_order/core/animations/loaders.dart';
import 'package:menu_order/core/brand/dineqr_logo.dart';
import 'package:menu_order/core/widgets/app_buttons.dart';
import 'package:menu_order/core/widgets/table_qr_code.dart';
import 'package:menu_order/features/qr_scanner/table_qr_parser.dart';
import 'package:qr/qr.dart';

import 'app_flow_test.dart'
    show createDependencies, scanDemoTable, settle, usePhoneScreen;

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('the DineQR symbol paints in every tone and reveal stage', (
    tester,
  ) async {
    for (final tone in DineQrTone.values) {
      for (final reveal in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        await tester.pumpWidget(
          _host(DineQrMark(size: 120, tone: tone, reveal: reveal, sheen: 0.5)),
        );
        expect(tester.takeException(), isNull);
      }
    }
    final size = tester.getSize(find.byType(DineQrMark));
    expect(size.width / size.height, closeTo(DineQrMark.aspectRatio, 0.01));
  });

  testWidgets('wordmark, tagline, lockup and app icon expose brand semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DineQrWordmark(),
            DineQrTagline(),
            DineQrLockup(),
            DineQrAppIcon(size: 64),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('DineQR'), findsWidgets);
    expect(find.bySemanticsLabel('Scan, order, enjoy'), findsOneWidget);
    expect(find.bySemanticsLabel('DineQR app icon'), findsOneWidget);
    semantics.dispose();
  });

  test('table QR codes encode every valid table payload', () {
    for (var table = 1; table <= TableQrParser.maxTable; table++) {
      final payload = TableQrParser.payloadFor(table);
      final code = QrCode(
        payload: QrPayload.fromString(payload),
        errorCorrectLevel: QrErrorCorrectLevel.high,
      );
      expect(QrImage(code).moduleCount, greaterThanOrEqualTo(21));
    }
  });

  testWidgets('table QR code renders with the centre logo', (tester) async {
    await tester.pumpWidget(
      _host(TableQrCode(payload: TableQrParser.payloadFor(5))),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(DineQrMark), findsOneWidget);
  });

  testWidgets('primary button shows the QR pulse loader instead of a spinner', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        PrimaryButton(label: 'Place', isLoading: true, onPressed: () => taps++),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QrPulseLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byType(PrimaryButton));
    expect(taps, 0, reason: 'disabled while loading');

    await tester.pumpWidget(
      _host(PrimaryButton(label: 'Place', onPressed: () => taps++)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QrPulseLoader), findsNothing);
    await tester.tap(find.text('Place'));
    expect(taps, 1);
  });

  testWidgets('animated star rating reports the tapped star and settles', (
    tester,
  ) async {
    var value = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          AnimatedStarRating(
            value: value,
            onChanged: (rating) => setState(() => value = rating),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('rating-star-3')));
    await tester.pumpAndSettle();
    expect(value, 3);
    await tester.tap(find.byKey(const ValueKey('rating-star-1')));
    await tester.pumpAndSettle();
    expect(value, 1);
  });

  testWidgets('one-shot effects finish and stop animating', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SuccessEmblem(size: 80),
            WipeReveal(child: Text('#OD1')),
          ],
        ),
      ),
    );
    // pumpAndSettle fails if anything keeps scheduling frames.
    await tester.pumpAndSettle();
    expect(find.text('#OD1'), findsOneWidget);
  });

  testWidgets('splash reaches the scanner with reduced motion enabled', (
    tester,
  ) async {
    usePhoneScreen(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final deps = await createDependencies();
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    expect(find.byType(DineQrMark), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2700));
    await settle(tester, 700);
    expect(find.text('Scan QR Code'), findsOneWidget);
  });

  testWidgets('home settles: no animation keeps running without a purpose', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final deps = await createDependencies();
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await scanDemoTable(tester, 'Table 05');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 900);
    expect(find.text('Popular Dishes'), findsOneWidget);
    // Would time out if a loader, shimmer or pulse were left running.
    await tester.pumpAndSettle();
    expect(find.byType(BrandShimmer), findsNothing);
  });
}
