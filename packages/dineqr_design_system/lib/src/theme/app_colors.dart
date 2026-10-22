import 'package:flutter/material.dart';

/// DineQR brand palette. Every screen takes its colours from here.
abstract final class AppColors {
  // Official brand colours.
  static const primary = Color(0xFFB5121B);
  static const deepRed = Color(0xFF8E0F17);
  static const accentRed = Color(0xFFD62828);
  static const vibrantOrange = Color(0xFFFF6A00);
  static const warmOrange = Color(0xFFFF8A00);
  static const charcoal = Color(0xFF202020);
  static const softWhite = Color(0xFFF8F8F8);
  static const paleWarm = Color(0xFFFFF5F2);
  static const success = Color(0xFF248A45);
  static const gold = Color(0xFFFFC83D);

  /// Darkest brand surface (splash, scanner and dark brand panels).
  static const ember = Color(0xFF3A0508);

  /// Warm accent text on red surfaces (readable where orange is not).
  static const peach = Color(0xFFFFD9BF);

  /// Orange for small text on white (meets 4.5:1 contrast).
  static const orangeText = Color(0xFFC2410C);

  // Double-layer depth colours.
  /// Solid "lip" under primary buttons.
  static const lip = Color(0xFF7A0C13);

  /// Lip under red brand panels and banners.
  static const panelLip = Color(0xFF5A0A10);

  /// Base layer of layered text on red surfaces.
  static const depthOnRed = Color(0xFF4A060B);

  /// Darkened brand red for scrims over the camera and photos.
  static const scrim = Color(0xFF140204);

  static const successLight = Color(0xFF39B060);
  static const inactive = Color(0xFFE6DCD9);

  static const background = Color(0xFFFFFFFF);
  static const surfaceSoft = paleWarm;
  static const card = Color(0xFFFFFFFF);

  static const textPrimary = charcoal;
  static const textSecondary = Color(0xFF737373);
  static const textMuted = Color(0xFFA3A3A3);

  static const border = Color(0xFFEFEAE8);
  static const error = Color(0xFFD32F2F);

  // Tints derived from the brand colours.
  static const primarySoft = Color(0xFFFDECEC);
  static const orangeSoft = Color(0xFFFFF0E3);
  static const successSoft = Color(0xFFE7F4EB);
  static const warning = Color(0xFFB7791F);
  static const warningSoft = Color(0xFFFFF3D6);
  static const info = Color(0xFF2F5DA8);
  static const infoSoft = Color(0xFFE9F0FB);
  static const nonVeg = Color(0xFFB5121B);
  static const veg = Color(0xFF248A45);
  static const divider = Color(0xFFF3EFEE);
  static const ink = Color(0xFF151515);
  static const skeleton = Color(0xFFF3ECEA);

  /// Main brand surface: deep red into primary red.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentRed, primary, deepRed],
    stops: [0, 0.45, 1],
  );

  /// Promotional banners.
  static const bannerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [deepRed, primary, accentRed],
  );

  /// The bright highlight layer of the double-layer treatment: red into
  /// orange, used on the "QR" of the wordmark and on primary CTAs.
  static const emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentRed, vibrantOrange, warmOrange],
    stops: [0, 0.62, 1],
  );

  /// Primary call-to-action fill.
  static const ctaGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primary, accentRed, Color(0xFFE8461A)],
    stops: [0, 0.6, 1],
  );

  /// Splash photo overlay: dark red light, darkest at the edges.
  static const splashOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xEB2A0306),
      Color(0xD9660A11),
      Color(0xE04A070C),
      Color(0xFA1A0203),
    ],
    stops: [0, 0.42, 0.7, 1],
  );

  /// Dish hero photo: darkened top for the buttons, warm shade at the base.
  static const heroImageOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x73000000),
      Color(0x00000000),
      Color(0x00000000),
      Color(0x4D3A0508),
    ],
    stops: [0, 0.38, 0.7, 1],
  );

  /// Dark brand backdrop (splash, inverted logo, app icon).
  static const nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF5A0A10), deepRed, ember],
    stops: [0, 0.45, 1],
  );
}
