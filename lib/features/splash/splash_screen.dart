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
/// 1. The restaurant photo fades up from black under a dark red light, with
///    a slow zoom.
/// 2. A warm glow blooms and the symbol draws itself in, followed by a
///    highlight sweep.
/// 3. "DineQR" rises out of a mask, then the tagline appears.
/// 4. QR modules assemble into a small code as the loading indicator.
/// 5. Fades through to the QR scanner exactly once.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 2600),
  });

  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ember,
        body: AnimatedBuilder(
          animation: Listenable.merge([_intro, _progress]),
          builder: (context, _) {
            final glow = _phase(0.05, 0.5, Motion.brand);
            final reveal = _phase(0.08, 0.62);
            final sheen = reduced ? null : _phase(0.64, 0.92, Curves.easeInOut);
            final wordmark = _phase(0.46, 0.76, Motion.brand);
            final tagline = _phase(0.66, 0.96, Motion.brand);
            final loader = _phase(0.35, 0.7);
            return Stack(
              fit: StackFit.expand,
              children: [
                // Stage 1: background photo, slow zoom-out with a gentle lift.
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
                  decoration: BoxDecoration(gradient: AppColors.splashOverlay),
                ),
                CustomPaint(
                  painter: BrandWavesPainter(
                    intensity: 0.25 + 0.4 * glow,
                    shift: _progress.value,
                  ),
                ),
                // Fade up from black.
                IgnorePointer(
                  child: ColoredBox(
                    color: AppColors.ember.withValues(
                      alpha: 1 - _phase(0, 0.28, Curves.easeOut),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      const Spacer(flex: 5),
                      // Stage 2: glow + symbol.
                      SizedBox(
                        width: 260,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: glow,
                              child: Transform.scale(
                                scale: 0.6 + 0.4 * glow,
                                child: Container(
                                  width: 260,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        AppColors.vibrantOrange.withValues(
                                          alpha: 0.42,
                                        ),
                                        AppColors.accentRed.withValues(
                                          alpha: 0.16,
                                        ),
                                        AppColors.accentRed.withValues(
                                          alpha: 0,
                                        ),
                                      ],
                                      stops: const [0, 0.45, 1],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            DineQrMark(
                              size: 176,
                              tone: DineQrTone.inverted,
                              reveal: reveal,
                              sheen: sheen,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Stage 3: wordmark rises out of a mask, then tagline.
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
                      const Spacer(flex: 6),
                      // Stage 4: signature loader.
                      Opacity(
                        opacity: loader,
                        child: QrAssembleLoader(progress: _progress, size: 40),
                      ),
                      const SizedBox(height: 44),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
