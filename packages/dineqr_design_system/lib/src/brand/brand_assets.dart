import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'dineqr_logo.dart';

/// Raster versions of the vector logo for generated documents (PDF
/// receipts, reports and QR sheets).
abstract final class BrandAssets {
  static Uint8List? _logo;

  /// The colour symbol as a transparent PNG.
  static Future<Uint8List?> logoPng() async {
    final cached = _logo;
    if (cached != null) return cached;
    try {
      const width = 240.0;
      const size = Size(width, width / DineQrMark.aspectRatio);
      final recorder = ui.PictureRecorder();
      const DineQrMarkPainter().paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return _logo = data?.buffer.asUint8List();
    } on Object {
      // Documents still render without the logo.
      return null;
    }
  }
}
