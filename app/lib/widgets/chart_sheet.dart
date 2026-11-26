import 'package:material_ui/material_ui.dart';

import '../core/chart_math.dart';

/// Chart data editor (object actions → Edit chart): title, style, and the
/// rows (label + one value per series). Every series' values are editable;
/// a series keeps its name and color. Done returns the new data; cancel
/// returns nothing.
class ChartSheet extends StatefulWidget {
  const ChartSheet({super.key, required this.data});

  final ChartData data;

  @override
  State<ChartSheet> createState() => _ChartSheetState();
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

const _styleNames = {
  'column': 'Column',
  'bar': 'Bar',
  'line': 'Line',
  'pie': 'Pie',
};

/// Table geometry: a fixed label column, one fixed value column per series,
/// and the remove button. The table scrolls sideways when it is wider.
const _labelWidth = 120.0;
const _valueWidth = 80.0;
const _removeWidth = 48.0;

class _ChartSheetState extends State<ChartSheet> {
  late String _style;
  late final TextEditingController _title;
  final _labels = <TextEditingController>[];

  /// One column per series: `_cols[s][row]` is that series' value at row.
  final _cols = <List<TextEditingController>>[];
  final _names = <String>[];
  final _colors = <String?>[];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _style = d.style;
    _title = TextEditingController(text: d.title ?? '');
    final series = d.series.isEmpty
        ? const [ChartSeriesData(name: 'Series 1', values: [])]
        : d.series;
    final rows = [
      d.labels.length,
      1,
      for (final s in series) s.values.length,
    ].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < rows; i++) {
      _labels.add(TextEditingController(
          text: i < d.labels.length ? d.labels[i] : ''));
    }
    for (final s in series) {
      _names.add(s.name);
      _colors.add(s.color);
      _cols.add([
        for (var i = 0; i < rows; i++)
          TextEditingController(
              text: i < s.values.length ? _fmt(s.values[i]) : ''),
      ]);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in [..._labels, for (final col in _cols) ...col]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _rowCount => _labels.length;

  bool get _valid => _rowCount > 0 &&
      _cols.every((col) =>
          col.every((c) => parseChartValue(c.text) != null));

  ChartData _result() {
    final title = _title.text.trim();
    return ChartData(
      style: _style,
      title: title.isEmpty ? null : title,
      labels: [for (final c in _labels) c.text.trim()],
      series: [
        for (var s = 0; s < _cols.length; s++)
          ChartSeriesData(
            name: _names[s],
            values: [for (final c in _cols[s]) parseChartValue(c.text) ?? 0.0],
            color: _colors[s],
          ),
      ],
    );
  }

  void _addRow() {
    setState(() {
      _labels.add(TextEditingController());
      for (final col in _cols) {
        col.add(TextEditingController());
      }
    });
  }

  void _removeRow(int i) {
    if (_rowCount <= 1) return;
    setState(() {
      _labels.removeAt(i).dispose();
      for (final col in _cols) {
        col.removeAt(i).dispose();
      }
    });
  }

  /// One value field, keyed so tests and the sheet agree: series 0 keeps the
  /// plain `chart_value_<row>` key; later series use `chart_value_s<n>_<row>`.
  Widget _valueField(int s, int i) {
    final c = _cols[s][i];
    return SizedBox(
      width: _valueWidth,
      child: TextField(
        key: Key(s == 0 ? 'chart_value_$i' : 'chart_value_s${s}_$i'),
        controller: c,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
          isDense: true,
          hintText: _cols.length > 1 ? _names[s] : 'Value',
          errorText: parseChartValue(c.text) == null && c.text.trim().isNotEmpty
              ? 'Number'
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = _labelWidth + _valueWidth * _cols.length + _removeWidth;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chart data', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              key: const Key('chart_title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final style in kChartStyles)
                  ChoiceChip(
                    key: Key('chart_style_$style'),
                    label: Text(_styleNames[style] ?? style),
                    selected: _style == style,
                    onSelected: (_) => setState(() => _style = style),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_cols.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const SizedBox(width: _labelWidth),
                            for (var s = 0; s < _cols.length; s++)
                              SizedBox(
                                width: _valueWidth,
                                child: Text(_names[s],
                                    key: Key('chart_series_name_$s'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall),
                              ),
                          ],
                        ),
                      ),
                    for (var i = 0; i < _rowCount; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: _labelWidth,
                              child: TextField(
                                key: Key('chart_label_$i'),
                                controller: _labels[i],
                                decoration: const InputDecoration(
                                    isDense: true, hintText: 'Label'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            for (var s = 0; s < _cols.length; s++)
                              _valueField(s, i),
                            IconButton(
                              key: Key('chart_row_remove_$i'),
                              tooltip: 'Remove row',
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20),
                              onPressed: _rowCount > 1
                                  ? () => _removeRow(i)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('chart_row_add'),
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add row'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('chart_done'),
                onPressed:
                    _valid ? () => Navigator.pop(context, _result()) : null,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
