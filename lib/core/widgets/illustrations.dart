import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../animations/motion.dart';
import '../brand/dineqr_logo.dart';

/// A restaurant table with a DineQR table tent on top and the table number
/// on its front.
class TableIllustration extends StatelessWidget {
  const TableIllustration({super.key, required this.label, this.width = 120});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Table $label',
      image: true,
      child: CustomPaint(
        size: Size(width, width * 0.92),
        painter: _TablePainter(label),
      ),
    );
  }
}

class _TablePainter extends CustomPainter {
  const _TablePainter(this.label);

  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // The table occupies the lower part; the tent card stands on it.
    final h = size.height;
    final top = h * 0.3;
    final tableH = h - top;
    Paint fill(Color color) => Paint()..color = color;
    RRect box(double l, double t, double r, double b, double radius) =>
        RRect.fromLTRBR(
          w * l,
          top + tableH * t,
          w * r,
          top + tableH * b,
          Radius.circular(radius),
        );

    // Back legs, front legs, apron.
    canvas.drawRRect(
      box(0.25, 0.5, 0.31, 0.8, 2),
      fill(const Color(0xFF4F2C17)),
    );
    canvas.drawRRect(
      box(0.69, 0.5, 0.75, 0.8, 2),
      fill(const Color(0xFF4F2C17)),
    );
    canvas.drawRRect(
      box(0.13, 0.52, 0.21, 0.98, 3),
      fill(const Color(0xFF6B3A1C)),
    );
    canvas.drawRRect(
      box(0.79, 0.52, 0.87, 0.98, 3),
      fill(const Color(0xFF6B3A1C)),
    );
    canvas.drawRRect(
      box(0.1, 0.34, 0.9, 0.6, 4),
      fill(const Color(0xFF7A4321)),
    );
    // Table top with a lighter front edge.
    canvas.drawRRect(
      box(0, 0.16, 1, 0.36, w * 0.04),
      fill(const Color(0xFF9C5A2E)),
    );
    canvas.drawRRect(
      box(0, 0.16, 1, 0.23, w * 0.04),
      fill(const Color(0xFFB8733F)),
    );

    // DineQR table tent: a white card with a mini QR, standing on the table.
    final tentBottom = top + tableH * 0.18;
    final tent = Path()
      ..moveTo(w * 0.36, tentBottom)
      ..lineTo(w * 0.4, h * 0.02)
      ..lineTo(w * 0.6, h * 0.02)
      ..lineTo(w * 0.64, tentBottom)
      ..close();
    canvas.drawShadow(tent, Colors.black, 3, false);
    canvas.drawPath(tent, fill(Colors.white));
    canvas.drawRect(
      Rect.fromLTRB(w * 0.4, h * 0.02, w * 0.6, h * 0.055),
      fill(AppColors.primary),
    );
    final cell = w * 0.052;
    final qrLeft = w * 0.5 - cell * 1.1;
    final qrTop = h * 0.09;
    const colors = [
      AppColors.charcoal,
      AppColors.vibrantOrange,
      AppColors.accentRed,
      AppColors.charcoal,
    ];
    for (var i = 0; i < 4; i++) {
      final x = qrLeft + (i % 2) * cell * 1.2;
      final y = qrTop + (i ~/ 2) * cell * 1.2;
      canvas.drawRRect(
        RRect.fromLTRBR(x, y, x + cell, y + cell, Radius.circular(cell * 0.25)),
        fill(colors[i]),
      );
    }

    // Table number on the apron.
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: tableH * 0.17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((w - painter.width) / 2, top + tableH * 0.47 - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_TablePainter oldDelegate) => oldDelegate.label != label;
}

/// One-shot confetti of brand-coloured QR modules that drifts into place and
/// stays as decoration.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.pieceCount = 26, this.seed = 7});

  final int pieceCount;
  final int seed;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiPiece {
  _ConfettiPiece(math.Random rng)
    : x = rng.nextDouble(),
      endY = 0.02 + rng.nextDouble() * 0.2,
      startY = -0.08 - rng.nextDouble() * 0.2,
      rotation = rng.nextDouble() * math.pi,
      spin = (rng.nextDouble() - 0.5) * 6,
      delay = rng.nextDouble() * 0.35,
      size = 4 + rng.nextDouble() * 5,
      round = rng.nextDouble() < 0.2,
      color = _colors[rng.nextInt(_colors.length)];

  static const _colors = [
    AppColors.primary,
    AppColors.gold,
    AppColors.accentRed,
    AppColors.vibrantOrange,
    AppColors.warmOrange,
  ];

  final double x;
  final double endY;
  final double startY;
  final double rotation;
  final double spin;
  final double delay;
  final double size;
  final bool round;
  final Color color;
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final List<_ConfettiPiece> _pieces = () {
    final rng = math.Random(widget.seed);
    return List.generate(widget.pieceCount, (_) => _ConfettiPiece(rng));
  }();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ConfettiPainter(_pieces, _controller),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.progress) : super(repaint: progress);

  final List<_ConfettiPiece> pieces;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final eased = Curves.easeOutCubic.transform(local);
      final y = (p.startY + (p.endY - p.startY) * eased) * size.height;
      final x = p.x * size.width + math.sin(eased * math.pi * 2) * 6;
      final opacity = math.min(1.0, local * 4) * 0.85;
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + p.spin * eased);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size),
            Radius.circular(p.size * 0.28),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => false;
}

/// Branded empty cart: a red shopping bag carrying the DineQR symbol, with a
/// few QR modules floating around it.
class EmptyCartIllustration extends StatelessWidget {
  const EmptyCartIllustration({super.key, this.size = 150});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.orangeSoft, AppColors.paleWarm],
                  stops: [0.5, 1],
                ),
              ),
            ),
            CustomPaint(
              size: Size(size * 0.5, size * 0.56),
              painter: const _BagPainter(),
            ),
            Positioned(
              top: size * 0.47,
              child: DineQrMark(
                size: size * 0.3,
                tone: DineQrTone.inverted,
                semanticLabel: null,
              ),
            ),
            for (final (dx, dy, s, color) in const [
              (0.16, 0.24, 0.06, AppColors.vibrantOrange),
              (0.8, 0.2, 0.05, AppColors.primary),
              (0.85, 0.66, 0.065, AppColors.warmOrange),
              (0.12, 0.7, 0.045, AppColors.accentRed),
            ])
              Positioned(
                left: size * dx,
                top: size * dy,
                child: Transform.rotate(
                  angle: dx * 2,
                  child: Container(
                    width: size * s,
                    height: size * s,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(size * s * 0.3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BagPainter extends CustomPainter {
  const _BagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = RRect.fromLTRBR(0, h * 0.28, w, h, Radius.circular(w * 0.14));
    // Handle.
    canvas.drawArc(
      Rect.fromLTRB(w * 0.26, h * 0.04, w * 0.74, h * 0.52),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.075
        ..strokeCap = StrokeCap.round
        ..color = AppColors.deepRed,
    );
    // Double layer: deep base, gradient face.
    canvas.drawRRect(
      body.shift(Offset(0, h * 0.035)),
      Paint()..color = AppColors.deepRed,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentRed, AppColors.primary, AppColors.deepRed],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        w * 0.08,
        h * 0.31,
        w * 0.92,
        h * 0.36,
        Radius.circular(w * 0.03),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_BagPainter oldDelegate) => false;
}
