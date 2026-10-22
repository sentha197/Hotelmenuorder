import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

export '../test/support/brand_fonts.dart';

/// Renders [child] at [size] logical pixels × [pixelRatio] and writes a PNG.
Future<void> renderToPng(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required String path,
  double pixelRatio = 1,
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, devicePixelRatio: pixelRatio),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.fromSize(size: size, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}
