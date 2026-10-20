import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'dineqr_logo.dart';

/// Soft, translucent red-orange waves sweeping up from the bottom-right, as
/// on the DineQR brand backgrounds. Static and cheap to paint.
class BrandWavesPainter extends CustomPainter {
  const BrandWavesPainter({this.intensity = 1, this.shift = 0});

  /// Overall opacity multiplier.
  final double intensity;

  /// Horizontal drift (0-1) for subtle parallax.
  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final dx = shift * w * 0.08;

    Path wave(double startY, double c1y, double c2y, double endY) => Path()
      ..moveTo(-20 + dx, h * startY)
      ..cubicTo(w * 0.35 + dx, h * c1y, w * 0.6 + dx, h * c2y, w + 20, h * endY)
      ..lineTo(w + 20, h + 20)
      ..lineTo(-20, h + 20)
      ..close();

    final rect = Offset.zero & size;
    canvas.drawPath(
      wave(0.78, 0.62, 1.02, 0.38),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            AppColors.accentRed.withValues(alpha: 0),
            AppColors.accentRed.withValues(alpha: 0.32 * intensity),
          ],
        ).createShader(rect),
    );
    canvas.drawPath(
      wave(0.92, 0.8, 1.05, 0.6),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.vibrantOrange.withValues(alpha: 0),
            AppColors.vibrantOrange.withValues(alpha: 0.22 * intensity),
          ],
        ).createShader(rect),
    );
    // A thin highlight edge along the top wave.
    canvas.drawPath(
      Path()
        ..moveTo(-20 + dx, h * 0.78)
        ..cubicTo(
          w * 0.35 + dx,
          h * 0.62,
          w * 0.6 + dx,
          h * 1.02,
          w + 20,
          h * 0.38,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            AppColors.warmOrange.withValues(alpha: 0.45 * intensity),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(BrandWavesPainter oldDelegate) =>
      oldDelegate.intensity != intensity || oldDelegate.shift != shift;
}

/// Deep red brand panel with layered waves. Used for headers, banners and
/// brand moments; content goes in [child].
class BrandPanel extends StatelessWidget {
  const BrandPanel({
    super.key,
    this.child,
    this.borderRadius = BorderRadius.zero,
    this.gradient = AppColors.brandGradient,
    this.waves = true,
    this.watermark = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget? child;
  final BorderRadius borderRadius;
  final Gradient gradient;
  final bool waves;

  /// Shows a faint oversized logo symbol in the corner.
  final bool watermark;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Stack(
          children: [
            if (waves)
              const Positioned.fill(
                child: CustomPaint(painter: BrandWavesPainter()),
              ),
            if (watermark)
              const Positioned(
                right: -36,
                top: -18,
                child: Opacity(
                  opacity: 0.08,
                  child: DineQrMark(
                    size: 190,
                    tone: DineQrTone.mono,
                    monoColor: Colors.white,
                    semanticLabel: null,
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Small rounded "QR module" squares used as brand decoration.
class QrModuleDots extends StatelessWidget {
  const QrModuleDots({super.key, this.size = 8, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color) => Container(
      width: size,
      height: size,
      margin: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
    );
    final first = onDark ? Colors.white : AppColors.primary;
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [dot(first), dot(AppColors.vibrantOrange)],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [dot(AppColors.warmOrange), dot(first)],
          ),
        ],
      ),
    );
  }
}
