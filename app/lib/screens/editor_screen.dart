import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import '../widgets/content_editor.dart';
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

  @override
  void initState() {
    super.initState();
    _deck = Map<String, dynamic>.from(widget.deck);
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

  // ---- quick single-field edit (tap text on the canvas) ----------------------

  Future<void> _editText(String key) async {
    final slide = _slides[_index];
    final content = Map<String, dynamic>.from(slide['content'] ?? <String, dynamic>{});
    final current = _resolveKey(content, key)?.toString() ?? '';
    final controller = TextEditingController(text: current);
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit — ${key.replaceAll('.', ' ')}'),
        content: TextField(controller: controller, autofocus: true, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (changed != true) return;
    final updated = _applyKey(content, key, controller.text);
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
    final controller = TextEditingController(text: (_deck['title'] ?? '').toString());
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename deck'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Rename')),
        ],
      ),
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
          preferredSize: Size.fromHeight(2),
          child: ColoredBox(color: Color(0xFF17181A)),
        ),
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
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SlideCanvas(layout: _layout!, onTextTap: _editText),
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
          // ---- slide toolbar ----------------------------------------------------
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x1F17181A))),
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
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B70)),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete slide',
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  onPressed: n == 0 ? null : () => _deleteAt(_index),
                ),
              ],
            ),
          ),
          // ---- filmstrip ---------------------------------------------------------
          SizedBox(
            height: 108,
            child: Row(
              children: [
                IconButton(onPressed: _addSlide, icon: const Icon(Icons.add_circle_outline), tooltip: 'Add slide'),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: n,
                    itemBuilder: (context, i) {
                      final selected = i == _index;
                      final label = _slideTitle(_slides[i]);
                      return Padding(
                        padding: const EdgeInsets.all(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              _index = i;
                              _refreshLayout();
                            });
                          },
                          onLongPress: () => _slideActions(i),
                          child: Container(
                            width: 132,
                            decoration: BoxDecoration(
                              border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.black12, width: selected ? 2 : 1),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.black.withValues(alpha: 0.02),
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '${i + 1}. $label',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
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
