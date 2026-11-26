import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/chart_math.dart';

/// Chart colors follow the deck's DNA palette when a series has no color of
/// its own, and the palette list from `resolve_dna` is read defensively.
void main() {
  group('chartColorAt with a deck palette', () {
    const deckPalette = ['112233', '445566', '778899'];

    test('an uncolored series takes its entry from the deck palette', () {
      const s = ChartSeriesData(name: 'a', values: []);
      expect(chartColorAt(s, 0, palette: deckPalette), '112233');
      expect(chartColorAt(s, 2, palette: deckPalette), '778899');
      expect(chartColorAt(s, 3, palette: deckPalette), '112233');
    });

    test('an explicit series color still wins over the deck palette', () {
      const s = ChartSeriesData(name: 'a', values: [], color: 'EF4444');
      expect(chartColorAt(s, 1, palette: deckPalette), 'EF4444');
    });

    test('no palette given falls back to the default palette', () {
      const s = ChartSeriesData(name: 'a', values: []);
      expect(chartColorAt(s, 0), kChartPalette[0]);
      expect(chartColorAt(s, 0, palette: const []), kChartPalette[0]);
    });
  });

  group('chartPaletteFrom', () {
    test('keeps six-digit hex entries, uppercased', () {
      expect(chartPaletteFrom(['aabbcc', '010203']), ['AABBCC', '010203']);
    });

    test('drops invalid entries and falls back when nothing is usable', () {
      expect(chartPaletteFrom(['zz', 12, 'AABBCC']), ['AABBCC']);
      expect(chartPaletteFrom(['nope']), kChartPalette);
      expect(chartPaletteFrom(null), kChartPalette);
      expect(chartPaletteFrom('AABBCC'), kChartPalette);
    });
  });
}
