import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/ink_math.dart';

/// Draw D: ink → shape. Recognition is deterministic geometry; these
/// synthetic strokes pin each class and the scribble fall-through.

/// A closed polyline through [corners], [per] points per edge, ending on
/// the first corner — the shape a finger leaves when it draws a loop.
List<Offset> _polyLoop(List<Offset> corners, int per) {
  final out = <Offset>[];
  for (var k = 0; k < corners.length; k++) {
    final a = corners[k];
    final b = corners[(k + 1) % corners.length];
    for (var i = 0; i < per; i++) {
      out.add(Offset.lerp(a, b, i / per)!);
    }
  }
  out.add(corners.first);
  return out;
}

/// An ellipse loop: [n] samples around, closing on the first.
List<Offset> _ellipseLoop(double cx, double cy, double a, double b, int n) => [
      for (var i = 0; i <= n; i++)
        Offset(
          cx + a * math.cos(2 * math.pi * i / n),
          cy + b * math.sin(2 * math.pi * i / n),
        ),
    ];

void main() {
  group('inkRecognizeShape', () {
    test('a straight stroke is a line', () {
      final pts = [
        for (var i = 0; i < 30; i++)
          Offset.lerp(const Offset(100, 100), const Offset(400, 250), i / 29)!,
      ];
      expect(inkRecognizeShape(pts), InkShapeKind.line);
    });

    test('a closed rectangle loop is a rect', () {
      final pts = _polyLoop(const [
        Offset(100, 100),
        Offset(400, 100),
        Offset(400, 300),
        Offset(100, 300),
      ], 10);
      expect(inkRecognizeShape(pts), InkShapeKind.rect);
    });

    test('a closed ellipse loop is an ellipse, not a rect', () {
      final pts = _ellipseLoop(300, 200, 150, 100, 60);
      expect(inkRecognizeShape(pts), InkShapeKind.ellipse);
    });

    test('a closed three-corner loop is a triangle', () {
      final pts = _polyLoop(const [
        Offset(100, 300),
        Offset(400, 300),
        Offset(250, 100),
      ], 20);
      expect(inkRecognizeShape(pts), InkShapeKind.triangle);
    });

    test('a zigzag that does not close stays freehand', () {
      final pts = [
        for (var i = 0; i < 40; i++)
          Offset(100 + i * 10.0, i.isEven ? 100 : 300),
      ];
      expect(inkRecognizeShape(pts), InkShapeKind.none);
    });

    test('a tiny loop is too small to classify', () {
      final pts = _polyLoop(const [
        Offset(100, 100),
        Offset(110, 100),
        Offset(110, 110),
        Offset(100, 110),
      ], 4);
      expect(inkRecognizeShape(pts), InkShapeKind.none);
    });

    test('fewer than four points is never a shape', () {
      expect(
        inkRecognizeShape(const [Offset(0, 0), Offset(100, 100), Offset(0, 0)]),
        InkShapeKind.none,
      );
    });
  });
}
