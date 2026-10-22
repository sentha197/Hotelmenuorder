import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Operational palette for the admin app: the DineQR reds for actions and
/// brand moments, a deep burgundy/charcoal navigation frame, and neutral
/// content surfaces so figures and order states stay easy to read.
abstract final class AdminColors {
  /// Navigation rail, sign-in backdrop and other "frame" surfaces.
  static const navy = Color(0xFF1C1012);
  static const frame = Color(0xFF2B1218);
  static const frameRaised = Color(0xFF411A23);
  static const frameText = Color(0xFFF6ECEC);
  static const frameMuted = Color(0xFFC4AEB1);

  /// Content canvas behind cards.
  static const canvas = Color(0xFFF5F3F2);
  static const card = Colors.white;
  static const line = Color(0xFFE7E1DF);
}

abstract final class AdminTheme {
  static ThemeData light() {
    final base = AppTheme.light();
    return base.copyWith(
      scaffoldBackgroundColor: AdminColors.canvas,
      visualDensity: VisualDensity.standard,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        centerTitle: false,
      ),
      // Snappy, directional transitions for an operational tool.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
