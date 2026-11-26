import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/ink_math.dart';

/// Draw B: lasso select. The geometry is pure (ink_math.dart): the
/// point-in-loop test, the selection rule, and the batch edits the editor
/// applies to each selected object.

/// A 100x100 square loop at the origin.
const _square = [
  Offset(0, 0),
  Offset(100, 0),
  Offset(100, 100),
  Offset(0, 100),
];

Map<String, dynamic> _obj(
  String id, {
  double x = 40,
  double y = 40,
  double w = 20,
  double h = 20,
  bool locked = false,
  Map<String, dynamic>? stroke,
}) =>
    {
      'id': id,
      'preset': 'rect',
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'locked': locked,
      if (stroke != null) 'stroke': stroke,
    };

void main() {
  group('inkPointInPolygon', () {
    test('a point inside the loop is in, outside is out', () {
      expect(inkPointInPolygon(const Offset(50, 50), _square), isTrue);
      expect(inkPointInPolygon(const Offset(150, 50), _square), isFalse);
      expect(inkPointInPolygon(const Offset(-5, 50), _square), isFalse);
    });

    test('works for a concave loop (the notch is outside)', () {
      // A "U": the inner notch between the arms is outside.
      const u = [
        Offset(0, 0),
        Offset(30, 0),
        Offset(30, 60),
        Offset(70, 60),
        Offset(70, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ];
      // Left arm and the bottom bar are in; the notch (y < 60, between
      // the arms) is out.
      expect(inkPointInPolygon(const Offset(15, 30), u), isTrue);
      expect(inkPointInPolygon(const Offset(80, 80), u), isTrue);
      expect(inkPointInPolygon(const Offset(50, 30), u), isFalse);
    });

    test('a polygon under three points encloses nothing', () {
      expect(
        inkPointInPolygon(const Offset(1, 1), const [Offset(0, 0), Offset(3, 3)]),
        isFalse,
      );
    });
  });

  group('inkLassoHits (the selection rule)', () {
    test('an object whose frame center is inside is selected', () {
      expect(inkLassoHits([_obj('a')], _square), ['a']);
    });

    test('an object whose center is outside is not, even if it overlaps', () {
      // Frame x 95..115 straddles the loop's right edge (x = 100), but its
      // center (105, 50) is outside, so it is not selected.
      expect(
        inkLassoHits([_obj('edge', x: 95, y: 40)], _square),
        isEmpty,
      );
    });

    test('locked objects are never selected', () {
      expect(
        inkLassoHits([_obj('l', locked: true), _obj('a')], _square),
        ['a'],
      );
    });

    test('content objects count too (the lasso is the general selection)', () {
      final text = _obj('t')..['content'] = {'type': 'text'};
      expect(inkLassoHits([text], _square), ['t']);
    });

    test('objects with no id are skipped', () {
      final anon = _obj('x')..remove('id');
      expect(inkLassoHits([anon], _square), isEmpty);
    });

    test('the center uses the frame, so rotation does not move it', () {
      final rot = _obj('r')..['rotation'] = 45.0;
      expect(inkObjectCenter(rot), const Offset(50, 50));
      expect(inkLassoHits([rot], _square), ['r']);
    });
  });

  group('inkTranslated (the move batch)', () {
    test('shifts x and y, never the input', () {
      final o = _obj('a');
      final moved = inkTranslated(o, 10, -5);
      expect(moved['x'], 50.0);
      expect(moved['y'], 35.0);
      expect(o['x'], 40.0);
      expect(identical(moved, o), isFalse);
    });
  });

  group('inkRestyled (the recolor batch)', () {
    test('an outline with width recolors', () {
      final o = _obj('a', stroke: {'color': '000000', 'width': 2.0});
      final r = inkRestyled(o, 'FF0000');
      expect((r['stroke'] as Map)['color'], 'FF0000');
      expect((r['stroke'] as Map)['width'], 2.0);
      expect((o['stroke'] as Map)['color'], '000000');
    });

    test('a text box (no stroke) comes back as the same instance', () {
      final o = _obj('t');
      expect(identical(inkRestyled(o, 'FF0000'), o), isTrue);
    });

    test('a zero-width outline comes back as the same instance', () {
      final o = _obj('z', stroke: {'color': '000000', 'width': 0.0});
      expect(identical(inkRestyled(o, 'FF0000'), o), isTrue);
    });
  });
}
