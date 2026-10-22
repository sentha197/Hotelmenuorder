// Lays the generated icon PNGs out on one sheet for visual review.
// Run: flutter test tool/icon_sheet_test.dart --dart-define=OUT=<dir>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/icon_sheet');

void main() {
  testWidgets('icon sheet', (tester) async {
    const files = [
      'branding/dineqr_app_icon_color.png',
      'branding/dineqr_app_icon_light.png',
      'branding/dineqr_app_icon_dark.png',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
      'web/icons/Icon-maskable-512.png',
      'branding/dineqr_logo_color.png',
      'branding/dineqr_logo_white.png',
      'branding/dineqr_lockup_horizontal.png',
      'web/favicon.png',
    ];
    final images = <String, ImageProvider>{
      for (final f in files) f: MemoryImage(File(f).readAsBytesSync()),
    };
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          color: Colors.white,
          child: Container(key: key),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (final image in images.values) {
        await precacheImage(image, key.currentContext!);
      }
    });
    Widget cell(String file, {Color background = const Color(0xFFEDEDED)}) =>
        Container(
          color: background,
          padding: const EdgeInsets.all(12),
          child: Image(image: images[file]!, filterQuality: FilterQuality.none),
        );
    await renderToPng(
      tester,
      GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final f in files)
            cell(
              f,
              background: f.contains('white') || f.contains('foreground')
                  ? const Color(0xFF8E0F17)
                  : const Color(0xFFEDEDED),
            ),
        ],
      ),
      size: const Size(1000, 760),
      path: '$_out/icon_sheet.png',
    );
  });
}
