// Native chart rules (Wave 3 item 2). Pure, so they are unit-tested. These
// mirror the core's Chart model: the same palette, the same value scale, and
// the same payload shape the exporters read.

/// The chart styles, in the order the picker shows them.
const kChartStyles = ['column', 'bar', 'line', 'pie'];

/// Default series colors, used in order when a series has no valid color.
const kChartPalette = ['4F46E5', '10B981', 'F59E0B', 'EF4444', '6B7280', '0EA5E9'];

class ChartSeriesData {
  const ChartSeriesData({required this.name, required this.values, this.color});
  final String name;
  final List<double> values;

  /// 6-digit hex, or null for the palette default.
  final String? color;
}

class ChartData {
  const ChartData({
    required this.style,
    this.title,
    required this.labels,
    required this.series,
  });
  final String style;
  final String? title;
  final List<String> labels;
  final List<ChartSeriesData> series;
}

/// Reads a chart payload (`content` of a chart object). Null when the map is
/// not a chart or its style is unknown.
ChartData? chartDataOf(Map<String, dynamic>? content) {
  if (content == null || content['kind'] != 'chart') return null;
  final style = content['style'];
  if (style is! String || !kChartStyles.contains(style)) return null;
  final title = content['title'];
  final labels = ((content['labels'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();
  final series = <ChartSeriesData>[];
  for (final raw in (content['series'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final values = <double>[];
    for (final v in (raw['values'] as List?) ?? const []) {
      if (v is num && v.isFinite) values.add(v.toDouble());
    }
    final color = raw['color'];
    series.add(ChartSeriesData(
      name: (raw['name'] ?? '').toString(),
      values: values,
      color: color is String ? color : null,
    ));
  }
  return ChartData(
    style: style,
    title: title is String && title.isNotEmpty ? title : null,
    labels: labels,
    series: series,
  );
}

/// The payload the core stores: optional fields are omitted when unset.
Map<String, dynamic> chartPayload(ChartData d) => {
      'kind': 'chart',
      'style': d.style,
      if (d.title != null && d.title!.isNotEmpty) 'title': d.title,
      'labels': d.labels,
      'series': [
        for (final s in d.series)
          {
            'name': s.name,
            'values': s.values,
            if (s.color != null) 'color': s.color,
          },
      ],
    };

/// A new chart: a column chart with sample quarters.
ChartData defaultChartData() => const ChartData(
      style: 'column',
      title: 'Chart',
      labels: ['Q1', 'Q2', 'Q3', 'Q4'],
      series: [
        ChartSeriesData(name: 'Sales', values: [3, 5, 2, 6]),
      ],
    );

/// The series color as 6 hex digits (no `#`). A series with no valid color
/// of its own takes entry [i] of [palette] — the deck's DNA chart palette
/// (`resolve_dna` → `chart_palette`), so a chart matches its deck.
String chartColorAt(ChartSeriesData s, int i,
    {List<String> palette = kChartPalette}) {
  final c = s.color;
  if (c != null) {
    final h = c.startsWith('#') ? c.substring(1) : c;
    if (h.length == 6 && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) {
      return h.toUpperCase();
    }
  }
  final pal = palette.isEmpty ? kChartPalette : palette;
  return pal[i % pal.length];
}

/// The chart palette from a `resolve_dna` result's `chart_palette` list. Six
/// hex entries are kept; anything else falls back to the default palette.
List<String> chartPaletteFrom(Object? raw) {
  if (raw is! List) return kChartPalette;
  final out = [
    for (final e in raw)
      if (e is String && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(e)) e.toUpperCase(),
  ];
  return out.isEmpty ? kChartPalette : out;
}

/// The value scale: lowest and highest values, always including zero. A
/// flat range is widened by 1 so it still draws. Mirrors the core's
/// `chart_range`.
(double, double) chartRangeOf(List<ChartSeriesData> series) {
  var lo = 0.0;
  var hi = 0.0;
  for (final s in series) {
    for (final v in s.values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
  }
  if (hi <= lo) hi = lo + 1;
  return (lo, hi);
}

/// Parses a typed chart value. Null when it is not a finite number.
double? parseChartValue(String raw) {
  final v = double.tryParse(raw.trim());
  return (v != null && v.isFinite) ? v : null;
}
