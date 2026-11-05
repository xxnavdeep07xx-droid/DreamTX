import 'dart:math' show cos, pi, sin;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../models/design_collection.dart';

/// Paints an abstract preview for a design direction.
///
/// These are visual studies of a direction — the future design engine will
/// generate dynamic compositions; these previews are not templates.
class DirectionPreviewPainter extends CustomPainter {
  const DirectionPreviewPainter(this.direction);

  final DesignDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF14141A));

    final soft = Paint()..color = const Color(0xFF2C2C37);
    final softer = Paint()..color = const Color(0xFF232330);
    final violet = Paint()..color = AppColors.violet.withOpacity(0.75);
    final blue = Paint()..color = AppColors.blue.withOpacity(0.6);
    final light = Paint()..color = AppColors.textSecondary.withOpacity(0.65);

    switch (direction) {
      case DesignDirection.editorial:
        // Drop cap + columns.
        canvas.drawRect(const Rect.fromLTWH(10, 10, 16, 26), violet);
        for (var i = 0; i < 5; i++) {
          canvas.drawRect(
            Rect.fromLTWH(32, 11 + i * 5.5, w * 0.30, 2.5),
            soft,
          );
        }
        for (var i = 0; i < 6; i++) {
          canvas.drawRect(
            Rect.fromLTWH(w * 0.55, 11 + i * 5.5, w * 0.38, 2.5),
            i == 0 ? light : softer,
          );
        }
        canvas.drawRect(Rect.fromLTWH(10, h - 14, w * 0.4, 2.5), soft);
        break;
      case DesignDirection.cinematic:
        // Letterbox bars + horizon.
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.18), soft);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.82, w, h * 0.18), soft);
        canvas.drawCircle(Offset(w * 0.5, h * 0.52), h * 0.16, blue);
        canvas.drawLine(
          Offset(w * 0.12, h * 0.78),
          Offset(w * 0.88, h * 0.78),
          Paint()
            ..color = AppColors.textSecondary.withOpacity(0.5)
            ..strokeWidth = 1.5,
        );
        break;
      case DesignDirection.minimal:
        // One quiet line and a dot.
        canvas.drawLine(
          Offset(w * 0.3, h * 0.42),
          Offset(w * 0.7, h * 0.42),
          Paint()
            ..color = AppColors.textSecondary.withOpacity(0.8)
            ..strokeWidth = 1.6,
        );
        canvas.drawCircle(Offset(w * 0.5, h * 0.62), 2.6, violet);
        break;
      case DesignDirection.scientific:
        // Grid + plot.
        final grid = Paint()
          ..color = const Color(0xFF232330)
          ..strokeWidth = 1;
        for (var i = 1; i < 4; i++) {
          canvas.drawLine(Offset(w * i / 4, 8), Offset(w * i / 4, h - 8), grid);
        }
        for (var i = 1; i < 3; i++) {
          canvas.drawLine(Offset(8, h * i / 3), Offset(w - 8, h * i / 3), grid);
        }
        final plot = Path()
          ..moveTo(8, h * 0.7)
          ..lineTo(w * 0.33, h * 0.5)
          ..lineTo(w * 0.62, h * 0.62)
          ..lineTo(w - 8, h * 0.26);
        canvas.drawPath(
          plot,
          Paint()
            ..color = AppColors.blue.withOpacity(0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(Offset(w * 0.62, h * 0.62), 2.8, violet);
        break;
      case DesignDirection.corporate:
        // Structured blocks + segment.
        canvas.drawRect(Rect.fromLTWH(10, 10, w * 0.28, 10), soft);
        canvas.drawRect(Rect.fromLTWH(10, 24, w * 0.2, 2.5), softer);
        canvas.drawRect(Rect.fromLTWH(10, h * 0.5, w * 0.24, h * 0.4), blue);
        canvas.drawRect(
          Rect.fromLTWH(10 + w * 0.28, h * 0.62, w * 0.24, h * 0.28),
          violet,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(w * 0.62, 10.0 + i * 6.5, w * 0.3, 2.5),
            softer,
          );
        }
        break;
      case DesignDirection.experimental:
        // Scattered rotated squares.
        void square(Offset c, double r, double radians, Paint p) {
          final path = Path();
          for (var i = 0; i < 4; i++) {
            final angle = radians + i * pi / 2;
            final point = Offset(
              c.dx + cos(angle) * r,
              c.dy + sin(angle) * r,
            );
            if (i == 0) {
              path.moveTo(point.dx, point.dy);
            } else {
              path.lineTo(point.dx, point.dy);
            }
          }
          path.close();
          canvas.drawPath(path, p);
        }

        square(Offset(w * 0.32, h * 0.36), 11, pi / 5, violet);
        square(Offset(w * 0.66, h * 0.6), 9, pi / 3.2, blue);
        square(Offset(w * 0.58, h * 0.28), 5, pi / 2.4,
            Paint()..color = AppColors.textSecondary.withOpacity(0.5));
        canvas.drawCircle(Offset(w * 0.3, h * 0.74), 3, soft);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant DirectionPreviewPainter oldDelegate) =>
      oldDelegate.direction != direction;
}
