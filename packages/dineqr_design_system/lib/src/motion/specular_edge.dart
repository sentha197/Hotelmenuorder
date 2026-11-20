import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'motion.dart';

/// A light that runs around [child]'s rounded edge over a faint hairline,
/// with a soft bloom (the web apps' SpecularButton). It paints over the
/// child's edge only and takes no touches. With reduced motion the light
/// stays put; it stops ticking when its route or tab is not shown.
class SpecularEdge extends StatefulWidget {
  const SpecularEdge({
    super.key,
    required this.child,
    this.borderRadius = 100,
    this.lineColor = AppColors.vibrantOrange,
    this.baseColor = const Color(0xFFF5D0C2),
    this.intensity = 0.9,
    this.shineSize = 12,
    this.shineFade = 40,
    this.thickness = 2,
    this.glow = 1,
    this.lap = const Duration(seconds: 2),
  });

  /// Tests set this to false to hold every light still, so `pumpAndSettle`
  /// can check that nothing else keeps animating (the light never settles:
  /// it circles for as long as it is shown).
  static bool debugAnimate = true;

  final Widget child;

  /// Corner radius (clamped to half the height, so 100 is a pill).
  final double borderRadius;

  /// Colour of the travelling light.
  final Color lineColor;

  /// Colour of the faint hairline the light runs along.
  final Color baseColor;

  /// Strength of the light (0 to about 1.5).
  final double intensity;

  /// Half-length of the light's bright core, then the length of its fade.
  final double shineSize;
  final double shineFade;

  /// Width of the edge line.
  final double thickness;

  /// Strength of the bloom outside the edge (0 for none).
  final double glow;

  /// Time for one lap: shorter is faster.
  final Duration lap;

  @override
  State<SpecularEdge> createState() => _SpecularEdgeState();
}

class _SpecularEdgeState extends State<SpecularEdge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.lap,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SpecularEdge old) {
    super.didUpdateWidget(old);
    if (old.lap != widget.lap) {
      _controller.duration = widget.lap;
      _sync(restart: true);
    }
  }

  void _sync({bool restart = false}) {
    if (Motion.reduced(context) || !SpecularEdge.debugAnimate) {
      _controller
        ..stop()
        ..value = 0.06;
    } else if (restart || !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _SpecularPainter(
        progress: _controller,
        radius: widget.borderRadius,
        line: widget.lineColor,
        base: widget.baseColor,
        intensity: widget.intensity,
        core: widget.shineSize,
        fade: widget.shineFade,
        thickness: widget.thickness,
        glow: widget.glow,
      ),
      child: widget.child,
    );
  }
}

class _SpecularPainter extends CustomPainter {
  _SpecularPainter({
    required this.progress,
    required this.radius,
    required this.line,
    required this.base,
    required this.intensity,
    required this.core,
    required this.fade,
    required this.thickness,
    required this.glow,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double radius;
  final Color line;
  final Color base;
  final double intensity;
  final double core;
  final double fade;
  final double thickness;
  final double glow;

  /// Pieces the light is drawn in on each side of its centre.
  static const _steps = 14;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final inset = thickness / 2;
    final rect = (Offset.zero & size).deflate(inset);
    final r = math.min(radius, rect.shortestSide / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
    final metric = path.computeMetrics().first;
    final length = metric.length;

    // The hairline all round.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = base.withValues(alpha: 0.45),
    );

    // The light: short pieces either side of its centre, brightest in the
    // middle, running to white at the core like a highlight. Starts at the
    // top left and runs clockwise.
    final strength = 1 - math.exp(-intensity * 2.4);
    final reach = core + fade * 1.6;
    final centre = progress.value * length + r * math.pi / 4;
    final piece = reach / _steps;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    final bloom = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness * 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * glow);
    for (var k = -_steps; k < _steps; k++) {
      final from = k * piece;
      final mid = from + piece / 2;
      final far = math.max(mid.abs() - core, 0) / fade;
      final shine = math.exp(-far * far) * strength;
      if (shine < 0.02) continue;
      final hot = (mid.abs() < core ? 1 - mid.abs() / core : 0.0) * 0.6;
      final colour = Color.lerp(line, Colors.white, hot)!;
      final segment = _extract(
        metric,
        length,
        centre + from,
        centre + from + piece,
      );
      if (glow > 0) {
        canvas.drawPath(
          segment,
          bloom
            ..color = line.withValues(alpha: (shine * 0.55 * glow).clamp(0, 1)),
        );
      }
      canvas.drawPath(segment, stroke..color = colour.withValues(alpha: shine));
    }
  }

  /// The edge from [start] to [end] (wrapping past the end of the loop).
  static Path _extract(
    PathMetric metric,
    double length,
    double start,
    double end,
  ) {
    final a = start % length;
    final b = a + (end - start);
    if (b <= length) return metric.extractPath(a, b);
    return metric.extractPath(a, length)
      ..addPath(metric.extractPath(0, b - length), Offset.zero);
  }

  @override
  bool shouldRepaint(_SpecularPainter old) =>
      old.radius != radius ||
      old.line != line ||
      old.base != base ||
      old.intensity != intensity ||
      old.core != core ||
      old.fade != fade ||
      old.thickness != thickness ||
      old.glow != glow;
}
