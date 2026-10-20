import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'motion.dart';

/// Signature DineQR loader: QR modules assembling into a small code. Each
/// loading context has its own indicator; this one is for the splash.
///
/// Driven by [progress] (0-1) so it always finishes with the work it
/// represents. The finder squares land first, then the data modules, and a
/// light line "scans" the finished code.
class QrAssembleLoader extends StatelessWidget {
  const QrAssembleLoader({
    super.key,
    required this.progress,
    this.size = 46,
    this.onDark = true,
  });

  final Animation<double> progress;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _QrAssemblePainter(progress, onDark: onDark),
        ),
      ),
    );
  }
}

class _QrAssemblePainter extends CustomPainter {
  _QrAssemblePainter(this.progress, {required this.onDark})
    : super(repaint: progress);

  final Animation<double> progress;
  final bool onDark;

  static const _grid = 7;

  // (row, col) for the three finder rings, then data modules in the order
  // they arrive.
  static const _finders = [
    [(0, 0), (0, 1), (0, 2), (1, 2), (2, 2), (2, 1), (2, 0), (1, 0)],
    [(0, 4), (0, 5), (0, 6), (1, 6), (2, 6), (2, 5), (2, 4), (1, 4)],
    [(4, 0), (4, 1), (4, 2), (5, 2), (6, 2), (6, 1), (6, 0), (5, 0)],
  ];
  static const _data = [
    (3, 3),
    (1, 3),
    (5, 5),
    (3, 1),
    (4, 4),
    (6, 4),
    (3, 6),
    (5, 3),
    (4, 5),
    (6, 6),
    (3, 4),
    (5, 6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final cell = size.width / _grid;
    final gap = cell * 0.14;
    final radius = Radius.circular(cell * 0.3);

    void drawCell(int row, int col, double appear, Color color) {
      if (appear <= 0) return;
      final s = Curves.easeOutBack.transform(appear.clamp(0.0, 1.0));
      final center = Offset((col + 0.5) * cell, (row + 0.5) * cell);
      final side = (cell - gap) * s;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: side, height: side),
          radius,
        ),
        Paint()..color = color.withValues(alpha: appear.clamp(0.0, 1.0)),
      );
    }

    // Finders assemble over the first 45%, cell by cell around each ring.
    final finderColor = onDark ? Colors.white : AppColors.charcoal;
    for (final (ring, cells) in _finders.indexed) {
      for (final (index, (row, col)) in cells.indexed) {
        final start = ring * 0.1 + index * 0.025;
        drawCell(row, col, (t - start) / 0.12, finderColor);
      }
    }
    // Data modules pop in over 45%-85% in brand reds and oranges.
    for (final (index, (row, col)) in _data.indexed) {
      final start = 0.42 + index * 0.033;
      final color = Color.lerp(
        AppColors.accentRed,
        AppColors.warmOrange,
        (row + col) / (_grid * 2 - 2),
      )!;
      drawCell(row, col, (t - start) / 0.1, color);
    }

    // Final scan sweep across the finished code.
    final sweep = ((t - 0.86) / 0.14).clamp(0.0, 1.0);
    if (sweep > 0 && sweep < 1) {
      final y = size.height * Curves.easeInOut.transform(sweep);
      final line = Rect.fromLTWH(
        -cell * 0.4,
        y - 1.5,
        size.width + cell * 0.8,
        3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(line, const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(
            colors: [
              AppColors.warmOrange.withValues(alpha: 0),
              AppColors.warmOrange,
              AppColors.warmOrange.withValues(alpha: 0),
            ],
          ).createShader(line)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(_QrAssemblePainter oldDelegate) =>
      oldDelegate.onDark != onDark;
}

/// Compact loader: four QR modules lighting up in turn. Used inside buttons
/// and for short local operations (placing an order, submitting feedback).
class QrPulseLoader extends StatefulWidget {
  const QrPulseLoader({
    super.key,
    this.size = 22,
    this.color = Colors.white,
    this.semanticLabel = 'Loading',
  });

  final double size;
  final Color color;
  final String semanticLabel;

  @override
  State<QrPulseLoader> createState() => _QrPulseLoaderState();
}

class _QrPulseLoaderState extends State<QrPulseLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 960),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
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
    return Semantics(
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _QrPulsePainter(_controller, widget.color),
        ),
      ),
    );
  }
}

class _QrPulsePainter extends CustomPainter {
  _QrPulsePainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  // Clockwise: top-left, top-right, bottom-right, bottom-left.
  static const _cells = [(0, 0), (0, 1), (1, 1), (1, 0)];

  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2;
    final gap = size.width * 0.12;
    final side = half - gap / 2;
    for (final (index, (row, col)) in _cells.indexed) {
      // Each module peaks a quarter cycle after the previous one.
      final phase = (progress.value - index / 4) % 1;
      final wave = 0.5 + 0.5 * math.cos(phase * 2 * math.pi);
      final scale = 0.62 + 0.38 * wave;
      final center = Offset(
        col * (side + gap) + side / 2,
        row * (side + gap) + side / 2,
      );
      final s = side * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: s, height: s),
          Radius.circular(s * 0.28),
        ),
        Paint()..color = color.withValues(alpha: 0.35 + 0.65 * wave),
      );
    }
  }

  @override
  bool shouldRepaint(_QrPulsePainter oldDelegate) => oldDelegate.color != color;
}

/// Warm shimmer for skeleton placeholders: a soft cream-to-peach highlight
/// sweeps across. Stops when reduced motion is requested.
class BrandShimmer extends StatefulWidget {
  const BrandShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<BrandShimmer> createState() => _BrandShimmerState();
}

class _BrandShimmerState extends State<BrandShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
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
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(_controller.value);
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(-2.2 + 4 * t, -0.4),
              end: Alignment(-1.0 + 4 * t, 0.4),
              colors: const [
                AppColors.skeleton,
                Color(0xFFFFF4EE),
                Color(0xFFFFE6D6),
                Color(0xFFFFF4EE),
                AppColors.skeleton,
              ],
              stops: const [0, 0.35, 0.5, 0.65, 1],
            ).createShader(bounds),
            child: child,
          );
        },
      ),
    );
  }
}

/// A placeholder block inside a [BrandShimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.skeleton,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Thin progress bar that fills with the brand gradient.
class BrandProgressBar extends StatelessWidget {
  const BrandProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.trackColor = AppColors.primarySoft,
  });

  /// 0-1. Changes animate.
  final double value;
  final double height;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: '${(value * 100).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: trackColor),
              TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0.0, 1.0)),
                duration: Motion.of(context, const Duration(milliseconds: 650)),
                curve: Motion.standard,
                builder: (context, fill, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fill,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.emberGradient,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
