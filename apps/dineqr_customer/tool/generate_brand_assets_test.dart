// Generates launcher icons and brand exports from the vector DineQR logo.
// Run from the project root: flutter test tool/generate_brand_assets_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

void main() {
  setUpAll(loadBrandFonts);

  testWidgets('generate brand assets', (tester) async {
    debugDisableShadows = false;

    /// Renders [child] at exactly [width]×[height] pixels.
    Future<ui.Image> render(Widget child, double width, double height) async {
      final key = GlobalKey();
      final size = Size(width, height);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      late ui.Image image;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        image = await boundary.toImage();
      });
      return image;
    }

    Future<void> savePng(
      Widget child,
      String path,
      double width, [
      double? height,
    ]) async {
      final image = await render(child, width, height ?? width);
      await tester.runAsync(() async {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
      });
      image.dispose();
    }

    /// Opaque RGB PNG (no alpha channel), as App Store icons require.
    Future<void> saveOpaquePng(Widget child, String path, double size) async {
      final image = await render(child, size, size);
      await tester.runAsync(() async {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(
            encodeRgbPng(data!.buffer.asUint8List(), image.width, image.height),
          );
      });
      image.dispose();
    }

    // Android legacy launcher icons (rounded square).
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    const res = 'android/app/src/main/res';
    for (final MapEntry(key: density, value: scale) in densities.entries) {
      final icon = 48 * scale;
      await savePng(
        DineQrAppIcon(size: icon),
        '$res/mipmap-$density/ic_launcher.png',
        icon,
      );
      // Adaptive icon layers: 108dp canvas, symbol inside the 66dp safe zone.
      final layer = 108 * scale;
      await savePng(
        Center(
          child: DineQrMark(
            size: layer * 0.5,
            tone: DineQrTone.inverted,
            semanticLabel: null,
          ),
        ),
        '$res/mipmap-$density/ic_launcher_foreground.png',
        layer,
      );
      await savePng(
        Center(
          child: DineQrMark(
            size: layer * 0.5,
            tone: DineQrTone.mono,
            monoColor: Colors.white,
            semanticLabel: null,
          ),
        ),
        '$res/mipmap-$density/ic_launcher_monochrome.png',
        layer,
      );
    }

    // The native launch screens are the plain ember background (no images):
    // the splash then draws the logo from nothing.

    // iOS app icons: full-bleed (iOS applies the mask), no alpha channel.
    const iosIcons = {
      'Icon-App-20x20@1x.png': 20.0,
      'Icon-App-20x20@2x.png': 40.0,
      'Icon-App-20x20@3x.png': 60.0,
      'Icon-App-29x29@1x.png': 29.0,
      'Icon-App-29x29@2x.png': 58.0,
      'Icon-App-29x29@3x.png': 87.0,
      'Icon-App-40x40@1x.png': 40.0,
      'Icon-App-40x40@2x.png': 80.0,
      'Icon-App-40x40@3x.png': 120.0,
      'Icon-App-60x60@2x.png': 120.0,
      'Icon-App-60x60@3x.png': 180.0,
      'Icon-App-76x76@1x.png': 76.0,
      'Icon-App-76x76@2x.png': 152.0,
      'Icon-App-83.5x83.5@2x.png': 167.0,
      'Icon-App-1024x1024@1x.png': 1024.0,
    };
    for (final MapEntry(key: name, value: size) in iosIcons.entries) {
      await saveOpaquePng(
        DineQrAppIcon(size: size, cornerRadius: 0),
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/$name',
        size,
      );
    }

    // Web icons.
    for (final size in [192.0, 512.0]) {
      await savePng(
        DineQrAppIcon(size: size),
        'web/icons/Icon-${size.toInt()}.png',
        size,
      );
      // Maskable: full bleed, symbol within the central 80% safe zone.
      await savePng(
        DineQrAppIcon(size: size, cornerRadius: 0, markScale: 0.56),
        'web/icons/Icon-maskable-${size.toInt()}.png',
        size,
      );
    }
    await savePng(
      const DineQrAppIcon(size: 16, markScale: 0.8),
      'web/favicon.png',
      16,
    );

    // Brand exports (transparent PNGs) for use outside the app.
    // Shared brand exports live at the repository root.
    const out = '../../branding';
    await savePng(
      const Center(child: DineQrMark(size: 960)),
      '$out/dineqr_symbol_color.png',
      1024,
      840,
    );
    await savePng(
      const Center(child: DineQrMark(size: 960, tone: DineQrTone.inverted)),
      '$out/dineqr_symbol_white.png',
      1024,
      840,
    );
    await savePng(
      const Center(
        child: DineQrMark(
          size: 960,
          tone: DineQrTone.mono,
          monoColor: AppColors.charcoal,
        ),
      ),
      '$out/dineqr_symbol_mono.png',
      1024,
      840,
    );
    Widget stacked({required bool onDark}) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DineQrMark(
            size: 620,
            tone: onDark ? DineQrTone.inverted : DineQrTone.color,
          ),
          const SizedBox(height: 28),
          DineQrWordmark(fontSize: 150, onDark: onDark),
          const SizedBox(height: 16),
          DineQrTagline(fontSize: 34, onDark: onDark),
        ],
      ),
    );
    await savePng(stacked(onDark: false), '$out/dineqr_logo_color.png', 1200);
    await savePng(stacked(onDark: true), '$out/dineqr_logo_white.png', 1200);
    await savePng(
      const Center(child: DineQrLockup(height: 200, showTagline: true)),
      '$out/dineqr_lockup_horizontal.png',
      1400,
      320,
    );
    await savePng(
      const Center(
        child: DineQrLockup(height: 200, showTagline: true, onDark: true),
      ),
      '$out/dineqr_lockup_horizontal_white.png',
      1400,
      320,
    );
    for (final style in DineQrIconStyle.values) {
      await savePng(
        DineQrAppIcon(size: 1024, style: style),
        '$out/dineqr_app_icon_${style.name}.png',
        1024,
      );
    }

    tester.view.reset();
    debugDisableShadows = true;
  });
}

/// Minimal PNG encoder for 8-bit RGB (colour type 2), dropping alpha.
Uint8List encodeRgbPng(Uint8List rgba, int width, int height) {
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    final row = Uint8List(width * 3);
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      row[x * 3] = rgba[i];
      row[x * 3 + 1] = rgba[i + 1];
      row[x * 3 + 2] = rgba[i + 2];
    }
    raw.add(row);
  }
  final out = BytesBuilder(copy: false)
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typeBytes = type.codeUnits;
    out
      ..add(_uint32(data.length))
      ..add(typeBytes)
      ..add(data)
      ..add(_uint32(_crc32([...typeBytes, ...data])));
  }

  chunk('IHDR', [..._uint32(width), ..._uint32(height), 8, 2, 0, 0, 0]);
  chunk('IDAT', ZLibCodec(level: 9).encode(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
