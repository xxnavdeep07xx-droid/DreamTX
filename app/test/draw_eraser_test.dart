import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/ink_math.dart';

/// Draw A-1: the eraser's S/M/L reach and "Erase all ink on this slide".
/// Both are pure functions (ink_math.dart) — the toolbox state and the
/// editor wiring ride on top and are covered by CI's analyze + the suite.

/// A horizontal scribble at height [y]: two points, 100 design px long,
/// stroke width 8 (half = 4px reach contribution).
Map<String, dynamic> _scribble(String id, {double y = 100}) => {
      'id': id,
      'preset': 'path',
      'x': 0.0,
      'y': y,
      'w': 100.0,
      'h': 1.0,
      'rotation': 0.0,
      'locked': false,
      'stroke': {'color': '17181A', 'width': 8.0, 'dash': 'solid'},
      'points': [
        {'x': 0.0, 'y': 0.0},
        {'x': 1.0, 'y': 0.0},
      ],
    };

void main() {
  group('inkScribbleIds — clear-all eligibility', () {
    test('every plain scribble is listed, in z-order', () {
      expect(
        inkScribbleIds([_scribble('a'), _scribble('b', y: 200)]),
        ['a', 'b'],
      );
    });

    test('content objects are never listed (text, image, table...)', () {
      final text = {
        'id': 't',
        'preset': 'rect',
        'x': 0.0,
        'y': 0.0,
        'w': 10.0,
        'h': 10.0,
        'content': {'type': 'text'},
        'points': [
          {'x': 0.0, 'y': 0.0},
          {'x': 1.0, 'y': 1.0},
        ],
      };
      expect(inkScribbleIds([text, _scribble('a')]), ['a']);
    });

    test('preset shapes are never listed', () {
      final rect = _scribble('r')..['preset'] = 'rect';
      expect(inkScribbleIds([rect]), isEmpty);
    });

    test('locked strokes are kept, same as the eraser', () {
      final locked = _scribble('l')..['locked'] = true;
      expect(inkScribbleIds([locked, _scribble('a')]), ['a']);
    });

    test('a path with fewer than two points is not a scribble', () {
      final dot = _scribble('d')
        ..['points'] = [
          {'x': 0.0, 'y': 0.0},
        ];
      expect(inkScribbleIds([dot]), isEmpty);
    });

    test('an empty slide yields nothing', () {
      expect(inkScribbleIds(const []), isEmpty);
    });
  });

  group('eraser reach (S / M / L)', () {
    // The probe sits 30 design px below the stroke: outside the S and M
    // corridors (12 + 4 and 24 + 4), inside the L corridor (40 + 4).
    final probe = [const Offset(50, 130)];

    test('S (12) does not reach a stroke 30px away', () {
      expect(
        inkEraseHits([_scribble('a')], probe, radius: 12.0),
        isEmpty,
      );
    });

    test('M (24, the default) does not reach a stroke 30px away', () {
      expect(kInkEraserRadius, 24.0);
      expect(
        inkEraseHits([_scribble('a')], probe),
        isEmpty,
      );
    });

    test('L (40) reaches the same stroke', () {
      expect(
        inkEraseHits([_scribble('a')], probe, radius: 40.0),
        ['a'],
      );
    });
  });
}
