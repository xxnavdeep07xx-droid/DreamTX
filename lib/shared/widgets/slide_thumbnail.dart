import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../models/project.dart';

/// Deterministic abstract "slide" preview for a project.
///
/// The composition is derived from the project id, so a project always keeps
/// the same placeholder thumbnail — realistic without any assets.
class SlideThumbnail extends StatelessWidget {
  const SlideThumbnail({super.key, required this.project, this.width, this.height});

  final Project project;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final seed = project.id.hashCode;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF15151C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: CustomPaint(
          painter: SlidePreviewPainter(
            seed: seed,
            variant: seed.abs() % 4,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Paints a small abstract slide composition.
class SlidePreviewPainter extends CustomPainter {
  SlidePreviewPainter({required this.seed, required this.variant});

  final int seed;
  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final w = size.width;
    final h = size.height;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF15151C));

    final line = Paint()..color = const Color(0xFF33333F);
    final lineSoft = Paint()..color = const Color(0xFF282831);
    final accent = Paint()..color = AppColors.violet.withOpacity(0.60);
    final accent2 = Paint()..color = AppColors.blue.withOpacity(0.50);

    void bar(double x, double y, double width, double height, Paint p) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, width, height),
          Radius.circular(height / 2.2),
        ),
        p,
      );
    }

    switch (variant) {
      case 0: // Title + bullets
        bar(10, 10, w * (0.5 + random.nextDouble() * 0.25), 7, line);
        var y = 26.0;
        for (var i = 0; i < 4; i++) {
          bar(10, y, w * (0.35 + random.nextDouble() * 0.5), 4, lineSoft);
          y += 10;
        }
        bar(10, h - 13, 20, 4, accent);
        break;
      case 1: // Chart
        bar(10, 10, w * 0.45, 6, line);
        final baseY = h - 14;
        canvas.drawLine(
          Offset(10, baseY),
          Offset(w - 10, baseY),
          Paint()
            ..color = const Color(0xFF282831)
            ..strokeWidth = 1.5,
        );
        const count = 5;
        final slot = (w - 24) / count;
        for (var i = 0; i < count; i++) {
          final barHeight = (h * 0.28) + random.nextDouble() * (h * 0.34);
          final rect = Rect.fromLTWH(
            13 + i * slot,
            baseY - barHeight,
            slot * 0.52,
            barHeight,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2.5)),
            i == count - 1 ? accent : lineSoft,
          );
        }
        break;
      case 2: // Media + text
        final side = h * 0.62;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(10, 24, side, side),
            const Radius.circular(6),
          ),
          Paint()..color = const Color(0xFF20202A),
        );
        canvas.drawCircle(
          Offset(10 + side / 2, 24 + side / 2),
          side * 0.22,
          accent2,
        );
        var y = 28.0;
        final textX = 10 + side + 10;
        for (var i = 0; i < 4; i++) {
          bar(
            textX,
            y,
            (w - textX - 10) * (0.45 + random.nextDouble() * 0.5),
            4,
            i == 0 ? line : lineSoft,
          );
          y += 10;
        }
        break;
      default: // Editorial quote
        canvas.drawRect(
          Rect.fromLTWH(10, 10, 3.5, h - 20),
          accent,
        );
        const textX = 20.0;
        bar(textX, 12, w * 0.6, 7, line);
        var y = 27.0;
        for (var i = 0; i < 4; i++) {
          bar(textX, y, (w - textX - 10) * (0.4 + random.nextDouble() * 0.5), 4,
              lineSoft);
          y += 10;
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant SlidePreviewPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.variant != variant;
}
