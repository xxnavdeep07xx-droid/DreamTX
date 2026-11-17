import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import '../theme.dart';
import '../widgets/content_editor.dart';
import '../widgets/design_sheets.dart';
import '../widgets/shape_canvas.dart';
import '../widgets/slide_canvas.dart';
import 'pair_sheet.dart';

/// Screen 2 — Editor. Canvas + filmstrip + full manual toolkit: edit every
/// content field, add / duplicate / reorder / delete slides, undo & redo,
/// pick the design family, rename the deck, export. And the AI can still
/// drive the same ops over MCP.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.deck});

  final Map<String, dynamic> deck;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late Map<String, dynamic> _deck;
  int _index = 0;
  Map<String, dynamic>? _layout;
  List<String> _warnings = [];
  bool _busy = false;
  final List<Map<String, dynamic>> _undo = [];
  final List<Map<String, dynamic>> _redo = [];

  // ---- design (vector overlay) state -------------------------------------------
  bool _designMode = false;
  bool _scribbleMode = false;
  String? _selectedObjectId;
  List<Map<String, dynamic>> _objectPresets = const [];
  int _oidSeq = 0;

  @override
  void initState() {
    super.initState();
    _deck = Map<String, dynamic>.from(widget.deck);
    final meta = Bridge.command({'op': 'meta'});
    _objectPresets = ((meta['object_presets'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    _refreshLayout();
  }

  List<Map<String, dynamic>> get _slides =>
      (_deck['slides'] as List? ?? []).whereType<Map<String, dynamic>>().toList();

  // ---- deck state + undo/redo ------------------------------------------------

  Map<String, dynamic> _copy() => jsonDecode(jsonEncode(_deck)) as Map<String, dynamic>;

  /// Apply a new deck produced by the engine (or a local edit): push undo,
  /// wipe redo, persist, refresh.
  void _mutate(Map? newDeck) {
    if (newDeck == null) return;
    _undo.add(_copy());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    _setDeck(newDeck);
  }

  void _setDeck(Map newDeck) {
    _deck = Map<String, dynamic>.from(newDeck);
    DeckStore.open().then((s) => s.save(_deck));
    _refreshLayout();
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_copy());
      _deck = _undo.removeLast();
      DeckStore.open().then((s) => s.save(_deck));
      _refreshLayout();
    });
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_copy());
      _deck = _redo.removeLast();
      DeckStore.open().then((s) => s.save(_deck));
      _refreshLayout();
    });
  }

  void _refreshLayout() {
    if (!mounted) return;
    if (_slides.isEmpty) {
      setState(() {
        _layout = null;
        _warnings = [];
      });
      return;
    }
    _index = _index.clamp(0, _slides.length - 1);
    final r = Bridge.command({'op': 'get_layout', 'deck': _deck, 'slide_index': _index});
    setState(() {
      if (r['ok'] == true && r['layout'] is Map) {
        _layout = (r['layout'] as Map).cast<String, dynamic>();
        _warnings = ((r['layout']['warnings'] as List?) ?? []).map((e) => e.toString()).toList();
      } else {
        _layout = null;
        _warnings = ['layout error: ${r['error']}'];
      }
    });
  }

  // ---- vector overlay layer (studio tools) -------------------------------------

  String? get _slideId => _slides.isEmpty ? null : _slides[_index]['id'] as String?;

  List<Map<String, dynamic>> get _objects {
    if (_slides.isEmpty) return const [];
    return ((_slides[_index]['objects'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Map<String, dynamic>? get _selectedObject {
    final id = _selectedObjectId;
    if (id == null) return null;
    for (final o in _objects) {
      if (o['id'] == id) return o;
    }
    return null;
  }

  String _newObjectId() {
    _oidSeq += 1;
    return 'o${DateTime.now().millisecondsSinceEpoch}_$_oidSeq';
  }

  void _toggleDesignMode() {
    setState(() {
      _designMode = !_designMode;
      if (!_designMode) {
        _scribbleMode = false;
        _selectedObjectId = null;
      }
    });
  }

  void _showLibrary() {
    if (_slides.isEmpty) return;
    showShapeLibrary(context, presets: _objectPresets, onPick: _addObject);
  }

  void _addObject(String preset) {
    final slideId = _slideId;
    if (slideId == null) return;
    final open = preset == 'line' || preset == 'wave' || preset == 'zigzag';
    var w = 240.0;
    var h = 140.0;
    if (open) {
      w = 320.0;
      h = preset == 'line' ? 0.0 : (preset == 'wave' ? 80.0 : 60.0);
    }
    final n = _objects.length;
    final shape = <String, dynamic>{
      'id': _newObjectId(),
      'preset': preset,
      'x': (1280.0 - w) / 2 + (n % 5) * 24.0,
      'y': (720.0 - h) / 2 + (n % 5) * 16.0,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': 1.0,
      'locked': false,
      'fill': open ? {'type': 'none'} : {'type': 'solid', 'color': 'FFFFFF'},
      'stroke': open
          ? {'color': 'D03028', 'width': 3.0, 'dash': 'solid', 'start_arrow': 'none', 'end_arrow': 'none'}
          : {'color': '17181A', 'width': 1.5, 'dash': 'solid', 'start_arrow': 'none', 'end_arrow': 'none'},
      'effects': {},
      'closed': true,
    };
    final r = Bridge.command({'op': 'add_object', 'deck': _deck, 'slide_id': slideId, 'shape': shape});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      setState(() => _selectedObjectId = shape['id'] as String?);
    } else {
      _toast('Could not add shape: ${r['error']}');
    }
  }

  void _onScribbleDone(List<Offset> pts) {
    final slideId = _slideId;
    if (slideId == null || pts.length < 2) return;
    var minx = pts.first.dx;
    var miny = pts.first.dy;
    var maxx = minx;
    var maxy = miny;
    for (final p in pts) {
      minx = math.min(minx, p.dx);
      miny = math.min(miny, p.dy);
      maxx = math.max(maxx, p.dx);
      maxy = math.max(maxy, p.dy);
    }
    final w = math.max(maxx - minx, 1.0);
    final h = math.max(maxy - miny, 1.0);
    final norm = [
      for (final p in pts)
        {'x': ((p.dx - minx) / w).clamp(0.0, 1.0).toDouble(), 'y': ((p.dy - miny) / h).clamp(0.0, 1.0).toDouble()},
    ];
    final shape = <String, dynamic>{
      'id': _newObjectId(),
      'preset': 'path',
      'x': minx,
      'y': miny,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': 1.0,
      'locked': false,
      'fill': {'type': 'none'},
      'stroke': {'color': 'D03028', 'width': 3.0, 'dash': 'solid', 'start_arrow': 'none', 'end_arrow': 'none'},
      'effects': {},
      'points': norm,
      'closed': false,
    };
    final r = Bridge.command({'op': 'add_object', 'deck': _deck, 'slide_id': slideId, 'shape': shape});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      setState(() => _selectedObjectId = shape['id'] as String?);
    }
  }

  void _objectGestureStart() {
    _undo.add(_copy());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void _liveObject(Map obj) {
    setState(() => _replaceObjectLocal(obj));
  }

  void _replaceObjectLocal(Map obj) {
    final slideId = _slideId;
    if (slideId == null) return;
    for (final s in (_deck['slides'] as List? ?? const []).whereType<Map>()) {
      if (s['id'] != slideId) continue;
      final objs = s['objects'] as List?;
      if (objs == null) return;
      for (var i = 0; i < objs.length; i++) {
        if (objs[i] is Map && objs[i]['id'] == obj['id']) {
          objs[i] = obj;
          return;
        }
      }
    }
  }

  /// Gesture commit: undo was already pushed at gesture start.
  void _commitObject(Map obj) {
    final slideId = _slideId;
    if (slideId == null) return;
    final r = Bridge.command({'op': 'update_object', 'deck': _deck, 'slide_id': slideId, 'object_id': obj['id'], 'shape': obj});
    if (r['ok'] == true && r['deck'] is Map) {
      _setDeck(r['deck'] as Map);
    } else {
      _toast('Could not save: ${r['error']}');
    }
  }

  /// Style change from the inspector: full mutate (own undo step).
  void _styleChanged(Map obj) {
    final slideId = _slideId;
    if (slideId == null) return;
    final r = Bridge.command({'op': 'update_object', 'deck': _deck, 'slide_id': slideId, 'object_id': obj['id'], 'shape': obj});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
    } else {
      _toast('Could not apply style: ${r['error']}');
    }
  }

  void _objOp(Map<String, dynamic> req) {
    final r = Bridge.command(req);
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
    } else {
      _toast('${r['error'] ?? 'operation failed'}');
    }
  }

  void _groupObjects(List<String> ids) => _objOp({'op': 'group_objects', 'deck': _deck, 'slide_id': _slideId, 'ids': ids});

  void _ungroupObjects(List<String> ids) => _objOp({'op': 'ungroup_objects', 'deck': _deck, 'slide_id': _slideId, 'ids': ids});

  void _alignObjects(String mode, List<String> ids) => _objOp({'op': 'align_objects', 'deck': _deck, 'slide_id': _slideId, 'ids': ids, 'mode': mode});

  void _booleanObjects(String mode, List<String> ids) {
    if (ids.length != 2) return;
    _objOp({'op': 'boolean_op', 'deck': _deck, 'slide_id': _slideId, 'a': ids[0], 'b': ids[1], 'mode': mode});
  }

  void _saveComponent(List<String> ids, String name) =>
      _objOp({'op': 'save_component', 'deck': _deck, 'slide_id': _slideId, 'ids': ids, 'name': name});

  void _placeComponent(String componentId) =>
      _objOp({'op': 'place_component', 'deck': _deck, 'slide_id': _slideId, 'component_id': componentId});

  void _syncComponent(String objectId) {
    if (objectId.isEmpty) return;
    _objOp({'op': 'update_component', 'deck': _deck, 'slide_id': _slideId, 'object_id': objectId});
  }

  void _reorderObject(String id, int dir) {
    final objs = _objects;
    final idx = objs.indexWhere((o) => o['id'] == id);
    if (idx < 0) return;
    final to = (idx + dir).clamp(0, objs.length - 1);
    _objOp({'op': 'move_object_z', 'deck': _deck, 'slide_id': _slideId, 'object_id': id, 'to_index': to});
  }

  void _toggleObjectLock(String id) {
    for (final o in _objects) {
      if (o['id'] == id) {
        final updated = Map<String, dynamic>.from(o);
        updated['locked'] = !(updated['locked'] == true);
        _styleChanged(updated);
        return;
      }
    }
  }

  void _deleteObject(String id) =>
      _objOp({'op': 'delete_object', 'deck': _deck, 'slide_id': _slideId, 'object_id': id});

  void _editStyleOf(String id) {
    for (final o in _objects) {
      if (o['id'] == id) {
        showInspector(context, object: o, onChange: _styleChanged);
        return;
      }
    }
  }

  void _duplicateObject(String id) {
    final objs = _objects;
    final idx = objs.indexWhere((o) => o['id'] == id);
    if (idx < 0) return;
    final copy = Map<String, dynamic>.from(objs[idx]);
    final newId = _newObjectId();
    copy['id'] = newId;
    copy['x'] = ((objs[idx]['x'] as num?)?.toDouble() ?? 0) + 24;
    copy['y'] = ((objs[idx]['y'] as num?)?.toDouble() ?? 0) + 24;
    final r = Bridge.command({'op': 'add_object', 'deck': _deck, 'slide_id': _slideId, 'shape': copy});
    if (r['ok'] != true || r['deck'] is! Map) {
      _toast('Could not duplicate: ${r['error']}');
      return;
    }
    final r2 = Bridge.command({
      'op': 'move_object_z',
      'deck': r['deck'],
      'slide_id': _slideId,
      'object_id': newId,
      'to_index': (idx + 1).clamp(0, objs.length),
    });
    if (r2['ok'] == true && r2['deck'] is Map) {
      _mutate(r2['deck'] as Map);
    } else {
      _mutate(r['deck'] as Map);
    }
    setState(() => _selectedObjectId = newId);
  }

  void _reflectObject(String id) {
    for (final o in _objects) {
      if (o['id'] != id) continue;
      final copy = Map<String, dynamic>.from(o);
      final y = (o['y'] as num?)?.toDouble() ?? 0;
      final h = (o['h'] as num?)?.toDouble() ?? 0;
      final op = (o['opacity'] as num?)?.toDouble() ?? 1;
      final newId = _newObjectId();
      copy['id'] = newId;
      copy['y'] = y + h + 10 + h;
      copy['opacity'] = (op * 0.35).clamp(0.05, 0.6);
      copy['effects'] = {};
      final r = Bridge.command({'op': 'add_object', 'deck': _deck, 'slide_id': _slideId, 'shape': copy});
      if (r['ok'] != true || r['deck'] is! Map) {
        _toast('Could not add reflection: ${r['error']}');
        return;
      }
      final r2 = Bridge.command({'op': 'group_objects', 'deck': r['deck'], 'slide_id': _slideId, 'ids': [id, newId]});
      if (r2['ok'] == true && r2['deck'] is Map) {
        _mutate(r2['deck'] as Map);
      } else {
        _mutate(r['deck'] as Map);
      }
      return;
    }
  }

  void _showLayers() {
    if (_slides.isEmpty) return;
    showLayersSheet(
      context,
      objects: _objects,
      presets: _objectPresets,
      deck: _deck,
      onGroup: _groupObjects,
      onUngroup: _ungroupObjects,
      onAlign: _alignObjects,
      onBoolean: _booleanObjects,
      onSaveComponent: _saveComponent,
      onPlaceComponent: _placeComponent,
      onSyncComponent: _syncComponent,
      onReorder: _reorderObject,
      onToggleLock: _toggleObjectLock,
      onEditStyle: _editStyleOf,
      onDelete: _deleteObject,
      onDuplicate: _duplicateObject,
      onReflect: _reflectObject,
    );
  }

  // ---- quick single-field edit (tap text on the canvas) ----------------------

  Future<void> _editText(String key) async {
    final slide = _slides[_index];
    final content = Map<String, dynamic>.from(slide['content'] ?? <String, dynamic>{});
    final current = _resolveKey(content, key)?.toString() ?? '';
    final text = await dreamInputDialog(
      context,
      title: 'Edit — ${key.replaceAll('.', ' ')}',
      initial: current,
      confirmLabel: 'Save',
      multiline: true,
    );
    if (text == null) return;
    final updated = _applyKey(content, key, text);
    _updateSlide(slide, slide['archetype'].toString(), updated);
  }

  /// Resolve a dotted path like `stats.0.value` inside the content map.
  dynamic _resolveKey(Map<String, dynamic> map, String path) {
    dynamic cur = map;
    for (final part in path.split('.')) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else if (cur is List) {
        final i = int.tryParse(part);
        if (i != null && i >= 0 && i < cur.length) {
          cur = cur[i];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return cur;
  }

  /// Set a dotted path inside a copy of the content map, returning the copy.
  Map<String, dynamic> _applyKey(Map<String, dynamic> content, String key, String value) {
    final updated = Map<String, dynamic>.from(content);
    final parts = key.split('.');
    dynamic cur = updated;
    for (var i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (cur is Map) {
        final next = cur[part];
        if (next is! Map && next is! List) {
          final nextIsList = int.tryParse(parts[i + 1]) != null;
          cur[part] = nextIsList ? <dynamic>[] : <String, dynamic>{};
        }
        cur = cur[part];
      } else if (cur is List) {
        final idx = int.tryParse(part);
        if (idx != null && idx >= 0 && idx < cur.length) {
          cur = cur[idx];
        }
      }
    }
    if (cur is Map) {
      cur[parts.last] = value;
    } else if (cur is List) {
      final idx = int.tryParse(parts.last);
      if (idx != null && idx >= 0 && idx < cur.length) cur[idx] = value;
    }
    return updated;
  }

  // ---- slide ops --------------------------------------------------------------

  void _updateSlide(Map slide, String archetype, Map content) {
    final r = Bridge.command({
      'op': 'update_slide',
      'deck': _deck,
      'slide_id': slide['id'],
      'archetype': archetype,
      'content': content,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
    } else {
      _toast('Could not save: ${r['error']}');
    }
  }

  Future<void> _addSlide() async {
    final meta = Bridge.command({'op': 'meta'});
    final r = Bridge.command({'op': 'pacing', 'deck': _deck});
    final suggested = (r['next_suggested'] ?? '').toString();
    final archetypes = (meta['archetypes'] as List? ?? []).map((e) => e.toString()).toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add slide${suggested.isEmpty ? '' : ' — suggested next: $suggested'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...archetypes.map((a) => ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: Text(a),
                  onTap: () => Navigator.pop(context, a),
                )),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final add = Bridge.command({'op': 'add_slide', 'deck': _deck, 'archetype': _archetypeOf(choice)});
    if (add['ok'] == true && add['deck'] is Map) {
      _mutate(add['deck'] as Map);
      setState(() => _index = _slides.length - 1);
      _refreshLayout();
    } else {
      _toast('Could not add: ${add['error']}');
    }
  }

  String _archetypeOf(String label) {
    const map = {
      'Cover': 'cover',
      'Agenda': 'agenda',
      'Section break': 'section',
      'Big statement': 'statement',
      'Stat wall': 'stat_wall',
      'Split text + visual': 'split',
      'Comparison': 'comparison',
      'Chart hero': 'chart_hero',
      'Closing': 'closing',
    };
    return map[label] ?? 'statement';
  }

  Future<void> _editContent() async {
    if (_slides.isEmpty) return;
    final slide = _slides[_index];
    final result = await showContentEditor(
      context,
      slide: slide,
      deckTitle: (_deck['title'] ?? 'Deck').toString(),
    );
    if (result == null) return;
    _updateSlide(slide, result.archetype, result.content);
  }

  void _duplicateAt(int i) {
    if (i < 0 || i >= _slides.length) return;
    final slide = _slides[i];
    final add = Bridge.command({
      'op': 'add_slide',
      'deck': _deck,
      'archetype': slide['archetype'],
      'content': slide['content'],
    });
    if (add['ok'] != true || add['deck'] is! Map) {
      _toast('Could not duplicate: ${add['error']}');
      return;
    }
    var deck = add['deck'] as Map;
    // add_slide appends; move the copy right behind the original.
    if (_slides.length > 1) {
      final newId = (((deck['slides'] as List?) ?? []).whereType<Map>().last)['id'];
      final move = Bridge.command({'op': 'move_slide', 'deck': deck, 'slide_id': newId, 'to_index': i + 1});
      if (move['ok'] == true && move['deck'] is Map) deck = move['deck'] as Map;
    }
    _mutate(deck);
    setState(() => _index = (i + 1).clamp(0, _slides.length - 1));
    _refreshLayout();
  }

  void _moveAt(int i, int delta) {
    if (_slides.isEmpty) return;
    final slide = _slides[i.clamp(0, _slides.length - 1)];
    final target = i + delta;
    if (target < 0 || target >= _slides.length) return;
    final r = Bridge.command({
      'op': 'move_slide',
      'deck': _deck,
      'slide_id': slide['id'],
      'to_index': target,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      setState(() => _index = target);
      _refreshLayout();
    }
  }

  void _deleteAt(int i) {
    if (i < 0 || i >= _slides.length) return;
    final slide = _slides[i];
    final r = Bridge.command({'op': 'delete_slide', 'deck': _deck, 'slide_id': slide['id']});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _refreshLayout(); // clamps _index
    } else {
      _toast('Could not delete: ${r['error']}');
    }
  }

  /// Long-press menu for a filmstrip thumbnail.
  Future<void> _slideActions(int i) async {
    if (i < 0 || i >= _slides.length) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Slide ${i + 1} of ${_slides.length}', style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit content'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(context, 'dup'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Move left'),
              enabled: i > 0,
              onTap: () => Navigator.pop(context, 'left'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Move right'),
              enabled: i < _slides.length - 1,
              onTap: () => Navigator.pop(context, 'right'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'del'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'edit':
        setState(() => _index = i);
        _editContent();
      case 'dup':
        _duplicateAt(i);
      case 'left':
        _moveAt(i, -1);
      case 'right':
        _moveAt(i, 1);
      case 'del':
        _deleteAt(i);
    }
  }

  // ---- deck-level ops ----------------------------------------------------------

  Future<void> _renameDeck() async {
    final title = await dreamInputDialog(
      context,
      title: 'Rename deck',
      initial: (_deck['title'] ?? '').toString(),
      confirmLabel: 'Rename',
    );
    if (title == null || title.trim().isEmpty) return;
    final updated = _copy();
    updated['title'] = title.trim();
    _mutate(updated);
  }

  /// Design family picker — explicit choice instead of blind cycling.
  Future<void> _designSheet() async {
    final current = ((_deck['dna'] ?? const {})['family'] ?? '').toString();
    const families = [('swiss_editorial', 'Swiss editorial'), ('cinematic', 'Cinematic'), ('magazine_serif', 'Magazine serif')];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Deck design'),
            ),
            for (final (id, label) in families)
              ListTile(
                leading: Icon(
                  id == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: id == current ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(label),
                onTap: () => Navigator.pop(context, id),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: const Text('New variant of this design'),
              subtitle: const Text('Another curated look inside the family'),
              onTap: () => Navigator.pop(context, 'next_variant'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || choice == current) return;
    final r = Bridge.command({'op': 'apply_dna', 'deck': _deck, 'change': choice});
    if (r['ok'] == true && r['deck'] is Map) _mutate(r['deck'] as Map);
  }

  // ---- export -------------------------------------------------------------------

  Future<void> _export(String op) async {
    setState(() => _busy = true);
    try {
      final r = Bridge.command({'op': op, 'deck': _deck});
      if (r['ok'] != true || r['base64'] is! String) {
        _toast('Export failed: ${r['error'] ?? 'engine unavailable'}');
        return;
      }
      final bytes = base64Decode(r['base64'] as String);
      final ext = op == 'export_pptx' ? 'pptx' : 'pdf';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${(_deck['title'] ?? 'deck').toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$ext');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: _deck['title'].toString()),
      );
    } catch (e) {
      _toast('Export error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = (_deck['title'] ?? 'Deck').toString();
    final family = ((_deck['dna'] ?? const {})['family'] ?? '').toString().replaceAll('_', ' ');
    final n = _slides.length;
    return Scaffold(
      appBar: AppBar(
        title: Tooltip(
          message: '$family — tap to rename deck',
          child: InkWell(
            onTap: _renameDeck,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(title, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(color: kHairline),
        ),
        actions: [
          IconButton(
            tooltip: _designMode ? 'Leave design mode' : 'Design mode — shapes, drawing, layers',
            icon: Icon(_designMode ? Icons.category : Icons.category_outlined),
            onPressed: _toggleDesignMode,
          ),
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: _undo.isEmpty ? null : _undoStep,
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
            onPressed: _redo.isEmpty ? null : _redoStep,
          ),
          IconButton(tooltip: 'Deck design', icon: const Icon(Icons.palette_outlined), onPressed: _designSheet),
          IconButton(tooltip: 'Pair with your AI', icon: const Icon(Icons.link), onPressed: _showPairSheet),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: _export,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export_pptx', child: Text('Export .pptx')),
              PopupMenuItem(value: 'export_pdf', child: Text('Export .pdf')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ---- canvas ----------------------------------------------------------
          Expanded(
            child: _layout == null
                ? const Center(child: Text('No slide here yet — add one below.'))
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Stack(
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    SlideCanvas(layout: _layout!, onTextTap: _designMode ? null : _editText),
                                    ShapesLayer(
                                      objects: _objects,
                                      selectedId: _selectedObjectId,
                                      interactive: _designMode,
                                      scribbleMode: _scribbleMode,
                                      onSelect: (id) => setState(() => _selectedObjectId = id),
                                      onLive: _liveObject,
                                      onCommit: _commitObject,
                                      onGestureStart: _objectGestureStart,
                                      onScribble: _onScribbleDone,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_warnings.isNotEmpty)
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: Chip(
                              avatar: const Icon(Icons.warning_amber_outlined, size: 18),
                              label: Text(_warnings.first, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          // ---- design dock (floating, design mode only) ------------------------
          if (_designMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: kElevated,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: kHairline),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(tooltip: 'Add shape', icon: const Icon(Icons.category_outlined), onPressed: _showLibrary),
                    IconButton(
                      tooltip: 'Freehand draw',
                      icon: Icon(Icons.gesture, color: _scribbleMode ? kText : kText2),
                      onPressed: () => setState(() => _scribbleMode = !_scribbleMode),
                    ),
                    IconButton(
                      tooltip: 'Style the selected object',
                      icon: const Icon(Icons.format_paint_outlined),
                      onPressed: _selectedObjectId == null
                          ? null
                          : () {
                              final obj = _selectedObject;
                              if (obj != null) showInspector(context, object: obj, onChange: _styleChanged);
                            },
                    ),
                    IconButton(tooltip: 'Layers, groups, components', icon: const Icon(Icons.layers_outlined), onPressed: _showLayers),
                    Expanded(
                      child: Center(
                        child: Text(
                          _scribbleMode ? 'draw on the slide' : 'drag to move · corners resize · top circle rotates',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: kText3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // ---- slide toolbar band ------------------------------------------------
          Container(
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(top: BorderSide(color: kHairline)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            height: 48,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Edit slide content',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: n == 0 ? null : _editContent,
                ),
                IconButton(
                  tooltip: 'Add slide',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _addSlide,
                ),
                IconButton(
                  tooltip: 'Duplicate slide',
                  icon: const Icon(Icons.content_copy),
                  onPressed: n == 0 ? null : () => _duplicateAt(_index),
                ),
                IconButton(
                  tooltip: 'Move slide left',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _index <= 0 ? null : () => _moveAt(_index, -1),
                ),
                IconButton(
                  tooltip: 'Move slide right',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _index >= n - 1 ? null : () => _moveAt(_index, 1),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      n == 0 ? 'no slides' : 'Slide ${_index + 1} / $n',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kText2),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete slide',
                  icon: const Icon(Icons.delete_outline, color: kAccent),
                  onPressed: n == 0 ? null : () => _deleteAt(_index),
                ),
              ],
            ),
          ),
          // ---- filmstrip (stories-style, gradient ring on the live slide) ----
          SizedBox(
            height: 104,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _addSlide,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: kInkGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: n,
                    itemBuilder: (context, i) {
                      final selected = i == _index;
                      final label = _slideTitle(_slides[i]);
                      return Padding(
                        padding: const EdgeInsets.all(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              _index = i;
                              _refreshLayout();
                            });
                          },
                          onLongPress: () => _slideActions(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 124,
                            padding: EdgeInsets.all(selected ? 2.5 : 1),
                            decoration: BoxDecoration(
                              gradient: selected ? kInkGradient : null,
                              color: selected ? null : kHairline,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    '${i + 1}. $label',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF17181A), fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _slideTitle(Map slide) {
    final content = slide['content'];
    if (content is Map) {
      for (final k in ['title', 'text', 'kicker']) {
        final v = content[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return (slide['archetype'] ?? 'slide').toString();
  }

  void _showPairSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PairSheet(deck: _deck),
    );
  }
}
