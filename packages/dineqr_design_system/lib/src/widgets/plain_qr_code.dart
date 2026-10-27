import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// A plain black-on-white QR code with the standard quiet zone: no logo, no
/// rounded modules, no colour. For payment links, where the code must be
/// read by whatever scanner the other person's UPI app uses. (The branded
/// [TableQrCode] is for table codes.)
class PlainQrCode extends StatelessWidget {
  const PlainQrCode({
    super.key,
    required this.payload,
    this.size = 220,
    this.semanticLabel,
  });

  final String payload;
  final double size;
  final String? semanticLabel;

  /// The quiet zone around the symbol, in modules (the standard asks for 4).
  static const quietModules = 4;

  static final Map<String, QrImage> _cache = {};

  static QrImage _imageFor(String payload) => _cache.putIfAbsent(
    payload,
    () => QrImage(
      QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.M),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? 'QR code',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PlainQrPainter(_imageFor(payload))),
      ),
    );
  }
}

class _PlainQrPainter extends CustomPainter {
  const _PlainQrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final modules = image.moduleCount;
    final cell = size.width / (modules + 2 * PlainQrCode.quietModules);
    final dark = Paint()..color = Colors.black;
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (!image.isDark(row, col)) continue;
        // A hair of overlap so neighbouring modules never show a seam.
        canvas.drawRect(
          Rect.fromLTWH(
            (col + PlainQrCode.quietModules) * cell,
            (row + PlainQrCode.quietModules) * cell,
            cell,
            cell,
          ).inflate(0.2),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PlainQrPainter oldDelegate) => oldDelegate.image != image;
}
