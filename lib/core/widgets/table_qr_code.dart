import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../app/theme/app_colors.dart';
import '../brand/dineqr_logo.dart';

/// A real, scannable QR code for [payload], styled for DineQR: rounded
/// charcoal finder squares, deep red data modules and the symbol in the
/// centre. High error correction keeps it readable with the logo on top.
class TableQrCode extends StatelessWidget {
  const TableQrCode({
    super.key,
    required this.payload,
    this.size = 160,
    this.showLogo = true,
    this.semanticLabel,
  });

  final String payload;
  final double size;
  final bool showLogo;
  final String? semanticLabel;

  static final Map<String, QrImage> _cache = {};

  static QrImage _imageFor(String payload) => _cache.putIfAbsent(
    payload,
    () => QrImage(
      QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.H),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = _imageFor(payload);
    return Semantics(
      label: semanticLabel ?? 'QR code',
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.06),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.08),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size * 0.88),
              painter: _QrPainter(image),
            ),
            if (showLogo)
              Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(size * 0.05),
                ),
                alignment: Alignment.center,
                child: DineQrMark(size: size * 0.2, semanticLabel: null),
              ),
          ],
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  bool _inFinder(int row, int col) {
    final n = image.moduleCount;
    bool corner(int r, int c) => r >= 0 && r < 7 && c >= 0 && c < 7;
    return corner(row, col) ||
        corner(row, col - (n - 7)) ||
        corner(row - (n - 7), col);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.width / n;
    final data = Paint()..color = AppColors.deepRed;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        if (!image.isDark(row, col) || _inFinder(row, col)) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(col * cell, row * cell, cell, cell).inflate(0.15),
            Radius.circular(cell * 0.3),
          ),
          data,
        );
      }
    }
    // Finder patterns: outer ring + inner block, rounded.
    final finder = Paint()..color = AppColors.charcoal;
    for (final (row, col) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
      final outer = Rect.fromLTWH(col * cell, row * cell, cell * 7, cell * 7);
      canvas.drawDRRect(
        RRect.fromRectAndRadius(outer, Radius.circular(cell * 2)),
        RRect.fromRectAndRadius(
          outer.deflate(cell),
          Radius.circular(cell * 1.3),
        ),
        finder,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(outer.deflate(cell * 2), Radius.circular(cell)),
        finder,
      );
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
