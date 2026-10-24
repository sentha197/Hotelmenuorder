import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The RGBA pixels of [mark] drawn on its own, 168 logical pixels wide at
/// 3× (as on a phone splash).
Future<Uint8List> _pixels(WidgetTester tester, Widget mark) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(key: key, child: mark),
      ),
    ),
  );
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

void main() {
  for (final tone in [DineQrTone.inverted, DineQrTone.color]) {
    testWidgets('the hand-drawn logo ends as exactly the logo ($tone)', (
      tester,
    ) async {
      final original = await _pixels(
        tester,
        DineQrMark(size: 168, tone: tone, semanticLabel: null),
      );
      // As the customer splash ends: drawn, smiling, sparkle played out.
      final drawn = await _pixels(
        tester,
        DineQrMark(
          size: 168,
          tone: tone,
          sketch: 1,
          smile: 1,
          smileGlint: 1,
          semanticLabel: null,
        ),
      );
      expect(drawn.length, original.length);
      expect(drawn, original, reason: 'every pixel of the final frame');
    });
  }

  testWidgets('the drawing starts from nothing', (tester) async {
    final empty = await _pixels(
      tester,
      const DineQrMark(
        size: 168,
        tone: DineQrTone.inverted,
        sketch: 0,
        smile: 0,
        semanticLabel: null,
      ),
    );
    expect(empty.every((byte) => byte == 0), isTrue);
  });

  testWidgets('midway, outlines are drawn and the smile is still to come', (
    tester,
  ) async {
    final original = await _pixels(
      tester,
      const DineQrMark(
        size: 168,
        tone: DineQrTone.inverted,
        semanticLabel: null,
      ),
    );
    final midway = await _pixels(
      tester,
      const DineQrMark(
        size: 168,
        tone: DineQrTone.inverted,
        sketch: 0.45,
        smile: 0,
        semanticLabel: null,
      ),
    );
    int inked(Uint8List rgba) {
      var count = 0;
      for (var i = 3; i < rgba.length; i += 4) {
        if (rgba[i] > 0) count++;
      }
      return count;
    }

    expect(inked(midway), greaterThan(0));
    expect(inked(midway), lessThan(inked(original)));
  });
}
