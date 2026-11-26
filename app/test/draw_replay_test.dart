import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/ink_math.dart';
import 'package:dreamtx/widgets/shape_canvas.dart';

/// Draw E: ink replay. The timing rules are pure; the partial stroke is
/// checked by arc length.
void main() {
  group('inkReplayProgress', () {
    test('strokes play one after another, each in an equal slice', () {
      // Three strokes: the first owns t in [0, 1/3).
      expect(inkReplayProgress(0, 3, 0), 0);
      expect(inkReplayProgress(0, 3, 1 / 6), closeTo(0.5, 1e-9));
      expect(inkReplayProgress(0, 3, 1 / 3), 1);
      expect(inkReplayProgress(1, 3, 1 / 3), 0);
      expect(inkReplayProgress(1, 3, 0.5), closeTo(0.5, 1e-9));
      expect(inkReplayProgress(2, 3, 1), 1);
    });

    test('the idle clock (t = 1) shows every stroke whole', () {
      for (var i = 0; i < 5; i++) {
        expect(inkReplayProgress(i, 5, 1), 1);
      }
    });

    test('out-of-range time is clamped; no strokes yields nothing', () {
      expect(inkReplayProgress(0, 2, -1), 0);
      expect(inkReplayProgress(1, 2, 9), 1);
      expect(inkReplayProgress(0, 0, 0.5), 1);
    });
  });

  group('inkReplayDuration', () {
    test('scales with the scribble count and is clamped', () {
      expect(inkReplayDuration(1), const Duration(milliseconds: 600));
      expect(inkReplayDuration(4), const Duration(milliseconds: 1800));
      expect(inkReplayDuration(100), const Duration(seconds: 6));
    });
  });

  group('inkPartialPath', () {
    Path line(double len) => Path()
      ..moveTo(0, 0)
      ..lineTo(len, 0);

    test('keeps the leading fraction of the arc length', () {
      final half = inkPartialPath(line(100), 0.5)!;
      final m = half.computeMetrics().single;
      expect(m.length, closeTo(50, 1e-6));
    });

    test('zero draws nothing; one draws the whole path', () {
      expect(inkPartialPath(line(100), 0), isNull);
      final whole = line(100);
      expect(identical(inkPartialPath(whole, 1), whole), isTrue);
    });
  });
}
