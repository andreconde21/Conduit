import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// A QR code drawn black on white (whatever the theme) with its quiet
/// zone, as scanners expect.
class QrCodeView extends StatelessWidget {
  const QrCodeView({required this.data, this.size = 260, super.key});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.low,
      ),
    );
    return Semantics(
      label: 'Setup QR code',
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size / 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final cell = size.shortestSide / count;
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    final path = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (image.isDark(row, col)) {
          // A hair of overlap so no seams show between modules.
          path.addRect(
            Rect.fromLTWH(col * cell, row * cell, cell + 0.3, cell + 0.3),
          );
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
