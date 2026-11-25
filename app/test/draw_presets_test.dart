import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/ink_math.dart';

/// Draw A-2: pen presets (the saved tool chips) and the pencil tip. The
/// rules are pure (ink_math.dart) so they are tested directly; the toolbox
/// state and band render on top and ride CI's analyze + the suite.
void main() {
  group('labels', () {
    test('pen presets carry their S/M/L size', () {
      expect(
        const InkPreset(kind: InkPresetKind.pen, colorHex: 'FF0000', width: 4)
            .label,
        'Pen S',
      );
      expect(
        const InkPreset(kind: InkPresetKind.pen, colorHex: 'FF0000', width: 8)
            .label,
        'Pen M',
      );
      expect(
        const InkPreset(kind: InkPresetKind.pen, colorHex: 'FF0000', width: 16)
            .label,
        'Pen L',
      );
    });

    test('pencil and highlighter have fixed names', () {
      expect(
        const InkPreset(kind: InkPresetKind.pencil, colorHex: '000000').label,
        'Pencil',
      );
      expect(
        const InkPreset(kind: InkPresetKind.highlighter, colorHex: 'FFD400')
            .label,
        'Highlighter',
      );
    });
  });

  group('equality (duplicates are detected by value)', () {
    test('same kind, color, width are equal', () {
      const a = InkPreset(kind: InkPresetKind.pen, colorHex: 'AABBCC', width: 8);
      const b = InkPreset(kind: InkPresetKind.pen, colorHex: 'AABBCC', width: 8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different color or width is a different preset', () {
      const a = InkPreset(kind: InkPresetKind.pen, colorHex: 'AABBCC', width: 8);
      expect(
        a == const InkPreset(kind: InkPresetKind.pen, colorHex: 'AABBC0', width: 8),
        isFalse,
      );
      expect(
        a == const InkPreset(kind: InkPresetKind.pen, colorHex: 'AABBCC', width: 16),
        isFalse,
      );
    });

    test('pencil and pen with the same color are different presets', () {
      const pen = InkPreset(kind: InkPresetKind.pen, colorHex: 'AABBCC', width: 8);
      const pencil = InkPreset(kind: InkPresetKind.pencil, colorHex: 'AABBCC');
      expect(pen == pencil, isFalse);
    });
  });

  group('inkSavePreset', () {
    const p1 = InkPreset(kind: InkPresetKind.pen, colorHex: '111111', width: 4);
    const p2 = InkPreset(kind: InkPresetKind.pencil, colorHex: '222222');

    test('a new preset is appended and reported saved', () {
      final r = inkSavePreset(const [p1], p2);
      expect(r.result, InkSaveResult.saved);
      expect(r.presets, [p1, p2]);
    });

    test('a value-equal preset is never saved twice', () {
      final r = inkSavePreset(const [p1], const InkPreset(
          kind: InkPresetKind.pen, colorHex: '111111', width: 4));
      expect(r.result, InkSaveResult.duplicate);
      expect(r.presets, [p1]);
    });

    test('the list is capped at kInkPresetCap', () {
      expect(kInkPresetCap, 6);
      var list = <InkPreset>[];
      for (var i = 0; i < kInkPresetCap; i++) {
        final r = inkSavePreset(
            list,
            InkPreset(
                kind: InkPresetKind.pen,
                colorHex: '00000$i',
                width: 8));
        expect(r.result, InkSaveResult.saved);
        list = r.presets;
      }
      expect(list.length, kInkPresetCap);
      final full = inkSavePreset(list, p2);
      expect(full.result, InkSaveResult.full);
      expect(full.presets.length, kInkPresetCap);
    });
  });

  group('inkRemovePresetAt', () {
    const a = InkPreset(kind: InkPresetKind.pen, colorHex: 'A00000', width: 4);
    const b = InkPreset(kind: InkPresetKind.pen, colorHex: 'B00000', width: 8);
    const c = InkPreset(kind: InkPresetKind.pen, colorHex: 'C00000', width: 16);

    test('removes exactly the indexed preset', () {
      expect(inkRemovePresetAt(const [a, b, c], 1), [a, c]);
    });

    test('an out-of-range index leaves the list unchanged', () {
      expect(inkRemovePresetAt(const [a, b], 5), [a, b]);
      expect(inkRemovePresetAt(const [a, b], -1), [a, b]);
    });
  });

  group('pencil tip', () {
    test('the pencil is thin and slightly translucent, not opaque', () {
      expect(kInkPencilWidth, 3.0);
      expect(kInkPencilOpacity, greaterThan(0.0));
      expect(kInkPencilOpacity, lessThan(1.0));
    });
  });
}
