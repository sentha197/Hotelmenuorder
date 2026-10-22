import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'motion.dart';

/// Base class for one-shot effects that run once when first shown (or
/// instantly when reduced motion is requested). The [delay] is folded into
/// the controller so no timers outlive the widget.
abstract class _OneShotState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin {
  Duration get delay;
  Duration get run;

  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: delay + run,
  );
  late final double _start =
      delay.inMicroseconds / (delay + run).inMicroseconds;
  bool _started = false;

  /// Maps [controller] to 0-1 over the [begin]-[end] part of the run.
  double phase(double begin, double end, [Curve curve = Curves.linear]) {
    final span = 1 - _start;
    return Interval(
      _start + span * begin,
      _start + span * end,
      curve: curve,
    ).transform(controller.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

/// Branded success emblem: a layered red-orange disc pops in, a check mark
/// draws itself, rings ripple out and QR-module confetti bursts around it.
class SuccessEmblem extends StatefulWidget {
  const SuccessEmblem({
    super.key,
    this.size = 112,
    this.delay = Duration.zero,
    this.gradient = AppColors.emberGradient,
    this.baseColor = AppColors.deepRed,
    this.burst = true,
    this.semanticLabel = 'Success',
  });

  /// Success green variant (for confirmations such as a table scan).
  const SuccessEmblem.green({
    super.key,
    this.size = 88,
    this.delay = Duration.zero,
    this.burst = false,
    this.semanticLabel = 'Success',
  }) : gradient = const LinearGradient(
         begin: Alignment.topLeft,
         end: Alignment.bottomRight,
         colors: [AppColors.successLight, AppColors.success],
       ),
       baseColor = const Color(0xFF17602F);

  final double size;
  final Duration delay;
  final Gradient gradient;
  final Color baseColor;
  final bool burst;
  final String semanticLabel;

  @override
  State<SuccessEmblem> createState() => _SuccessEmblemState();
}

class _SuccessEmblemState extends _OneShotState<SuccessEmblem> {
  @override
  Duration get delay => widget.delay;
  @override
  Duration get run => const Duration(milliseconds: 1250);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => CustomPaint(
            // Extra room around the disc for rings and confetti.
            size: Size.square(widget.size * 1.7),
            painter: _EmblemPainter(
              diameter: widget.size,
              gradient: widget.gradient,
              baseColor: widget.baseColor,
              disc: phase(0, 0.5, Curves.elasticOut),
              check: phase(0.3, 0.7, Curves.easeOutCubic),
              ring: phase(0.2, 0.85, Curves.easeOutCubic),
              burst: widget.burst ? phase(0.22, 1, Curves.easeOutCubic) : 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter({
    required this.diameter,
    required this.gradient,
    required this.baseColor,
    required this.disc,
    required this.check,
    required this.ring,
    required this.burst,
  });

  final double diameter;
  final Gradient gradient;
  final Color baseColor;
  final double disc;
  final double check;
  final double ring;
  final double burst;

  static const _confettiColors = [
    AppColors.accentRed,
    AppColors.vibrantOrange,
    AppColors.gold,
    AppColors.warmOrange,
    AppColors.primary,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = diameter / 2;

    // Ripple rings.
    if (ring > 0 && ring < 1) {
      for (var i = 0; i < 2; i++) {
        final t = (ring - i * 0.18).clamp(0.0, 1.0);
        if (t <= 0) continue;
        canvas.drawCircle(
          center,
          r * (1 + 0.55 * t),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.06 * (1 - t) + 0.5
            ..color = AppColors.vibrantOrange.withValues(alpha: 0.5 * (1 - t)),
        );
      }
    }

    // QR-module confetti flying outward.
    if (burst > 0 && burst < 1) {
      for (var i = 0; i < 12; i++) {
        final angle = i * math.pi / 6 + 0.26;
        final distance = r * (1.05 + 0.65 * burst) * (i.isEven ? 1 : 0.86);
        final position = center + Offset.fromDirection(angle, distance);
        final side = r * 0.13 * (1 - burst * 0.6);
        canvas.save();
        canvas.translate(position.dx, position.dy);
        canvas.rotate(angle + burst * math.pi);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: side, height: side),
            Radius.circular(side * 0.28),
          ),
          Paint()
            ..color = _confettiColors[i % _confettiColors.length].withValues(
              alpha: (1 - burst).clamp(0.0, 1.0),
            ),
        );
        canvas.restore();
      }
    }

    if (disc <= 0) return;
    final discRadius = r * disc.clamp(0.0, 1.15);
    // Double layer: deep base offset down, gradient disc on top, soft rim.
    canvas.drawCircle(
      center + Offset(0, r * 0.07),
      discRadius,
      Paint()..color = baseColor,
    );
    final discRect = Rect.fromCircle(center: center, radius: discRadius);
    canvas.drawCircle(
      center,
      discRadius,
      Paint()..shader = gradient.createShader(discRect),
    );
    canvas.drawCircle(
      center,
      discRadius * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(discRect),
    );

    if (check <= 0) return;
    final path = Path()
      ..moveTo(center.dx - r * 0.38, center.dy + r * 0.02)
      ..lineTo(center.dx - r * 0.1, center.dy + r * 0.3)
      ..lineTo(center.dx + r * 0.42, center.dy - r * 0.28);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.17
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawPartial(canvas, path, check, paint);
  }

  static void _drawPartial(Canvas canvas, Path path, double t, Paint paint) {
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(
      0,
      (sum, PathMetric m) => sum + m.length,
    );
    var remaining = total * t;
    for (final metric in metrics) {
      final length = math.min(remaining, metric.length);
      canvas.drawPath(metric.extractPath(0, length), paint);
      remaining -= length;
      if (remaining <= 0) break;
    }
  }

  @override
  bool shouldRepaint(_EmblemPainter oldDelegate) =>
      oldDelegate.disc != disc ||
      oldDelegate.check != check ||
      oldDelegate.ring != ring ||
      oldDelegate.burst != burst;
}

/// Wraps a favourite toggle: when [active] turns on, the child pops and a
/// ring of small hearts' sparks bursts around it.
class FavoriteBurst extends StatefulWidget {
  const FavoriteBurst({
    super.key,
    required this.active,
    required this.child,
    this.radius = 26,
  });

  final bool active;
  final Widget child;
  final double radius;

  @override
  State<FavoriteBurst> createState() => _FavoriteBurstState();
}

class _FavoriteBurstState extends State<FavoriteBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void didUpdateWidget(covariant FavoriteBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !Motion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        final animating = _controller.isAnimating;
        // Squash then overshoot.
        final scale = !animating
            ? 1.0
            : t < 0.25
            ? 1 - 0.25 * Curves.easeOut.transform(t / 0.25)
            : 0.75 + 0.25 * Curves.elasticOut.transform((t - 0.25) / 0.75);
        return CustomPaint(
          foregroundPainter: animating ? _SparkPainter(t, widget.radius) : null,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.t, this.radius);

  final double t;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final burst = Curves.easeOutCubic.transform(
      ((t - 0.15) / 0.85).clamp(0.0, 1.0),
    );
    if (burst <= 0) return;
    final opacity = (1 - burst).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      radius * (0.55 + 0.6 * burst),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * opacity
        ..color = AppColors.accentRed.withValues(alpha: opacity * 0.6),
    );
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final p =
          center + Offset.fromDirection(angle, radius * (0.7 + 0.55 * burst));
      canvas.drawCircle(
        p,
        2.6 * opacity + 0.4,
        Paint()
          ..color = (i.isEven ? AppColors.accentRed : AppColors.warmOrange)
              .withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) => oldDelegate.t != t;
}

/// Five interactive stars. Selecting a rating fills the stars in a quick
/// staggered wave with a sparkle on the chosen star.
class AnimatedStarRating extends StatelessWidget {
  const AnimatedStarRating({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 46,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var star = 1; star <= 5; star++)
          Semantics(
            button: true,
            selected: star <= value,
            label: 'Rate $star ${star == 1 ? 'star' : 'stars'}',
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('rating-star-$star'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(star);
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size * 0.08),
                child: _Star(
                  filled: star <= value,
                  // Stars fill outward from the first one.
                  delay: Duration(milliseconds: 45 * (star - 1)),
                  sparkle: star == value,
                  size: size,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Star extends StatefulWidget {
  const _Star({
    required this.filled,
    required this.delay,
    required this.sparkle,
    required this.size,
  });

  final bool filled;
  final Duration delay;
  final bool sparkle;
  final double size;

  @override
  State<_Star> createState() => _StarState();
}

class _StarState extends State<_Star> with SingleTickerProviderStateMixin {
  static const _run = Duration(milliseconds: 520);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _run,
    value: widget.filled ? 1 : 0,
  );
  double _start = 0;

  @override
  void didUpdateWidget(covariant _Star oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filled == oldWidget.filled &&
        !(widget.sparkle && !oldWidget.sparkle)) {
      return;
    }
    if (Motion.reduced(context)) {
      _controller.value = widget.filled ? 1 : 0;
      return;
    }
    if (widget.filled) {
      final total = widget.delay + _run;
      _start = widget.delay.inMicroseconds / total.inMicroseconds;
      _controller.duration = total;
      _controller.forward(from: 0);
    } else {
      _start = 0;
      _controller.duration = const Duration(milliseconds: 180);
      _controller.reverse(from: 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final raw = _controller.value;
        final t = _start >= 1
            ? raw
            : ((raw - _start) / (1 - _start)).clamp(0.0, 1.0);
        final fill = widget.filled ? Curves.easeOut.transform(t) : raw;
        final pop = widget.filled && _controller.isAnimating
            ? 1 + 0.28 * math.sin(math.pi * t)
            : 1.0;
        return CustomPaint(
          foregroundPainter:
              widget.sparkle && widget.filled && _controller.isAnimating
              ? _StarSparkle(t)
              : null,
          child: Transform.scale(
            scale: pop,
            // Bottom-aligned so the gold fill rises from the base of the star.
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: widget.size,
                  color: const Color(0xFFE7E1DF),
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: fill,
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFD866),
                          AppColors.gold,
                          Color(0xFFF2A516),
                        ],
                      ).createShader,
                      child: Icon(
                        Icons.star_rounded,
                        size: widget.size,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StarSparkle extends CustomPainter {
  _StarSparkle(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(t);
    final opacity = (1 - t).clamp(0.0, 1.0);
    final paint = Paint()
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.warmOrange.withValues(alpha: opacity);
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 - math.pi / 2;
      final inner = size.width * (0.42 + 0.18 * eased);
      final outer = inner + size.width * 0.12 * (1 - eased * 0.5);
      canvas.drawLine(
        center + Offset.fromDirection(angle, inner),
        center + Offset.fromDirection(angle, outer),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarSparkle oldDelegate) => oldDelegate.t != t;
}

/// Read-only star row (ratings already given).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 18});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rated $rating out of 5',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i <= rating ? AppColors.gold : const Color(0xFFD9D2D0),
              size: size,
            ),
        ],
      ),
    );
  }
}

/// Reveals its child with a left-to-right wipe while it rises into place.
/// One-shot; used for the order number on the success screen.
class WipeReveal extends StatefulWidget {
  const WipeReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 700),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<WipeReveal> createState() => _WipeRevealState();
}

class _WipeRevealState extends _OneShotState<WipeReveal> {
  @override
  Duration get delay => widget.delay;
  @override
  Duration get run => widget.duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final t = phase(0, 1, Curves.easeOutCubic);
        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: t,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - t)),
              child: Opacity(opacity: t, child: child),
            ),
          ),
        );
      },
    );
  }
}
