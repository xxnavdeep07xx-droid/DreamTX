import 'package:material_ui/material_ui.dart';

import '../core/chart_math.dart';

/// Chart data editor (object actions → Edit chart): title, style, and the
/// rows of the first series (label + value). Other series and the first
/// series' color are carried through untouched. Done returns the new data;
/// cancel returns nothing.
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

class _ChartSheetState extends State<ChartSheet> {
  late String _style;
  late final TextEditingController _title;
  final _labels = <TextEditingController>[];
  final _values = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _style = d.style;
    _title = TextEditingController(text: d.title ?? '');
    final first = d.series.isEmpty ? null : d.series.first;
    final rows = [
      d.labels.length,
      first?.values.length ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < rows; i++) {
      _labels.add(TextEditingController(
          text: i < d.labels.length ? d.labels[i] : ''));
      _values.add(TextEditingController(
          text: first != null && i < first.values.length
              ? _fmt(first.values[i])
              : ''));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in [..._labels, ..._values]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _values.isNotEmpty && _values.every((c) => parseChartValue(c.text) != null);

  ChartData _result() {
    final d = widget.data;
    final orig = d.series.isEmpty ? null : d.series.first;
    final first = ChartSeriesData(
      name: orig?.name ?? 'Series 1',
      values: [for (final c in _values) parseChartValue(c.text) ?? 0.0],
      color: orig?.color,
    );
    final title = _title.text.trim();
    return ChartData(
      style: _style,
      title: title.isEmpty ? null : title,
      labels: [for (final c in _labels) c.text.trim()],
      series: [first, ...d.series.skip(1)],
    );
  }

  void _addRow() {
    setState(() {
      _labels.add(TextEditingController());
      _values.add(TextEditingController());
    });
  }

  void _removeRow(int i) {
    if (_values.length <= 1) return;
    setState(() {
      _labels.removeAt(i).dispose();
      _values.removeAt(i).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
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
            for (var i = 0; i < _values.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('chart_label_$i'),
                        controller: _labels[i],
                        decoration: const InputDecoration(
                            isDense: true, hintText: 'Label'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        key: Key('chart_value_$i'),
                        controller: _values[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Value',
                          errorText: parseChartValue(_values[i].text) == null &&
                                  _values[i].text.trim().isNotEmpty
                              ? 'Number'
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      key: Key('chart_row_remove_$i'),
                      tooltip: 'Remove row',
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed:
                          _values.length > 1 ? () => _removeRow(i) : null,
                    ),
                  ],
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
