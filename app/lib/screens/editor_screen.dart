import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import '../widgets/slide_canvas.dart';
import 'pair_sheet.dart';

/// Screen 2 — Editor. Canvas + filmstrip; tap text to edit; swap archetype;
/// cycle DNA variant; export. Deliberately nothing more in v1.
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

  @override
  void initState() {
    super.initState();
    _deck = Map<String, dynamic>.from(widget.deck);
    _refreshLayout();
  }

  List<Map<String, dynamic>> get _slides =>
      (_deck['slides'] as List? ?? []).whereType<Map<String, dynamic>>().toList();

  void _setDeck(Map newDeck) {
    _deck = Map<String, dynamic>.from(newDeck);
    DeckStore.open().then((s) => s.save(_deck));
    _refreshLayout();
  }

  void _refreshLayout() {
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

  // ---- editing actions ------------------------------------------------------

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
    final r = Bridge.command({
      'op': 'update_slide',
      'deck': _deck,
      'slide_id': slide['id'],
      'archetype': slide['archetype'],
      'content': updated,
    });
    if (r['ok'] == true && r['deck'] is Map) _setDeck(r['deck'] as Map);
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
      _setDeck(add['deck'] as Map);
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

  Future<void> _swapArchetype() async {
    if (_slides.isEmpty) return;
    final slide = _slides[_index];
    const choices = [
      ('Cover', 'cover'),
      ('Section break', 'section'),
      ('Big statement', 'statement'),
      ('Stat wall', 'stat_wall'),
      ('Split text + visual', 'split'),
      ('Comparison', 'comparison'),
      ('Chart hero', 'chart_hero'),
      ('Closing', 'closing'),
    ];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text("Swapping replaces this slide's content with the archetype default.")),
            ...choices.map((c) => ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: Text(c.$1),
              onTap: () => Navigator.pop(context, c.$2),
            )),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final r = Bridge.command({
      'op': 'update_slide',
      'deck': _deck,
      'slide_id': slide['id'],
      'archetype': choice,
      'content': _defaultContent(choice, slide),
    });
    if (r['ok'] == true && r['deck'] is Map) _setDeck(r['deck'] as Map);
  }

  Map<String, dynamic> _defaultContent(String archetype, Map slide) {
    switch (archetype) {
      case 'cover':
        return {'kind': 'cover', 'kicker': null, 'title': (slide['title'] ?? _deck['title'] ?? 'Title').toString(), 'subtitle': null};
      case 'section':
        return {'kind': 'section', 'index': _index + 1, 'title': 'Section', 'blurb': null};
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
        return {
          'kind': 'split',
          'title': 'Title',
          'bullets': ['Point one', 'Point two'],
          'visual_label': 'visual'
        };
      case 'comparison':
        return {
          'kind': 'comparison',
          'title': null,
          'left': {'title': 'Option A', 'points': ['pro']},
          'right': {'title': 'Option B', 'points': ['pro']}
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
          'takeaway': null
        };
      case 'closing':
        return {'kind': 'closing', 'title': 'Thank you', 'subtitle': null};
      default:
        return {'kind': 'agenda', 'title': 'Agenda', 'items': ['First topic', 'Second topic']};
    }
  }

  void _cycleVariant() {
    final r = Bridge.command({'op': 'apply_dna', 'deck': _deck, 'change': 'next_variant'});
    if (r['ok'] == true && r['deck'] is Map) _setDeck(r['deck'] as Map);
  }

  void _cycleFamily() {
    final r = Bridge.command({'op': 'apply_dna', 'deck': _deck, 'change': 'next_family'});
    if (r['ok'] == true && r['deck'] is Map) _setDeck(r['deck'] as Map);
  }

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

  // ---- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = (_deck['title'] ?? 'Deck').toString();
    final family = ((_deck['dna'] ?? const {})['family'] ?? '').toString().replaceAll('_', ' ');
    return Scaffold(
      appBar: AppBar(
        title: Tooltip(message: family, child: Text(title)),
        actions: [
          IconButton(tooltip: 'New variant of this design', icon: const Icon(Icons.shuffle), onPressed: _cycleVariant),
          IconButton(tooltip: 'Switch design family', icon: const Icon(Icons.palette_outlined), onPressed: _cycleFamily),
          IconButton(tooltip: 'Swap archetype', icon: const Icon(Icons.swap_horiz), onPressed: _swapArchetype),
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
          SizedBox(
            height: 108,
            child: Row(
              children: [
                IconButton(onPressed: _addSlide, icon: const Icon(Icons.add_circle_outline), tooltip: 'Add slide'),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _slides.length,
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
