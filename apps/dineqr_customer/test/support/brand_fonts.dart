import 'dart:io';

import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/services.dart';

/// Loads the bundled Poppins weights (and the SDK's Material icons) so text
/// in tests has the app's real metrics instead of the square test font.
/// Tests run from the app folder; the fonts live in the design system.
Future<void> loadBrandFonts() async {
  final loader = FontLoader(AppTypography.fontFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File(
      '../../packages/dineqr_design_system/assets/fonts/Poppins-$weight.ttf',
    ).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();

  final sdk = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
  final icons = File(
    '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await iconLoader.load();
  }
}
