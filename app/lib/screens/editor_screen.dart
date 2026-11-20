import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/aspects.dart';
import '../core/bridge.dart';
import '../core/media_pickers.dart';
import '../core/object_content.dart';
import '../core/resources.dart';
import '../core/store.dart';
import '../theme.dart';
import '../widgets/content_editor.dart';
import '../widgets/design_sheets.dart';
import '../widgets/object_content_layer.dart';
import '../widgets/rich_doc.dart';
import '../widgets/shape_canvas.dart';
import '../widgets/slide_canvas.dart';
import '../widgets/text_edit_field.dart';
import '../widgets/typing_toolbar.dart';
import 'files_drawer.dart';
import 'insert_sheet.dart';
import 'pair_sheet.dart';

/// Screen 2 — Editor. Canvas + filmstrip + a PowerPoint-style bottom ribbon —
/// AI · Files · Insert · Draw · Design · Transitions · Animations ·
/// Slide show · Review · View · Help — horizontally scrollable, each tab
/// opening its contextual tool row under the canvas. The top bar keeps
/// deck-level controls: rename (tap the title), undo/redo, comments, share,
/// and the More menu with Editing / Viewing / Presenting modes and Export.
/// **+** adds a blank slide instantly (the curated layout list is a
/// deliberate choice from a long-press on **+**). And the
/// AI can still drive the same ops over MCP.
///
/// Insert is where things get ADDED: its compact drawer rides the ribbon's
/// top edge (the same sheet machinery as Files) with a 3×2 grid — Text Box,
/// Image, Shapes, Table, Icons / Stickers, Media — and inserting or tapping
/// an object swaps the grid for that object's editing panel: the slide stays
/// fully visible and interactive above it, most of the panel is controls,
/// and a narrow icon-only rail on the far right switches between groups.
/// A text box edits WYSIWYG on the canvas: while typing, the drawer hides
/// and a horizontally scrollable toolbar rides above the keyboard; with
/// the keyboard closed, the full panel carries Quick Tools / Character /
/// Paragraph & Box.
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

  // ---- the Insert drawer's object/text editing session ---------------------------

  /// The live text-editing session for the selected text box: the doc + the
  /// controller + the field's focus node, one undo snapshot per session,
  /// and a debounced engine commit so typing never round-trips per keystroke.
  _TextSession? _textSession;

  /// True while the text field has focus — the TYPING state: the Insert
  /// sheet is hidden (the keyboard covers it) and the typing toolbar
  /// rides above the keyboard in the root overlay.
  bool _typing = false;

  /// The typing toolbar's root-overlay entry (null when not typing).
  OverlayEntry? _typingToolbarEntry;

  /// The deck's resolved palette (deck colors) + base text style for text
  /// boxes — read from the engine's `resolve_dna`, cached per deck version.
  List<Color> _deckPalette = const [];
  Color _baseTextColor = const Color(0xFF17181A);
  String? _baseTextFamily;
  int _paletteForVersion = -1;

  /// Live style edits from the object panel (one undo snapshot per
  /// selection, debounced commit — same contract as the text session).
  bool _styleUndoPushed = false;
  Timer? _objectCommitDebounce;

  /// Cached image-resource paths: 'brand:<id>' / 'deck:<id>' → file path.
  final Map<String, String> _resourcePaths = {};

  /// The Insert drawer's two resting extents. The GRID sheet is compact —
  /// header + the full 3×2 grid above the filmstrip tray's overlay, with
  /// the slide's center still visible and tappable above it (mid-slide
  /// objects stay selectable). The PANEL sheet is taller — its control
  /// area earns the height, and the object it edits is already selected.
  static const double _insertGridSheetHeight = 400;
  static const double _insertPanelSheetHeight = 436;

  /// The sheet tab whose surface the layer is showing (or last showed) —
  /// the Files ⇄ Insert switch swaps content without unmounting the layer,
  /// and the exit slide keeps showing the surface it is animating OUT.
  _NavTab _lastSheetTab = _NavTab.files;

  // ---- PowerPoint-style bottom ribbon ------------------------------------------
  /// The active ribbon tab; its contextual action row renders between
  /// the canvas and the filmstrip. Null = collapsed (canvas gets the space).
  _NavTab? _navTab;

  /// Filmstrip expansion — driven from the handle built into the strip's
  /// divider: one continuous boundary runs the editor's full width directly
  /// above the strip band (or, when collapsed, directly above the ribbon);
  /// near the right edge it ramps up into a short ledge flush to the edge,
  /// and the chevron in that pocket folds the band up under the rule or
  /// unfolds it back. The OPEN state keeps the 2.15 canvas geometry: same
  /// 104dp band, same + disc spot, same 74dp slide-0 origin — nothing
  /// resizes or realigns, and selection plus scroll offset survive every
  /// round trip (the band is revealed/clipped, never unmounted).
  bool _filmOpen = true;

  /// Must stay in lockstep with the filmstrip band's own height below
  /// (the `SizedBox(key: ValueKey('filmstrip_row'))` inside the reveal).
  static const double _filmstripBandHeight = 104.0;

  /// The reveal's reparent anchor. While the Files sheet is closed the strip
  /// is a row in the editor's flow; while the sheet is open the SAME subtree
  /// is the foreground overlay riding the sheet's lower part. Both slots
  /// build the strip under this GlobalKey, so the move between them
  /// reparents the element instead of remounting it — the rail's scroll
  /// offset and the selection survive every Files open/close, exactly as
  /// they survive the strip's own fold (the reveal clips, never unmounts).
  final GlobalKey _filmstripRevealHost = GlobalKey();

  /// Must stay in lockstep with `_EditorNavBar`'s Material-3 band (the 76dp
  /// trimmed NavigationBar anatomy) — the ribbon's own 1px top hairline is
  /// accounted separately wherever the anchor needs it (sheetAnchor).
  static const double _navBarHeight = 76.0;

  /// The Files drawer's live extent, in logical px — the sheet floats as
  /// its own layer pinned directly to the ribbon's top edge. null = the
  /// resting half detent (recomputed each build from the layer cake's
  /// actual space); anything else = a drag in flight or a snapped detent.
  /// The settle logic (fling one detent, nearest-detent release, dismiss
  /// zone at the bottom) reads the cached [_drawerHalf]/[_drawerTall],
  /// refreshed on every build. The sheet's extent is completely
  /// independent of the filmstrip's state — the strip never takes layout
  /// space while the sheet is open, so its toggles can never move the
  /// sheet's top edge.
  double? _drawerExtent;
  double _drawerHalf = 296;
  double _drawerTall = 356;
  bool _drawerDragging = false;

  /// The sheet's entrance slide. Arriving at Files, the sheet is laid out
  /// at its FULL intended height (the resting detent — never a mid-screen
  /// sliver) but translated fully below the navbar's top edge, so its
  /// first mounted frame paints nothing; the post-frame callback in
  /// [_setNavTab] then translates it up into view over the same 200ms
  /// family, clipped at the navbar boundary — the sheet emerges
  /// continuously from behind the navbar, the navbar fixed in front.
  bool _sheetEntering = false;

  /// True while the sheet is translating back down behind the navbar on
  /// its way out: the layer stays mounted (the flow's spacer and the tray
  /// stay with it) until the slide completes — the AnimatedPositioned's
  /// onEnd — so the exit is the entrance's exact reverse rather than a
  /// vanish. Re-entering Files mid-slide simply retargets the same
  /// animation, so interrupted or reversed slides continue from the
  /// current visible position, never resetting.
  bool _sheetClosing = false;

  /// The filmstrip's flow footprint, frozen at the moment Files opens:
  /// while the strip lives in the foreground overlay, the flow keeps
  /// exactly this much space as an empty spacer, so the slide preview's
  /// constraints cannot change with the sheet's visibility, its animation
  /// progress, or the tray's toggles — opening or closing Files, or
  /// toggling the tray over the open sheet, can never move, resize, or
  /// recenter the preview. On close the spacer hands its height back to
  /// the strip over the same 200ms family.
  double? _frozenStripFootprint;

  /// The sheet's floor: a sliver of grab handle plus a breath of panel —
  /// never smaller, so the pinned header always fits and the drag surface
  /// is on screen at every height the sheet can be at. In ultra-cramped
  /// layouts the detents themselves may sit below it, so the floor never
  /// exceeds the tall detent.
  static const double _drawerSliver = 56;

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
    _loadResourceIndex();
  }

  @override
  void dispose() {
    _removeTypingToolbar();
    _disposeTextSession();
    _objectCommitDebounce?.cancel();
    _commentField.dispose();
    _navScroll.dispose();
    super.dispose();
  }

  /// A different deck handed to the SAME editor instance (a parent
  /// rebuilding with another deck): reload everything — the state belongs
  /// to the deck it was opened on, never to the widget slot.
  @override
  void didUpdateWidget(EditorScreen old) {
    super.didUpdateWidget(old);
    if (identical(widget.deck, old.deck)) return;
    _removeTypingToolbar();
    _disposeTextSession();
    _objectCommitDebounce?.cancel();
    setState(() {
      _deck = Map<String, dynamic>.from(widget.deck);
      _index = 0;
      _selectedObjectId = null;
      _typing = false;
      _navTab = null;
      _designMode = false;
      _scribbleMode = false;
      _sheetEntering = false;
      _sheetClosing = false;
      _drawerExtent = null;
      _frozenStripFootprint = null;
      _paletteForVersion = -1;
    });
    _refreshLayout();
    _loadResourceIndex();
  }

  /// The image-resource index (both scopes) + resolved paths, loaded once —
  /// the content layer's resolver reads the cache synchronously; inserts
  /// refresh the touched entries.
  Future<void> _loadResourceIndex() async {
    try {
      final store = await ResourceStore.open();
      final deckId = (_deck['id'] ?? '').toString();
      for (final (brand, scope) in [(false, 'deck'), (true, 'brand')]) {
        final items =
            await store.list(brand: brand, deckId: brand ? null : deckId);
        for (final e in items) {
          final path = await store.resolve(
              brand: brand, deckId: brand ? null : deckId, id: '${e['id']}');
          if (path != null) {
            _resourcePaths['$scope:${e['id']}'] = path;
          }
        }
      }
    } catch (_) {
      // Storage offline — image objects fall back to their name chip.
    }
  }

  /// The sync resolver handed to the canvas content layer.
  String? _resolveResourcePath(Map<String, dynamic> content) {
    final scope = content['brand'] == true ? 'brand' : 'deck';
    return _resourcePaths['$scope:${content['resource_id']}'];
  }

  /// The deck's design-space frame — objects, content widgets and the edit
  /// field all live in it.
  (double, double) get _designDims => deckDimsOf(_deck['aspect']?.toString());

  /// The panel's text formatting bundle, bound to the live session.
  late final TextActions _textActions = TextActions(
    toggleFlag: (flag) =>
        _docMutate((doc, a, b) => doc.toggleFlag(a, b, flag)),
    setColor: (hex) =>
        _docMutate((doc, a, b) => doc.setAttr(a, b, 'color', hex)),
    setHighlight: (hex) =>
        _docMutate((doc, a, b) => doc.setAttr(a, b, 'highlight', hex)),
    setAlign: (v) =>
        _docMutate((doc, a, b) => doc.setParagraphAttr(a, b, 'align', v)),
    toggleList: (k) => _docMutate((doc, a, b) => doc.toggleList(a, b, k)),
    setFontFamily: (f) =>
        _docMutate((doc, a, b) => doc.setAttr(a, b, 'font_family', f)),
    setFontSize: (s) =>
        _docMutate((doc, a, b) => doc.setAttr(a, b, 'font_size', s)),
    clearFormatting: () => _docMutate((doc, a, b) {
          if (a == b) {
            doc.clearRange(0, doc.text.length);
          } else {
            doc.clearRange(a, b);
          }
        }),
    setValign: (v) => _docMutate((doc, a, b) => doc.valign = v),
    setAutofit: (v) => _docMutate((doc, a, b) => doc.autofit = v),
    setLineSpacing: (s) => _docMutate(
        (doc, a, b) => doc.setParagraphAttr(a, b, 'line_spacing', s)),
    indentBy: (d) => _docMutate((doc, a, b) => doc.indentBy(a, b, d)),
  );

  /// The panel's "full style inspector" affordance — the existing sheet,
  /// driven on the CURRENT selection.
  void _editSelectedObjectStyle() {
    final obj = _selectedObject;
    if (obj == null) return;
    showInspector(context, object: obj, onChange: _styleChanged);
  }

  /// The deck's palette + the text boxes' slide-theme base — recomputed when
  /// the deck version moves (new deck, DNA change, undo/redo).
  void _refreshPalette() {
    final version = (_deck['version'] as num?)?.toInt() ?? 0;
    if (version == _paletteForVersion) return;
    _paletteForVersion = version;
    final r = Bridge.command({'op': 'resolve_dna', 'deck': _deck});
    if (r['ok'] != true || r['dna'] is! Map) return;
    final palette = (r['dna']['palette'] as Map?) ?? const {};
    final colors = <Color>[];
    for (final key in ['bg', 'surface', 'fg', 'muted', 'accent']) {
      final hex = palette[key]?.toString();
      if (hex != null && hex.length == 6) {
        colors.add(hexToColor(hex));
      }
    }
    // The deck colors first, then the studio's standard swatches.
    _deckPalette = [...colors, ...kSwatchPalette];
    final fg = palette['fg']?.toString();
    _baseTextColor = fg != null && fg.length == 6
        ? hexToColor(fg)
        : const Color(0xFF17181A);
    _baseTextFamily = (r['dna']['body_font'] ?? '').toString() == 'serif'
        ? 'serif'
        : null;
  }

  List<Map<String, dynamic>> get _slides => (_deck['slides'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();

  // ---- deck state + undo/redo ------------------------------------------------

  Map<String, dynamic> _copy() =>
      jsonDecode(jsonEncode(_deck)) as Map<String, dynamic>;

  /// Fire-and-forget by design — the editor never blocks on the disk — but
  /// never *unhandled*: the store snapshots the deck at enqueue time and
  /// serializes writes per deck, so rapid edits/undo/redo land in order with
  /// the latest state always winning, and a failed write leaves the prior
  /// valid file untouched and surfaces here (throttled toast). Later saves
  /// recover automatically; the deck list shown on return is coordinated by
  /// the dashboard's flush-then-scan reload.
  Future<void> _persist() async {
    try {
      final store = await DeckStore.open();
      await store.save(_deck);
    } catch (e, st) {
      print('[deck-store] editor save failed: $e\n$st');
      _warnSaveFailed();
    }
  }

  /// At most one save-failure toast per 10s — a broken disk must be visible,
  /// not deafening. The message is actionable without being a stack trace.
  DateTime? _lastSaveToastAt;
  void _warnSaveFailed() {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastSaveToastAt;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastSaveToastAt = now;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Could not save this deck — your edits stay in memory and saving '
            'retries automatically.')));
  }

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
    unawaited(_persist());
    _refreshLayout();
    _refreshPalette();
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_copy());
      _deck = _undo.removeLast();
    });
    unawaited(_persist());
    _refreshLayout();
    _refreshPalette();
    _styleUndoPushed = false;
    _resyncTextSession();
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_copy());
      _deck = _redo.removeLast();
    });
    unawaited(_persist());
    _refreshLayout();
    _refreshPalette();
    _styleUndoPushed = false;
    _resyncTextSession();
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
    final r = Bridge.command(
        {'op': 'get_layout', 'deck': _deck, 'slide_index': _index});
    setState(() {
      if (r['ok'] == true && r['layout'] is Map) {
        _layout = (r['layout'] as Map).cast<String, dynamic>();
        _warnings = ((r['layout']['warnings'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
      } else {
        _layout = null;
        _warnings = ['layout error: ${r['error']}'];
      }
    });
  }

  // ---- vector overlay layer (studio tools) -------------------------------------

  String? get _slideId =>
      _slides.isEmpty ? null : _slides[_index]['id'] as String?;

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

  /// Switch the active slide. A different slide means the old slide's
  /// selection is CLEARED — the object panel, the text session and the
  /// editing state all belong to the slide they were opened on, and no
  /// one keeps accidentally editing the previous slide's object.
  void _gotoSlide(int i) {
    if (i < 0 || i >= _slides.length || i == _index) {
      if (i == _index) _refreshLayout();
      return;
    }
    _flushTextSession();
    _disposeTextSession();
    _removeTypingToolbar();
    setState(() {
      _index = i;
      _selectedObjectId = null;
      _typing = false;
    });
    _refreshLayout();
  }

  /// Ribbon state machine: one contextual row at a time, tapped again to
  /// collapse. Tabs that work on the canvas overlay (Insert, Draw) double
  /// as design mode, so leaving them clears scribble/selection — but the
  /// selection SURVIVES a Files ⇄ Insert switch (both are sheet tabs over
  /// the same design mode canvas).
  void _setNavTab(_NavTab? tab) {
    final wasSheet = _isSheetTab(_navTab);
    final willBeSheet = _isSheetTab(tab);
    // The sheet's height where it stands RIGHT NOW (before the tab flips) —
    // what the exit slide holds when it reverses.
    final leavingHeight = _drawerExtent ??
        (_navTab == _NavTab.files
            ? _drawerHalf
            : (_selectedObjectId != null
                ? _insertPanelSheetHeight
                : _insertGridSheetHeight));
    // The strip's live height where it stands right now — read BEFORE the
    // setState rebuild, so a fold caught mid-flight freezes at its real
    // on-screen height, not its target.
    final arrivingFootprint = _liveStripFlowHeight();
    setState(() {
      _navTab = tab;
      if (willBeSheet) _lastSheetTab = tab!;
      _designMode = tab == _NavTab.insert || tab == _NavTab.draw;
      if (!_designMode) {
        _scribbleMode = false;
        _selectedObjectId = null;
        _disposeTextSession();
      }
      if (tab != _NavTab.insert) {
        // Leaving the typing state: any tab switch closes the keyboard and
        // ends the typing session's field focus (the sheet returns).
        _endTyping();
      }
      // The drawer layer's lifecycle. ARRIVING at a sheet tab (Files or
      // Insert): the sheet mounts at its full intended height translated
      // fully below the navbar's top edge — the first frame paints nothing —
      // and the post-frame callback below slides it up into view; the flow
      // freezes the strip's footprint so the slide preview cannot move.
      // SWITCHING Files ⇄ Insert: the layer simply swaps its content —
      // same layer, same spacer, no entrance.
      // LEAVING a sheet tab: the sheet reverses the entrance — it
      // translates back down behind the navbar, and the layer unmounts
      // when the slide completes (onEnd below). Only if it never rose past
      // its mount frame is there nothing on screen to animate out — then
      // the layer unmounts at once.
      if (!willBeSheet) {
        _drawerDragging = false;
        if (wasSheet) {
          if (_sheetEntering) {
            // Never rose: no pixels were ever shown — nothing to animate.
            _sheetEntering = false;
            _sheetClosing = false;
            _drawerExtent = null;
          } else {
            _sheetClosing = true;
            // hold the height it stands at
            _drawerExtent ??= leavingHeight;
          }
        }
        // (Leaving a sheet tab for another non-sheet tab while the exit
        // slide already runs changes nothing — the slide continues to the
        // same unmount.)
      } else if (!wasSheet) {
        final resumingExit = _sheetClosing;
        _sheetClosing = false;
        _sheetEntering = !resumingExit;
        _drawerExtent = null;
        _frozenStripFootprint = arrivingFootprint;
      }
    });
    if (willBeSheet && !wasSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_isSheetTab(_navTab) ||
            _drawerDragging ||
            !_sheetEntering) {
          return;
        }
        // Flip the entrance: the sheet's bottom retargets from
        // (anchor - height) to the anchor, and AnimatedPositioned slides
        // it up over the 200ms family.
        setState(() => _sheetEntering = false);
      });
    }
    if (tab != null) {
      // Keep the freshly-lit tab centered in the scrollable bar.
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerNavTab(tab));
    }
  }

  bool _isSheetTab(_NavTab? tab) =>
      tab == _NavTab.files || tab == _NavTab.insert;

  /// The sheet layer's live height for the CURRENT state: a held drag/settle
  /// extent when one exists, the Files detents when Files is the active tab,
  /// the Insert drawer's current extent otherwise (compact grid, taller
  /// object panel — the AnimatedPositioned morphs between them).
  double _sheetLiveHeightFor(bool filesOpen) => _drawerExtent ??
      (filesOpen
          ? _drawerHalf
          : (_selectedObjectId != null
              ? _insertPanelSheetHeight
              : _insertGridSheetHeight));

  /// Centers the active ribbon tab in the bar's viewport — but only when
  /// the tab is actually off-screen. A tab that is already fully visible
  /// never nudges the bar: the centering glide is a nicety for reaching
  /// far-edge tabs, and an unnecessary one would leave the scroll animating
  /// (and its content ignoring pointers) for a quarter second after every
  /// switch — exactly when the user's next tap lands.
  void _centerNavTab(_NavTab tab) {
    if (!_navScroll.hasClients) return;
    final i = _NavTab.values.indexOf(tab);
    final view = _navScroll.position.viewportDimension;
    final maxExtent = _navScroll.position.maxScrollExtent;
    final itemLeft = i * _navItemWidth;
    if (itemLeft >= -4 && itemLeft + _navItemWidth <= view + 4) {
      return; // fully visible — the bar stays put
    }
    final target = (i * _navItemWidth + _navItemWidth / 2 - view / 2)
        .clamp(0.0, maxExtent)
        .toDouble();
    _navScroll.animateTo(target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic);
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
    // New shapes center on the deck's actual frame — 4:3 and 1:1 decks drop
    // them on-frame, not at the classic 1280-wide midpoint.
    final (dw, dh) = deckDimsOf(_deck['aspect']?.toString());
    final shape = <String, dynamic>{
      'id': _newObjectId(),
      'preset': preset,
      'x': (dw - w) / 2 + (n % 5) * 24.0,
      'y': (dh - h) / 2 + (n % 5) * 16.0,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': 1.0,
      'locked': false,
      'fill': open ? {'type': 'none'} : {'type': 'solid', 'color': 'FFFFFF'},
      'stroke': open
          ? {
              'color': 'D03028',
              'width': 3.0,
              'dash': 'solid',
              'start_arrow': 'none',
              'end_arrow': 'none'
            }
          : {
              'color': '17181A',
              'width': 1.5,
              'dash': 'solid',
              'start_arrow': 'none',
              'end_arrow': 'none'
            },
      'effects': {},
      'closed': true,
    };
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': slideId,
      'shape': shape
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _prepareSelectionFor(shape['id'] as String?);
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
        {
          'x': ((p.dx - minx) / w).clamp(0.0, 1.0).toDouble(),
          'y': ((p.dy - miny) / h).clamp(0.0, 1.0).toDouble()
        },
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
      'stroke': {
        'color': 'D03028',
        'width': 3.0,
        'dash': 'solid',
        'start_arrow': 'none',
        'end_arrow': 'none'
      },
      'effects': {},
      'points': norm,
      'closed': false,
    };
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': slideId,
      'shape': shape
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _prepareSelectionFor(shape['id'] as String?);
    }
  }

  // ---- object selection + the text editing session ---------------------------

  /// Selection from the canvas layer (tap): first tap selects and shows the
  /// object's panel; tapping the SAME text box again re-enters typing.
  void _onObjectSelected(String? id) {
    if (id == null) {
      _flushTextSession();
      _disposeTextSession();
      setState(() => _selectedObjectId = null);
      return;
    }
    if (id == _selectedObjectId) {
      final obj = _selectedObject;
      if (obj != null && ObjectContent.isText(obj)) {
        _beginTyping();
        return;
      }
    }
    _prepareSelectionFor(id);
  }

  /// Point the editor's selection at [id]: swap the text session (a text box
  /// gets a live doc + controller; anything else ends it), reset the
  /// per-selection style undo bookkeeping.
  void _prepareSelectionFor(String? id) {
    _flushTextSession();
    _disposeTextSession();
    _endTyping();
    _styleUndoPushed = false;
    _objectCommitDebounce?.cancel();
    _objectCommitDebounce = null;
    setState(() {
      _selectedObjectId = id;
      if (id == null) return;
      final obj = _selectedObject;
      if (obj != null && ObjectContent.isText(obj)) {
        _textSession = _TextSession(
          controller: RichEditingController(
            doc: ObjectContent.textDocOf(obj) ?? RichDoc(),
          ),
          focus: FocusNode(),
        );
        _wireTextSession();
      }
    });
  }

  void _wireTextSession() {
    final s = _textSession;
    if (s == null) return;
    // Text changes: local deck update + debounced engine commit; one undo
    // snapshot per session (typing is one undo group, like the pros).
    s.controller.addListener(_onSessionTextChanged);
    // The typing state IS the field's focus.
    s.focus.addListener(_onSessionFocusChanged);
  }

  void _onSessionTextChanged() {
    final s = _textSession;
    if (s == null) return;
    if (!s.undoPushed) {
      s.undoPushed = true;
      _undo.add(_copy());
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    _syncSessionDocIntoDeck();
    _scheduleTextCommit();
    if (mounted) setState(() {});
  }

  /// The session's doc, written back into the LOCAL deck map (the debounced
  /// commit takes it across the engine + storage).
  void _syncSessionDocIntoDeck() {
    final s = _textSession;
    if (s == null) return;
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isText(obj)) return;
    _replaceObjectLocal(ObjectContent.withTextDoc(obj, s.controller.doc));
  }

  void _scheduleTextCommit() {
    final s = _textSession;
    if (s == null) return;
    s.commitDebounce?.cancel();
    s.commitDebounce = Timer(const Duration(milliseconds: 450), () {
      _flushTextSession();
    });
  }

  /// Commit the live text session to the engine now (persist + layout).
  void _flushTextSession() {
    final s = _textSession;
    if (s == null) return;
    s.commitDebounce?.cancel();
    s.commitDebounce = null;
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isText(obj)) return;
    final r = Bridge.command({
      'op': 'update_object',
      'deck': _deck,
      'slide_id': _slideId,
      'object_id': obj['id'],
      'shape': obj,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _setDeck(r['deck'] as Map);
    }
  }

  void _disposeTextSession() {
    final s = _textSession;
    _textSession = null;
    if (s == null) return;
    s.commitDebounce?.cancel();
    s.controller.removeListener(_onSessionTextChanged);
    s.focus.removeListener(_onSessionFocusChanged);
    s.controller.dispose();
    s.focus.dispose();
  }

  /// After an undo/redo swap of the whole deck, the live session must
  /// re-read its object (the box may be gone or carry older text).
  void _resyncTextSession() {
    final s = _textSession;
    if (s == null) return;
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isText(obj)) {
      _disposeTextSession();
      return;
    }
    final fresh = ObjectContent.textDocOf(obj) ?? RichDoc();
    s.controller.doc = fresh;
    s.undoPushed = false;
    s.controller.text = fresh.text;
    s.controller.refresh();
  }

  // ---- the typing state --------------------------------------------------------

  void _beginTyping() {
    final s = _textSession;
    if (s == null) return;
    // The field mounts focused (autofocus) — the focus listener below
    // flips the typing state, hides the sheet, shows the toolbar.
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_typing) return;
      s.focus.requestFocus();
    });
  }

  void _endTyping() {
    final s = _textSession;
    if (_typing || _typingToolbarEntry != null) {
      s?.focus.unfocus();
    }
    setState(() => _typing = false);
    _removeTypingToolbar();
  }

  void _onSessionFocusChanged() {
    final s = _textSession;
    if (s == null || !mounted) return;
    if (s.focus.hasFocus) {
      setState(() => _typing = true);
      _showTypingToolbar();
    } else {
      // Keyboard closed with the text box still selected: the sheet (and
      // its full panel) returns — capture the strip's footprint first, in
      // flow-order, so the spacer is honest through the reparent.
      _removeTypingToolbar();
      final footprint = _liveStripFlowHeight();
      setState(() {
        _typing = false;
        _frozenStripFootprint = footprint;
      });
      _flushTextSession();
    }
  }

  void _showTypingToolbar() {
    if (_typingToolbarEntry != null) return;
    final s = _textSession;
    if (s == null) return;
    _typingToolbarEntry = OverlayEntry(
      builder: (overlayContext) {
        // The root overlay sees the REAL viewport: the toolbar rides the
        // keyboard in both inset-delivery and window-resize mode.
        final bottom = MediaQuery.viewInsetsOf(overlayContext).bottom;
        return Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: s.controller,
              builder: (context, _) => TypingToolbar(
                docState: _TypingDocState(s),
                palette: _deckPalette,
                onToggle: (flag) => _docMutate(
                    (doc, a, b) => doc.toggleFlag(a, b, flag)),
                onColor: (hex) =>
                    _docMutate((doc, a, b) => doc.setAttr(a, b, 'color', hex)),
                onHighlight: (hex) => _docMutate(
                    (doc, a, b) => doc.setAttr(a, b, 'highlight', hex)),
                onAlign: (v) =>
                    _docMutate((doc, a, b) => doc.setParagraphAttr(a, b, 'align', v)),
                onList: (k) => _docMutate((doc, a, b) => doc.toggleList(a, b, k)),
                onExpand: _endTyping,
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_typingToolbarEntry!);
  }

  void _removeTypingToolbar() {
    _typingToolbarEntry?.remove();
    _typingToolbarEntry = null;
  }

  /// One mutator for every toolbar/panel text action: target the current
  /// selection (or caret), apply, refresh the field, commit live.
  void _docMutate(void Function(RichDoc doc, int a, int b) fn) {
    final s = _textSession;
    if (s == null) return;
    final sel = s.controller.effectiveSelection;
    fn(s.controller.doc, sel.baseOffset, sel.extentOffset);
    _onSessionTextChanged();
    s.controller.refresh();
  }

  // ---- live object style edits (the panel) -------------------------------------

  void _liveObjectEdit(Map<String, dynamic> updated) {
    if (!_styleUndoPushed) {
      _styleUndoPushed = true;
      _undo.add(_copy());
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    _replaceObjectLocal(updated);
    _objectCommitDebounce?.cancel();
    _objectCommitDebounce = Timer(const Duration(milliseconds: 350), () {
      final obj = _selectedObject;
      if (obj == null) return;
      final r = Bridge.command({
        'op': 'update_object',
        'deck': _deck,
        'slide_id': _slideId,
        'object_id': obj['id'],
        'shape': obj,
      });
      if (r['ok'] == true && r['deck'] is Map) {
        _setDeck(r['deck'] as Map);
      }
    });
    if (mounted) setState(() {});
  }

  // ---- the Insert drawer's flows -------------------------------------------------

  Map<String, dynamic> _newContentObject({
    required double w,
    required double h,
    Map<String, dynamic>? content,
    Map<String, dynamic>? fill,
    Map<String, dynamic>? stroke,
  }) {
    final (dw, dh) = deckDimsOf(_deck['aspect']?.toString());
    return {
      'id': _newObjectId(),
      'preset': 'rectangle',
      'x': (dw - w) / 2,
      'y': (dh - h) / 2,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': 1.0,
      'locked': false,
      'fill': fill ?? {'type': 'none'},
      'stroke': stroke ?? {'color': '17181A', 'width': 0.0, 'dash': 'solid', 'start_arrow': 'none', 'end_arrow': 'none'},
      'effects': {},
      'closed': true,
      if (content != null) 'content': content,
    };
  }

  void _insertObject(Map<String, dynamic> shape, {bool startTyping = false}) {
    final slideId = _slideId;
    if (slideId == null) {
      _toast('Add a slide first.');
      return;
    }
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': slideId,
      'shape': shape,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _prepareSelectionFor(shape['id'] as String?);
      // The Insert tab must be the active sheet when inserting (the grid
      // lives there); a text box goes straight into typing.
      if (_navTab != _NavTab.insert) _setNavTab(_NavTab.insert);
      if (startTyping) _beginTyping();
    } else {
      _toast('Could not insert: ${r['error']}');
    }
  }

  /// Text Box: an editable text box mid-slide, selected, keyboard open.
  void _insertTextBox() {
    _insertObject(
      _newContentObject(w: 560, h: 170, content: ObjectContent.text(RichDoc())),
      startTyping: true,
    );
  }

  /// Table: 3×3 with editable cells.
  void _insertTable() {
    _insertObject(
      _newContentObject(
        w: 620,
        h: 340,
        content: ObjectContent.table(3, 3),
        stroke: const {
          'color': '17181A',
          'width': 1.5,
          'dash': 'solid',
          'start_arrow': 'none',
          'end_arrow': 'none',
        },
      ),
    );
  }

  /// Icon sticker from the searchable registry.
  void _insertIcon(String name) {
    _insertObject(
      _newContentObject(
        w: 140,
        h: 140,
        content: ObjectContent.icon(name),
        fill: {'type': 'solid', 'color': colorToHex(_baseTextColor)},
      ),
    );
  }

  /// Image: Gallery / Camera / Deck Resources / Brand Resources.
  Future<void> _pickImage(String source) async {
    if (source == 'deck' || source == 'brand') {
      await _pickImageResource(source == 'brand');
      return;
    }
    final path =
        await ImagePickers.pickImage(camera: source == 'camera');
    if (path == null || !mounted) return;
    await _insertImageFromPath(path);
  }

  Future<void> _insertImageFromPath(String path) async {
    try {
      final store = await ResourceStore.open();
      final entry = await store.add(
        brand: false,
        deckId: (_deck['id'] ?? '').toString(),
        sourcePath: path,
      );
      final resolved = _resourcePathOf(entry, brand: false);
      if (resolved != null) {
        _resourcePaths['deck:${entry['id']}'] = resolved;
      }
      _insertObject(
        _newContentObject(
          w: 480,
          h: 300,
          content: ObjectContent.image('${entry['id']}',
              brand: false, name: '${entry['name']}'),
        ),
      );
    } catch (e) {
      _toast('Could not import that image: $e');
    }
  }

  String? _resourcePathOf(Map<String, dynamic> entry, {required bool brand}) {
    try {
      final store = ResourceStore.peek();
      if (store == null) return null;
      final dir = store.scopeDirPath(
          brand: brand,
          deckId: brand ? null : (_deck['id'] ?? '').toString());
      return '$dir/${entry['file']}';
    } catch (_) {
      return null;
    }
  }

  /// Pick an image from the device's resource libraries (deck or brand).
  Future<void> _pickImageResource(bool brand) async {
    try {
      final store = await ResourceStore.open();
      final items = await store.list(
          brand: brand, deckId: brand ? null : (_deck['id'] ?? '').toString());
      final images = items
          .where((e) => isImagePath('${e['name']}'))
          .toList(growable: false);
      if (!mounted) return;
      if (images.isEmpty) {
        _toast(brand
            ? 'No images in Brand resources yet — import some from Files.'
            : 'No images in this deck\'s resources yet — import some from Files.');
        return;
      }
      final choice = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.55,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    brand ? 'Brand resources — images' : 'Deck resources — images',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final e in images)
                  ListTile(
                    leading: Image(
                      image: FileImage(
                          File(_resourcePathOf(e, brand: brand) ?? '')),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_outlined, size: 22),
                    ),
                    title: Text('${e['name']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${((e['size'] ?? 0) as num).toInt() ~/ 1024} KB',
                        style: const TextStyle(fontSize: 11.5)),
                    onTap: () => Navigator.pop(sheetContext, e),
                  ),
              ],
            ),
          ),
        ),
      );
      if (choice == null || !mounted) return;
      _insertObject(
        _newContentObject(
          w: 480,
          h: 300,
          content: ObjectContent.image('${choice['id']}',
              brand: brand, name: '${choice['name']}'),
        ),
      );
    } catch (e) {
      _toast('Storage is not answering — try again in a moment.');
    }
  }

  /// Media: import an existing video or audio file (no recorder, ever).
  Future<void> _pickMedia(String kind) async {
    final path = await ImagePickers.pickMedia(kind: kind);
    if (path == null || !mounted) return;
    try {
      final store = await ResourceStore.open();
      final entry = await store.add(
        brand: false,
        deckId: (_deck['id'] ?? '').toString(),
        sourcePath: path,
      );
      _insertObject(
        _newContentObject(
          w: 460,
          h: 240,
          content: ObjectContent.media('${entry['id']}',
              brand: false,
              name: '${entry['name']}',
              mediaKind: kind),
        ),
      );
    } catch (e) {
      _toast('Could not import that file: $e');
    }
  }

  /// Table cell editing — the route dialog (text entry lives in routes,
  /// outside the keyboard-stable subtree).
  Future<void> _editTableCell(int index) async {
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isTable(obj)) return;
    final (rows, cols, cells) = ObjectContent.tableOf(obj);
    if (index < 0 || index >= cells.length) return;
    final text = await dreamInputDialog(
      context,
      title: 'Cell ${index ~/ cols + 1},${index % cols + 1}',
      initial: cells[index],
      confirmLabel: 'Save',
    );
    if (text == null || !mounted) return;
    final updated = List<String>.from(cells);
    updated[index] = text;
    final copy = Map<String, dynamic>.from(obj);
    final content = Map<String, dynamic>.from(copy['content'] as Map);
    content['cells'] = updated;
    copy['content'] = content;
    // A committed cell edit is its own undo step (discrete, deliberate).
    _styleChanged(copy);
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
    final r = Bridge.command({
      'op': 'update_object',
      'deck': _deck,
      'slide_id': slideId,
      'object_id': obj['id'],
      'shape': obj
    });
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
    final r = Bridge.command({
      'op': 'update_object',
      'deck': _deck,
      'slide_id': slideId,
      'object_id': obj['id'],
      'shape': obj
    });
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

  void _groupObjects(List<String> ids) => _objOp(
      {'op': 'group_objects', 'deck': _deck, 'slide_id': _slideId, 'ids': ids});

  void _ungroupObjects(List<String> ids) => _objOp({
        'op': 'ungroup_objects',
        'deck': _deck,
        'slide_id': _slideId,
        'ids': ids
      });

  void _alignObjects(String mode, List<String> ids) => _objOp({
        'op': 'align_objects',
        'deck': _deck,
        'slide_id': _slideId,
        'ids': ids,
        'mode': mode
      });

  void _booleanObjects(String mode, List<String> ids) {
    if (ids.length != 2) return;
    _objOp({
      'op': 'boolean_op',
      'deck': _deck,
      'slide_id': _slideId,
      'a': ids[0],
      'b': ids[1],
      'mode': mode
    });
  }

  void _saveComponent(List<String> ids, String name) => _objOp({
        'op': 'save_component',
        'deck': _deck,
        'slide_id': _slideId,
        'ids': ids,
        'name': name
      });

  void _placeComponent(String componentId) => _objOp({
        'op': 'place_component',
        'deck': _deck,
        'slide_id': _slideId,
        'component_id': componentId
      });

  void _syncComponent(String objectId) {
    if (objectId.isEmpty) return;
    _objOp({
      'op': 'update_component',
      'deck': _deck,
      'slide_id': _slideId,
      'object_id': objectId
    });
  }

  void _reorderObject(String id, int dir) {
    final objs = _objects;
    final idx = objs.indexWhere((o) => o['id'] == id);
    if (idx < 0) return;
    final to = (idx + dir).clamp(0, objs.length - 1);
    _objOp({
      'op': 'move_object_z',
      'deck': _deck,
      'slide_id': _slideId,
      'object_id': id,
      'to_index': to
    });
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

  void _deleteObject(String id) => _objOp({
        'op': 'delete_object',
        'deck': _deck,
        'slide_id': _slideId,
        'object_id': id
      });

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
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': _slideId,
      'shape': copy
    });
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
      final r = Bridge.command({
        'op': 'add_object',
        'deck': _deck,
        'slide_id': _slideId,
        'shape': copy
      });
      if (r['ok'] != true || r['deck'] is! Map) {
        _toast('Could not add reflection: ${r['error']}');
        return;
      }
      final r2 = Bridge.command({
        'op': 'group_objects',
        'deck': r['deck'],
        'slide_id': _slideId,
        'ids': [id, newId]
      });
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
    final content =
        Map<String, dynamic>.from(slide['content'] ?? <String, dynamic>{});
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
  Map<String, dynamic> _applyKey(
      Map<String, dynamic> content, String key, String value) {
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
    final r = Bridge.command(
        {'op': 'add_slide', 'deck': _deck, 'archetype': 'blank'});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _gotoSlide(_slides.length - 1);
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
    final archetypes =
        (meta['archetypes'] as List? ?? []).map((e) => e.toString()).toList();
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
    final add = Bridge.command(
        {'op': 'add_slide', 'deck': _deck, 'archetype': _archetypeOf(choice)});
    if (add['ok'] == true && add['deck'] is Map) {
      _mutate(add['deck'] as Map);
      _gotoSlide(_slides.length - 1);
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
      final newId =
          (((deck['slides'] as List?) ?? []).whereType<Map>().last)['id'];
      final move = Bridge.command({
        'op': 'move_slide',
        'deck': deck,
        'slide_id': newId,
        'to_index': i + 1
      });
      if (move['ok'] == true && move['deck'] is Map) deck = move['deck'] as Map;
    }
    _mutate(deck);
    _gotoSlide((i + 1).clamp(0, _slides.length - 1));
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
      _gotoSlide(target);
    }
  }

  void _deleteAt(int i) {
    if (i < 0 || i >= _slides.length) return;
    final slide = _slides[i];
    final r = Bridge.command(
        {'op': 'delete_slide', 'deck': _deck, 'slide_id': slide['id']});
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
              child: Text('Slide ${i + 1} of ${_slides.length}',
                  style: Theme.of(context).textTheme.titleMedium),
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
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'del'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'edit':
        _gotoSlide(i);
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
    final r =
        Bridge.command({'op': 'apply_dna', 'deck': _deck, 'change': choice});
    if (r['ok'] == true && r['deck'] is Map) _mutate(r['deck'] as Map);
  }

  // ---- the Files drawer's deck-level tools --------------------------------------

  /// The deck's declared frame aspect ("16:9" for every deck that predates
  /// the field — the engine defaults the same way, so app and engine agree
  /// without a round-trip).
  String get _deckAspect => (_deck['aspect'] ?? '16:9').toString();

  /// **New** — a fresh deck in its own file, never over the active one.
  /// Blank starts with zero slides; Template asks for a design family and
  /// the engine composes the deck in that DNA. Either way the result is a
  /// new deck id under its own file, and the editor hands over to it.
  Future<void> _filesNewDeck() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('New deck',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.note_add, color: kPurple),
              title: const Text('Blank'),
              subtitle: const Text('Starts empty — no template content'),
              onTap: () => Navigator.pop(context, 'blank'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: kPurple),
              title: const Text('Template'),
              subtitle: const Text('A design family composes the deck'),
              onTap: () => Navigator.pop(context, 'template'),
            ),
          ],
        ),
      ),
    );
    if (kind == null) return;

    final title = await dreamInputDialog(
      context,
      title: kind == 'blank' ? 'New blank deck' : 'New deck from a template',
      hint: 'Deck name',
      confirmLabel: 'Create',
    );
    if (title == null || title.trim().isEmpty) return;

    var family = 'swiss_editorial';
    if (kind == 'template') {
      final fam = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Design family',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final (id, label) in _designFamilies)
                ListTile(
                  leading: const Icon(Icons.palette, color: kPurple),
                  title: Text(label),
                  onTap: () => Navigator.pop(context, id),
                ),
            ],
          ),
        ),
      );
      if (fam == null) return;
      family = fam;
    }

    final r = Bridge.command({
      'op': 'new_deck',
      'title': title.trim(),
      'family': family,
      'blank': kind == 'blank',
    });
    if (r['ok'] != true || r['deck'] is! Map) {
      _toast('Could not create the deck: ${r['error'] ?? 'engine error'}');
      return;
    }
    final deck = Map<String, dynamic>.from(r['deck'] as Map);
    // The active deck's file is never touched: the new deck saves under its
    // own engine-issued id, and storage trouble here is never silent.
    try {
      final store = await DeckStore.open();
      await store.save(deck);
    } catch (e) {
      print('[deck-store] new deck could not be written: $e');
      _toast('Deck created, but storage is not answering — it will retry '
          'on the next save.');
    }
    if (!mounted) return;
    await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => EditorScreen(deck: deck)));
  }

  /// **Open** — Recents (the decks on this device, newest first) or Browse
  /// Files (the platform document browser). The app opens DreamTX deck
  /// files (.json) — .pptx import is not supported and is not offered.
  Future<void> _filesOpenDeck() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Open a deck',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.history, color: kPurple),
              title: const Text('Recents'),
              subtitle: const Text('Decks saved on this device'),
              onTap: () => Navigator.pop(context, 'recents'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: kPurple),
              title: const Text('Browse files'),
              subtitle: const Text('DreamTX deck (.json) — .pptx import isn\u2019t supported'),
              onTap: () => Navigator.pop(context, 'browse'),
            ),
          ],
        ),
      ),
    );
    if (kind == 'recents') {
      await _openRecentDeck();
    } else if (kind == 'browse') {
      await _browseForDeck();
    }
  }

  Future<void> _openRecentDeck() async {
    List<Map<String, dynamic>> decks;
    try {
      final store = await DeckStore.open();
      decks = (await store.scan()).decks;
    } catch (e) {
      print('[deck-store] recents failed: $e');
      _toast('Storage is not answering — try again in a moment.');
      return;
    }
    final currentId = _deck['id'].toString();
    final choice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Recents',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final d in decks)
                ListTile(
                  leading: const Icon(Icons.layers_outlined, color: kPurple),
                  title: Text((d['title'] ?? 'Untitled').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${((d['slides'] as List?) ?? []).length} slides · '
                    '${((d['dna'] ?? const {})['family'] ?? '').toString().replaceAll('_', ' ')}'
                    '${d['id'].toString() == currentId ? ' · this deck' : ''}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onTap: () => Navigator.pop(context, d),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => EditorScreen(
                deck: Map<String, dynamic>.from(choice))));
  }

  Future<void> _browseForDeck() async {
    // file_picker 13.x: pickFile() is the single-file entry point — a
    // PlatformFile, or null when the user dismisses the browser.
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = file?.path;
    if (path == null) return; // dismissed — nothing to do
    Map<String, dynamic>? deck;
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is Map<String, dynamic>) deck = decoded;
    } catch (_) {}
    if (deck == null ||
        (deck['slides'] is! List) ||
        (deck['dna'] is! Map && deck['dna'] == null)) {
      _toast('That file is not a DreamTX deck (.json) — nothing was opened.');
      return;
    }
    // Importing never overwrites: a colliding id gets a fresh one under its
    // own file, the original deck on this device stays untouched.
    final imported = Map<String, dynamic>.from(deck);
    final store = await DeckStore.open();
    final ids = (await store.scan()).decks.map((d) => d['id'].toString()).toSet();
    var id = imported['id'].toString();
    if (id.isEmpty || ids.contains(id)) {
      id = 'd${DateTime.now().millisecondsSinceEpoch}';
      imported['id'] = id;
    }
    try {
      await store.save(imported);
    } catch (e) {
      print('[deck-store] import could not be written: $e');
      _toast('Storage is not answering — the deck was not opened.');
      return;
    }
    if (!mounted) return;
    await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EditorScreen(deck: imported)));
  }

  /// **Aspect ratio** — the current ratio plus the supported presets. The
  /// change is applied to the deck (rendering AND export read the same
  /// field; the engine re-frames drawn objects), never just the preview —
  /// and when existing objects would move, that is stated up front and
  /// confirmed before anything happens.
  Future<void> _filesAspect() async {
    final current = _deckAspect;
    final meta = Bridge.command({'op': 'meta'});
    final aspects =
        ((meta['aspects'] as List?) ?? const ['16:9', '16:10', '4:3', '1:1'])
            .map((e) => e.toString())
            .toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Aspect ratio',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Current: $current · ${dimsLabel(current)}',
                      style: const TextStyle(fontSize: 12.5, color: kText2)),
                ],
              ),
            ),
            for (final a in aspects)
              ListTile(
                leading: Icon(
                  a == current ? Icons.check_circle : Icons.crop_free,
                  color: a == current ? kPurple : kText2,
                ),
                title: Text(a),
                subtitle: Text(dimsLabel(a),
                    style: const TextStyle(fontSize: 11.5)),
                onTap: () => Navigator.pop(context, a),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice == current) return;

    // Re-framing moves drawn objects: say so explicitly and get a yes first.
    final hasDrawn = _slides.any(
            (s) => ((s['objects'] as List?) ?? []).isNotEmpty) ||
        ((_deck['components'] as List?) ?? []).isNotEmpty;
    if (hasDrawn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => dreamDialog(
          title: Text('Re-frame to $choice?'),
          content: const Text(
              'Drawn objects keep their height and vertical position; their '
              'horizontal positions and widths scale to the new frame. '
              'Layouts re-flow for the new width. This applies to the deck '
              '— rendering and export both follow.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Keep $current')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Apply $choice')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final r = Bridge.command(
        {'op': 'set_aspect', 'deck': _deck, 'aspect': choice});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map); // persists + re-renders at the new frame
    } else {
      _toast('Could not change the aspect: ${r['error']}');
    }
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
      final file = File(
          '${dir.path}/${(_deck['title'] ?? 'deck').toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$ext');
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
    // Deck colors + the text boxes' slide-theme base track the deck version.
    _refreshPalette();
    final title = (_deck['title'] ?? 'Deck').toString();
    final family = ((_deck['dna'] ?? const {})['family'] ?? '')
        .toString()
        .replaceAll('_', ' ');
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
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2))
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
                PopupMenuItem(
                    value: 'presenting', child: Text('Presenting Mode')),
                // The modes are chrome states; Export is an action from a
                // different family — a real divider line keeps them apart.
                PopupMenuDivider(height: 12),
                PopupMenuItem(value: 'export', child: Text('Export')),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        // ---- THE LAYER CAKE --------------------------------------------------
        // The body is not one stacked flow but layers that cannot disturb
        // each other, in one stable stacking order: main slide → Files
        // sheet → filmstrip tray → bottom navbar. The base layer is the
        // editor's whole flow — canvas, contextual row, filmstrip chrome,
        // ribbon — and while the Files sheet is CLOSED the strip is simply
        // one more row in that flow. While the sheet is OPEN the cake
        // inverts: the sheet floats as its own layer pinned DIRECTLY to the
        // ribbon's top edge (a constant anchor — see [sheetAnchor]) and
        // SLIDES as a rigid body — in at full intended height from fully
        // below the navbar's top edge, out the same way — and the filmstrip
        // becomes a bottom-aligned FOREGROUND layer riding the sheet's
        // lower part, painted above it, stationary through the sheet's
        // whole lifecycle. The strip takes no layout space while the sheet
        // is open (the flow keeps a frozen spacer of its exact footprint),
        // so the sheet's height is the user's choice alone AND the slide
        // preview's constraints are frozen: opening or closing the sheet,
        // its animation progress, or toggling the strip can never push,
        // shrink, move, or recenter the sheet, the preview, or the ribbon.
        // The tray may cover the sheet's lower part, but it is
        // clip-constrained to the sheet's own live extent, so it can never
        // reach past the sheet's top edge into the slide preview; and the
        // whole moving sheet is clip-constrained to the navbar boundary, so
        // it can never paint over the navbar — the ribbon stays fixed in
        // front while the sheet rises behind it.
        body: LayoutBuilder(
          builder: (context, constraints) {
            final filesOpen =
                _mode == _Mode.editing && _navTab == _NavTab.files;
            // The Insert sheet: same layer, compact drawer. While the user
            // is TYPING into a text box the sheet stands down (the keyboard
            // owns the bottom of the screen and the typing toolbar rides it
            // in the root overlay) — the flow's spacer system keeps the
            // canvas's constraints frozen through that too.
            final insertOpen = _mode == _Mode.editing &&
                _navTab == _NavTab.insert &&
                !_typing;
            // The sheet's layer is alive while a sheet tab is active OR its
            // exit slide is still running — the unmount lands when that
            // slide completes (the AnimatedPositioned's onEnd below).
            final sheetOpen = filesOpen || insertOpen;
            final sheetLive = sheetOpen || _sheetClosing;
            // The strip's flow footprint at its CURRENT state — what the
            // spacer hands back to on close, and the fallback for a missing
            // freeze.
            final stripFlowHeight = _FilmstripDivider.regionHeight +
                (_filmOpen ? _filmstripBandHeight : 0.0);
            // The sheet's anchor: the ribbon's top edge, full stop. While
            // the sheet is open the ribbon's own top hairline always shows
            // (both the open tray and the collapsed divider sit directly on
            // it, and the tray keeps the same boundary it has in the flow),
            // so the band is a constant 77dp — which makes the anchor a
            // constant: toggling the filmstrip never moves the sheet, the
            // canvas, or the ribbon by a single pixel.
            const sheetAnchor = _navBarHeight + 1.0;
            // The space the sheet may occupy: everything above the ribbon
            // inside this body. From it, the two detents the header's drag
            // settles between — the resting HALF (floor 296 so the whole
            // 3×2 grid always fits, ceiling 430) and the TALL sheet
            // (~78%, leaving the slide's top sliver in view). The drag
            // handlers run between builds, so both are cached per build.
            final available =
                math.max(64.0, constraints.maxHeight - sheetAnchor);
            final half = math.min(
                math.min(430.0, math.max(296.0, available * 0.45)),
                available - 12.0);
            final tall =
                math.min(math.max(available * 0.78, half + 60.0), available - 12.0);
            _drawerHalf = half;
            _drawerTall = tall;
            // The strip overlay's own box: the strip's live height target —
            // the divider region plus the revealed band while open, just
            // the divider region while collapsed — capped at the sheet's
            // live extent. The cap is the whole "constrain the tray to the
            // available space" contract: mid-drag (both layers track the
            // finger at zero duration) and mid-grow-in/settle (both layers
            // run the same 200ms curve retargeted on the same rebuild) the
            // overlay's animated height stays at or under the sheet's
            // animated height, so the tray can never poke above the
            // sheet's top edge into the preview at any instant.
            final stripH = _filmOpen
                ? _FilmstripDivider.regionHeight + _filmstripBandHeight
                : _FilmstripDivider.regionHeight;
            final sheetHeight = _sheetLiveHeightFor(filesOpen);
            final overlayH = math.min(stripH, sheetHeight);
            return Stack(
              children: [
                // The base layer: the editor's whole flow. While the Files
                // sheet is open the filmstrip is NOT in this flow (it is the
                // foreground overlay above the sheet — see the layer cake
                // below), which is what keeps the canvas's geometry and the
                // sheet's anchor completely independent of the strip's
                // state. (The children below keep their historical
                // indentation on purpose — only the strip's placement
                // became conditional.)
                Column(
          children: [
            // ---- canvas ----------------------------------------------------------
            Expanded(
              child: _layout == null
                  ? const Center(
                      child: Text('No slide here yet — add one below.'))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Stack(
                        children: [
                          Center(
                            child: AspectRatio(
                              // The deck's true frame ratio — 16:9 for every
                              // existing deck, and whatever the Files drawer's
                              // Aspect tool has since applied.
                              aspectRatio: aspectRatioOf(_deck['aspect']?.toString()),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      SlideCanvas(
                                          layout: _layout!,
                                          onTextTap: _designMode ||
                                                  _mode == _Mode.viewing
                                              ? null
                                              : _editText),
                                      // Content objects (text boxes, images,
                                      // icons, media, tables) render as
                                      // CONTENT under the geometry layer.
                                      ObjectContentLayer(
                                        objects: _objects,
                                        designW: _designDims.$1,
                                        designH: _designDims.$2,
                                        baseColor: _baseTextColor,
                                        baseFamily: _baseTextFamily,
                                        baseFontSize: kTextBoxBaseSize,
                                        resolveResourcePath:
                                            _resolveResourcePath,
                                      ),
                                      ShapesLayer(
                                        objects: _objects,
                                        selectedId: _selectedObjectId,
                                        interactive: _designMode,
                                        scribbleMode: _scribbleMode,
                                        designW: _designDims.$1,
                                        designH: _designDims.$2,
                                        onSelect: _onObjectSelected,
                                        onLive: _liveObject,
                                        onCommit: _commitObject,
                                        onGestureStart: _objectGestureStart,
                                        onScribble: _onScribbleDone,
                                      ),
                                      // The typing state's WYSIWYG field —
                                      // mounted only while the selected text
                                      // box is focused.
                                      if (_typing &&
                                          _textSession != null &&
                                          _selectedObject != null)
                                        TextEditFieldLayer(
                                          obj: _selectedObject!,
                                          controller:
                                              _textSession!.controller,
                                          focusNode: _textSession!.focus,
                                          designW: _designDims.$1,
                                          designH: _designDims.$2,
                                          baseColor: _baseTextColor,
                                          baseFamily: _baseTextFamily,
                                          baseFontSize: kTextBoxBaseSize,
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
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
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: kText2),
                              ),
                            ),
                          ),
                          if (_warnings.isNotEmpty)
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: Chip(
                                avatar: const Icon(Icons.warning_amber_outlined,
                                    size: 18),
                                label: Text(_warnings.first,
                                    overflow: TextOverflow.ellipsis),
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
                                  icon: const Icon(Icons.chevron_left,
                                      size: 30, color: kText2),
                                  onPressed:
                                      _index > 0 ? () => _step(-1) : null,
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
                                  icon: const Icon(Icons.chevron_right,
                                      size: 30, color: kText2),
                                  onPressed:
                                      _index < n - 1 ? () => _step(1) : null,
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
              // Tabs with no tools yet (transitions / animations / help)
              // skip the band entirely; Files and Insert live in their docked
              // drawers instead of a contextual row — the canvas keeps the
              // space until their toolboxes get spec'd.
              if (_navTab != null &&
                  _navTab != _NavTab.files &&
                  _navTab != _NavTab.insert &&
                  _navTab != _NavTab.transitions &&
                  _navTab != _NavTab.animations &&
                  _navTab != _NavTab.help)
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
              // The strip unit — the boundary divider plus the reveal, built
              // once by [_filmstripUnit] — lives in the flow ONLY while the
              // Files sheet is closed: canvas above, ribbon below, and the
              // canvas reclaims the 104dp when the band folds. While the
              // sheet (or its exit slide) is live the SAME subtree is the
              // bottom-aligned foreground layer over the sheet's lower part
              // (see the layer cake below), so it takes no layout space
              // here — the frozen spacer below holds its exact footprint —
              // which is what keeps the sheet, the slide preview, and the
              // ribbon immune to the strip's state. The move between the
              // two slots happens under the reveal's reparent GlobalKey,
              // so the rail's scroll offset and selection survive every
              // Files open/close.
              if (!sheetLive)
                _filmstripUnit(context)
              else
                // The frozen footprint: an EMPTY spacer of exactly the
                // height the strip occupied in the flow when Files opened
                // (frozen — never tracking the tray's toggles, so the slide
                // preview's constraints cannot move while the sheet is
                // open). On close it animates to the strip's current
                // footprint over the same 200ms family, handing the space
                // back as the strip returns to the flow — a continuous
                // handoff, never a jump. Instant under reduced motion.
                AnimatedContainer(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeInOutCubic,
                  height: sheetOpen
                      ? (_frozenStripFootprint ?? stripFlowHeight)
                      : stripFlowHeight,
                ),

              // ---- PowerPoint-style ribbon ----------------------------------------
              _EditorNavBar(
                  active: _navTab,
                  controller: _navScroll,
                  onSelect: _onNavSelect,
                  // The ribbon's top hairline separates whatever sits directly
                  // on it from the band. In the flow that is the strip's
                  // business: the divider's own rule is the boundary while
                  // collapsed (showing this too would double the line), and
                  // the open band rides the hairline. While the Files sheet
                  // is open the hairline ALWAYS shows — the overlay's tray
                  // and collapsed divider both sit directly on it, and a
                  // constant band keeps the sheet's anchor, the canvas, and
                  // the ribbon itself frozen through every tray toggle.
                  showTopRule: filesOpen || _filmOpen),
            ],
          ],
                ),
                // The sheet + overlay layers, grouped behind ONE semantics
                // boundary ([Semantics] with container: true): the filmstrip
                // overlay's BlockSemantics drops the semantics of everything
                // painted before it BELOW that boundary — the covered part of
                // the sheet — while the base layer (ribbon included, painted
                // before the boundary but OUTSIDE it) keeps its accessibility
                // contract: the Files tab stays reachable, the top bar stays
                // reachable, and the tray's own semantics stay live.
                if (sheetLive)
                  Semantics(
                    container: true,
                    // The slide's hard boundary: the sheet may translate
                    // below the navbar's top edge while entering or leaving,
                    // but it may never PAINT there — the clip keeps the
                    // navbar fixed in front of the moving layer, and
                    // hit-testing follows the same rect, so the hidden part
                    // of the sheet is untappable at every instant of the
                    // slide. (The tray's own box ends exactly at this edge,
                    // so it is untouched by the clip.)
                    child: ClipRect(
                      clipper: _SheetPortalClipper(boundary: sheetAnchor),
                      child: Stack(
                      children: [
                        // ---- the drawer layer -------------------------------------
                        // The Files sheet floats ABOVE the canvas and rides the
                        // RIBBON's top edge (bottom offset = the constant
                        // sheetAnchor), so the filmstrip's state can never
                        // move it: the strip is not in the flow beneath it —
                        // the sheet's own kSurface fills the whole region down
                        // to the ribbon, and the tray overlays it in front
                        // (the layer above) with no spacer of any kind in
                        // between. THE ENTRANCE/EXIT: the sheet is laid out at
                        // its full intended height and translated as a rigid
                        // body — arriving, its top edge starts exactly at the
                        // navbar's top edge (fully below it) and slides up
                        // into view; leaving, the same motion runs in reverse.
                        // The origin is the navbar's edge alone, never the
                        // filmstrip's. While the header's drag is live the
                        // duration is zero (the edge tracks the finger
                        // exactly); every slide runs the same 200ms eased
                        // family as the filmstrip's own reveal — instant under
                        // reduced motion. The slide's ClipRect (above) keeps
                        // the navbar fixed in front of the moving layer.
                        AnimatedPositioned(
                          duration: _drawerDragging
                              ? Duration.zero
                              : (MediaQuery.of(context).disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200)),
                          curve: Curves.easeInOutCubic,
                          left: 0,
                          right: 0,
                          // In place (open, dragging, settled) the sheet's
                          // bottom sits on the anchor; entering or closing, it
                          // is translated fully below the navbar's top edge —
                          // bottom = anchor minus the sheet's own height, so
                          // its top edge lands exactly on the boundary.
                          // AnimatedPositioned retargets from its live value,
                          // so interrupted or reversed slides continue from
                          // the current visible position, never resetting.
                          bottom: (_sheetEntering || _sheetClosing)
                              ? sheetAnchor - sheetHeight
                              : sheetAnchor,
                          height: sheetHeight,
                          // The exit slide's bookend: when the translation
                          // completes the layer unmounts at its slot (a
                          // tab's chrome appears and disappears there).
                          onEnd: () {
                            if (!mounted ||
                                !_sheetClosing ||
                                _isSheetTab(_navTab)) {
                              return;
                            }
                            setState(() {
                              _sheetClosing = false;
                              _sheetEntering = false;
                              _drawerExtent = null;
                            });
                          },
                          // The sheet's CONTENT: the Files drawer or the
                          // Insert drawer — same layer, same lifecycle, same
                          // clip; switching between the two sheet tabs swaps
                          // the surface without unmounting the layer, and the
                          // exit slide keeps the surface it is animating out.
                          child: _lastSheetTab == _NavTab.insert
                              ? InsertSheet(
                                  bottomInset: _FilmstripDivider.regionHeight +
                                      _filmstripBandHeight,
                                  selectedObject: _selectedObject,
                                  textController: _selectedObject != null &&
                                          ObjectContent.isText(_selectedObject!)
                                      ? _textSession?.controller
                                      : null,
                                  textActions: _textActions,
                                  deckPalette: _deckPalette,
                                  onInsertTextBox: _insertTextBox,
                                  onPickImage: _pickImage,
                                  onPickShape: _addObject,
                                  onInsertTable: _insertTable,
                                  onInsertIcon: _insertIcon,
                                  onPickMedia: _pickMedia,
                                  onObjectStyle: _liveObjectEdit,
                                  onTableCell: _editTableCell,
                                  onShowLayers: _showLayers,
                                  onEditStyleSheet: _editSelectedObjectStyle,
                                  onStartTyping: _beginTyping,
                                )
                              : FilesDrawer(
                                  aspect: _deckAspect,
                                  deckId: (_deck['id'] ?? '').toString(),
                                  onNew: _filesNewDeck,
                                  onOpen: _filesOpenDeck,
                                  onRename: _renameDeck,
                                  onAspect: _filesAspect,
                                  onDismiss: () => _setNavTab(null),
                                  // The overlay clearance: the tray (divider
                                  // region + band) rides the sheet's lower part,
                                  // so the grid's scrollable carries this as
                                  // bottom padding — the last row can always be
                                  // scrolled fully above the tray, including its
                                  // raised handle. Scroll content, never chrome:
                                  // the sheet's outer height is the detents' alone.
                                  bottomInset: _FilmstripDivider.regionHeight +
                                      _filmstripBandHeight,
                                  onDragUpdate: _drawerDragUpdate,
                                  onDragSettle: _drawerDragSettle,
                                ),
                        ),
                        // ---- the filmstrip overlay layer --------------------------
                        // The tray is a FOREGROUND layer over the sheet's lower
                        // part: the SAME strip unit that lives in the flow
                        // while the sheet is closed (reparented here under
                        // its GlobalKey — scroll and selection survive), now
                        // painted above the sheet. The tray is STATIONARY
                        // through the sheet's whole lifecycle — mounted,
                        // expanded, and already in place from the sheet's
                        // first frame, so the sheet's entrance rises behind
                        // it without flashing, jumping, or briefly covering
                        // the thumbnails (and the exit slide leaves the same
                        // way). The box tracks the sheet's
                        // own live extent (min(stripH, extent), the same
                        // duration/curve as the sheet's layer, retargeted on
                        // the same rebuild — while dragging both are
                        // zero-duration), and the ClipRect clips BOTH paint
                        // and hit-testing to it, so the tray may cover the
                        // sheet but can never reach past the sheet's top edge
                        // into the slide preview, and nothing above the box's
                        // top ever falls through to the sheet underneath.
                        // Inside the clip the OverflowBox lets the strip lay
                        // out at its NATURAL height (divider + the revealed
                        // band, bottom-anchored so the tray always rides the
                        // ribbon), so the reveal's own 200ms fold works
                        // verbatim with no reflow: the box and the strip
                        // retarget on the same frame and share one curve, so
                        // they stay in lockstep through every toggle. The hit
                        // wall behind the strip makes the covered tools inert:
                        // taps on the tray's background or the collapsed
                        // divider's empty zone land on the wall (opaque, no
                        // action) instead of the tools underneath, and the
                        // BlockSemantics around the whole overlay keeps those
                        // covered tools out of the accessibility tree while
                        // the tray is open. (The block rides INSIDE the
                        // positioned box — a Positioned cannot be wrapped by a
                        // render-owning widget on its way to the Stack.)
                        if (_mode == _Mode.editing)
                          AnimatedPositioned(
                          duration: _drawerDragging
                              ? Duration.zero
                              : (MediaQuery.of(context).disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200)),
                          curve: Curves.easeInOutCubic,
                          left: 0,
                          right: 0,
                          bottom: sheetAnchor,
                          height: overlayH,
                          child: BlockSemantics(
                            blocking: _filmOpen,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.bottomCenter,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: Stack(
                                  children: [
                                    // The hit wall: exactly the strip's own
                                    // live footprint (the Stack sizes to the
                                    // strip unit; the wall fills it) — a
                                    // deliberately inert opaque region. Taps
                                    // that miss every real control (the
                                    // chevron pocket, the rail, the disc)
                                    // stop here instead of triggering the
                                    // sheet's tools underneath.
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {},
                                      ),
                                    ),
                                    _filmstripUnit(context),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- the filmstrip unit (one subtree, two slots) -----------------------------

  /// The strip unit: the boundary divider plus the reveal, as ONE subtree —
  /// identical in both of its slots. While the Files sheet is closed it is a
  /// row in the editor's flow (canvas above, ribbon below); while the sheet
  /// is open it is the bottom-aligned foreground layer over the sheet's
  /// lower part. The reveal's outer [KeyedSubtree] carries the reparent
  /// GlobalKey ([_filmstripRevealHost]), so the unit's moves between the two
  /// slots preserve the rail's scroll offset and the selection — the element
  /// is reparented, never remounted.
  ///
  /// The strip's boundary is the toggle itself: one continuous rule drawn by
  /// [_FilmstripDivider] directly above the band — flat across the editor,
  /// then near the right edge a ramp up into a short ledge that runs flush
  /// to the edge, with the chevron centered in the pocket under the ledge.
  /// Collapsed, the same rule carries an up chevron in the cool light
  /// neutral; open, the stroke wears the signature sweep — the same purple
  /// → magenta → orange stops as the + disc (kInkGradient's own colors),
  /// run left → right along the boundary so the line warms from quiet
  /// purple to orange exactly at the ramp and ledge, and the chevron
  /// repeats the disc's diagonal gradient over its glyph — the user's
  /// verdict after two single-color tries was that only the disc's own
  /// gradient reads on-theme. And the band itself is a real panel: one
  /// continuous kFilmstrip charcoal fill (a dedicated token — a step
  /// lighter than the black workspace, a shade darker than the nav's
  /// kSurface) runs the full width of the expanded strip behind
  /// everything, so the strip reads as its own surface instead of melting
  /// into the black canvas — flat fill only, no border, no shadow, no left
  /// fade, and the divider still draws the boundary above it.
  ///
  /// The reveal: the band itself never unmounts — it stays laid out at the
  /// full 104dp inside a top-anchored Align/ClipRect pair (Align's
  /// heightFactor drives the reveal height; the clip carries the same
  /// boundary to hit-testing) that collapses paint and taps down to nothing
  /// when collapsed (and ExcludeSemantics pulls it out of the a11y tree).
  /// That is what preserves the scroll offset and the selected slide
  /// across every fold/unfold — and, in the overlay slot, across every
  /// Files open/close — and one 200ms eased height transition, instant
  /// under reduced-motion, is the single coordinated move.
  Widget _filmstripUnit(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilmstripDivider(
            expanded: _filmOpen,
            onToggle: _toggleFilmstrip,
          ),
          KeyedSubtree(
            key: _filmstripRevealHost,
            child: KeyedSubtree(
              key: const ValueKey('filmstrip_reveal'),
              child: ExcludeSemantics(
                key: const ValueKey('filmstrip_strip_semantics'),
                excluding: !_filmOpen,
                child: TweenAnimationBuilder<double>(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeInOutCubic,
                  tween: Tween<double>(begin: 1.0, end: _filmOpen ? 1.0 : 0.0),
                  builder: (context, v, child) => ClipRect(
                    // Top-anchored: the band folds UP under the divider's
                    // baseline — its bottom edge rises to meet the rule —
                    // and drops back down on unfold. Align's heightFactor
                    // drives the reveal height; the clip carries the same
                    // boundary to hit-testing, so the hidden band cannot
                    // be tapped.
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: v,
                      child: child,
                    ),
                  ),
                  child: SizedBox(
                    key: const ValueKey('filmstrip_row'),
                    height: _filmstripBandHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // The panel fill: one continuous charcoal surface
                        // behind the whole expanded band — full width,
                        // behind the + disc, behind the thumbnails, in every
                        // gap and edge. It lives INSIDE the reveal's clip, so
                        // it appears and folds with the row itself: nothing
                        // lingers or flashes during the 200ms transition, and
                        // collapsed the clip takes the fill to zero height —
                        // no colored strip left above the navigation. Flat
                        // kFilmstrip only (dedicated token, between the
                        // black workspace and the nav's kSurface): no
                        // border, no shadow, no gradient — the divider above
                        // stays the only boundary. The fill's top edge meets
                        // the divider's 2dp stroke guard under its baseline,
                        // so the gradient rule reads as lying directly on the
                        // panel's top edge; everything ON the fill — white
                        // cards, selection ring, disc — keeps its own colors.
                        const Positioned.fill(
                          child: ColoredBox(color: kFilmstrip),
                        ),
                        // The rail: full width, slides only. The leading
                        // inset puts slide 0 at the exact resting spot it
                        // has always had since 2.15 (first card at 74dp, a
                        // 16dp gap from the disc's right edge), its border
                        // and rounded corners fully visible. The trailing
                        // inset is the plain 4dp again — nothing reserves
                        // the rail's end zone anymore (the old end chevron
                        // is gone; the toggle lives in the divider above).
                        ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(68, 6, 4, 6),
                          itemCount: _slides.length,
                          itemBuilder: (context, i) {
                            final selected = i == _index;
                            final label = _slideTitle(_slides[i]);
                            return Padding(
                              padding: const EdgeInsets.all(6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _gotoSlide(i),
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Text(
                                          '${i + 1}. $label',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF17181A),
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // The floating +: the signature gradient disc, at its
                        // home spot and size — 14dp from the strip's left edge,
                        // vertically centered (top 30 of the 104dp band), 44dp
                        // across, original soft shadow. Painted LAST, over the
                        // rail and the panel fill: the slides it passes over
                        // are seen behind it, and nothing clips it — the +
                        // still reads as a floating button, now riding the
                        // charcoal panel instead of the bare black canvas.
                        // Tap adds a blank slide; long-press opens the
                        // layout list.
                        Positioned(
                          left: 14,
                          top: 30,
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
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.add,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  // ---- ribbon wiring ---------------------------------------------------------

  /// The strip's live flow footprint: the divider region plus the reveal's
  /// CURRENT height — read off the mounted reveal (works in both of the
  /// unit's slots, the box under the reparent GlobalKey being the same
  /// subtree), so a fold caught mid-flight reports its real on-screen
  /// height, not its target. This is what gets frozen when Files opens and
  /// what the spacer hands back to on close.
  double _liveStripFlowHeight() {
    final revealH = _filmstripRevealHost.currentContext?.size?.height ??
        (_filmOpen ? _filmstripBandHeight : 0.0);
    return _FilmstripDivider.regionHeight + revealH;
  }

  /// The one toggle behind the integrated edge handle: the strip band folds
  /// up under the divider (the canvas reclaims the 104dp) and unfolds back.
  /// Selection, scroll offset, and the ribbon's own tab state are all kept —
  /// nothing here touches them.
  void _toggleFilmstrip() {
    setState(() => _filmOpen = !_filmOpen);
  }

  // ---- the Files drawer's layer ---------------------------------------------

  /// A live drag on the drawer's header: the sheet's top edge follows the
  /// finger — down shrinks, up grows — clamped between the header sliver
  /// (the pinned handle always fits) and the tall detent. While the drag is
  /// live the sheet tracks the finger exactly (the layer's duration is zero
  /// mid-drag), so the settle below is where the detents do their work.
  void _drawerDragUpdate(double dy) {
    // The entrance/exit slide owns the layer's translation — a drag that
    // lands mid-slide is dead until the sheet is in place.
    if (_sheetEntering || _sheetClosing) return;
    final base = _drawerExtent ?? _drawerHalf;
    final floor = math.min(_drawerSliver, _drawerTall);
    setState(() {
      _drawerDragging = true;
      _drawerExtent = (base - dy).clamp(floor, _drawerTall).toDouble();
    });
  }

  /// The drag's settle: a fling moves one detent in its direction; a plain
  /// release snaps to the NEAREST detent — with a dismiss zone below ~70%
  /// of the half detent where the sheet closes outright instead of snapping
  /// back up.
  void _drawerDragSettle(double velocityDy) {
    // No drag can be in flight while a slide owns the layer.
    if (_sheetEntering || _sheetClosing) return;
    final extent = _drawerExtent ?? _drawerHalf;
    if (velocityDy > 700) {
      // Fling down: tall → half, half-or-lower → dismissed.
      if (extent > _drawerTall - 24) {
        _snapDrawer(_drawerHalf);
      } else {
        _setNavTab(null);
      }
      return;
    }
    if (velocityDy < -700) {
      // Fling up: below half → half, half-or-above → tall.
      _snapDrawer(extent < _drawerHalf - 24 ? _drawerHalf : _drawerTall);
      return;
    }
    if (extent < _drawerHalf * 0.7) {
      _setNavTab(null); // the dismiss zone: gone, cleanly, at its slot
      return;
    }
    _snapDrawer((extent - _drawerHalf).abs() <= (extent - _drawerTall).abs()
        ? _drawerHalf
        : _drawerTall);
  }

  /// Snap to a detent: the settle animates over the 200ms family (the drag
  /// itself was tracking the finger directly, no rubber-banding — the
  /// detents stay honest).
  void _snapDrawer(double target) {
    setState(() {
      _drawerDragging = false;
      _drawerExtent = target;
    });
  }

  void _onNavSelect(_NavTab tab) {
    _setNavTab(
        _navTab == tab ? null : tab); // tap the active tab again to collapse
  }

  /// The contextual action row for the active ribbon tab — the selected
  /// tool swaps in a compact toolbar right under the canvas, above the
  /// filmstrip "timeline". Tabs without tools yet render nothing (their
  /// band is skipped in build); the filler hint texts are gone by request.
  Widget _contextualRow() {
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
          ],
        );
      case _NavTab.files:
        // The Files tab's tools live in the docked drawer that replaces this
        // band (see build) — the row itself never renders for Files.
        return const SizedBox.shrink();
      case _NavTab.insert:
        // Insert is where things get ADDED to the slide — its compact drawer
        // (the same sheet layer as Files) replaces this band.
        return const SizedBox.shrink();
      case _NavTab.draw:
        return Row(
          children: [
            IconButton(
              tooltip: 'Freehand draw',
              icon: Icon(Icons.gesture, color: _scribbleMode ? kText : kText2),
              onPressed: () => setState(() => _scribbleMode = !_scribbleMode),
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
                child: _DesignChip(
                    label: label,
                    selected: id == current,
                    onTap: () => _applyDesign(id)),
              ),
            IconButton(
              tooltip: 'New variant of this design',
              icon: const Icon(Icons.shuffle),
              onPressed: () => _applyDesign('next_variant'),
            ),
          ],
        );
      case _NavTab.transitions:
        return const SizedBox.shrink();
      case _NavTab.animations:
        return const SizedBox.shrink();
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
          ],
        );
      case _NavTab.help:
        return const SizedBox.shrink();
    }
  }

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
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Comments',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (_comments.isEmpty)
                  const SizedBox(
                    height: 120,
                    child: Center(
                        child: Text('No comments yet — leave the first one.',
                            style: _rowHint)),
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
                            leading: const Icon(Icons.person_outline,
                                size: 20, color: kText2),
                            title: Text(c['text'] ?? ''),
                            subtitle: const Text('You · just now'),
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 1, color: kHairline),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              child: Text('Export deck',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          Navigator.pop(context);
                          _export('export_pptx');
                        },
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
                  onPressed: _busy
                      ? null
                      : () {
                          Navigator.pop(context);
                          _export('export_pdf');
                        },
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
/// The filmstrip's boundary rule and its built-in edge handle.
///
/// One continuous rule runs the editor's full width directly above the strip
/// band — or, when the strip is collapsed, directly above the ribbon. Near
/// the right edge it ramps up into a short horizontal ledge that runs flush
/// to the screen edge, and the chevron sits centered in the pocket under
/// that ledge: a toggle built into the boundary itself — no detached
/// floating button, no rectangular outline. The drawn tab keeps one
/// silhouette in both states; the state reads three ways (chevron direction,
/// the line's color, the a11y label), with color reinforcing but never
/// carrying the state alone:
///
/// * collapsed — a cool light neutral rule (kText2) and an up chevron;
/// * expanded — the signature gradient sweep and a down chevron that is a
///   miniature of the + disc's own gradient.
///
/// The accent took three rounds to settle by the user's eye: a warm red
/// (kAccent) read off-theme, and a flat single purple still read off — so
/// the open boundary now wears the exact three stops the + disc wears
/// (kPurple → kMagenta → kOrange): [ruleSweep] runs them left → right
/// along the rule (quiet purple along the flat baseline, warming through
/// magenta, arriving at orange exactly where the ramp lifts into the
/// ledge), and the chevron glyph repeats the disc's own diagonal
/// kInkGradient through a srcIn ShaderMask. The collapsed state stays the
/// cool neutral — the boundary earns the signature colors only while the
/// strip is worth looking at — and kAccent stays reserved for
/// destructive/live semantics.
///
/// The rule is drawn by [_FilmstripDividerPainter] from the same geometry
/// constants that place the handle, so the chevron is always optically
/// centered in the pocket at every width — the numbers are right-edge
/// relative, which keeps the handle right-aligned on any screen.
///
/// The tap target is a reserved 48 × 48 box at the right edge while the drawn
/// tab itself stays ~30dp tall. The hit box lives entirely inside the 48dp
/// header region — it never overlaps the canvas, the thumbnail row, or the
/// ribbon, and the decorative painting below it never claims taps.
class _FilmstripDivider extends StatelessWidget {
  const _FilmstripDivider({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  // ---- shared geometry (logical px, right-edge relative) ---------------------
  //
  //   0 ........................ W-92   W-70 ................. W
  //   ───────────────────────────╱──────── ledge, y = 18 ─────┐ edge
  //   baseline, y = 46         ╱        ^ chevron (20dp)      │
  //
  /// The compact header region — exactly the 48dp hit target's height.
  static const double regionHeight = 48;

  /// The raised ledge: 28dp above the baseline (the spec's 24–30 rise).
  static const double ledgeY = 18;

  /// The flat rule — 2dp in from the region's bottom so the stroke never
  /// bleeds into the strip/ribbon below; it sits directly above both.
  static const double baselineY = 46;

  /// The ramp starts this far from the right edge.
  static const double rampFromRight = 92;

  /// ...and climbs the full rise over these many horizontal pixels.
  static const double rampRun = 22;

  static const double chevronSize = 20;

  /// The reserved tap target. The drawn tab stays ~30dp tall.
  static const double hitSize = 48;

  static const double stroke = 1.8;

  /// The open rule's sweep — the signature family's three stops run flat
  /// along the boundary: quiet purple at the left edge, warming through
  /// magenta, arriving at orange exactly where the ramp lifts into the
  /// ledge and the chevron sits. Same three stops as the + disc's
  /// kInkGradient, laid out horizontally for a wide thin rule.
  static const LinearGradient ruleSweep = LinearGradient(
    colors: [kPurple, kMagenta, kOrange],
  );

  @override
  Widget build(BuildContext context) {
    final String label = expanded ? 'Collapse slides' : 'Expand slides';
    // Chevron center: horizontally the middle of the flat ledge (the ledge
    // spans the last rampFromRight - rampRun = 70dp), vertically the optical
    // middle of the pocket between ledge and baseline — both expressed as
    // padding inside the 48×48 hit box at the right edge.
    const double chevronLeft =
        hitSize - (rampFromRight - rampRun) / 2 - chevronSize / 2;
    const double chevronTop =
        (ledgeY + baselineY) / 2 - chevronSize / 2;
    return SizedBox(
      height: regionHeight,
      child: Stack(
        children: [
          // The rule: one continuous baseline → ramp → ledge. Decorative
          // painting only — no child, so it can never capture a tap. Open,
          // the stroke carries the signature sweep; collapsed, the same
          // path wears the cool light neutral.
          Positioned.fill(
            child: CustomPaint(
              key: const ValueKey('filmstrip_divider'),
              painter: _FilmstripDividerPainter(
                color: kText2,
                sweep: expanded ? ruleSweep : null,
              ),
            ),
          ),
          // The handle: the whole reserved 48×48 at the right edge toggles,
          // carrying the chevron centered in its pocket. The tooltip serves
          // long-press/hover discovery; the Semantics node carries the action
          // (and exposes the expanded state) for assistive tech.
          Positioned(
            right: 0,
            top: 0,
            child: SizedBox(
              key: const ValueKey('filmstrip_handle'),
              width: hitSize,
              height: hitSize,
              child: Semantics(
                button: true,
                label: label,
                value: expanded ? 'expanded' : 'collapsed',
                onTap: onToggle,
                child: Tooltip(
                  message: label,
                  excludeFromSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          chevronLeft, chevronTop, 0, 0),
                      // Open, the chevron is a miniature of the + disc: the
                      // disc's own diagonal kInkGradient applied to the glyph
                      // through a srcIn ShaderMask (the white base supplies
                      // only the alpha the shader fills). Collapsed it stays
                      // the cool light neutral.
                      child: expanded
                          ? ShaderMask(
                              shaderCallback: kInkGradient.createShader,
                              blendMode: BlendMode.srcIn,
                              child: const Icon(
                                Icons.keyboard_arrow_down,
                                size: chevronSize,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.keyboard_arrow_up,
                              size: chevronSize,
                              color: kText2,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the filmstrip's boundary: the flat baseline from the editor's left
/// edge (no side padding), the ramp up near the right edge, and the ledge
/// running flush to the right edge — one path, one stroke, rounded joins.
///
/// Beneath that same geometry the painter first fills the tray's SILHOUETTE
/// with the tray's own charcoal (kFilmstrip): the full-width strip from the
/// baseline down to the region's floor, plus the raised tab above it — the
/// ramp's triangle and the ledge's pocket behind the chevron. The fill and
/// the gradient stroke share one geometry, so there is no seam: the stroked
/// boundary lies exactly on the fill's top edge, and the charcoal runs
/// unbroken from the rule down into the band's own fill below the region.
/// Only the raised tab projects above the baseline — the fill never paints a
/// full-width rectangle above the line — so the divider keeps its transparent
/// window left of the ramp (whatever surface sits behind the tray shows
/// through there, by design), while the sloped ramp and the chevron's pocket
/// are fully opaque: the Files sheet's tiles can never show through the tab.
/// The chevron and the sweep ride on top of it all.
///
/// The stroke is the collapsed cool neutral ([color]) or, when the strip is
/// open, the signature [sweep]: its shader spans the path's own bounds, so
/// t maps purely to x — the three stops land the same at every width.
class _FilmstripDividerPainter extends CustomPainter {
  _FilmstripDividerPainter({required this.color, this.sweep});

  /// The collapsed stroke color.
  final Color color;

  /// The open stroke's gradient (kPurple → kMagenta → kOrange); null when
  /// collapsed.
  final LinearGradient? sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // The silhouette beneath the boundary path — the SAME geometry the
    // stroke below traces, closed down to the region's floor so the fill
    // and the stroke share one edge (no seam), and so the charcoal meets
    // the band's own fill flush at the region's bottom edge.
    final silhouette = Path()
      ..moveTo(0, _FilmstripDivider.baselineY)
      ..lineTo(
          w - _FilmstripDivider.rampFromRight, _FilmstripDivider.baselineY)
      ..lineTo(w - _FilmstripDivider.rampFromRight + _FilmstripDivider.rampRun,
          _FilmstripDivider.ledgeY)
      ..lineTo(w, _FilmstripDivider.ledgeY)
      ..lineTo(w, _FilmstripDivider.regionHeight)
      ..lineTo(0, _FilmstripDivider.regionHeight)
      ..close();
    canvas.drawPath(
        silhouette,
        Paint()
          ..color = kFilmstrip
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
    );
    final path = Path()
      ..moveTo(0, _FilmstripDivider.baselineY)
      ..lineTo(
          w - _FilmstripDivider.rampFromRight, _FilmstripDivider.baselineY)
      ..lineTo(w - _FilmstripDivider.rampFromRight + _FilmstripDivider.rampRun,
          _FilmstripDivider.ledgeY)
      ..lineTo(w, _FilmstripDivider.ledgeY);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _FilmstripDivider.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final sweep = this.sweep;
    if (sweep == null) {
      paint.color = color;
    } else {
      // The shader rect is the path's own bounds (ledge top → baseline):
      // over that rect the horizontal sweep maps t to x alone, so the left
      // edge is purple and the ramp/ledge zone arrives at orange at any
      // width or region height.
      paint.shader = sweep.createShader(Rect.fromLTWH(
          0,
          _FilmstripDivider.ledgeY,
          w,
          _FilmstripDivider.baselineY - _FilmstripDivider.ledgeY));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FilmstripDividerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sweep != sweep;
}

/// Clips the sheet's moving layer at the navbar's top boundary: while the
/// entrance or exit slide runs, the sheet is translated so that part of its
/// body sits below the navbar's top edge — but it may never PAINT (or
/// hit-test) there. The clip keeps the navbar fixed in front of the moving
/// layer and the sheet emerging continuously from behind it.
///
/// [boundary] is the navbar's top edge measured up from the clip box's
/// bottom (the same [sheetAnchor] the sheet rides) — a constant, so the clip
/// never moves; the tray's own box ends exactly at this edge and is
/// untouched by it.
class _SheetPortalClipper extends CustomClipper<Rect> {
  _SheetPortalClipper({required this.boundary});

  /// The navbar's top edge, as an inset from the clip box's bottom.
  final double boundary;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
      0, 0, size.width, math.max(0.0, size.height - boundary));

  @override
  bool shouldReclip(_SheetPortalClipper oldClipper) =>
      oldClipper.boundary != boundary;
}

class _EditorNavBar extends StatelessWidget {
  const _EditorNavBar(
      {required this.active,
      required this.controller,
      required this.onSelect,
      this.showTopRule = true});

  final _NavTab? active;
  final ScrollController controller;
  final void Function(_NavTab) onSelect;

  /// Whether to draw the ribbon's own top hairline. The integrated filmstrip
  /// divider already paints the boundary directly above the ribbon while the
  /// strip is collapsed; showing this rule too would double the line.
  final bool showTopRule;

  static const _icons = {
    _NavTab.ai: Icons.auto_awesome,
    _NavTab.files: Icons.folder,
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
    // The ONE stadium pill, shared across tabs: it glides to the active
    // slot (260ms ease-out) ONLY when switching between two open tabs; on
    // open/collapse it mounts/unmounts in place — no fade, no sweep, no
    // blink. Slot math: item pitch _navItemWidth, pill 58 wide, pill top =
    // item padding (6) + centered column gap (5).
    final double? slot = active == null
        ? null
        : _NavTab.values.indexOf(active!) * _navItemWidth +
            (_navItemWidth - 58) / 2;
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        // The hairline is a PAINT choice, never a layout one: the border's
        // 1dp inset exists in EVERY state (transparent while the filmstrip
        // divider's own rule owns the boundary) so the band's total height
        // is a constant 77dp — nothing above it (the canvas's constraints,
        // the sheet's anchor, the strip's flow spot) can ever move by the
        // hairline's own pixel when a tab or the tray toggles it.
        border: Border(
          top: BorderSide(
              color: showTopRule ? kHairline : Colors.transparent),
        ),
      ),
      // Material-3 NavigationBar anatomy, trimmed 80 -> 76dp because our
      // labels are single-line: a 24dp icon in a stadium pill, an 11sp label
      // under it, real vertical breathing room — and the ribbon melts into
      // the surface at both ends instead of hard-clipping half an icon.
      // (The 1dp border inset above brings the whole band to its constant
      // 77dp.)
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
                child: Stack(
                  children: [
                    // Behind the icons: the shared active pill. It mounts
                    // directly at its slot when the ribbon opens and
                    // unmounts on collapse — the only time it MOVES is a
                    // tab-to-tab switch (the glide). No fade, no sweep from
                    // the far-left edge: that was the blink.
                    if (slot != null)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        top: 11,
                        left: slot,
                        width: 58,
                        height: 34,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0x1FFFFFFF),
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      ),
                    Row(
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
        // No rectangular ripple: on the dark bar the default splash paints
        // as an unclipped WHITE SQUARE around the tap point, which reads as
        // a glitch next to the round pill. The active state is carried by
        // the shared gliding pill + color switch instead — no ink needed.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The icon slot exactly matches the shared pill's footprint
              // (58 x 34), so the gliding pill lands dead-center behind the
              // icon. Fixed label height pins the math (6 + 5 = pill top 11).
              SizedBox(
                width: 58,
                height: 34,
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 16,
                child: Center(
                  child: Text(
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
    final r = Bridge.command(
        {'op': 'get_layout', 'deck': widget.deck, 'slide_index': i});
    return r['ok'] == true && r['layout'] is Map
        ? (r['layout'] as Map).cast<String, dynamic>()
        : null;
  }

  void _go(int delta) {
    var target = _page + delta;
    if (target < 0) target = 0;
    if (target >= _slides.length) target = _slides.length - 1;
    if (target == _page) return;
    _pages.animateToPage(target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
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
                      ? const Center(
                          child: Text('Unable to render this slide',
                              style: TextStyle(color: kText2)))
                      : SlideCanvas(layout: layout),
                ),
              );
            },
          ),
          // Tap zones: right side advances, left side goes back — swipes still
          // work because tap recognizers never claim drags.
          Row(
            children: [
              Expanded(
                  child: GestureDetector(
                      onTap: () => _go(-1),
                      behavior: HitTestBehavior.translucent)),
              const SizedBox(width: 90),
              Expanded(
                  child: GestureDetector(
                      onTap: () => _go(1),
                      behavior: HitTestBehavior.translucent)),
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
  const _DesignChip(
      {required this.label, required this.selected, required this.onTap});

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
            border: Border.all(
                color: selected ? kMagenta : kHairline,
                width: selected ? 1.4 : 1),
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

// ---------------------------------------------------------------------------
// The Insert drawer's session + toolbar state adapters
// ---------------------------------------------------------------------------

/// The live text-editing session for the selected text box.
class _TextSession {
  _TextSession({required this.controller, required this.focus});

  final RichEditingController controller;
  final FocusNode focus;

  /// One undo snapshot per session — typing and its formatting are a
  /// single undo group.
  bool undoPushed = false;

  /// Debounced engine commit while typing (keystrokes never round-trip).
  Timer? commitDebounce;
}

/// The typing toolbar's live view over the session — rebuilt on every
/// controller notification, so the active states track the caret.
class _TypingDocState extends TypingToolbarStateLike {
  _TypingDocState(this._session);

  final _TextSession _session;

  (int, int) get _sel {
    final s = _session.controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  RichRun? _runAtSelection(String? Function(RichRun) pick) {
    final (a, b) = _sel;
    if (a == b) {
      // A caret reads its typing source.
      final src = _session.controller.doc.typingSourceAt(a);
      return src == null ? null : (pick(src) != null ? src : null);
    }
    for (final r in _session.controller.doc.runs) {
      if (r.end <= r.start) continue;
      if (r.start < b && a < r.end) return r;
    }
    return null;
  }

  @override
  bool isFlagActive(String flag) {
    final (a, b) = _sel;
    return _session.controller.doc.isFlagActive(a, b, flag);
  }

  @override
  String? get color => _runAtSelection((r) => r.color)?.color;

  @override
  String? get highlight => _runAtSelection((r) => r.highlight)?.highlight;

  @override
  String? get align {
    final (a, b) = _sel;
    final caret = (a == b) ? a : b;
    return _session.controller.doc
        .effectiveParaAt(caret.clamp(0, _session.controller.doc.text.length))
        ?.align;
  }

  @override
  String? get list {
    final (a, b) = _sel;
    final caret = (a == b) ? a : b;
    return _session.controller.doc
        .effectiveParaAt(caret.clamp(0, _session.controller.doc.text.length))
        ?.list;
  }
}
