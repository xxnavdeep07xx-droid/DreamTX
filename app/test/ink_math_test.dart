import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/ink_math.dart';

/// The Draw tab's capture pipeline (ink_math.dart) — the pure geometry
/// contract both sides of a stroke depend on: the live preview runs the
/// pipeline on the growing raw list, the editor commits its output, so
/// the invariants below are the WYSIWYG guarantee.
void main() {
  group('inkCapture: degenerate input', () {
    test('empty in, empty out', () {
      expect(inkCapture(const []), isEmpty);
    });

    test('a single point passes through (dropped by the >=2 rule upstream)',
        () {
      expect(inkCapture(const [Offset(10, 20)]), const [Offset(10, 20)]);
    });

    test('two points pass through unchanged — a straight flick stroke', () {
      expect(
        inkCapture(const [Offset(0, 0), Offset(100, 40)]),
        const [Offset(0, 0), Offset(100, 40)],
      );
    });
  });

  group('inkCapture: thin + simplify', () {
    test('dense collinear points collapse to their anchors', () {
      // 1px steps along a line: thinning (>=6px) keeps every ~6th, then
      // simplification (eps 2) collapses a straight line to 2 endpoints.
      final raw = [
        for (var i = 0; i <= 60; i++) Offset(i.toDouble(), i * 2.0),
      ];
      final out = inkCapture(raw);
      expect(out, hasLength(2));
      expect(out.first, const Offset(0, 0));
      // The lift point is always kept: (60, 120).
      expect(out.last, const Offset(60, 120));
    });

    test('a real corner survives simplification', () {
      final out = inkCapture(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
      ]);
      // Thin keeps all three (10px gaps), simplify keeps the corner
      // (deviation from the diagonal is ~7px > eps 2), smooth resamples
      // the one quadratic at 4 pts + the straight tail.
      expect(out, hasLength(1 + 4 + 1));
      expect(out.first, const Offset(0, 0));
      expect(out.last, const Offset(10, 10));
      // The first quadratic ends at the midpoint of the corner segment.
      expect(out[4], const Offset(10, 5));
    });

    test('wobble under epsilon is discarded, the anchors are not', () {
      // +-1px noise around a straight line: all under eps 2. Thinning
      // lands on the even (y+1) samples only, so what survives is a
      // straight line that collapses to its anchors.
      final raw = <Offset>[
        for (var i = 0; i <= 50; i++)
          Offset(i * 4.0, 100 + (i.isEven ? 1.0 : -1.0)),
      ];
      final out = inkCapture(raw);
      expect(out.first, raw.first);
      expect(out.last, raw.last);
      expect(out, hasLength(2));
    });
  });

  group('inkCapture: smoothing', () {
    test('resampled points sit ON the curve, not the control polygon', () {
      // The quadratic from (0,0) with control (10,0) to (10,5): at t=0.5,
      // B = 0.25*(0,0) + 0.5*(10,0) + 0.25*(10,5) = (7.5, 1.25) — on the
      // curve, well below the control point the finger passed through.
      final out = inkCapture(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
      ]);
      final mid = out[2]; // t = 2/4 of the first quadratic.
      expect(mid.dx, closeTo(7.5, 0.001));
      expect(mid.dy, closeTo(1.25, 0.001));
    });

    test('the resample count is exact: anchors + 4/segment + tail', () {
      // Both interior points deviate ~30px from the anchor chord, so
      // simplify keeps all four and smooth resamples both quadratics.
      final out = inkCapture(const [
        Offset(0, 0),
        Offset(40, 30),
        Offset(80, 30),
        Offset(120, 0),
      ]);
      expect(out, hasLength(1 + 2 * 4 + 1));
      expect(out.first, const Offset(0, 0));
      expect(out.last, const Offset(120, 0));
      // Points between the anchors stay inside the polyline's extent.
      for (final p in out) {
        expect(p.dx, inInclusiveRange(0, 120));
        expect(p.dy, inInclusiveRange(0, 30));
      }
    });
  });

  group('inkCapture: the point budget', () {
    test('a pathological long zigzag stays under 400 points, anchors kept',
        () {
      // 1500 raw points of +-30px zigzag: every consecutive pair is ~60px
      // apart so thinning keeps them all, the first simplify/smooth pass
      // overflows the budget, and the loop escalates epsilon until the
      // committed polyline fits.
      final raw = <Offset>[
        for (var i = 0; i <= 1500; i++)
          Offset(i.toDouble(), 100 + (i.isEven ? 30.0 : -30.0)),
      ];
      final out = inkCapture(raw);
      expect(out.length, lessThanOrEqualTo(400));
      expect(out.length, greaterThanOrEqualTo(2));
      expect(out.first, raw.first);
      expect(out.last, raw.last);
    });

    test('the budget escalation is deterministic', () {
      final raw = <Offset>[
        for (var i = 0; i <= 800; i++)
          Offset(i.toDouble(), 300 + 200 * (i.isEven ? 1.0 : -1.0)),
      ];
      final a = inkCapture(raw);
      final b = inkCapture(raw);
      expect(a, equals(b));
      expect(a.length, lessThanOrEqualTo(400));
    });
  });

  group('inkCapture: determinism', () {
    test('the same raw input yields the identical polyline twice', () {
      final raw = <Offset>[
        for (var i = 0; i <= 200; i++)
          Offset(50 + 300 * (i / 200), 300 + 80 * math.sin(i / 9.0)),
      ];
      final a = inkCapture(raw);
      final b = inkCapture(raw);
      expect(a, equals(b));
      expect(a.length, greaterThan(2));
    });
  });

  group('InkStyle equality', () {
    test('field-wise == and hashCode (painter repaint checks depend on it)',
        () {
      const a = InkStyle(colorHex: 'D03028', width: 8, opacity: 1);
      const b = InkStyle(colorHex: 'D03028', width: 8, opacity: 1);
      const c = InkStyle(colorHex: 'D03028', width: 16, opacity: 1);
      const d = InkStyle(colorHex: 'FFD400', width: 28, opacity: 0.35);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == d, isFalse);
    });
  });
}
