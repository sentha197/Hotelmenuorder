import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
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

/// QR-scanner loader for the splash: four corner brackets draw in, then a
/// single scan line sweeps between them until the widget is removed. With
/// reduced motion it shows the brackets and a still line.
class QrScanLoader extends StatefulWidget {
  const QrScanLoader({
    super.key,
    this.size = 44,
    this.onDark = true,
    this.semanticLabel = 'Loading',
  });

  final double size;
  final bool onDark;
  final String semanticLabel;

  @override
  State<QrScanLoader> createState() => _QrScanLoaderState();
}

class _QrScanLoaderState extends State<QrScanLoader>
    with TickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _appear.value = 1;
      _sweep.value = 0.5;
      return;
    }
    _appear.forward().whenComplete(() {
      if (mounted) _sweep.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _appear.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _QrScanPainter(
            appear: _appear,
            sweep: _sweep,
            onDark: widget.onDark,
          ),
        ),
      ),
    );
  }
}

class _QrScanPainter extends CustomPainter {
  _QrScanPainter({
    required this.appear,
    required this.sweep,
    required this.onDark,
  }) : super(repaint: Listenable.merge([appear, sweep]));

  final Animation<double> appear;
  final Animation<double> sweep;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.075;
    final arm = s * 0.3;
    final inset = stroke / 2;
    final rect = Rect.fromLTWH(inset, inset, s - stroke, s - stroke);
    final drawn = Motion.brand.transform(appear.value);
    final color = onDark ? Colors.white : AppColors.primary;
    final bracket = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Corner brackets grow out from each corner.
    final length = arm * drawn;
    if (length > 0) {
      for (final (corner, dx, dy) in [
        (rect.topLeft, 1.0, 1.0),
        (rect.topRight, -1.0, 1.0),
        (rect.bottomLeft, 1.0, -1.0),
        (rect.bottomRight, -1.0, -1.0),
      ]) {
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx, corner.dy + dy * length)
            ..lineTo(corner.dx, corner.dy)
            ..lineTo(corner.dx + dx * length, corner.dy),
          bracket,
        );
      }
    }

    // One scan line sweeping between the brackets, with a soft trail.
    if (drawn < 1) return;
    final travel = Curves.easeInOutSine.transform(sweep.value);
    final y = rect.top + stroke * 1.6 + (rect.height - stroke * 3.2) * travel;
    final left = rect.left + stroke * 1.4;
    final right = rect.right - stroke * 1.4;
    final goingDown = sweep.status != AnimationStatus.reverse;
    final trail = s * 0.22;
    canvas.drawRect(
      Rect.fromLTRB(
        left,
        goingDown ? y - trail : y,
        right,
        goingDown ? y : y + trail,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: goingDown ? Alignment.bottomCenter : Alignment.topCenter,
          end: goingDown ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            AppColors.warmOrange.withValues(alpha: 0.35),
            AppColors.warmOrange.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTRB(left, y - trail, right, y + trail)),
    );
    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      Paint()
        ..color = onDark ? AppColors.peach : AppColors.vibrantOrange
        ..strokeWidth = stroke * 0.7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_QrScanPainter oldDelegate) =>
      oldDelegate.onDark != onDark;
}

/// The splash's QR emblem: a small, stylised QR glyph on a frosted tile,
/// framed by scanner brackets. The finder squares and modules assemble, then
/// a scan line sweeps the glyph while a soft glow breathes behind it, until
/// the widget is removed. With reduced motion it shows the finished emblem
/// with a still line.
///
/// It is decoration, not a code: a 7 × 7 glyph cannot be scanned (a real QR
/// code has at least 21 × 21 modules), and it is announced as [semanticLabel]
/// ("Loading" by default), never as a QR code.
class QrScanEmblem extends StatefulWidget {
  const QrScanEmblem({
    super.key,
    this.size = 72,
    this.onDark = true,
    this.semanticLabel = 'Loading',
  });

  final double size;
  final bool onDark;
  final String semanticLabel;

  @override
  State<QrScanEmblem> createState() => _QrScanEmblemState();
}

class _QrScanEmblemState extends State<QrScanEmblem>
    with TickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _appear.value = 1;
      _sweep.value = 0.5;
      return;
    }
    _appear.forward().whenComplete(() {
      if (mounted) _sweep.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _appear.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _QrEmblemPainter(
            appear: _appear,
            sweep: _sweep,
            onDark: widget.onDark,
          ),
        ),
      ),
    );
  }
}

class _QrEmblemPainter extends CustomPainter {
  _QrEmblemPainter({
    required this.appear,
    required this.sweep,
    required this.onDark,
  }) : super(repaint: Listenable.merge([appear, sweep]));

  final Animation<double> appear;
  final Animation<double> sweep;
  final bool onDark;

  static const _grid = 7;

  /// Top-left cells of the three finder squares.
  static const _finders = [(0, 0), (0, 4), (4, 0)];

  /// Data modules (row, column), in the order they arrive.
  static const _data = [
    (3, 3),
    (1, 3),
    (4, 4),
    (3, 1),
    (5, 5),
    (3, 5),
    (6, 3),
    (4, 6),
    (6, 6),
  ];

  static double _phase(double t, double begin, double end) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final t = appear.value;
    final scanning = t >= 1;
    // One slow breath per sweep there and back.
    final breath = scanning
        ? 0.5 - 0.5 * math.cos(sweep.value * math.pi)
        : Curves.easeOut.transform(t) * 0.5;
    final center = Offset(s / 2, s / 2);
    final tile = Rect.fromCenter(
      center: center,
      width: s * 0.86,
      height: s * 0.86,
    );
    final tileShape = RRect.fromRectAndRadius(tile, Radius.circular(s * 0.2));

    // Soft glow behind the tile.
    canvas.drawCircle(
      center,
      s * 0.56,
      Paint()
        ..color = AppColors.warmOrange.withValues(
          alpha: (0.1 + 0.16 * breath) * Curves.easeOut.transform(t),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.16),
    );

    // Frosted tile.
    final tileIn = Curves.easeOut.transform(_phase(t, 0, 0.35));
    canvas.drawRRect(
      tileShape,
      Paint()
        ..color = (onDark ? Colors.white : AppColors.primarySoft).withValues(
          alpha: (onDark ? 0.1 : 1.0) * tileIn,
        ),
    );
    canvas.drawRRect(
      tileShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s * 0.016)
        ..color = (onDark ? Colors.white : AppColors.primary).withValues(
          alpha: 0.24 * tileIn,
        ),
    );

    // Scanner brackets grow out from each corner.
    final arm = s * 0.2 * Motion.brand.transform(_phase(t, 0.05, 0.5));
    if (arm > 0) {
      final bracket = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.045
        ..strokeCap = StrokeCap.round
        ..color = onDark ? Colors.white : AppColors.primary;
      final r = tile.inflate(s * 0.03);
      for (final (corner, dx, dy) in [
        (r.topLeft, 1.0, 1.0),
        (r.topRight, -1.0, 1.0),
        (r.bottomLeft, 1.0, -1.0),
        (r.bottomRight, -1.0, -1.0),
      ]) {
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx, corner.dy + dy * arm)
            ..lineTo(corner.dx, corner.dy)
            ..lineTo(corner.dx + dx * arm, corner.dy),
          bracket,
        );
      }
    }

    // The glyph: finder squares land first, then the modules pop in.
    final glyph = Rect.fromCenter(
      center: center,
      width: s * 0.52,
      height: s * 0.52,
    );
    final cell = glyph.width / _grid;
    final ink = onDark ? Colors.white : AppColors.charcoal;
    for (final (index, (row, col)) in _finders.indexed) {
      final f = Curves.easeOutBack.transform(
        _phase(t, 0.2 + index * 0.08, 0.5 + index * 0.08),
      );
      if (f <= 0) continue;
      final box = Rect.fromLTWH(
        glyph.left + col * cell,
        glyph.top + row * cell,
        cell * 3,
        cell * 3,
      );
      canvas.save();
      canvas.translate(box.center.dx, box.center.dy);
      canvas.scale(f);
      canvas.translate(-box.center.dx, -box.center.dy);
      final opacity = f.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          box.deflate(cell * 0.4),
          Radius.circular(cell * 0.7),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.8
          ..color = ink.withValues(alpha: opacity),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: box.center,
            width: cell * 1.05,
            height: cell * 1.05,
          ),
          Radius.circular(cell * 0.3),
        ),
        Paint()..color = ink.withValues(alpha: opacity),
      );
      canvas.restore();
    }
    for (final (index, (row, col)) in _data.indexed) {
      final d = Curves.easeOutBack.transform(
        _phase(t, 0.45 + index * 0.045, 0.62 + index * 0.045),
      );
      if (d <= 0) continue;
      final colour = Color.lerp(
        onDark ? AppColors.warmOrange : AppColors.accentRed,
        onDark ? AppColors.peach : AppColors.vibrantOrange,
        (row + col) / (_grid * 2 - 2),
      )!;
      final side = cell * 0.82 * d;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              glyph.left + (col + 0.5) * cell,
              glyph.top + (row + 0.5) * cell,
            ),
            width: side,
            height: side,
          ),
          Radius.circular(side * 0.3),
        ),
        Paint()..color = colour.withValues(alpha: d.clamp(0.0, 1.0)),
      );
    }

    // The scan line, once the glyph is complete, inside the tile.
    if (!scanning) return;
    canvas.save();
    canvas.clipRRect(tileShape);
    final travel = Curves.easeInOutSine.transform(sweep.value);
    final top = glyph.top - cell * 0.6;
    final y = top + (glyph.height + cell * 1.2) * travel;
    final goingDown = sweep.status != AnimationStatus.reverse;
    final trail = s * 0.2;
    final left = tile.left + s * 0.08;
    final right = tile.right - s * 0.08;
    canvas.drawRect(
      Rect.fromLTRB(
        left,
        goingDown ? y - trail : y,
        right,
        goingDown ? y : y + trail,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: goingDown ? Alignment.bottomCenter : Alignment.topCenter,
          end: goingDown ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            AppColors.warmOrange.withValues(alpha: 0.3),
            AppColors.warmOrange.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTRB(left, y - trail, right, y + trail)),
    );
    final line = Rect.fromLTRB(left, y - s * 0.017, right, y + s * 0.017);
    canvas.drawRRect(
      RRect.fromRectAndRadius(line, Radius.circular(s * 0.02)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.peach.withValues(alpha: 0),
            onDark ? Colors.white : AppColors.vibrantOrange,
            AppColors.peach.withValues(alpha: 0),
          ],
        ).createShader(line),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QrEmblemPainter oldDelegate) =>
      oldDelegate.onDark != onDark;
}
