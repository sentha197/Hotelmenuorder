import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../motion/motion.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Spacing scale (logical pixels).
abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Horizontal page gutter.
  static const page = 20.0;
}

/// Corner radii.
abstract final class AppRadii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;

  static const button = BorderRadius.all(Radius.circular(14));
  static const card = BorderRadius.all(Radius.circular(lg));
  static const pill = BorderRadius.all(Radius.circular(100));
}

/// Elevation shadows.
abstract final class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const soft = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 3)),
  ];

  static const floating = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.32),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.deepRed,
      secondary: AppColors.deepRed,
      onSecondary: Colors.white,
      tertiary: AppColors.gold,
      onTertiary: AppColors.textPrimary,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.surfaceSoft,
      surfaceContainer: AppColors.surfaceSoft,
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
      shadow: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: AppTypography.display,
        headlineSmall: AppTypography.headline,
        titleLarge: AppTypography.screenTitle,
        titleMedium: AppTypography.sectionTitle,
        titleSmall: AppTypography.cardTitle,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.bodySecondary,
        labelLarge: AppTypography.button,
        labelMedium: AppTypography.label,
        labelSmall: AppTypography.caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: Color(0x22000000),
        centerTitle: true,
        titleTextStyle: AppTypography.screenTitle,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppTypography.label.copyWith(color: Colors.white),
        actionTextColor: AppColors.gold,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.button),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSoft,
        hintStyle: AppTypography.bodySecondary.copyWith(
          color: AppColors.textMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: Color(0x33B5121B),
        selectionHandleColor: AppColors.primary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFFDDDDDD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.border,
        labelStyle: AppTypography.cardTitle,
        unselectedLabelStyle: AppTypography.label,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        side: const BorderSide(color: Color(0xFFC9C9C9), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.windows: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.linux: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeSlidePageTransitionsBuilder(),
        },
      ),
    );
  }
}
