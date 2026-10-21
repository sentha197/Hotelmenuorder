import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../core/animations/loaders.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/brand_surfaces.dart';
import '../../core/brand/dineqr_logo.dart';

/// Screen 1: the DineQR brand introduction.
///
/// The native launch screens (Android and iOS) show the white DineQR symbol,
/// [launchMarkWidth] wide, centred on the ember background. The first frame
/// here is identical, so the hand-over is invisible. Then:
/// 1. The restaurant photo fades up under a dark red light, with a slow zoom,
///    and a warm glow blooms behind the symbol.
/// 2. The symbol lifts and grows into place, with a highlight sweep.
/// 3. "DineQR" rises out of a mask, then the tagline appears.
/// 4. QR modules assemble into a small code as the loading indicator.
/// 5. Fades through to the QR scanner exactly once.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 2200),
  });

  final Duration duration;

  /// Width of the symbol on the native launch screens (logical pixels). The
  /// launch images are generated at this size by
  /// `tool/generate_brand_assets_test.dart`.
  static const launchMarkWidth = 120.0;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _markWidth = 176.0;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

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
    } else {
      _intro.forward();
    }
    _progress.forward();
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(
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
            // Where the symbol starts (as on the launch screen) and ends.
            final start = screen.center(Offset.zero);
            final end = Offset(
              screen.width / 2,
              padding.top + (screen.height - padding.vertical) * 0.36,
            );
            final textTop = end.dy + _markWidth / DineQrMark.aspectRatio / 2;
            return AnimatedBuilder(
              animation: Listenable.merge([_intro, _progress]),
              builder: (context, _) {
                final glow = _phase(0.05, 0.5, Motion.brand);
                final lift = _phase(0.1, 0.55, Motion.emphasized);
                final sheen = reduced
                    ? null
                    : _phase(0.58, 0.9, Curves.easeInOut);
                final wordmark = _phase(0.42, 0.74, Motion.brand);
                final tagline = _phase(0.6, 0.94, Motion.brand);
                final loader = _phase(0.35, 0.7);
                final markWidth = lerpDouble(
                  SplashScreen.launchMarkWidth,
                  _markWidth,
                  lift,
                )!;
                final markHeight = markWidth / DineQrMark.aspectRatio;
                final center = Offset.lerp(start, end, lift)!;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background photo, slow zoom-out with a gentle lift.
                    Transform.translate(
                      offset: Offset(0, reduced ? 0 : -12 * _progress.value),
                      child: Transform.scale(
                        scale: reduced ? 1.04 : 1.14 - 0.1 * _progress.value,
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
                        gradient: AppColors.splashOverlay,
                      ),
                    ),
                    CustomPaint(
                      painter: BrandWavesPainter(
                        intensity: 0.25 + 0.4 * glow,
                        shift: _progress.value,
                      ),
                    ),
                    // Starts as the plain launch-screen ember, then fades.
                    IgnorePointer(
                      child: ColoredBox(
                        color: AppColors.ember.withValues(
                          alpha: 1 - _phase(0, 0.3, Curves.easeOut),
                        ),
                      ),
                    ),
                    // Warm glow behind the symbol.
                    Positioned(
                      left: center.dx - 130,
                      top: center.dy - 130,
                      width: 260,
                      height: 260,
                      child: Opacity(
                        opacity: glow,
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * glow,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.vibrantOrange.withValues(
                                    alpha: 0.42,
                                  ),
                                  AppColors.accentRed.withValues(alpha: 0.16),
                                  AppColors.accentRed.withValues(alpha: 0),
                                ],
                                stops: const [0, 0.45, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: center.dx - markWidth / 2,
                      top: center.dy - markHeight / 2,
                      child: DineQrMark(
                        size: markWidth,
                        tone: DineQrTone.inverted,
                        sheen: sheen,
                      ),
                    ),
                    // Wordmark rises out of a mask, then the tagline.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: textTop + 14,
                      child: Column(
                        children: [
                          ClipRect(
                            child: Transform.translate(
                              offset: Offset(0, 52 * (1 - wordmark)),
                              child: Opacity(
                                opacity: wordmark,
                                child: const DineQrWordmark(
                                  fontSize: 46,
                                  onDark: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Opacity(
                            opacity: tagline,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - tagline)),
                              child: const DineQrTagline(
                                fontSize: 12.5,
                                onDark: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Signature loader.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: padding.bottom + 44,
                      child: Center(
                        child: Opacity(
                          opacity: loader,
                          child: QrAssembleLoader(
                            progress: _progress,
                            size: 40,
                          ),
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
