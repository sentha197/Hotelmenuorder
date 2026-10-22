import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../state/session_controller.dart';

/// Screen 1: the DineQR brand introduction, built around the logo's smile.
///
/// The native launch screens (Android and iOS) show the white DineQR symbol,
/// [launchMarkWidth] wide, centred on the ember background, with its smile
/// drawn faintly. The first frame here is identical, so the hand-over is
/// invisible. Then, in about two seconds:
/// 1. A deep red-to-orange light blooms over the restaurant photo.
/// 2. The symbol lifts and grows into place on a restrained spring.
/// 3. The smile draws itself from left to right, deepens into its full
///    curve, settles, and glows once.
/// 4. "DineQR" rises out of a mask, then SCAN • ORDER • ENJOY.
/// 5. A QR-scanner loader runs until the app moves on: to the scanner, or
///    straight back to the menu when a recent table session can resume.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 2200),
  });

  /// Time on the splash with full motion. With reduced motion the final
  /// composition is shown at once and the app moves on sooner.
  final Duration duration;

  /// Width of the symbol on the native launch screens (logical pixels). The
  /// launch images are generated at this size by
  /// `tool/generate_brand_assets_test.dart`.
  static const launchMarkWidth = 120.0;

  /// The smile's progress on the native launch screens: the faint,
  /// understated starting state of the signature animation.
  static const launchSmile = 0.0;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  );
  late final AnimationController _progress = AnimationController(vsync: this);

  bool _started = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _intro.value = 1;
      _progress.duration = const Duration(milliseconds: 900);
    } else {
      _intro.forward();
      _progress.duration = widget.duration;
    }
    _progress.forward();
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final table = context.read<SessionController>().resumableTable;
    final navigator = Navigator.of(context);
    if (table != null &&
        context.read<SettingsController>().isOrderable(table)) {
      // A guest reopening the app mid-meal goes straight back to the menu.
      navigator.pushReplacementNamed(Routes.home);
      return;
    }
    navigator.pushReplacementNamed(
      Routes.scan,
      arguments: const ScanArgs(fromSplash: true),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _progress.dispose();
    super.dispose();
  }

  double _phase(double begin, double end, [Curve curve = Curves.linear]) =>
      Interval(begin, end, curve: curve).transform(_intro.value);

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ember,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final screen = constraints.biggest;
            final usable = screen.height - padding.vertical;
            // Scales with the screen, so it also fits landscape and tablets.
            final markWidth = math.min(168.0, screen.shortestSide * 0.4);
            final finalMarkHeight = markWidth / DineQrMark.aspectRatio;
            final wordSize = (markWidth * 0.27).clamp(32.0, 46.0);
            // Where the symbol starts (as on the launch screen) and ends.
            final start = screen.center(Offset.zero);
            final end = Offset(
              screen.width / 2,
              padding.top +
                  usable * (screen.height > screen.width ? 0.37 : 0.3),
            );
            final textTop = end.dy + finalMarkHeight / 2 + 14;
            return AnimatedBuilder(
              animation: Listenable.merge([_intro, _progress]),
              builder: (context, _) {
                final ember = 1 - _phase(0, 0.32, Curves.easeOut);
                final glow = _phase(0.04, 0.5, Motion.brand);
                final lift = _phase(0.06, 0.62, Motion.spring);
                final smile = _phase(0.3, 0.84);
                // One warm pulse as the smile settles.
                final smileGlow = math.sin(math.pi * _phase(0.66, 1.0));
                final wordmark = _phase(0.46, 0.8, Motion.brand);
                final tagline = _phase(0.62, 0.94, Motion.brand);
                final loader = _phase(0.56, 0.8);
                final width = lerpDouble(
                  SplashScreen.launchMarkWidth,
                  markWidth,
                  lift,
                )!;
                final height = width / DineQrMark.aspectRatio;
                final center = Offset.lerp(start, end, lift)!;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _Backdrop(drift: reduced ? 0 : _progress.value, glow: glow),
                    // Starts as the plain launch-screen ember, then clears.
                    IgnorePointer(
                      child: ColoredBox(
                        color: AppColors.ember.withValues(alpha: ember),
                      ),
                    ),
                    // Ambient light behind the symbol.
                    Positioned(
                      left: center.dx - width * 0.95,
                      top: center.dy - width * 0.95,
                      width: width * 1.9,
                      height: width * 1.9,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: glow,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0x66FF6A00),
                                  Color(0x26D62828),
                                  Color(0x00D62828),
                                ],
                                stops: [0, 0.45, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: center.dx - width / 2,
                      top: center.dy - height / 2,
                      child: DineQrMark(
                        size: width,
                        tone: DineQrTone.inverted,
                        smile: smile,
                        smileGlow: smileGlow,
                      ),
                    ),
                    // Wordmark rises out of a mask, then the tagline.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: textTop,
                      child: Column(
                        children: [
                          ClipRect(
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                wordSize * 1.1 * (1 - wordmark),
                              ),
                              child: Opacity(
                                opacity: wordmark,
                                child: DineQrWordmark(
                                  fontSize: wordSize,
                                  onDark: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Opacity(
                            opacity: tagline,
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - tagline)),
                              child: DineQrTagline(
                                fontSize: (wordSize * 0.28).clamp(11.0, 13.0),
                                onDark: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // QR-scanner loader.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: padding.bottom + 40,
                      child: Center(
                        child: Opacity(
                          opacity: loader,
                          child: loader > 0
                              ? const QrScanLoader(
                                  size: 38,
                                  semanticLabel: 'Preparing DineQR',
                                )
                              : const SizedBox.square(dimension: 38),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Restaurant photo under a deep red-to-orange light, drifting slowly.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.drift, required this.glow});

  /// 0-1 over the splash, for the slow zoom.
  final double drift;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.translate(
          offset: Offset(0, -10 * drift),
          child: Transform.scale(
            scale: 1.12 - 0.08 * drift,
            child: Image.asset(
              'assets/images/splash_bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: AppColors.ember),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xF23A0508),
                Color(0xE68E0F17),
                Color(0xD9B5121B),
                Color(0xE6C2330F),
              ],
              stops: [0, 0.38, 0.72, 1],
            ),
          ),
        ),
        // Warm light rising from the bottom edge.
        Opacity(
          opacity: glow,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 1.25),
                radius: 1.05,
                colors: [Color(0x73FF8A00), Color(0x00FF8A00)],
              ),
            ),
          ),
        ),
        CustomPaint(
          painter: BrandWavesPainter(intensity: 0.2 + 0.3 * glow, shift: drift),
        ),
      ],
    );
  }
}
