import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The DreamTX geometric mark: two overlapping diamonds — layered slides.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: AppColors.border),
      ),
      child: CustomPaint(
        painter: _LogoMarkPainter(),
        size: Size.square(size),
      ),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final unit = size.width;

    void drawDiamond(Offset c, double radius, Paint paint) {
      final path = Path()
        ..moveTo(c.dx, c.dy - radius)
        ..lineTo(c.dx + radius, c.dy)
        ..lineTo(c.dx, c.dy + radius)
        ..lineTo(c.dx - radius, c.dy)
        ..close();
      canvas.drawPath(path, paint);
    }

    // Outer diamond — muted violet stroke, lifted slightly up-left.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.075
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.violet;
    final offset = unit * 0.10;
    drawDiamond(
      center.translate(-offset, -offset),
      unit * 0.29,
      stroke,
    );

    // Inner diamond — cool blue fill, pushed slightly down-right.
    final fill = Paint()..color = AppColors.blue;
    drawDiamond(
      center.translate(offset * 0.75, offset * 0.75),
      unit * 0.125,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter oldDelegate) => false;
}
