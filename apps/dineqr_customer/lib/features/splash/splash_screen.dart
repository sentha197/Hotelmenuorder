import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../state/session_controller.dart';

/// Screen 1: the DineQR brand introduction, built around the logo's smile.
///
/// The native launch screens (Android and iOS) show the white DineQR symbol,
/// [launchMarkWidth] wide, centred on the ember background, with its smile
/// drawn faintly. The first frame here is identical, so the hand-over is
/// invisible. Then, in about two seconds:
/// 1. A deep red-to-orange light blooms over the restaurant photo, and a
///    soft band of light crosses it once.
/// 2. The symbol lifts and grows into place on a restrained spring, sending
///    two faint rings outwards as it lands.
/// 3. The smile draws itself from left to right, deepens into its full
///    curve, settles, glows once and catches a small sparkle at its tip.
/// 4. "DineQR" rises out of a mask, then SCAN • ORDER • ENJOY.
/// 5. The QR emblem assembles beneath them and scans until the app moves on:
///    to the scanner, or straight back to the menu when a recent table (or
///    takeaway) session can resume.
///
/// The splash never waits on the network to appear. It moves on once the
/// animation has played and the restaurant's settings are in
/// ([CustomerDependencies.prepare]); if they take long it says so, and if
/// the server cannot be reached it offers a retry.
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

  /// How long the app waits on the server before saying it may be waking
  /// up (a hosted server that was idle takes a while to start).
  static const slowAfter = Duration(seconds: 8);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

enum _Startup { preparing, ready, failed }

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  );
  late final AnimationController _progress = AnimationController(vsync: this);

  bool _started = false;
  bool _navigated = false;
  _Startup _startup = _Startup.preparing;
  String? _problem;
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (_startup == _Startup.preparing) _startWaiting();
      _maybeGoNext();
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
    _prepare();
  }

  /// Waits for the restaurant's settings (started when the app was created,
  /// so usually already under way or done).
  void _prepare() {
    final prepare = context.read<CustomerDependencies>().prepare();
    prepare.then(
      (_) {
        if (!mounted) return;
        _slowTimer?.cancel();
        setState(() => _startup = _Startup.ready);
        _maybeGoNext();
      },
      onError: (Object error) {
        if (!mounted) return;
        _slowTimer?.cancel();
        setState(() {
          _startup = _Startup.failed;
          _problem = error is ApiException
              ? error.message
              : 'Something went wrong while connecting. Please try again.';
        });
      },
    );
  }

  /// The animation has finished but the server has not answered yet.
  void _startWaiting() {
    _slowTimer?.cancel();
    _slowTimer = Timer(SplashScreen.slowAfter, () {
      if (mounted && _startup == _Startup.preparing) {
        setState(() => _slow = true);
      }
    });
    setState(() {});
  }

  void _retry() {
    HapticFeedback.lightImpact();
    setState(() {
      _startup = _Startup.preparing;
      _problem = null;
      _slow = false;
    });
    _startWaiting();
    _prepare();
  }

  void _maybeGoNext() {
    if (_startup == _Startup.ready && _progress.isCompleted) _goNext();
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final table = context.read<SessionController>().resumableTable;
    final navigator = Navigator.of(context);
    if (table != null &&
        context.read<SettingsController>().isOrderable(table)) {
      // A guest reopening the app mid-meal (or while waiting for takeaway)
      // goes straight back to the menu.
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
    _slowTimer?.cancel();
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
    final waiting =
        _startup == _Startup.preparing && _progress.isCompleted && !_navigated;
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
            // The QR emblem sits under the wordmark and tagline, in the
            // space above the bottom edge, never closer than it fits.
            final emblemSize = (markWidth * 0.44).clamp(58.0, 74.0);
            final textBottom = textTop + wordSize * 1.15 + 34;
            final emblemTop = math.min(
              textBottom +
                  math.max(
                    28.0,
                    (screen.height - padding.bottom - textBottom) * 0.3,
                  ),
              screen.height - padding.bottom - emblemSize - 64,
            );
            return AnimatedBuilder(
              animation: Listenable.merge([_intro, _progress]),
              builder: (context, _) {
                final ember = 1 - _phase(0, 0.32, Curves.easeOut);
                final glow = _phase(0.04, 0.5, Motion.brand);
                final sweep = _phase(0.3, 0.85, Curves.easeInOut);
                final lift = _phase(0.06, 0.62, Motion.spring);
                final smile = _phase(0.3, 0.84);
                // One warm pulse as the smile settles, then a sparkle.
                final smileGlow = math.sin(math.pi * _phase(0.66, 1.0));
                final glint = _phase(0.78, 1.0);
                final rings = _phase(0.4, 1.0);
                final wordmark = _phase(0.46, 0.8, Motion.brand);
                final tagline = _phase(0.62, 0.94, Motion.brand);
                final emblem = _phase(0.56, 0.8);
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
                    // Every layer stays in the tree for the whole splash
                    // (idle ones paint nothing): adding or removing one
                    // would rebuild the emblem below and restart it.
                    _Backdrop(drift: reduced ? 0 : _progress.value, glow: glow),
                    // A soft band of light crossing once.
                    IgnorePointer(
                      child: _LightSweep(progress: reduced ? 0 : sweep),
                    ),
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
                    // Two faint rings sent outwards as the symbol lands.
                    Positioned(
                      left: center.dx - width * 1.3,
                      top: center.dy - width * 1.3,
                      width: width * 2.6,
                      height: width * 2.6,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _RipplePainter(
                            progress: reduced ? 0 : rings,
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
                        smileGlint: reduced ? 0 : glint,
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
                    // The QR emblem, scanning until the app moves on.
                    Positioned(
                      key: const ValueKey('emblem'),
                      left: 0,
                      right: 0,
                      top: emblemTop,
                      child: Center(
                        child: Opacity(
                          opacity:
                              emblem * (_startup == _Startup.failed ? 0.45 : 1),
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - emblem)),
                            child: emblem > 0
                                ? QrScanEmblem(
                                    size: emblemSize,
                                    semanticLabel: 'Preparing DineQR',
                                  )
                                : SizedBox.square(dimension: emblemSize),
                          ),
                        ),
                      ),
                    ),
                    // What the app is waiting for, or what went wrong.
                    Positioned(
                      left: AppSpacing.xxl,
                      right: AppSpacing.xxl,
                      top: emblemTop + emblemSize + 18,
                      child: AnimatedSwitcher(
                        duration: Motion.of(context, Motion.medium),
                        child: switch (_startup) {
                          _Startup.failed => _ProblemPanel(
                            key: const ValueKey('problem'),
                            message: _problem!,
                            onRetry: _retry,
                          ),
                          _ when waiting => _StatusLine(
                            key: ValueKey(_slow),
                            text: _slow
                                ? 'Still connecting. The restaurant server '
                                      'can take up to a minute to wake up.'
                                : 'Connecting to the restaurant…',
                          ),
                          _ => const SizedBox.shrink(),
                        },
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

/// Restaurant photo under a deep red-to-orange light, drifting slowly, with
/// darker edges for depth.
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
        // Vignette: the edges fall away so the logo reads first.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.15,
              colors: [Color(0x00000000), Color(0x00000000), Color(0x59140204)],
              stops: [0, 0.6, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// A wide, soft diagonal band of light that crosses the screen once.
class _LightSweep extends StatelessWidget {
  const _LightSweep({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return const SizedBox.expand();
    // Fades in and out at the ends of its journey.
    final strength = math.sin(math.pi * progress);
    final x = -1.6 + 3.2 * progress;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(x - 0.9, -1),
          end: Alignment(x + 0.9, 1),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.07 * strength),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.3, 0.5, 0.7],
        ),
      ),
    );
  }
}

/// Two thin rings growing out from the symbol and fading, one after the
/// other.
class _RipplePainter extends CustomPainter {
  const _RipplePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (final delay in [0.0, 0.22]) {
      final t = ((progress - delay) / (1 - 0.22)).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final eased = Curves.easeOutCubic.transform(t);
      canvas.drawCircle(
        center,
        maxRadius * (0.46 + 0.54 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = AppColors.peach.withValues(alpha: 0.32 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// One calm line under the emblem while the app waits for the server.
class _StatusLine extends StatelessWidget {
  const _StatusLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.label.copyWith(
          color: Colors.white.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}

/// The server could not be reached: what happened and a way to try again.
class _ProblemPanel extends StatelessWidget {
  const _ProblemPanel({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Can't reach the restaurant",
            textAlign: TextAlign.center,
            style: AppTypography.sectionTitle.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.label.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Pressable(
            onTap: onRetry,
            scale: 0.96,
            semanticLabel: 'Try again',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: 10,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadii.pill,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Try again',
                    style: AppTypography.button.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
