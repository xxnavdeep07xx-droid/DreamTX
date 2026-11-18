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

/// Screen 2 — Editor. Canvas + filmstrip + a PowerPoint-style bottom ribbon —
/// AI · Files · Home · Insert · Draw · Design · Transitions · Animations ·
/// Slide show · Review · View · Help — horizontally scrollable, each tab
/// opening a contextual tool row under the canvas. The top bar keeps
/// deck-level controls: rename (tap the title), undo/redo, comments, share,
/// and the More menu with Editing / Viewing / Presenting modes and Export.
/// **+** adds a blank slide instantly (the curated layout list is a
/// deliberate choice from the Home row or a long-press on **+**). And the
/// AI can still drive the same ops over MCP.
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

  // ---- PowerPoint-style bottom ribbon ------------------------------------------
  /// The active ribbon tab; its contextual action row renders between
  /// the canvas and the filmstrip. Null = collapsed (canvas gets the space).
  _NavTab? _navTab;

  /// Editor chrome mode (More menu): editing = the full toolkit, viewing =
  /// a chrome-free read-only pass over the deck.
  _Mode _mode = _Mode.editing;

  /// Drives the horizontally scrollable ribbon bar; the freshly-lit tab
  /// gets centered so it never hides off-screen.
  final ScrollController _navScroll = ScrollController();

  /// In-memory review comments (top-bar Comments / Review tab).
  final List<Map<String, String>> _comments = [];
  final TextEditingController _commentField = TextEditingController();

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

  @override
  void dispose() {
    _commentField.dispose();
    _navScroll.dispose();
    super.dispose();
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

  /// Ribbon state machine: one contextual row at a time, tapped again to
  /// collapse. Tabs that work on the canvas overlay (Insert, Draw) double
  /// as design mode, so leaving them clears scribble/selection.
  void _setNavTab(_NavTab? tab) {
    setState(() {
      _navTab = tab;
      _designMode = tab == _NavTab.insert || tab == _NavTab.draw;
      if (!_designMode) {
        _scribbleMode = false;
        _selectedObjectId = null;
      }
    });
    if (tab != null) {
      // Keep the freshly-lit tab centered in the scrollable bar.
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerNavTab(tab));
    }
  }

  /// Centers the active ribbon tab in the bar's viewport.
  void _centerNavTab(_NavTab tab) {
    if (!_navScroll.hasClients) return;
    final i = _NavTab.values.indexOf(tab);
    final view = _navScroll.position.viewportDimension;
    final maxExtent = _navScroll.position.maxScrollExtent;
    final target =
        (i * _navItemWidth + _navItemWidth / 2 - view / 2).clamp(0.0, maxExtent).toDouble();
    _navScroll.animateTo(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
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

  /// The **+** button: add a blank slide instantly — no picker, no template.
  /// The user gets an empty canvas (just the deck's background) to draw on
  /// or fill later; the curated layout list lives in the Slides tool row.
  void _addSlide() {
    final r = Bridge.command({'op': 'add_slide', 'deck': _deck, 'archetype': 'blank'});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      setState(() => _index = _slides.length - 1);
      _refreshLayout();
    } else {
      _toast('Could not add: ${r['error']}');
    }
  }

  /// The curated template list (Cover, Agenda, …) — a deliberate choice
  /// from the Slides tool row or a long-press on **+** when you DO want a
  /// pre-styled layout.
  Future<void> _addLayoutSlide() async {
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
      'Blank': 'blank',
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

  /// Design-family change (family id or 'next_variant') — driven by the
  /// Theme contextual row.
  void _applyDesign(String choice) {
    final current = ((_deck['dna'] ?? const {})['family'] ?? '').toString();
    if (choice == current) return;
    final r = Bridge.command({'op': 'apply_dna', 'deck': _deck, 'change': choice});
    if (r['ok'] == true && r['deck'] is Map) _mutate(r['deck'] as Map);
  }

  // ---- export -------------------------------------------------------------------

  Future<void> _export(String op, {String verb = 'Export'}) async {
    setState(() => _busy = true);
    try {
      final r = Bridge.command({'op': op, 'deck': _deck});
      if (r['ok'] != true || r['base64'] is! String) {
        _toast('$verb failed: ${r['error'] ?? 'engine unavailable'}');
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
      _toast('$verb error: $e');
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
    // KeyboardStableMetrics: all text entry on this screen happens in
    // bottom-sheet routes (content editor, inspector, pair sheet) that sit
    // OUTSIDE this Scaffold and track the keyboard themselves — so the
    // canvas, tool row and filmstrip below keep their steady layout while the
    // keyboard is open, in both inset-delivery and window-resize mode.
    // (The ribbon bar and its contextual tool row sit inside this
    // subtree too, so they stay put as well.)
    return KeyboardStableMetrics(
      child: Scaffold(
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
        // The toolkit lives in the bottom ribbon — the top bar keeps
        // deck-level controls: rename (tap the title), undo/redo, comments,
        // share (a .pptx copy straight to the system share sheet), and the
        // More menu (modes + export with a format choice).
        actions: [
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
          IconButton(
            tooltip: 'Comments',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: _showComments,
          ),
          IconButton(
            tooltip: 'Share',
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                : const Icon(Icons.share),
            onPressed: _busy ? null : _showShareSheet,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !_busy,
            icon: const Icon(Icons.more_vert),
            onSelected: _onModeMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'editing', child: Text('Editing Mode')),
              PopupMenuItem(value: 'viewing', child: Text('Viewing Mode')),
              PopupMenuItem(value: 'presenting', child: Text('Presenting Mode')),
              // The modes are chrome states; Export is an action from a
              // different family — a real divider line keeps them apart.
              PopupMenuDivider(height: 12),
              PopupMenuItem(value: 'export', child: Text('Export')),
            ],
          ),
          const SizedBox(width: 4),
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
                                    SlideCanvas(layout: _layout!, onTextTap: _designMode || _mode == _Mode.viewing ? null : _editText),
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
                        // CapCut-style floating position chip (like the
                        // timeline counter) — always-visible slide index.
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kHairline),
                            ),
                            child: Text(
                              n == 0
                                  ? 'no slides'
                                  : _mode == _Mode.viewing
                                      ? 'viewing · ${_index + 1} / $n'
                                      : 'Slide ${_index + 1} / $n',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kText2),
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
                        // Viewing mode: edge chevrons replace the editing chrome.
                        if (_mode == _Mode.viewing) ...[
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: IconButton(
                                tooltip: 'Previous slide',
                                icon: const Icon(Icons.chevron_left, size: 30, color: kText2),
                                onPressed: _index > 0 ? () => _step(-1) : null,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: IconButton(
                                tooltip: 'Next slide',
                                icon: const Icon(Icons.chevron_right, size: 30, color: kText2),
                                onPressed: _index < n - 1 ? () => _step(1) : null,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          // ---- editing chrome: tool row + filmstrip + ribbon nav ---------------
          if (_mode == _Mode.editing) ...[
            if (_navTab != null)
              Container(
                decoration: const BoxDecoration(
                  color: kSurface,
                  border: Border(
                    top: BorderSide(color: kHairline),
                    bottom: BorderSide(color: kHairline),
                  ),
                ),
                height: 48,
                child: _contextualRow(),
              ),
            // ---- filmstrip (stories-style, gradient ring on the live slide) --
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
                        onLongPress: _addLayoutSlide,
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
            // ---- PowerPoint-style ribbon ----------------------------------------
            _EditorNavBar(active: _navTab, controller: _navScroll, onSelect: _onNavSelect),
          ],
        ],
      ),
      ),
    );
  }

  // ---- ribbon wiring ---------------------------------------------------------

  void _onNavSelect(_NavTab tab) {
    _setNavTab(_navTab == tab ? null : tab); // tap the active tab again to collapse
  }

  /// The contextual action row for the active ribbon tab — the selected
  /// tool swaps in a compact toolbar right under the canvas, above the
  /// filmstrip "timeline". Tabs whose toolboxes the user hasn't spec'd yet
  /// park a "coming soon" note.
  Widget _contextualRow() {
    final n = _slides.length;
    switch (_navTab) {
      case null:
        return const SizedBox.shrink();
      case _NavTab.ai:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.tonalIcon(
                onPressed: _showPairSheet,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Pair AI'),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'MCP pair · your AI drafts the deck',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.files:
        return Row(
          children: [
            IconButton(
              tooltip: 'Rename deck',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _renameDeck,
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'deck-level tools',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.home:
        return Row(
          children: [
            IconButton(
              tooltip: 'Add blank slide',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _addSlide,
            ),
            IconButton(
              tooltip: 'Add from a layout template',
              icon: const Icon(Icons.dashboard_outlined),
              onPressed: _addLayoutSlide,
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
            const Expanded(
              child: Center(
                child: Text(
                  '+ is blank · long-press a thumbnail for more',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete slide',
              icon: const Icon(Icons.delete_outline, color: kAccent),
              onPressed: n == 0 ? null : () => _deleteAt(_index),
            ),
          ],
        );
      case _NavTab.insert:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.icon(
                onPressed: n == 0 ? null : _editContent,
                icon: const Icon(Icons.text_fields, size: 18),
                label: const Text('Add text'),
              ),
            ),
            IconButton(tooltip: 'Add shape', icon: const Icon(Icons.category_outlined), onPressed: _showLibrary),
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
            const Expanded(
              child: Center(
                child: Text(
                  'tap text on the slide to edit it',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.draw:
        return Row(
          children: [
            IconButton(
              tooltip: 'Freehand draw',
              icon: Icon(Icons.gesture, color: _scribbleMode ? kText : kText2),
              onPressed: () => setState(() => _scribbleMode = !_scribbleMode),
            ),
            Expanded(
              child: Center(
                child: Text(
                  _scribbleMode ? 'draw on the slide' : 'freehand pen · drag to move · corners resize',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.design:
        final current = ((_deck['dna'] ?? const {})['family'] ?? '').toString();
        return Row(
          children: [
            const SizedBox(width: 8),
            for (final (id, label) in _designFamilies)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _DesignChip(label: label, selected: id == current, onTap: () => _applyDesign(id)),
              ),
            IconButton(
              tooltip: 'New variant of this design',
              icon: const Icon(Icons.shuffle),
              onPressed: () => _applyDesign('next_variant'),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'design DNA — whole deck',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.transitions:
        return _comingSoon('Transitions');
      case _NavTab.animations:
        return _comingSoon('Animations');
      case _NavTab.slideshow:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.icon(
                onPressed: _startPresenting,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Present'),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'fullscreen · swipe or tap the sides to advance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.review:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.tonalIcon(
                onPressed: _showComments,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Comments'),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'leave notes on this deck',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.view:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.tonalIcon(
                onPressed: () => _setMode(_Mode.viewing),
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('Reading view'),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'chrome-free pass · also in the More menu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowHint,
                ),
              ),
            ),
          ],
        );
      case _NavTab.help:
        return _comingSoon('Help');
    }
  }

  /// Placeholder row for a ribbon tab whose toolbox is still being spec'd.
  Widget _comingSoon(String what) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          child: Text(
            '$what · coming soon',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _rowHint,
          ),
        ),
      );

  String _slideTitle(Map slide) {
    final archetype = (slide['archetype'] ?? 'slide').toString();
    if (archetype == 'blank') return 'Blank';
    final content = slide['content'];
    if (content is Map) {
      for (final k in ['title', 'text', 'kicker']) {
        final v = content[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return archetype;
  }

  void _showPairSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PairSheet(deck: _deck),
    );
  }

  // ---- editor modes (More menu) ---------------------------------------------

  void _setMode(_Mode m) {
    setState(() {
      _mode = m;
      if (m == _Mode.viewing) {
        _navTab = null;
        _designMode = false;
        _scribbleMode = false;
        _selectedObjectId = null;
      }
    });
  }

  Future<void> _onModeMenu(String choice) async {
    switch (choice) {
      case 'editing':
        _setMode(_Mode.editing);
      case 'viewing':
        _setMode(_Mode.viewing);
      case 'presenting':
        await _startPresenting();
      case 'export':
        await _showExportSheet();
    }
  }

  /// Slide-step helper for the viewing chevrons.
  void _step(int delta) {
    if (_slides.isEmpty) return;
    var target = _index + delta;
    if (target < 0) target = 0;
    if (target >= _slides.length) target = _slides.length - 1;
    if (target == _index) return;
    setState(() => _index = target);
    _refreshLayout();
  }

  /// Presenting mode — a fullscreen, chrome-free pass over the deck.
  Future<void> _startPresenting() async {
    if (_slides.isEmpty) {
      _toast('Add a slide first.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PresenterScreen(deck: _deck, first: _index),
      ),
    );
  }

  // ---- comments & share -------------------------------------------------------

  Future<void> _showComments() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Comments', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (_comments.isEmpty)
                  const SizedBox(
                    height: 120,
                    child: Center(child: Text('No comments yet — leave the first one.', style: _rowHint)),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final c in _comments)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline, size: 20, color: kText2),
                            title: Text(c['text'] ?? ''),
                            subtitle: const Text('You · just now'),
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 1, color: kHairline),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentField,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Add a comment',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Post comment',
                        icon: const Icon(Icons.send, size: 20),
                        onPressed: () {
                          final text = _commentField.text.trim();
                          if (text.isEmpty) return;
                          setState(() => _comments.add({'text': text}));
                          _commentField.clear();
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The top-bar Share button — "send a copy": no format dialog, just export
  /// the deck as .pptx and hand it straight to the system share sheet.
  /// Picking a format (pptx/pdf) is the Export menu's job; Share is the
  /// fast lane out of the app.
  Future<void> _showShareSheet() => _export('export_pptx', verb: 'Share');

  Future<void> _showExportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Export deck', style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () { Navigator.pop(context); _export('export_pptx'); },
                  icon: const Icon(Icons.description, size: 18),
                  label: const Text('PowerPoint (.pptx)'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () { Navigator.pop(context); _export('export_pdf'); },
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('PDF (.pdf)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- PowerPoint-style bottom ribbon --------------------------------------------

/// The ribbon tabs, in PowerPoint order. Each swaps in a contextual tool row
/// under the canvas; the remaining tabs get their toolboxes spec'd next.
enum _NavTab {
  ai,
  files,
  home,
  insert,
  draw,
  design,
  transitions,
  animations,
  slideshow,
  review,
  view,
  help,
}

/// Editor chrome mode, driven by the More (⋮) menu on the top bar.
enum _Mode { editing, viewing }

const List<(String, String)> _designFamilies = [
  ('swiss_editorial', 'Swiss editorial'),
  ('cinematic', 'Cinematic'),
  ('magazine_serif', 'Magazine serif'),
];

const TextStyle _rowHint = TextStyle(fontSize: 10.5, color: kText3);

/// One ribbon tab's footprint — twelve at this width overflow any phone, so
/// the bar scrolls and centers the active tab.
const double _navItemWidth = 66;

/// The editor's primary navigation — a PowerPoint-style ribbon, horizontally
/// scrollable so all twelve tabs sit one thumb away: AI · Files · Home ·
/// Insert · Draw · Design · Transitions · Animations · Slide show · Review ·
/// View · Help. Material-3 navigation proportions: 76dp tall, a 24dp icon in
/// a stadium pill when active, an 11sp label below, and edge fades so tabs
/// melt into the surface instead of clipping. The active tab's contextual
/// action row renders between the canvas and the filmstrip.
class _EditorNavBar extends StatelessWidget {
  const _EditorNavBar({required this.active, required this.controller, required this.onSelect});

  final _NavTab? active;
  final ScrollController controller;
  final void Function(_NavTab) onSelect;

  static const _icons = {
    _NavTab.ai: Icons.auto_awesome,
    _NavTab.files: Icons.folder,
    _NavTab.home: Icons.home,
    _NavTab.insert: Icons.add_box,
    _NavTab.draw: Icons.gesture,
    _NavTab.design: Icons.palette,
    _NavTab.transitions: Icons.swap_horiz,
    _NavTab.animations: Icons.animation,
    _NavTab.slideshow: Icons.slideshow,
    _NavTab.review: Icons.rate_review,
    _NavTab.view: Icons.visibility,
    _NavTab.help: Icons.help,
  };
  static const _labels = {
    _NavTab.ai: 'AI',
    _NavTab.files: 'Files',
    _NavTab.home: 'Home',
    _NavTab.insert: 'Insert',
    _NavTab.draw: 'Draw',
    _NavTab.design: 'Design',
    _NavTab.transitions: 'Transitions',
    _NavTab.animations: 'Animations',
    _NavTab.slideshow: 'Slide show',
    _NavTab.review: 'Review',
    _NavTab.view: 'View',
    _NavTab.help: 'Help',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kHairline)),
      ),
      // Material-3 NavigationBar anatomy, trimmed 80 -> 76dp because our
      // labels are single-line: a 24dp icon in a stadium pill, an 11sp label
      // under it, real vertical breathing room — and the ribbon melts into
      // the surface at both ends instead of hard-clipping half an icon.
      child: SizedBox(
        height: 76,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    for (final t in _NavTab.values)
                      SizedBox(
                        width: _navItemWidth,
                        child: _NavItemButton(
                          icon: _icons[t]!,
                          label: _labels[t]!,
                          active: active == t,
                          onTap: () => onSelect(t),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Edge fades, the PowerPoint-ribbon affordance: 12dp of surface
            // gradient over each end so tabs glide under instead of slicing.
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 12,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [kSurface, Color(0x00141417)],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 12,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [kSurface, Color(0x00141417)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemButton extends StatelessWidget {
  const _NavItemButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? kText : kText3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Material-3 active indicator: a stadium pill behind the icon
              // when the tab is lit. Two rows, not three — the pill IS the
              // active state, so no separate underline tick is needed.
              Container(
                width: 58,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? const Color(0x1FFFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                  color: active ? kText : kText3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Presenting mode — a fullscreen, chrome-free pass over the deck: each
/// slide rendered on black, swipe or tap the side zones to advance, a counter
/// at the bottom and a close button up top.
class _PresenterScreen extends StatefulWidget {
  const _PresenterScreen({required this.deck, required this.first});

  final Map<String, dynamic> deck;
  final int first;

  @override
  State<_PresenterScreen> createState() => _PresenterScreenState();
}

class _PresenterScreenState extends State<_PresenterScreen> {
  late final PageController _pages;
  late final List<Map<String, dynamic>> _slides;
  late final List<Map<String, dynamic>?> _layouts;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _slides = ((widget.deck['slides'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    _layouts = [for (var i = 0; i < _slides.length; i++) _layoutAt(i)];
    var first = widget.first;
    if (first < 0) first = 0;
    if (first >= _slides.length) first = _slides.length - 1;
    _pages = PageController(initialPage: first);
    _page = first;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _layoutAt(int i) {
    final r = Bridge.command({'op': 'get_layout', 'deck': widget.deck, 'slide_index': i});
    return r['ok'] == true && r['layout'] is Map ? (r['layout'] as Map).cast<String, dynamic>() : null;
  }

  void _go(int delta) {
    var target = _page + delta;
    if (target < 0) target = 0;
    if (target >= _slides.length) target = _slides.length - 1;
    if (target == _page) return;
    _pages.animateToPage(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: _slides.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, i) {
              final layout = _layouts[i];
              return Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: layout == null
                      ? const Center(child: Text('Unable to render this slide', style: TextStyle(color: kText2)))
                      : SlideCanvas(layout: layout),
                ),
              );
            },
          ),
          // Tap zones: right side advances, left side goes back — swipes still
          // work because tap recognizers never claim drags.
          Row(
            children: [
              Expanded(child: GestureDetector(onTap: () => _go(-1), behavior: HitTestBehavior.translucent)),
              const SizedBox(width: 90),
              Expanded(child: GestureDetector(onTap: () => _go(1), behavior: HitTestBehavior.translucent)),
            ],
          ),
          Positioned(
            top: 24,
            right: 12,
            child: IconButton(
              tooltip: 'Exit',
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: Text(
                _slides.isEmpty ? '' : '${_page + 1} / ${_slides.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact capsule chip for a design family (Design tool row).
class _DesignChip extends StatelessWidget {
  const _DesignChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? kElevated : kBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? kMagenta : kHairline, width: selected ? 1.4 : 1),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? kText : kText2,
            ),
          ),
        ),
      ),
    );
  }
}
