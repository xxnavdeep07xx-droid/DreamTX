import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/chart_math.dart';

/// Native charts: the payload round trip, colors, the value scale, and the
/// typed-number rule the data sheet uses.
void main() {
  group('chartDataOf / chartPayload', () {
    test('a default chart survives a payload round trip', () {
      final payload = chartPayload(defaultChartData());
      final back = chartDataOf(payload)!;
      expect(back.style, 'column');
      expect(back.title, 'Chart');
      expect(back.labels, ['Q1', 'Q2', 'Q3', 'Q4']);
      expect(back.series.single.name, 'Sales');
      expect(back.series.single.values, [3, 5, 2, 6]);
      expect(back.series.single.color, isNull);
    });

    test('an unknown style or a non-chart map reads as no chart', () {
      expect(chartDataOf({'kind': 'chart', 'style': 'donut'}), isNull);
      expect(chartDataOf({'kind': 'table', 'style': 'column'}), isNull);
      expect(chartDataOf(null), isNull);
    });

    test('optional fields stay out of the payload when unset', () {
      const d = ChartData(
        style: 'pie',
        labels: ['a'],
        series: [ChartSeriesData(name: 's', values: [1])],
      );
      final p = chartPayload(d);
      expect(p.containsKey('title'), isFalse);
      expect(((p['series'] as List).single as Map).containsKey('color'), isFalse);
    });

    test('non-finite and non-numeric values are dropped on read', () {
      final d = chartDataOf({
        'kind': 'chart',
        'style': 'line',
        'labels': ['a', 'b', 'c'],
        'series': [
          {'name': 's', 'values': [1, 'x', 2.5]},
        ],
      })!;
      expect(d.series.single.values, [1.0, 2.5]);
    });
  });

  group('chartColorAt', () {
    test('uses a valid hex color, with or without #', () {
      expect(chartColorAt(const ChartSeriesData(name: 'a', values: [], color: '#10b981'), 0), '10B981');
      expect(chartColorAt(const ChartSeriesData(name: 'a', values: [], color: 'EF4444'), 3), 'EF4444');
    });

    test('falls back to the palette by index', () {
      expect(chartColorAt(const ChartSeriesData(name: 'a', values: [], color: 'red'), 0), kChartPalette[0]);
      expect(chartColorAt(const ChartSeriesData(name: 'a', values: []), 7), kChartPalette[1]);
    });
  });

  group('chartRangeOf', () {
    test('includes zero and widens a flat range', () {
      const s = [ChartSeriesData(name: 'a', values: [-2, 5])];
      expect(chartRangeOf(s), (-2.0, 5.0));
      const flat = [ChartSeriesData(name: 'a', values: [0, 0])];
      expect(chartRangeOf(flat), (0.0, 1.0));
    });
  });

  group('parseChartValue', () {
    test('accepts finite numbers and rejects the rest', () {
      expect(parseChartValue(' 2.5 '), 2.5);
      expect(parseChartValue('-3'), -3.0);
      expect(parseChartValue(''), isNull);
      expect(parseChartValue('abc'), isNull);
      expect(parseChartValue('Infinity'), isNull);
    });
  });
}
