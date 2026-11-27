import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Full manual slide editor. The user edits every content field by hand —
/// same semantic model the AI speaks, no coordinates. Changing archetype
/// resets the form to that archetype's defaults. Returns the new
/// (archetype, content) on Save; null on cancel.

typedef ContentEdit = ({String archetype, Map<String, dynamic> content});

const List<(String, String)> archetypeChoices = [
  ('Cover', 'cover'),
  ('Agenda', 'agenda'),
  ('Section break', 'section'),
  ('Big statement', 'statement'),
  ('Stat wall', 'stat_wall'),
  ('Split text + visual', 'split'),
  ('Comparison', 'comparison'),
  ('Chart hero', 'chart_hero'),
  ('Closing', 'closing'),
  ('Blank canvas', 'blank'),
];

String archetypeLabelOf(String snake) => archetypeChoices
    .firstWhere((c) => c.$2 == snake, orElse: () => ('Slide', snake)).$1;

/// Default content when the user switches archetype mid-edit.
Map<String, dynamic> defaultContentFor(String archetype, String deckTitle) {
  switch (archetype) {
    case 'cover':
      return {'kind': 'cover', 'kicker': null, 'title': deckTitle, 'subtitle': null};
    case 'agenda':
      return {'kind': 'agenda', 'title': 'Agenda', 'items': ['First topic', 'Second topic', 'Third topic']};
    case 'section':
      return {'kind': 'section', 'index': 1, 'title': 'Section', 'blurb': null};
    case 'statement':
      return {'kind': 'statement', 'text': 'One idea per slide.', 'attribution': null};
    case 'stat_wall':
      return {
        'kind': 'stat_wall',
        'title': null,
        'stats': [
          {'value': '42%', 'label': 'of something that matters'}
        ]
      };
    case 'split':
      return {'kind': 'split', 'title': 'Title', 'bullets': ['Point one', 'Point two'], 'visual_label': 'visual'};
    case 'comparison':
      return {
        'kind': 'comparison',
        'title': null,
        'left': {'title': 'Option A', 'points': ['pro']},
        'right': {'title': 'Option B', 'points': ['pro']},
      };
    case 'chart_hero':
      return {
        'kind': 'chart_hero',
        'title': 'Trend',
        'chart': {
          'type': 'bar',
          'categories': ['Q1', 'Q2', 'Q3'],
          'series': [
            {'name': 'value', 'values': [1.0, 2.0, 3.0]}
          ]
        },
        'takeaway': null,
      };
    case 'closing':
      return {'kind': 'closing', 'title': 'Thank you', 'subtitle': null};
    case 'blank':
      return {'kind': 'blank'};
    default:
      return {'kind': 'statement', 'text': 'One idea per slide.', 'attribution': null};
  }
}

class FieldSpec {
  const FieldSpec(this.key, this.label, this.type);
  final String key;
  final String label;
  final String type; // text | multiline | opt | number | list | stats | side | chart
}

const Map<String, List<FieldSpec>> fieldSpecs = {
  'cover': [FieldSpec('kicker', 'Kicker', 'opt'), FieldSpec('title', 'Title', 'text'), FieldSpec('subtitle', 'Subtitle', 'opt')],
  'agenda': [FieldSpec('title', 'Title', 'text'), FieldSpec('items', 'Agenda items', 'list')],
  'section': [FieldSpec('index', 'Section number', 'number'), FieldSpec('title', 'Title', 'text'), FieldSpec('blurb', 'Blurb', 'opt')],
  'statement': [FieldSpec('text', 'Statement', 'multiline'), FieldSpec('attribution', 'Attribution', 'opt')],
  'stat_wall': [FieldSpec('title', 'Title', 'opt'), FieldSpec('stats', 'Stats', 'stats')],
  'split': [FieldSpec('title', 'Title', 'text'), FieldSpec('bullets', 'Bullets', 'list'), FieldSpec('visual_label', 'Visual label', 'opt')],
  'comparison': [FieldSpec('title', 'Title', 'opt'), FieldSpec('left', 'Left column', 'side'), FieldSpec('right', 'Right column', 'side')],
  'chart_hero': [FieldSpec('title', 'Title', 'text'), FieldSpec('chart', 'Chart', 'chart'), FieldSpec('takeaway', 'Takeaway', 'opt')],
  'closing': [FieldSpec('title', 'Title', 'text'), FieldSpec('subtitle', 'Subtitle', 'opt')],
};

Future<ContentEdit?> showContentEditor(
  BuildContext context, {
  required Map slide,
  required String deckTitle,
}) {
  return showModalBottomSheet<ContentEdit>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ContentSheet(slide: slide, deckTitle: deckTitle),
  );
}

class ContentSheet extends StatefulWidget {
  const ContentSheet({super.key, required this.slide, required this.deckTitle});

  final Map slide;
  final String deckTitle;

  @override
  State<ContentSheet> createState() => _ContentSheetState();
}

class _ContentSheetState extends State<ContentSheet> {
  late String _archetype;
  String _chartType = 'bar';
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, bool> _present = {}; // optional fields in use
  final Map<String, int> _listLens = {}; // 'items' | 'bullets' | 'left.points' | …

  Map<String, dynamic> get _initialContent =>
      Map<String, dynamic>.from(widget.slide['content'] as Map? ?? const {});

  @override
  void initState() {
    super.initState();
    _archetype = (widget.slide['archetype'] ?? 'statement').toString();
    _initFrom(_initialContent);
  }

  @override
  void dispose() {
    for (final c in _ctrl.values.toList()) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _for(String path, String initial) =>
      _ctrl.putIfAbsent(path, () => TextEditingController(text: initial));

  /// Reset every field from a content map (also used on archetype switch).
  void _initFrom(Map content) {
    for (final c in _ctrl.values.toList()) {
      c.dispose();
    }
    _ctrl.clear();
    _present.clear();
    _listLens.clear();
    final specs = fieldSpecs[_archetype] ?? const <FieldSpec>[];
    for (final s in specs) {
      final v = content[s.key];
      switch (s.type) {
        case 'text':
        case 'multiline':
          _for(s.key, (v ?? '').toString());
        case 'number':
          _for(s.key, (v ?? 1).toString());
        case 'opt':
          _present[s.key] = v != null;
          if (v != null) _for(s.key, v.toString());
        case 'list':
          final list = (v as List? ?? const []).whereType<String>().toList();
          _listLens[s.key] = list.length;
          for (var i = 0; i < list.length; i++) {
            _for('${s.key}.$i', list[i]);
          }
        case 'stats':
          final list = (v as List? ?? const []).whereType<Map>().toList();
          _listLens[s.key] = list.length;
          for (var i = 0; i < list.length; i++) {
            _for('$s.key.$i.value', (list[i]['value'] ?? '').toString());
            _for('$s.key.$i.label', (list[i]['label'] ?? '').toString());
          }
        case 'side':
          final side = Map<String, dynamic>.from(v as Map? ?? const {});
          _for('${s.key}.title', (side['title'] ?? '').toString());
          final points = (side['points'] as List? ?? const []).whereType<String>().toList();
          _listLens['$s.key.points'] = points.length;
          for (var i = 0; i < points.length; i++) {
            _for('${s.key}.points.$i', points[i]);
          }
        case 'chart':
          final chart = Map<String, dynamic>.from(v as Map? ?? const {});
          _chartType = (chart['type'] ?? 'bar').toString() == 'line' ? 'line' : 'bar';
          final cats = (chart['categories'] as List? ?? const []).whereType<String>().toList();
          _listLens['chart.categories'] = cats.length;
          for (var i = 0; i < cats.length; i++) {
            _for('chart.categories.$i', cats[i]);
          }
          final series = (chart['series'] as List? ?? const []).whereType<Map>().toList();
          _listLens['chart.series'] = series.length;
          for (var i = 0; i < series.length; i++) {
            _for('chart.series.$i.name', (series[i]['name'] ?? '').toString());
            final values = (series[i]['values'] as List? ?? const []).map((e) => e.toString()).join(', ');
            _for('chart.series.$i.values', values);
          }
      }
    }
  }

  Map<String, dynamic> _compose() {
    final out = <String, dynamic>{'kind': _archetype};
    for (final s in fieldSpecs[_archetype] ?? const <FieldSpec>[]) {
      switch (s.type) {
        case 'text':
        case 'multiline':
          out[s.key] = _ctrl[s.key]?.text ?? '';
        case 'number':
          out[s.key] = int.tryParse(_ctrl[s.key]?.text ?? '') ?? 1;
        case 'opt':
          if (_present[s.key] == true) out[s.key] = _ctrl[s.key]?.text ?? '';
        case 'list':
          out[s.key] = [
            for (var i = 0; i < (_listLens[s.key] ?? 0); i++) _ctrl['${s.key}.$i']?.text ?? ''
          ];
        case 'stats':
          out[s.key] = [
            for (var i = 0; i < (_listLens[s.key] ?? 0); i++)
              {'value': _ctrl['$s.key.$i.value']?.text ?? '', 'label': _ctrl['$s.key.$i.label']?.text ?? ''}
          ];
        case 'side':
          out[s.key] = {
            'title': _ctrl['${s.key}.title']?.text ?? '',
            'points': [
              for (var i = 0; i < (_listLens['$s.key.points'] ?? 0); i++)
                _ctrl['${s.key}.points.$i']?.text ?? ''
            ],
          };
        case 'chart':
          out[s.key] = {
            'type': _chartType,
            'categories': [
              for (var i = 0; i < (_listLens['chart.categories'] ?? 0); i++)
                _ctrl['chart.categories.$i']?.text ?? ''
            ],
            'series': [
              for (var i = 0; i < (_listLens['chart.series'] ?? 0); i++)
                {
                  'name': _ctrl['chart.series.$i.name']?.text ?? '',
                  'values': _parseDoubles(_ctrl['chart.series.$i.values']?.text ?? ''),
                }
            ],
          };
      }
    }
    return out;
  }

  List<double> _parseDoubles(String text) {
    final values = text
        .split(',')
        .map((e) => double.tryParse(e.trim()))
        .whereType<double>()
        .toList();
    return values.isEmpty ? [0.0] : values;
  }

  // ---- list surgery -------------------------------------------------------

  void _addListItem(String base, {String placeholder = ''}) {
    setState(() {
      final n = _listLens[base] ?? 0;
      _listLens[base] = n + 1;
      _for('$base.$n', placeholder);
    });
  }

  void _removeListItem(String base, int i, {List<String> subfields = const ['']}) {
    setState(() {
      final n = _listLens[base] ?? 0;
      for (var j = i; j < n - 1; j++) {
        for (final f in subfields) {
          final from = f.isEmpty ? '$base.$j' : '$base.$j.$f';
          final to = f.isEmpty ? '$base.${j + 1}' : '$base.${j + 1}.$f';
          _ctrl[from]?.text = _ctrl[to]?.text ?? '';
        }
      }
      for (final f in subfields) {
        final last = f.isEmpty ? '$base.${n - 1}' : '$base.${n - 1}.$f';
        _ctrl[last]?.dispose();
        _ctrl.remove(last);
      }
      _listLens[base] = n - 1;
    });
  }

  void _moveListItem(String base, int i, int dir, {List<String> subfields = const ['']}) {
    final n = _listLens[base] ?? 0;
    final j = i + dir;
    if (j < 0 || j >= n) return;
    setState(() {
      for (final f in subfields) {
        final a = f.isEmpty ? '$base.$i' : '$base.$i.$f';
        final b = f.isEmpty ? '$base.$j' : '$base.$j.$f';
        final tmp = _ctrl[a]?.text ?? '';
        _ctrl[a]?.text = _ctrl[b]?.text ?? '';
        _ctrl[b]?.text = tmp;
      }
    });
  }

  // ---- widgets --------------------------------------------------------------

  Widget _gap() => const SizedBox(height: 12);

  Widget _field(String path, String label, {int maxLines = 1, TextInputType? kb}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _for(path, ''),
        maxLines: maxLines,
        keyboardType: kb,
        style: const TextStyle(color: kText, fontSize: 14),
        cursorColor: kPurple,
        decoration: darkInput(label: label),
      ),
    );
  }

  Widget _optional(String key, String label) {
    if (_present[key] != true) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: Text('Add ${label.toLowerCase()}'),
            onPressed: () => setState(() {
              _present[key] = true;
              _for(key, '');
            }),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              tooltip: 'Remove ${label.toLowerCase()}',
              onPressed: () => setState(() => _present[key] = false),
            ),
          ],
        ),
        _field(key, label),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      );

  Widget _stringList(String base, String label) {
    final n = _listLens[base] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('$label · $n')),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add',
              onPressed: () => _addListItem(base),
            ),
          ],
        ),
        for (var i = 0; i < n; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${i + 1}', style: Theme.of(context).textTheme.labelMedium),
                ),
                Expanded(child: _field('$base.$i', '$label ${i + 1}')),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (v) {
                    if (v == 'up') _moveListItem(base, i, -1);
                    if (v == 'down') _moveListItem(base, i, 1);
                    if (v == 'remove') _removeListItem(base, i);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'up', child: Text('Move up')),
                    PopupMenuItem(value: 'down', child: Text('Move down')),
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statsEditor() {
    final n = _listLens['stats'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('Stats · $n')),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add stat',
              onPressed: () => setState(() {
                final n = _listLens['stats'] ?? 0;
                _listLens['stats'] = n + 1;
                _for('stats.$n.value', '');
                _for('stats.$n.label', '');
              }),
            ),
          ],
        ),
        for (var i = 0; i < n; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: kHairline),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 2, child: _field('stats.$i.value', 'Value')),
                      Expanded(flex: 3, child: _field('stats.$i.label', 'Label')),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (v) {
                          if (v == 'up') _moveListItem('stats', i, -1, subfields: const ['value', 'label']);
                          if (v == 'down') _moveListItem('stats', i, 1, subfields: const ['value', 'label']);
                          if (v == 'remove') _removeListItem('stats', i, subfields: const ['value', 'label']);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'up', child: Text('Move up')),
                          PopupMenuItem(value: 'down', child: Text('Move down')),
                          PopupMenuItem(value: 'remove', child: Text('Remove')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _side(String key, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        _field('$key.title', '$label title'),
        _stringList('$key.points', 'Points'),
      ],
    );
  }

  Widget _chartEditor() {
    final cats = _listLens['chart.categories'] ?? 0;
    final series = _listLens['chart.series'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Chart'),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Bar'),
              selected: _chartType == 'bar',
              onSelected: (_) => setState(() => _chartType = 'bar'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Line'),
              selected: _chartType == 'line',
              onSelected: (_) => setState(() => _chartType = 'line'),
            ),
          ],
        ),
        _gap(),
        _stringList('chart.categories', 'Category'),
        Row(
          children: [
            Expanded(child: _sectionLabel('Series · $series')),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add series',
              onPressed: () => setState(() {
                _listLens['chart.series'] = series + 1;
                _for('chart.series.$series.name', 'Series');
                _for('chart.series.$series.values', '1, 2, 3');
              }),
            ),
          ],
        ),
        for (var i = 0; i < series; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: kHairline),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _field('chart.series.$i.name', 'Series name')),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (v) {
                          if (v == 'up') _moveListItem('chart.series', i, -1, subfields: const ['name', 'values']);
                          if (v == 'down') _moveListItem('chart.series', i, 1, subfields: const ['name', 'values']);
                          if (v == 'remove') _removeListItem('chart.series', i, subfields: const ['name', 'values']);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'up', child: Text('Move up')),
                          PopupMenuItem(value: 'down', child: Text('Move down')),
                          PopupMenuItem(value: 'remove', child: Text('Remove')),
                        ],
                      ),
                    ],
                  ),
                  _field('chart.series.$i.values', 'Values (comma separated)'),
                ],
              ),
            ),
          ),
        if (cats == 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Add at least one category.', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _fieldFor(FieldSpec s) {
    switch (s.type) {
      case 'text':
        return _field(s.key, s.label);
      case 'multiline':
        return _field(s.key, s.label, maxLines: 3);
      case 'number':
        return _field(s.key, s.label, kb: TextInputType.number);
      case 'opt':
        return _optional(s.key, s.label);
      case 'list':
        return _stringList(s.key, s.label);
      case 'stats':
        return _statsEditor();
      case 'side':
        return _side(s.key, s.label);
      case 'chart':
        return _chartEditor();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- header: archetype switch -------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit slide', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          archetypeLabelOf(_archetype),
                          style: const TextStyle(fontSize: 12, color: kText2),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Change archetype',
                    icon: const Icon(Icons.swap_horiz),
                    onSelected: (v) {
                      if (v == _archetype) return;
                      setState(() {
                        _archetype = v;
                        _initFrom(defaultContentFor(v, widget.deckTitle));
                      });
                    },
                    itemBuilder: (_) => [
                      for (final (label, snake) in archetypeChoices)
                        PopupMenuItem(
                          value: snake,
                          child: Text(label, style: snake == _archetype ? const TextStyle(fontWeight: FontWeight.w700) : null),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            // ---- scrollable form -----------------------------------------
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in fieldSpecs[_archetype] ?? const <FieldSpec>[]) _fieldFor(s),
                    if ((fieldSpecs[_archetype] ?? const <FieldSpec>[]).isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(Icons.crop_square, size: 40, color: kText3),
                            SizedBox(height: 10),
                            Text(
                              'Blank slide — nothing to edit here.\nDraw with the Shapes tool, or switch the layout (swap icon above).',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: kText2, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // ---- actions --------------------------------------------------
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        (archetype: _archetype, content: _compose()),
                      ),
                      child: const Text('Save slide'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
