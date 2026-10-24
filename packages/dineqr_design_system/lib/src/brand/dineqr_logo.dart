import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// How the DineQR symbol is coloured.
enum DineQrTone {
  /// Full-colour symbol for light surfaces: red outline, red-orange
  /// highlight layer and orange QR modules.
  color,

  /// White symbol with orange QR accents, for red and dark surfaces.
  inverted,

  /// One flat colour (watermarks, monochrome contexts).
  mono,
}

/// The DineQR symbol: a chef-hat outline with a fork, a spoon and a QR motif,
/// drawn as vector paths so it stays sharp at every size.
///
/// [reveal] (0-1) stages the symbol in: the hat outline draws around, the
/// cutlery rises, the QR modules pop in and the swoosh sweeps underneath.
/// [sheen] (0-1) moves a soft highlight across the symbol.
///
/// The swoosh under the cutlery is the logo's smile. [smile] (0-1) animates
/// it on its own for the splash signature: it starts as a faint, flatter
/// curve, draws itself from left to right, deepens into its full curve and
/// settles in place. [smileGlow] (0-1) adds a warm glow beneath it, and
/// [smileGlint] (0-1) a brief sparkle at its tip that grows, turns and fades.
/// Only the smile's own path is animated; the rest of the logo is untouched.
class DineQrMark extends StatelessWidget {
  const DineQrMark({
    super.key,
    this.size = 96,
    this.tone = DineQrTone.color,
    this.monoColor = AppColors.primary,
    this.reveal = 1,
    this.sheen,
    this.smile,
    this.smileGlow = 0,
    this.smileGlint = 0,
    this.semanticLabel = 'DineQR logo',
  });

  /// Width of the symbol. Height follows the symbol's aspect ratio.
  final double size;
  final DineQrTone tone;
  final Color monoColor;
  final double reveal;
  final double? sheen;
  final double? smile;
  final double smileGlow;
  final double smileGlint;
  final String? semanticLabel;

  static const aspectRatio = _MarkGeometry.width / _MarkGeometry.height;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size(size, size / aspectRatio),
      painter: DineQrMarkPainter(
        tone: tone,
        monoColor: monoColor,
        reveal: reveal,
        sheen: sheen,
        smile: smile,
        smileGlow: smileGlow,
        smileGlint: smileGlint,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

/// Paints the DineQR symbol scaled to fit (and centred in) its size.
class DineQrMarkPainter extends CustomPainter {
  const DineQrMarkPainter({
    this.tone = DineQrTone.color,
    this.monoColor = AppColors.primary,
    this.reveal = 1,
    this.sheen,
    this.smile,
    this.smileGlow = 0,
    this.smileGlint = 0,
  });

  final DineQrTone tone;
  final Color monoColor;
  final double reveal;
  final double? sheen;

  /// Smile progress (see [DineQrMark.smile]); null follows [reveal].
  final double? smile;
  final double smileGlow;

  /// Sparkle at the smile's tip (see [DineQrMark.smileGlint]).
  final double smileGlint;

  static double _interval(double t, double begin, double end) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal <= 0) return;
    const w = _MarkGeometry.width;
    const h = _MarkGeometry.height;
    final scale = math.min(size.width / w, size.height / h);
    canvas.save();
    canvas.translate(
      (size.width - w * scale) / 2,
      (size.height - h * scale) / 2,
    );
    canvas.scale(scale);

    final sheenValue = sheen;
    final useSheen = sheenValue != null && sheenValue > 0 && sheenValue < 1;
    if (useSheen) {
      canvas.saveLayer(const Rect.fromLTWH(-8, -8, w + 16, h + 16), Paint());
    }

    final colors = _MarkColors.of(tone, monoColor);
    final staged = reveal < 1;

    // 1. Hat outline: drawn around from the bottom-left, like a pen stroke.
    final hat = staged
        ? Curves.easeInOutCubic.transform(_interval(reveal, 0, 0.55))
        : 1.0;
    if (hat > 0) {
      canvas.save();
      if (hat < 1) canvas.clipPath(_MarkGeometry.sweepClip(hat));
      _layered(canvas, _MarkGeometry.ribbon, colors.ribbon, colors.depth);
      _layered(canvas, _MarkGeometry.rightLobe, colors.rightLobe, colors.depth);
      canvas.restore();
    }

    // 2. Fork and spoon rise into place.
    final cutlery = staged
        ? Curves.easeOutCubic.transform(_interval(reveal, 0.3, 0.72))
        : 1.0;
    if (cutlery > 0) {
      _faded(canvas, cutlery, () {
        canvas.translate(0, (1 - cutlery) * 16);
        _layered(canvas, _MarkGeometry.fork, colors.cutlery, colors.depth);
        _layered(canvas, _MarkGeometry.spoon, colors.cutlery, colors.depth);
      });
    }

    // 3. QR modules pop in one after another.
    for (final (index, module) in _MarkGeometry.qrModules.indexed) {
      final t = staged
          ? Curves.easeOutBack.transform(
              _interval(reveal, 0.5 + index * 0.07, 0.68 + index * 0.07),
            )
          : 1.0;
      if (t <= 0) continue;
      final center = module.bounds.center;
      _faded(canvas, t.clamp(0.0, 1.0), () {
        canvas.translate(center.dx, center.dy);
        canvas.scale(t);
        canvas.translate(-center.dx, -center.dy);
        _layered(canvas, module.path, colors.qr[index], colors.depth);
      });
    }

    // 4. The swoosh (the smile) sweeps underneath, in front of the cutlery.
    final smileValue = smile;
    if (smileValue != null) {
      _paintSmile(canvas, smileValue.clamp(0.0, 1.0), colors);
    }
    final swoosh = smileValue != null
        ? 0.0
        : staged
        ? Curves.easeInOutCubic.transform(_interval(reveal, 0.55, 0.95))
        : 1.0;
    if (swoosh > 0) {
      canvas.save();
      if (swoosh < 1) {
        canvas.clipRect(Rect.fromLTWH(0, 0, 8 + (w - 8) * swoosh, h));
      }
      _layered(canvas, _MarkGeometry.swoosh, colors.swoosh, colors.depth);
      canvas.restore();
    }
    _paintGlint(canvas, smileGlint, colors);

    if (useSheen) {
      // A soft diagonal light band, painted only where the symbol is.
      final x = -w * 0.4 + w * 1.8 * sheenValue;
      canvas.drawRect(
        const Rect.fromLTWH(-8, -8, w + 16, h + 16),
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = LinearGradient(
            begin: const Alignment(-1, -0.35),
            end: const Alignment(1, 0.35),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: colors.sheenStrength),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(x - 34, -20, 68, h + 40)),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  /// The smile signature (see [DineQrMark.smile]), in design-space units.
  void _paintSmile(Canvas canvas, double t, _MarkColors colors) {
    final path = _MarkGeometry.swoosh;
    final bounds = path.getBounds();
    // The smile's corners sit on its top edge; scaling about that line
    // deepens the curve while the corners stay where they belong.
    final anchorY = bounds.top + 3;
    final curve = Motion.softSpring.transform(_interval(t, 0.18, 1));
    final draw = Curves.easeInOutCubic.transform(_interval(t, 0, 0.72));
    final depth = 0.52 + 0.48 * curve;

    void inSmileSpace(VoidCallback paint) {
      canvas.save();
      canvas.translate(0, anchorY + (1 - curve) * 3);
      canvas.scale(1, depth);
      canvas.translate(0, -anchorY);
      paint();
      canvas.restore();
    }

    // Warm glow beneath the smile.
    if (smileGlow > 0) {
      inSmileSpace(() {
        canvas.drawPath(
          path.shift(const Offset(0, 4)),
          Paint()
            ..color = AppColors.warmOrange.withValues(
              alpha: 0.55 * smileGlow.clamp(0.0, 1.0),
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
      });
    }

    // The understated starting smile: faint, and gone once drawn over.
    final faint = 0.3 * (1 - draw);
    if (faint > 0.01) {
      inSmileSpace(() {
        canvas.saveLayer(
          bounds.inflate(6),
          Paint()..color = Color.fromRGBO(0, 0, 0, faint),
        );
        _layered(canvas, path, colors.swoosh, null);
        canvas.restore();
      });
    }

    // The smile drawing itself from left to right with a soft leading
    // edge, like a pen stroke.
    if (draw <= 0) return;
    inSmileSpace(() {
      final layer = bounds.inflate(6);
      canvas.saveLayer(layer, Paint());
      _layered(canvas, path, colors.swoosh, colors.depth);
      if (draw < 1) {
        const feather = 18.0;
        final head = layer.left + (layer.width + feather) * draw;
        canvas.drawRect(
          layer,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = LinearGradient(
              colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
              stops: const [0, 0.5, 1],
            ).createShader(Rect.fromLTRB(head - feather * 2, 0, head, 1)),
        );
      }
      canvas.restore();
    });
  }

  /// A four-point sparkle at the smile's right tip: it grows with a small
  /// overshoot while turning an eighth of a turn, then fades. Nothing is
  /// painted at 0 or 1, so the resting logo never changes.
  void _paintGlint(Canvas canvas, double t, _MarkColors colors) {
    if (t <= 0 || t >= 1) return;
    final grow = Curves.easeOutBack.transform(_interval(t, 0, 0.45));
    final fade = 1 - Curves.easeIn.transform(_interval(t, 0.45, 1));
    final radius = 15.0 * grow;
    if (radius <= 0 || fade <= 0) return;
    canvas.save();
    canvas.translate(_MarkGeometry.smileTip.dx, _MarkGeometry.smileTip.dy);
    canvas.drawCircle(
      Offset.zero,
      radius * 0.95,
      Paint()
        ..color = colors.glintHalo.withValues(alpha: 0.5 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.55),
    );
    canvas.rotate(math.pi / 4 * t);
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? radius : radius * 0.2;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = Offset(math.cos(angle) * r, math.sin(angle) * r);
      i == 0
          ? star.moveTo(point.dx, point.dy)
          : star.lineTo(point.dx, point.dy);
    }
    star.close();
    canvas.drawPath(
      star,
      Paint()..color = colors.glintCore.withValues(alpha: fade),
    );
    canvas.restore();
  }

  /// Draws [path] twice: a darker base layer offset down-right for depth,
  /// then the gradient top layer with a faint top-edge highlight.
  void _layered(
    Canvas canvas,
    Path path,
    Paint Function(Rect) fill,
    Color? depth,
  ) {
    final bounds = path.getBounds();
    if (depth != null) {
      canvas.save();
      canvas.translate(1.6, 2.2);
      canvas.drawPath(path, Paint()..color = depth);
      canvas.restore();
    }
    canvas.drawPath(path, fill(bounds));
  }

  void _faded(Canvas canvas, double opacity, VoidCallback draw) {
    canvas.save();
    if (opacity < 1) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    }
    draw();
    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(DineQrMarkPainter oldDelegate) =>
      oldDelegate.tone != tone ||
      oldDelegate.monoColor != monoColor ||
      oldDelegate.reveal != reveal ||
      oldDelegate.sheen != sheen ||
      oldDelegate.smile != smile ||
      oldDelegate.smileGlow != smileGlow ||
      oldDelegate.smileGlint != smileGlint;
}

/// Fills for each part of the symbol in one tone.
class _MarkColors {
  const _MarkColors({
    required this.ribbon,
    required this.rightLobe,
    required this.swoosh,
    required this.cutlery,
    required this.qr,
    required this.depth,
    required this.sheenStrength,
    required this.glintCore,
    required this.glintHalo,
  });

  final Paint Function(Rect) ribbon;
  final Paint Function(Rect) rightLobe;
  final Paint Function(Rect) swoosh;
  final Paint Function(Rect) cutlery;
  final List<Paint Function(Rect)> qr;
  final Color? depth;
  final double sheenStrength;

  /// The smile glint's star and the soft light around it.
  final Color glintCore;
  final Color glintHalo;

  static Paint Function(Rect) _gradient(
    List<Color> colors, {
    List<double>? stops,
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
  }) =>
      (rect) => Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
          stops: stops,
        ).createShader(rect);

  static Paint Function(Rect) _solid(Color color) =>
      (_) => Paint()..color = color;

  static _MarkColors of(DineQrTone tone, Color mono) {
    switch (tone) {
      case DineQrTone.color:
        final orangeModule = _gradient(const [
          AppColors.vibrantOrange,
          AppColors.accentRed,
        ]);
        return _MarkColors(
          ribbon: _gradient(
            const [AppColors.accentRed, AppColors.primary, AppColors.deepRed],
            stops: const [0, 0.5, 1],
          ),
          rightLobe: _gradient(
            const [
              AppColors.accentRed,
              AppColors.vibrantOrange,
              AppColors.warmOrange,
            ],
            stops: const [0, 0.55, 1],
            begin: Alignment.centerLeft,
            end: Alignment.bottomRight,
          ),
          swoosh: _gradient(
            const [
              AppColors.deepRed,
              AppColors.primary,
              AppColors.vibrantOrange,
              AppColors.warmOrange,
            ],
            stops: const [0, 0.3, 0.75, 1],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          cutlery: _gradient(
            const [AppColors.accentRed, AppColors.primary, AppColors.deepRed],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          qr: [
            orangeModule,
            orangeModule,
            orangeModule,
            _solid(AppColors.deepRed),
          ],
          depth: const Color(0xFF6E0A10),
          sheenStrength: 0.45,
          glintCore: AppColors.warmOrange,
          glintHalo: AppColors.gold,
        );
      case DineQrTone.inverted:
        final white = _solid(Colors.white);
        final orangeModule = _gradient(const [
          AppColors.warmOrange,
          AppColors.vibrantOrange,
        ]);
        return _MarkColors(
          ribbon: white,
          rightLobe: _gradient(
            const [Colors.white, Color(0xFFFFE9DC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          swoosh: _gradient(
            const [Colors.white, Colors.white, Color(0xFFFFC796)],
            stops: const [0, 0.55, 1],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          cutlery: white,
          qr: [white, orangeModule, orangeModule, white],
          depth: const Color(0x8C3A0508),
          sheenStrength: 0.0,
          glintCore: Colors.white,
          glintHalo: AppColors.warmOrange,
        );
      case DineQrTone.mono:
        final flat = _solid(mono);
        return _MarkColors(
          ribbon: flat,
          rightLobe: flat,
          swoosh: flat,
          cutlery: flat,
          qr: [flat, flat, flat, flat],
          depth: null,
          sheenStrength: 0.35,
          glintCore: mono,
          glintHalo: mono,
        );
    }
  }
}

class _QrModule {
  _QrModule(this.path) : bounds = path.getBounds();

  final Path path;
  final Rect bounds;
}

/// Symbol geometry in a 240 × 196 design space, built once.
abstract final class _MarkGeometry {
  static const width = 240.0;
  static const height = 196.0;

  static Path _circle(double x, double y, double r) =>
      Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

  static Path _union(Iterable<Path> paths) =>
      paths.reduce((a, b) => Path.combine(PathOperation.union, a, b));

  // Lobes. Inner circles are offset from their outer circles so the outline
  // is thicker on one side, like a brush stroke.
  static const _rightCenter = Offset(199, 80);
  static const _rightRadius = 39.5;
  static const _rightInnerCenter = Offset(191.5, 86.5);
  static const _rightInnerRadius = 25.0;

  /// Left leg, left lobe and centre lobe (the deep red layer).
  static final Path ribbon = () {
    final legOuter = Path()
      ..moveTo(1.5, 78)
      ..quadraticBezierTo(4, 131, 46, 156)
      ..lineTo(66, 156)
      ..lineTo(66, 70)
      ..close();
    final outer = _union([
      _circle(41, 76.5, 39.8),
      _circle(112.4, 62.7, 60.5),
      legOuter,
    ]);
    // Everything inside the hat; on the right it rises so the centre lobe
    // ends tucked under the right lobe.
    final legInner = Path()
      ..moveTo(58, 92)
      ..lineTo(150, 92)
      ..lineTo(150, 58)
      ..lineTo(width + 20, 58)
      ..lineTo(width + 20, height + 20)
      ..lineTo(58, height + 20)
      ..close();
    final inner = _union([
      _circle(50.6, 81.3, 26.8),
      _circle(114.6, 71.3, 48.4),
      _circle(_rightInnerCenter.dx, _rightInnerCenter.dy, _rightInnerRadius),
      legInner,
      // Knockout gap so the right lobe sits cleanly on top of this layer.
      _circle(_rightCenter.dx, _rightCenter.dy, _rightRadius + 3.5),
    ]);
    return Path.combine(PathOperation.difference, outer, inner);
  }();

  /// The overlapping right lobe (the bright highlight layer).
  static final Path rightLobe = () {
    final ring = Path.combine(
      PathOperation.difference,
      _circle(_rightCenter.dx, _rightCenter.dy, _rightRadius),
      _circle(_rightInnerCenter.dx, _rightInnerCenter.dy, _rightInnerRadius),
    );
    const start = 200 * math.pi / 180;
    const sweep = 278 * math.pi / 180;
    final sector = Path()
      ..moveTo(_rightCenter.dx, _rightCenter.dy)
      ..arcTo(
        Rect.fromCircle(center: _rightCenter, radius: _rightRadius + 10),
        start,
        sweep,
        false,
      )
      ..close();
    return Path.combine(PathOperation.intersect, ring, sector);
  }();

  /// The smile's tapered right tip (where [DineQrMark.smileGlint] sparkles).
  static const smileTip = Offset(206, 144);

  /// Crescent under the cutlery, tapering to a point on the right.
  static final Path swoosh = Path()
    ..moveTo(44, 149)
    ..quadraticBezierTo(110, 226, 206, 144)
    ..quadraticBezierTo(120, 184, 58, 146)
    ..close();

  static final Path fork = () {
    final path = Path();
    const top = 67.0;
    const left = 64.0;
    const tine = 4.6;
    const gap = 2.53;
    for (var i = 0; i < 4; i++) {
      final x = left + i * (tine + gap);
      path.addRRect(
        RRect.fromLTRBR(x, top, x + tine, 99, const Radius.circular(tine / 2)),
      );
    }
    final neck = Path()
      ..moveTo(left, 94)
      ..lineTo(90, 94)
      ..lineTo(90, 98)
      ..quadraticBezierTo(90, 107.5, 81.5, 110.5)
      ..lineTo(81.5, 156)
      ..arcToPoint(const Offset(72.5, 156), radius: const Radius.circular(4.5))
      ..lineTo(72.5, 110.5)
      ..quadraticBezierTo(left, 107.5, left, 98)
      ..close();
    return Path.combine(PathOperation.union, path, neck);
  }();

  static final Path spoon = () {
    final bowl = Path()
      ..moveTo(158.5, 68)
      ..cubicTo(168.5, 68, 174.5, 80, 174.5, 92)
      ..cubicTo(174.5, 106, 166.5, 117, 158.5, 117)
      ..cubicTo(150.5, 117, 142.5, 106, 142.5, 92)
      ..cubicTo(142.5, 80, 148.5, 68, 158.5, 68)
      ..close();
    final handle = Path()
      ..moveTo(154.2, 110)
      ..lineTo(162.8, 110)
      ..lineTo(162.8, 156)
      ..arcToPoint(const Offset(154.2, 156), radius: const Radius.circular(4.3))
      ..close();
    return Path.combine(PathOperation.union, bowl, handle);
  }();

  /// Four QR-style modules: three finder rings and one solid block.
  static final List<_QrModule> qrModules = () {
    const size = 19.0;
    const gap = 4.0;
    const left = 95.5;
    const top = 116.5;
    Path ring(double x, double y) => Path.combine(
      PathOperation.difference,
      Path()..addRRect(
        RRect.fromLTRBR(x, y, x + size, y + size, const Radius.circular(4.8)),
      ),
      Path()..addRRect(
        RRect.fromLTRBR(
          x + 5.2,
          y + 5.2,
          x + size - 5.2,
          y + size - 5.2,
          const Radius.circular(2),
        ),
      ),
    );
    Path solid(double x, double y) => Path.combine(
      PathOperation.difference,
      Path()..addRRect(
        RRect.fromLTRBR(x, y, x + size, y + size, const Radius.circular(4.8)),
      ),
      Path()..addRRect(
        RRect.fromLTRBR(
          x + 7,
          y + 7,
          x + size - 7,
          y + size - 7,
          const Radius.circular(1.5),
        ),
      ),
    );
    const x2 = left + size + gap;
    const y2 = top + size + gap;
    return [
      _QrModule(ring(left, top)),
      _QrModule(ring(x2, top)),
      _QrModule(ring(left, y2)),
      _QrModule(solid(x2, y2)),
    ];
  }();

  /// Sector from the symbol centre, growing clockwise from the bottom-left,
  /// used to "draw" the hat outline during the reveal.
  static Path sweepClip(double t) {
    const center = Offset(118, 104);
    const start = 125 * math.pi / 180;
    return Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: 200),
        start,
        2 * math.pi * t,
        false,
      )
      ..close();
  }
}

/// Text painted in two layers: a deep red base offset down-right, and a
/// red-to-orange gradient on top. The signature DineQR treatment, used on the
/// "QR" of the wordmark and a few hero numbers.
class LayeredGradientText extends StatelessWidget {
  const LayeredGradientText(
    this.text, {
    super.key,
    required this.style,
    this.gradient = AppColors.emberGradient,
    this.baseColor = AppColors.deepRed,
    this.depth = 0.055,
  });

  final String text;
  final TextStyle style;
  final Gradient gradient;
  final Color baseColor;

  /// Base layer offset as a fraction of the font size.
  final double depth;

  @override
  Widget build(BuildContext context) {
    final offset = (style.fontSize ?? 14) * depth;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: Offset(offset * 0.6, offset),
            child: Text(text, style: style.copyWith(color: baseColor)),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: gradient.createShader,
            child: Text(text, style: style.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// "DineQR" in the brand type: "Dine" in charcoal (or white on dark) and a
/// layered red-orange "QR".
class DineQrWordmark extends StatelessWidget {
  const DineQrWordmark({super.key, this.fontSize = 32, this.onDark = false});

  final double fontSize;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -0.03 * fontSize,
    );
    return Semantics(
      label: 'DineQR',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'Dine',
            style: style.copyWith(
              color: onDark ? Colors.white : AppColors.charcoal,
              shadows: [
                Shadow(
                  color: onDark
                      ? const Color(0x80300407)
                      : const Color(0x24000000),
                  offset: Offset(0, fontSize * 0.05),
                  blurRadius: fontSize * 0.06,
                ),
              ],
            ),
          ),
          LayeredGradientText(
            'QR',
            style: style,
            gradient: onDark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.warmOrange, AppColors.vibrantOrange],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.vibrantOrange,
                      AppColors.accentRed,
                      AppColors.primary,
                    ],
                    stops: [0, 0.55, 1],
                  ),
            baseColor: onDark ? AppColors.depthOnRed : AppColors.deepRed,
          ),
        ],
      ),
    );
  }
}

/// "SCAN • ORDER • ENJOY"
class DineQrTagline extends StatelessWidget {
  const DineQrTagline({super.key, this.fontSize = 12, this.onDark = false});

  static const text = 'SCAN • ORDER • ENJOY';

  final double fontSize;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final word = AppTypography.overline.copyWith(
      fontSize: fontSize,
      letterSpacing: fontSize * 0.32,
      fontWeight: FontWeight.w600,
      color: onDark ? Colors.white.withValues(alpha: 0.88) : AppColors.charcoal,
    );
    final dot = word.copyWith(
      color: onDark ? AppColors.warmOrange : AppColors.accentRed,
    );
    return Semantics(
      label: 'Scan, order, enjoy',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'SCAN ', style: word),
            TextSpan(text: '•', style: dot),
            TextSpan(text: ' ORDER ', style: word),
            TextSpan(text: '•', style: dot),
            TextSpan(text: ' ENJOY', style: word),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}

/// Background styles for [DineQrAppIcon], matching the brand sheet's
/// colour, light and dark app icons.
enum DineQrIconStyle { color, light, dark }

/// The DineQR app icon: the symbol centred on a brand surface. Used to
/// generate launcher icons and wherever the app shows its own icon.
class DineQrAppIcon extends StatelessWidget {
  const DineQrAppIcon({
    super.key,
    this.size = 96,
    this.style = DineQrIconStyle.color,
    this.cornerRadius,
    this.markScale = 0.66,
  });

  final double size;
  final DineQrIconStyle style;

  /// Defaults to a 22% squircle-like radius; 0 for full-bleed icons that the
  /// platform masks itself (iOS, Android adaptive, maskable web icons).
  final double? cornerRadius;

  /// Symbol width as a fraction of the icon size.
  final double markScale;

  @override
  Widget build(BuildContext context) {
    final radius = cornerRadius ?? size * 0.22;
    final background = switch (style) {
      DineQrIconStyle.color => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentRed, AppColors.primary, AppColors.deepRed],
          stops: [0, 0.5, 1],
        ),
      ),
      DineQrIconStyle.light => const BoxDecoration(color: Colors.white),
      DineQrIconStyle.dark => const BoxDecoration(color: AppColors.charcoal),
    };
    return Semantics(
      label: 'DineQR app icon',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: background,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (style == DineQrIconStyle.color)
                  // Soft light from the top-left for a premium finish.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.7, -0.8),
                          radius: 1.1,
                          colors: [
                            Colors.white.withValues(alpha: 0.16),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                DineQrMark(
                  size: size * markScale,
                  tone: style == DineQrIconStyle.light
                      ? DineQrTone.color
                      : DineQrTone.inverted,
                  semanticLabel: null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Symbol next to the wordmark, for headers and compact spaces.
class DineQrLockup extends StatelessWidget {
  const DineQrLockup({
    super.key,
    this.height = 36,
    this.onDark = false,
    this.showTagline = false,
  });

  final double height;
  final bool onDark;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DineQrMark(
          size: height * DineQrMark.aspectRatio,
          tone: onDark ? DineQrTone.inverted : DineQrTone.color,
          semanticLabel: null,
        ),
        SizedBox(width: height * 0.22),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DineQrWordmark(fontSize: height * 0.62, onDark: onDark),
            if (showTagline)
              DineQrTagline(fontSize: height * 0.2, onDark: onDark),
          ],
        ),
      ],
    );
  }
}
