import 'package:flutter/material.dart';

class SocratesLogo extends StatelessWidget {
  const SocratesLogo({
    this.size = 34,
    this.color,
    super.key,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SocratesLogoPainter(
        color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _SocratesLogoPainter extends CustomPainter {
  const _SocratesLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 48, size.height / 48);

    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bust = Path()
      ..moveTo(12, 21)
      ..cubicTo(9, 12, 14, 5, 23, 5)
      ..cubicTo(32, 4, 38, 11, 36, 21)
      ..moveTo(12, 19)
      ..cubicTo(8, 17, 7, 21, 9, 25)
      ..cubicTo(10, 27, 12, 27, 14, 26)
      ..moveTo(36, 19)
      ..cubicTo(40, 17, 41, 21, 39, 25)
      ..cubicTo(38, 27, 36, 27, 34, 26)
      ..moveTo(13, 18)
      ..cubicTo(12, 25, 16, 31, 20, 33)
      ..cubicTo(21, 37, 23, 40, 24, 42)
      ..cubicTo(27, 39, 30, 36, 31, 33)
      ..cubicTo(35, 30, 37, 24, 35, 18)
      ..moveTo(17, 21)
      ..lineTo(21, 21)
      ..moveTo(27, 21)
      ..lineTo(31, 21)
      ..moveTo(24, 21)
      ..cubicTo(23, 24, 22, 27, 24, 27)
      ..moveTo(18, 29)
      ..cubicTo(20, 27, 22, 28, 24, 29)
      ..cubicTo(26, 28, 29, 27, 31, 29)
      ..moveTo(19, 32)
      ..cubicTo(20, 36, 22, 38, 24, 39)
      ..cubicTo(27, 37, 29, 35, 30, 32)
      ..moveTo(18, 33)
      ..lineTo(17, 37)
      ..cubicTo(10, 38, 5, 41, 4, 46)
      ..cubicTo(11, 43, 17, 43, 21, 46)
      ..cubicTo(23, 47, 25, 47, 27, 46)
      ..cubicTo(32, 43, 38, 43, 44, 46)
      ..cubicTo(43, 41, 38, 38, 31, 37)
      ..lineTo(30, 33)
      ..moveTo(8, 43)
      ..cubicTo(13, 40, 17, 40, 21, 42)
      ..moveTo(27, 42)
      ..cubicTo(31, 40, 36, 40, 40, 43);

    canvas.drawPath(bust, outline);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SocratesLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
