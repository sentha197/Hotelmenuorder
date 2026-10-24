import 'dart:async';
import 'dart:math' as math;

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/admin_theme.dart';
import '../brand/admin_backdrop.dart';
import '../brand/admin_brand.dart';
import '../state/admin_session_controller.dart';
import 'admin_login_screen.dart';

/// Where the splash hands over to.
enum AdminSplashExit { signIn, workspace }

/// The admin app's opening, shown while the saved staff session is restored.
///
/// The first frame is the native launch screen: the white DineQR symbol,
/// [AdminLoginScreen.launchMarkWidth] wide, centred on [AdminColors.navy].
/// Then, in about 1.3 seconds:
/// 1. The burgundy-to-charcoal backdrop and its red and orange lights bloom
///    in over a faint grid.
/// 2. The symbol scales up on a restrained spring while a red-to-orange
///    halo draws around it.
/// 3. "DineQR ADMIN" rises in, the accent bar extends under it, then
///    "Restaurant management", and the logo's smile catches a sparkle.
///
/// The halo keeps turning while the session is restored. If that takes a
/// while the splash says what it is waiting for, and if the server cannot
/// be reached it offers a retry or the sign-in screen, never an endless
/// spinner. Without a saved session nothing waits on the network.
///
/// Leaving for sign-in, the extras fade and the symbol settles back to its
/// launch size: the sign-in screen's first frame, so the hand-over is
/// seamless. [onFinished] says where to go.
class AdminSplashScreen extends StatefulWidget {
  const AdminSplashScreen({super.key, required this.onFinished});

  final ValueChanged<AdminSplashExit> onFinished;

  /// After this, the status says the server may be waking up (a hosted
  /// server that was idle takes a while to start).
  static const slowAfter = Duration(seconds: 8);

  @override
  State<AdminSplashScreen> createState() => _AdminSplashScreenState();
}

enum _Restore { running, done, failed }

class _AdminSplashScreenState extends State<AdminSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  _Restore _restore = _Restore.running;
  ({String title, String message})? _problem;
  bool _waiting = false;
  bool _slow = false;
  bool _leaving = false;
  int _attempts = 0;
  Timer? _waitTimer;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) _maybeFinish();
    });
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _spin.repeat();
    }
    unawaited(_restoreSession());
  }

  /// Restores the saved session. A network failure is retried once by
  /// itself (a waking server often answers the second time), then the
  /// staff member decides.
  Future<void> _restoreSession() async {
    final admin = context.read<AdminSessionController>();
    _attempts++;
    // Only say something once the wait is noticeable.
    _waitTimer ??= Timer(const Duration(milliseconds: 1600), () {
      if (mounted && _restore == _Restore.running) {
        setState(() => _waiting = true);
      }
    });
    _slowTimer ??= Timer(AdminSplashScreen.slowAfter, () {
      if (mounted && _restore == _Restore.running) {
        setState(() => _slow = true);
      }
    });
    try {
      await admin.restore();
      if (!mounted) return;
      _stopTimers();
      setState(() => _restore = _Restore.done);
      _maybeFinish();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isOffline && _attempts < 2) {
        setState(() => _slow = true);
        await Future<void>.delayed(const Duration(seconds: 1));
        if (mounted) unawaited(_restoreSession());
        return;
      }
      _stopTimers();
      setState(() {
        _restore = _Restore.failed;
        _problem = (
          title: "Can't reach the DineQR server",
          message: '${error.message} Your sign-in is kept for when it is back.',
        );
      });
    } on Object catch (error) {
      // Anything unexpected (an answer that cannot be read, storage) gets
      // the same choice as a network failure, never an endless wait.
      debugPrint('Restoring the staff session failed: $error');
      if (!mounted) return;
      _stopTimers();
      setState(() {
        _restore = _Restore.failed;
        _problem = (
          title: "Couldn't restore your session",
          message: 'Try again, or sign in again.',
        );
      });
    }
  }

  void _stopTimers() {
    _waitTimer?.cancel();
    _slowTimer?.cancel();
    _waitTimer = null;
    _slowTimer = null;
  }

  void _retry() {
    HapticFeedback.lightImpact();
    setState(() {
      _restore = _Restore.running;
      _problem = null;
      _waiting = true;
      _slow = false;
      _attempts = 0;
    });
    unawaited(_restoreSession());
  }

  /// Leaves for the sign-in screen without the session (it stays saved, so
  /// the next start restores it once the server is back).
  void _signInInstead() {
    setState(() => _restore = _Restore.done);
    _leave(AdminSplashExit.signIn);
  }

  void _maybeFinish() {
    if (_restore != _Restore.done || !_intro.isCompleted) return;
    final signedIn = context.read<AdminSessionController>().isSignedIn;
    _leave(signedIn ? AdminSplashExit.workspace : AdminSplashExit.signIn);
  }

  Future<void> _leave(AdminSplashExit exit) async {
    if (_leaving) return;
    _leaving = true;
    // The workspace cross-fades in over the splash; sign-in takes over
    // from the launch frame the splash settles into.
    if (exit == AdminSplashExit.signIn && !Motion.reduced(context)) {
      await _exit.forward();
    }
    if (mounted) widget.onFinished(exit);
  }

  @override
  void dispose() {
    _stopTimers();
    _intro.dispose();
    _spin.dispose();
    _exit.dispose();
    super.dispose();
  }

  double _phase(double begin, double end, [Curve curve = Curves.linear]) =>
      Interval(begin, end, curve: curve).transform(_intro.value);

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final reduced = Motion.reduced(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AdminColors.navy,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final screen = constraints.biggest;
            final center = screen.center(Offset.zero);
            const markWidth = AdminLoginScreen.launchMarkWidth;
            return AnimatedBuilder(
              animation: Listenable.merge([_intro, _spin, _exit]),
              builder: (context, _) {
                final exit = Curves.easeInOut.transform(_exit.value);
                final stay = 1 - exit;
                final bloom = _phase(0, 0.4);
                final grow = _phase(0.05, 0.6, Motion.spring);
                final scale = 1 + 0.12 * grow * stay;
                final halo = _phase(0.1, 0.62, Motion.emphasized);
                final lockup = _phase(0.36, 0.76, Motion.brand);
                final bar = _phase(0.5, 0.86, Motion.brand);
                final subtitle = _phase(0.6, 0.95, Motion.brand);
                final glint = _phase(0.7, 1.0);
                final markHeight = markWidth / DineQrMark.aspectRatio;
                final haloRadius = markWidth * 0.66 * scale + 12;
                // Below the halo at its largest, so the two never touch.
                final textTop = center.dy + markWidth * 0.66 * 1.12 + 12 + 26;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AdminBackdrop(reveal: bloom),
                    // A faint grid, like a floor plan, around the symbol.
                    IgnorePointer(
                      child: Opacity(
                        opacity: bloom * stay,
                        child: const RepaintBoundary(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                      ),
                    ),
                    // Light pooled behind the symbol.
                    Positioned(
                      left: center.dx - markWidth * 1.25,
                      top: center.dy - markWidth * 1.25,
                      width: markWidth * 2.5,
                      height: markWidth * 2.5,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: bloom * stay,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0x40FF6A00),
                                  Color(0x14D62828),
                                  Color(0x00D62828),
                                ],
                                stops: [0, 0.5, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The halo: it draws in, then turns while waiting.
                    Positioned(
                      left: center.dx - markWidth,
                      top: center.dy - markWidth,
                      width: markWidth * 2,
                      height: markWidth * 2,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: stay,
                          child: CustomPaint(
                            painter: _HaloPainter(
                              draw: halo,
                              turn: reduced ? 0 : _spin.value,
                              radius: haloRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: center.dx - markWidth * scale / 2,
                      top: center.dy - markHeight * scale / 2,
                      child: DineQrMark(
                        size: markWidth * scale,
                        tone: DineQrTone.inverted,
                        smileGlint: reduced ? 0 : glint,
                        semanticLabel: 'DineQR Admin',
                      ),
                    ),
                    // Identity: name, accent bar and what the app is for.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: textTop,
                      child: Opacity(
                        opacity: stay,
                        child: Column(
                          children: [
                            _Rise(
                              value: lockup,
                              child: const DineQrAdminLockup(
                                height: 46,
                                showMark: false,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Container(
                              width: 64 * bar,
                              height: 4,
                              decoration: BoxDecoration(
                                borderRadius: AppRadii.pill,
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.accentRed,
                                    AppColors.vibrantOrange,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.vibrantOrange.withValues(
                                      alpha: 0.45 * bar,
                                    ),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _Rise(
                              value: subtitle,
                              child: Text(
                                'Restaurant management',
                                style: AppTypography.bodySecondary.copyWith(
                                  color: AdminColors.frameMuted,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // What the app is waiting for, or what went wrong.
                    Positioned(
                      left: AppSpacing.xl,
                      right: AppSpacing.xl,
                      bottom: padding.bottom + AppSpacing.xxl,
                      child: Opacity(
                        opacity: stay,
                        child: AnimatedSwitcher(
                          duration: Motion.of(context, Motion.medium),
                          child: switch (_restore) {
                            _Restore.failed => _ProblemCard(
                              key: const ValueKey('problem'),
                              title: _problem!.title,
                              message: _problem!.message,
                              onRetry: _retry,
                              onSignIn: _signInInstead,
                            ),
                            _Restore.running when _waiting || _slow => _Status(
                              key: ValueKey(_slow),
                              text: _slow
                                  ? 'The DineQR server is starting up. '
                                        'This can take up to a minute.'
                                  : 'Restoring your session…',
                            ),
                            _ => const SizedBox.shrink(),
                          },
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

/// Fades [child] in while it rises a little, for [value] 0 → 1.
class _Rise extends StatelessWidget {
  const _Rise({required this.value, required this.child});

  final double value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - value)),
        child: child,
      ),
    );
  }
}

/// A faint dot grid that fades out towards the edges.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 24.0;
    final center = size.center(Offset.zero);
    final reach = size.shortestSide * 0.75;
    final dot = Paint();
    for (var x = (size.width % step) / 2; x < size.width; x += step) {
      for (var y = (size.height % step) / 2; y < size.height; y += step) {
        final distance = (Offset(x, y) - center).distance / reach;
        if (distance >= 1) continue;
        dot.color = Colors.white.withValues(alpha: 0.07 * (1 - distance));
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// A thin full ring with a red-to-orange arc that draws in ([draw]) and
/// turns ([turn], 0-1 per revolution).
class _HaloPainter extends CustomPainter {
  const _HaloPainter({
    required this.draw,
    required this.turn,
    required this.radius,
  });

  final double draw;
  final double turn;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (draw <= 0) return;
    final center = size.center(Offset.zero);
    final circle = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.08 * draw),
    );
    final sweep = math.pi * 1.4 * draw;
    final start = -math.pi / 2 + turn * 2 * math.pi;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: sweep,
      transform: GradientRotation(start),
      colors: const [
        Color(0x00D62828),
        AppColors.accentRed,
        AppColors.vibrantOrange,
        AppColors.warmOrange,
      ],
      stops: const [0, 0.35, 0.8, 1],
    ).createShader(circle);
    canvas.drawArc(
      circle,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(
      circle,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) =>
      oldDelegate.draw != draw ||
      oldDelegate.turn != turn ||
      oldDelegate.radius != radius;
}

class _Status extends StatelessWidget {
  const _Status({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.label.copyWith(color: AdminColors.frameMuted),
      ),
    );
  }
}

/// The session could not be restored (usually: the server could not be
/// reached).
class _ProblemCard extends StatelessWidget {
  const _ProblemCard({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onSignIn,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  color: AppColors.warmOrange,
                  size: 28,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.sectionTitle.copyWith(
                    color: AdminColors.frameText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySecondary.copyWith(
                    color: AdminColors.frameMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: onSignIn,
                  style: TextButton.styleFrom(
                    foregroundColor: AdminColors.frameText,
                  ),
                  child: const Text('Go to sign-in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
