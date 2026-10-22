// Combines screenshots into contact sheets for quick review.
// Run: flutter test tool/contact_sheet_test.dart --dart-define=DIR=<dir>
//   [--dart-define=PER_SHEET=6]
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = String.fromEnvironment('DIR', defaultValue: 'build/screens');
const _perSheet = int.fromEnvironment('PER_SHEET', defaultValue: 6);

void main() {
  testWidgets('contact sheets', (tester) async {
    await tester.runAsync(() async {
      final files =
          Directory(_dir)
              .listSync()
              .whereType<File>()
              .where(
                (f) =>
                    f.path.endsWith('.png') &&
                    !f.uri.pathSegments.last.startsWith('sheet_'),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (var start = 0; start < files.length; start += _perSheet) {
        final batch = files.skip(start).take(_perSheet).toList();
        final images = <ui.Image>[];
        for (final file in batch) {
          final codec = await ui.instantiateImageCodec(
            file.readAsBytesSync(),
            targetWidth: 390,
          );
          images.add((await codec.getNextFrame()).image);
        }
        final w = images.map((i) => i.width).reduce((a, b) => a > b ? a : b);
        final h = images.map((i) => i.height).reduce((a, b) => a > b ? a : b);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(Colors.grey, BlendMode.src);
        for (final (i, image) in images.indexed) {
          canvas.drawImage(image, Offset(i * (w + 10.0), 0), Paint());
        }
        final sheet = await recorder.endRecording().toImage(
          images.length * (w + 10),
          h,
        );
        final data = await sheet.toByteData(format: ui.ImageByteFormat.png);
        final n = (start ~/ _perSheet).toString().padLeft(2, '0');
        File('$_dir/sheet_$n.png').writeAsBytesSync(data!.buffer.asUint8List());
      }
    });
  });
}
