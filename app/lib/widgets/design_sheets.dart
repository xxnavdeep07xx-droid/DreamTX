import 'package:material_ui/material_ui.dart';

import '../core/color_utils.dart';
import 'controls.dart';
import '../theme.dart';

/// Shape library, style inspector, layers panel and components sheet —
/// the manual studio UI for the vector overlay layer.

// ---------------------------------------------------------------------------
// Style inspector
// ---------------------------------------------------------------------------

Future<void> showInspector(
  BuildContext context, {
  required Map<String, dynamic> object,
  required void Function(Map<String, dynamic>) onChange,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _InspectorSheet(object: object, onChange: onChange),
  );
}

class _InspectorSheet extends StatefulWidget {
  const _InspectorSheet({required this.object, required this.onChange});

  final Map<String, dynamic> object;
  final void Function(Map<String, dynamic>) onChange;

  @override
  State<_InspectorSheet> createState() => _InspectorSheetState();
}

class _InspectorSheetState extends State<_InspectorSheet> {
  late Map<String, dynamic> _obj;

  @override
  void initState() {
    super.initState();
    _obj = _deepCopy(widget.object);
  }

  Map<String, dynamic> _deepCopy(Map src) {
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      if (v is Map) {
        out[k] = _deepCopy(v);
      } else if (v is List) {
        out[k] = v.map((e) => e is Map ? _deepCopy(e) : e).toList();
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  Map<String, dynamic> get _fill {
    final f = _obj['fill'];
    if (f is Map<String, dynamic>) return f;
    final created = <String, dynamic>{'type': 'none'};
    _obj['fill'] = created;
    return created;
  }

  Map<String, dynamic> get _stroke {
    final s = _obj['stroke'];
    if (s is Map<String, dynamic>) return s;
    final created = <String, dynamic>{'color': '17181A', 'width': 0, 'dash': 'solid', 'start_arrow': 'none', 'end_arrow': 'none'};
    _obj['stroke'] = created;
    return created;
  }

  Map<String, dynamic> get _effects {
    final e = _obj['effects'];
    if (e is Map<String, dynamic>) return e;
    final created = <String, dynamic>{};
    _obj['effects'] = created;
    return created;
  }

  void _setFillType(String t) {
    final cur = _fill;
    setState(() {
      switch (t) {
        case 'solid':
          _obj['fill'] = {'type': 'solid', 'color': (cur['color'] ?? cur['from'] ?? 'D03028').toString()};
        case 'linear_gradient':
          _obj['fill'] = {
            'type': 'linear_gradient',
            'angle': ((cur['angle'] ?? 0) as num).toDouble(),
            'from': (cur['from'] ?? cur['color'] ?? 'D03028').toString(),
            'to': (cur['to'] ?? 'F7F6F3').toString(),
          };
        case 'radial_gradient':
          _obj['fill'] = {
            'type': 'radial_gradient',
            'from': (cur['from'] ?? cur['color'] ?? 'D03028').toString(),
            'to': (cur['to'] ?? 'F7F6F3').toString(),
          };
        default:
          _obj['fill'] = {'type': 'none'};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fill = _fill;
    final fillType = (fill['type'] ?? 'none').toString();
    final maxH = MediaQuery.of(context).size.height * 0.86;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Style', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Text(
                    (widget.object['preset'] ?? 'shape').toString().replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 12, color: kText2),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel('Fill'),
                    _chips(
                      ['none', 'solid', 'linear_gradient', 'radial_gradient'],
                      ['None', 'Solid', 'Gradient', 'Radial'],
                      fillType,
                      _setFillType,
                    ),
                    if (fillType == 'solid') ...[
                      _ColorField(
                        label: 'Color',
                        initial: (fill['color'] ?? 'D03028').toString(),
                        onChanged: (c) => setState(() => fill['color'] = c),
                      ),
                    ],
                    if (fillType == 'linear_gradient') ...[
                      _ColorField(
                        label: 'From',
                        initial: (fill['from'] ?? 'D03028').toString(),
                        onChanged: (c) => setState(() => fill['from'] = c),
                      ),
                      _ColorField(
                        label: 'To',
                        initial: (fill['to'] ?? 'F7F6F3').toString(),
                        onChanged: (c) => setState(() => fill['to'] = c),
                      ),
                      _slider(
                        'Angle',
                        ((fill['angle'] ?? 0) as num).toDouble(),
                        0,
                        360,
                        (v) => setState(() => fill['angle'] = v.round()),
                        suffix: '°',
                      ),
                    ],
                    if (fillType == 'radial_gradient') ...[
                      _ColorField(
                        label: 'Center color',
                        initial: (fill['from'] ?? 'D03028').toString(),
                        onChanged: (c) => setState(() => fill['from'] = c),
                      ),
                      _ColorField(
                        label: 'Edge color',
                        initial: (fill['to'] ?? 'F7F6F3').toString(),
                        onChanged: (c) => setState(() => fill['to'] = c),
                      ),
                    ],
                    _sectionLabel('Stroke'),
                    _ColorField(
                      label: 'Color',
                      initial: (_stroke['color'] ?? '17181A').toString(),
                      onChanged: (c) => setState(() => _stroke['color'] = c),
                    ),
                    _slider(
                      'Width',
                      ((_stroke['width'] ?? 0) as num).toDouble(),
                      0,
                      16,
                      (v) => setState(() => _stroke['width'] = v.roundToDouble()),
                    ),
                    _chips(
                      ['solid', 'dash', 'dot', 'dash_dot'],
                      ['Solid', 'Dashed', 'Dotted', 'Dash-dot'],
                      (_stroke['dash'] ?? 'solid').toString(),
                      (v) => setState(() => _stroke['dash'] = v),
                    ),
                    _chips(
                      ['none', 'arrow', 'triangle'],
                      ['No start', '→ start', '▲ start'],
                      (_stroke['start_arrow'] ?? 'none').toString(),
                      (v) => setState(() => _stroke['start_arrow'] = v),
                    ),
                    _chips(
                      ['none', 'arrow', 'triangle'],
                      ['No end', '→ end', '▲ end'],
                      (_stroke['end_arrow'] ?? 'none').toString(),
                      (v) => setState(() => _stroke['end_arrow'] = v),
                    ),
                    _sectionLabel('Effects'),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Drop shadow'),
                      value: _effects['shadow'] is Map,
                      onChanged: (v) => setState(() {
                        _effects['shadow'] = v ? {'dx': 8.0, 'dy': 10.0, 'blur': 16.0, 'color': '000000', 'opacity': 0.45} : null;
                      }),
                    ),
                    if (_effects['shadow'] is Map) ..._shadowFields(_effects['shadow'] as Map<String, dynamic>),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Glow'),
                      value: _effects['glow'] is Map,
                      onChanged: (v) => setState(() {
                        _effects['glow'] = v ? {'color': 'D03028', 'blur': 14.0} : null;
                      }),
                    ),
                    if (_effects['glow'] is Map) ...[
                      _ColorField(
                        label: 'Glow color',
                        initial: ((_effects['glow'] as Map)['color'] ?? 'D03028').toString(),
                        onChanged: (c) => setState(() => (_effects['glow'] as Map)['color'] = c),
                      ),
                      _slider(
                        'Glow blur',
                        (((_effects['glow'] as Map)['blur'] ?? 14) as num).toDouble(),
                        2,
                        48,
                        (v) => setState(() => (_effects['glow'] as Map)['blur'] = v.roundToDouble()),
                      ),
                    ],
                    _sectionLabel('Object'),
                    _slider(
                      'Opacity',
                      ((_obj['opacity'] ?? 1) as num).toDouble(),
                      0.05,
                      1,
                      (v) => setState(() => _obj['opacity'] = double.parse(v.toStringAsFixed(2))),
                    ),
                    _slider(
                      'Rotation',
                      ((_obj['rotation'] ?? 0) as num).toDouble(),
                      0,
                      360,
                      (v) => setState(() => _obj['rotation'] = v.round().toDouble()),
                      suffix: '°',
                    ),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Lock (no accidental edits)'),
                      value: _obj['locked'] == true,
                      onChanged: (v) => setState(() => _obj['locked'] = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
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
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onChange(_obj);
                      },
                      child: const Text('Apply style'),
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

  List<Widget> _shadowFields(Map<String, dynamic> sh) {
    return [
      _ColorField(
        label: 'Shadow color',
        initial: (sh['color'] ?? '000000').toString(),
        onChanged: (c) => setState(() => sh['color'] = c),
      ),
      _slider('Offset X', ((sh['dx'] ?? 0) as num).toDouble(), -40, 40, (v) => setState(() => sh['dx'] = v.roundToDouble())),
      _slider('Offset Y', ((sh['dy'] ?? 0) as num).toDouble(), -40, 40, (v) => setState(() => sh['dy'] = v.roundToDouble())),
      _slider('Blur', ((sh['blur'] ?? 16) as num).toDouble(), 0, 60, (v) => setState(() => sh['blur'] = v.roundToDouble())),
      _slider(
        'Strength',
        ((sh['opacity'] ?? 0.45) as num).toDouble(),
        0.05,
        1,
        (v) => setState(() => sh['opacity'] = double.parse(v.toStringAsFixed(2))),
      ),
    ];
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: kText2),
        ),
      );

  Widget _chips(List<String> values, List<String> labels, String current, void Function(String) onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < values.length; i++)
          DreamChoiceChip(
            label: labels[i],
            selected: current == values[i],
            onTap: () => onPick(values[i]),
          ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, void Function(double) onChanged, {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label — ${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}$suffix',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorField extends StatefulWidget {
  const _ColorField({required this.label, required this.initial, required this.onChanged});

  final String label;
  final String initial;
  final void Function(String) onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late TextEditingController _controller;

  /// The last value that COMMITTED (a valid 6-hex). The preview swatch holds
  /// this while the field holds a partial or invalid string, so it never
  /// flips to a phantom mid-typing color.
  late String _lastValid;

  static String _normalize(String v) =>
      v.trim().toUpperCase().replaceAll('#', '');

  bool _isValid(String v) {
    final hex = _normalize(v);
    return hex.length == 6 && int.tryParse(hex, radix: 16) != null;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial.toUpperCase());
    _lastValid = _normalize(widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String v) {
    if (_isValid(v)) {
      final hex = _normalize(v);
      widget.onChanged(hex);
      setState(() => _lastValid = hex);
    } else {
      // Nothing commits — but the hint and the swatch still need to reflect
      // the field's current (in)validity.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final valid = _isValid(text);
    // Quiet while the user is mid-word ("1A"); honest once the entry looks
    // complete but is not a 6-digit hex ("GGGGGG", "1234567").
    final showHint =
        text.isNotEmpty && !valid && _normalize(text).length >= 6;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: kText, fontSize: 13),
                  cursorColor: kPurple,
                  decoration: darkInput(hint: 'RRGGBB'),
                  onChanged: _commit,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  // Stable preview: the live value while valid, the last
                  // committed one otherwise — never a mid-typing phantom.
                  color: valid ? hexToColor(text) : hexToColor(_lastValid),
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          if (showHint)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Enter 6 hex digits, e.g. A1B2C3 — changes apply only when the value parses',
                style: TextStyle(fontSize: 10.5, color: kAccent),
              ),
            ),
          const SizedBox(height: 4),
          DreamColorChips(
            palette: kSwatchPalette,
            selected: _controller.text,
            onPick: (hex) {
              if (hex == null) return; // a typed hex is the only "clear"
              _controller.text = hex;
              _commit(hex);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layers panel
// ---------------------------------------------------------------------------

Future<void> showLayersSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> objects,
  required List<Map<String, dynamic>> presets,
  required Map<String, dynamic> deck,
  required void Function(List<String> ids) onGroup,
  required void Function(List<String> ids) onUngroup,
  required void Function(String mode, List<String> ids) onAlign,
  required void Function(String mode, List<String> ids) onBoolean,
  required void Function(List<String> ids, String name) onSaveComponent,
  required void Function(String componentId) onPlaceComponent,
  required void Function(String objectId) onSyncComponent,
  required void Function(String id, int dir) onReorder,
  required void Function(String id) onToggleLock,
  required void Function(String id) onEditStyle,
  required void Function(String id) onDelete,
  required void Function(String id) onDuplicate,
  required void Function(String id) onReflect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LayersSheet(
      objects: objects,
      presets: presets,
      deck: deck,
      onGroup: onGroup,
      onUngroup: onUngroup,
      onAlign: onAlign,
      onBoolean: onBoolean,
      onSaveComponent: onSaveComponent,
      onPlaceComponent: onPlaceComponent,
      onSyncComponent: onSyncComponent,
      onReorder: onReorder,
      onToggleLock: onToggleLock,
      onEditStyle: onEditStyle,
      onDelete: onDelete,
      onDuplicate: onDuplicate,
      onReflect: onReflect,
    ),
  );
}

class _LayersSheet extends StatefulWidget {
  const _LayersSheet({
    required this.objects,
    required this.presets,
    required this.deck,
    required this.onGroup,
    required this.onUngroup,
    required this.onAlign,
    required this.onBoolean,
    required this.onSaveComponent,
    required this.onPlaceComponent,
    required this.onSyncComponent,
    required this.onReorder,
    required this.onToggleLock,
    required this.onEditStyle,
    required this.onDelete,
    required this.onDuplicate,
    required this.onReflect,
  });

  final List<Map<String, dynamic>> objects;
  final List<Map<String, dynamic>> presets;
  final Map<String, dynamic> deck;
  final void Function(List<String> ids) onGroup;
  final void Function(List<String> ids) onUngroup;
  final void Function(String mode, List<String> ids) onAlign;
  final void Function(String mode, List<String> ids) onBoolean;
  final void Function(List<String> ids, String name) onSaveComponent;
  final void Function(String componentId) onPlaceComponent;
  final void Function(String objectId) onSyncComponent;
  final void Function(String id, int dir) onReorder;
  final void Function(String id) onToggleLock;
  final void Function(String id) onEditStyle;
  final void Function(String id) onDelete;
  final void Function(String id) onDuplicate;
  final void Function(String id) onReflect;

  @override
  State<_LayersSheet> createState() => _LayersSheetState();
}

class _LayersSheetState extends State<_LayersSheet> {
  final Set<String> _sel = {};

  bool _isConvex(Map obj) {
    if (obj['points'] != null) return false; // freeform — let the engine judge
    final name = (obj['preset'] ?? '').toString();
    for (final p in widget.presets) {
      if (p['name'] == name) return p['convex'] == true;
    }
    return false;
  }

  bool get _twoConvex =>
      _sel.length == 2 &&
      widget.objects.where((o) => _sel.contains(o['id'] as String)).every(_isConvex);

  void _pop() => Navigator.pop(context);

  Future<void> _askComponentName() async {
    final name = await dreamInputDialog(
      context,
      title: 'Save as component',
      hint: 'e.g. Brand badge',
      confirmLabel: 'Save',
    );
    if (name == null || name.trim().isEmpty) return;
    widget.onSaveComponent(_sel.toList(), name.trim());
    _pop();
  }

  @override
  Widget build(BuildContext context) {
    final objects = List<Map<String, dynamic>>.from(widget.objects.reversed); // top first
    final components = (widget.deck['components'] as List? ?? []).whereType<Map>().toList();
    final maxH = MediaQuery.of(context).size.height * 0.86;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Layers', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Text('${objects.length} objects · ${_sel.length} selected',
                      style: const TextStyle(fontSize: 12, color: kText2)),
                ],
              ),
            ),
            const Divider(height: 12),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  children: [
                    for (var i = 0; i < objects.length; i++)
                      _layerRow(objects[i], i == 0, i == objects.length - 1),
                    if (objects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No objects on this slide yet — add a shape.'),
                      ),
                    const Divider(height: 24),
                    _sectionLabel('Selection actions'),
                    _actionWrap(),
                    const Divider(height: 24),
                    _sectionLabel('Components (update everywhere)'),
                    for (final comp in components)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.extension_outlined),
                        title: Text((comp['name'] ?? 'Component').toString()),
                        subtitle: Text('${((comp['objects'] as List?) ?? []).length} objects'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Place a copy on this slide',
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              onPressed: () {
                                widget.onPlaceComponent(comp['id'].toString());
                                _pop();
                              },
                            ),
                            IconButton(
                              tooltip: 'Sync this component from its current instance',
                              icon: const Icon(Icons.sync, size: 20),
                              onPressed: () {
                                widget.onSyncComponent(
                                  _firstInstanceOf(comp['id'].toString()) ?? '',
                                );
                                _pop();
                              },
                            ),
                          ],
                        ),
                      ),
                    if (components.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Select objects and “Save as component” to create one.'),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _firstInstanceOf(String componentId) {
    for (final o in widget.objects) {
      if (o['component'] == componentId) return o['id'] as String?;
    }
    return null;
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: kText2),
          ),
        ),
      );

  Widget _layerRow(Map obj, bool first, bool last) {
    final id = obj['id'] as String;
    final selected = _sel.contains(id);
    final preset = (obj['preset'] ?? 'shape').toString().replaceAll('_', ' ');
    final isComp = obj['component'] != null;
    final locked = obj['locked'] == true;
    return CheckboxListTile(
      dense: true,
      value: selected,
      onChanged: (v) => setState(() {
        if (v == true) {
          _sel.add(id);
        } else {
          _sel.remove(id);
        }
      }),
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: [
          Expanded(
            child: Text(
              preset,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (isComp) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.extension_outlined, size: 14, color: kText2)),
          if (locked) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.lock_outline, size: 14, color: kText2)),
        ],
      ),
      subtitle: Text(
        'x${(obj['x'] as num?)?.round()} y${(obj['y'] as num?)?.round()} · ${((obj['w'] as num?) ?? 0).round()}x${((obj['h'] as num?) ?? 0).round()}',
        style: const TextStyle(fontSize: 11),
      ),
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Bring forward',
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            onPressed: first ? null : () => widget.onReorder(id, -1),
          ),
          IconButton(
            tooltip: 'Send backward',
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            onPressed: last ? null : () => widget.onReorder(id, 1),
          ),
          IconButton(
            tooltip: locked ? 'Unlock' : 'Lock',
            icon: Icon(locked ? Icons.lock_outline : Icons.lock_open_outlined, size: 20),
            onPressed: () => widget.onToggleLock(id),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete(id);
            },
          ),
        ],
      ),
    );
  }

  Widget _actionWrap() {
    final selIds = _sel.toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.group_work_outlined, size: 16),
          label: const Text('Group'),
          onPressed: _sel.length >= 2 ? () { widget.onGroup(selIds); _pop(); } : null,
        ),
        ActionChip(
          avatar: const Icon(Icons.link_off, size: 16),
          label: const Text('Ungroup'),
          onPressed: _sel.isNotEmpty ? () { widget.onUngroup(selIds); _pop(); } : null,
        ),
        ActionChip(
          avatar: const Icon(Icons.call_merge, size: 16),
          label: const Text('Union'),
          onPressed: _twoConvex ? () { widget.onBoolean('union', selIds); _pop(); } : null,
        ),
        ActionChip(
          avatar: const Icon(Icons.call_split, size: 16),
          label: const Text('Subtract'),
          onPressed: _twoConvex ? () { widget.onBoolean('subtract', selIds); _pop(); } : null,
        ),
        ActionChip(
          avatar: const Icon(Icons.filter_center_focus, size: 16),
          label: const Text('Intersect'),
          onPressed: _twoConvex ? () { widget.onBoolean('intersect', selIds); _pop(); } : null,
        ),
        for (final (mode, icon, label) in [
          ('left', Icons.align_horizontal_left, 'Left'),
          ('center', Icons.align_horizontal_center, 'Center X'),
          ('right', Icons.align_horizontal_right, 'Right'),
          ('top', Icons.align_vertical_top, 'Top'),
          ('middle', Icons.align_vertical_center, 'Middle'),
          ('bottom', Icons.align_vertical_bottom, 'Bottom'),
        ])
          ActionChip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
            onPressed: _sel.isNotEmpty ? () { widget.onAlign(mode, selIds); _pop(); } : null,
          ),
        ActionChip(
          avatar: const Icon(Icons.extension_outlined, size: 16),
          label: const Text('Save as component'),
          onPressed: _sel.isNotEmpty ? _askComponentName : null,
        ),
        ActionChip(
          avatar: const Icon(Icons.format_paint_outlined, size: 16),
          label: const Text('Style'),
          onPressed: _sel.length == 1 ? () { widget.onEditStyle(_sel.first); _pop(); } : null,
        ),
        ActionChip(
          avatar: const Icon(Icons.content_copy, size: 16),
          label: const Text('Duplicate'),
          onPressed: _sel.length == 1 ? () { widget.onDuplicate(_sel.first); _pop(); } : null,
        ),
        ActionChip(
          avatar: const Icon(Icons.flip, size: 16),
          label: const Text('Reflection'),
          onPressed: _sel.length == 1 ? () { widget.onReflect(_sel.first); _pop(); } : null,
        ),
      ],
    );
  }
}
