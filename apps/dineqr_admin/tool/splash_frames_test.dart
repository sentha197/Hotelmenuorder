// Renders the admin splash frame by frame, through its hand-over to the
// sign-in screen, and saves a contact sheet to review the motion.
// Run: flutter test tool/splash_frames_test.dart --dart-define=OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/app/dependencies.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/splash');

void main() {
  setUpAll(loadBrandFonts);

  testWidgets('admin splash frames', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final deps = await AdminDependencies.create(
      store: MemoryStore(),
      menuLatency: Duration.zero,
      orderLatency: Duration.zero,
      seedDemoData: false,
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: DineQrAdminApp(dependencies: deps, showSplash: true),
      ),
    );

    final frames = <ui.Image>[];
    var elapsed = 0;
    for (final at in [
      0,
      100,
      220,
      360,
      500,
      650,
      800,
      950,
      1100,
      1300,
      1450,
      1600,
      1800,
      2100,
    ]) {
      while (elapsed < at) {
        await tester.pump(const Duration(milliseconds: 20));
        elapsed += 20;
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        frames.add(await boundary.toImage(pixelRatio: 0.75));
      });
    }

    // Contact sheet: 7 columns.
    const columns = 7;
    final w = frames.first.width.toDouble();
    final h = frames.first.height.toDouble();
    final rows = (frames.length / columns).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    for (final (i, frame) in frames.indexed) {
      canvas.drawImage(
        frame,
        Offset((i % columns) * (w + 8), (i ~/ columns) * (h + 8)),
        Paint(),
      );
    }
    await tester.runAsync(() async {
      final sheet = await recorder.endRecording().toImage(
        (columns * (w + 8)).toInt(),
        (rows * (h + 8)).toInt(),
      );
      final data = await sheet.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/admin_splash_sheet.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data!.buffer.asUint8List());
      for (final (i, frame) in frames.indexed) {
        final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$_out/admin_frame_${i.toString().padLeft(2, '0')}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    });
    for (final frame in frames) {
      frame.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    debugDisableShadows = true;
  });
}
