import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/ink_math.dart';

/// Draw R: the ruler's tick math. The overlay paints exactly what
/// [rulerTicks] returns, so these pin the spacing and the major/middle
/// classification the labels depend on.
void main() {
  group('rulerTicks', () {
    test('ticks every 10 design px, never at the origin edge', () {
      final t = rulerTicks(35);
      expect(t.map((e) => e.pos).toList(), [10.0, 20.0, 30.0]);
    });

    test('every 100 px is major (kind 2), every 50 px middle (kind 1)', () {
      final t = rulerTicks(250);
      final kinds = {for (final e in t) e.pos: e.kind};
      expect(kinds[100.0], 2);
      expect(kinds[200.0], 2);
      expect(kinds[50.0], 1);
      expect(kinds[150.0], 1);
      expect(kinds[250.0], 1);
      expect(kinds[30.0], 0);
    });

    test('a tick lands exactly on the far edge when the length is a multiple', () {
      // 1200 is a multiple of 100: the far edge gets a major tick.
      final t = rulerTicks(1200);
      expect(t.last.pos, 1200.0);
      expect(t.last.kind, 2);
    });

    test('a non-positive length or step yields nothing', () {
      expect(rulerTicks(0), isEmpty);
      expect(rulerTicks(-5), isEmpty);
      expect(rulerTicks(100, step: 0), isEmpty);
    });
  });
}
