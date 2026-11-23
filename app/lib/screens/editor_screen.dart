import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/aspects.dart';
import '../core/bridge.dart';
import '../core/color_utils.dart';
import '../core/ink_math.dart';
import '../core/media_pickers.dart';
import '../core/media_playback.dart';
import '../core/object_content.dart';
import '../core/resources.dart';
import '../core/store.dart';
import '../theme.dart';
import '../widgets/content_editor.dart';
import '../widgets/controls.dart';
import '../widgets/design_sheets.dart';
import '../widgets/rich_doc.dart';
import '../widgets/slide_stage.dart';
import '../widgets/typing_toolbar.dart';
import 'files_drawer.dart';
import 'insert_sheet.dart';
import 'pair_sheet.dart';
// ---- parts (one library, split by concern; private state shared) ----
part 'editor_nav_bar.dart';
part 'editor_filmstrip.dart';
part 'presenter_screen.dart';
part 'editor_sheets.dart';
part 'editor_sheet_builders.dart';
part 'editor_draw_tools.dart';


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

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late Map<String, dynamic> _deck;
  int _index = 0;
  Map<String, dynamic>? _layout;
  List<String> _warnings = [];
  bool _busy = false;
  final List<Map<String, dynamic>> _undo = [];
  final List<Map<String, dynamic>> _redo = [];

  // ---- design (vector overlay) state -------------------------------------------
  bool _designMode = false;

  /// The Draw tab's toolbox (armed tool + per-tool colors + pen width +
  /// the palette band) — ONE field replacing the old `_scribbleMode` bool;
  /// the row widget in editor_draw_tools.dart owns the surface, this class
  /// owns only the field and the state machine around it.
  _DrawToolboxState _drawToolbox = const _DrawToolboxState();
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

  /// The deck's resolved DNA accent (RRGGBB) — the Draw pen's default
  /// color, refreshed with the palette so ink matches the deck identity.
  String _dnaAccentHex = 'D03028';

  /// Live style edits from the object panel (one undo snapshot per
  /// selection, debounced commit — same contract as the text session).
  bool _styleUndoPushed = false;
  Timer? _objectCommitDebounce;

  /// Cached image-resource paths: 'brand:<id>' / 'deck:<id>' → file path.
  final Map<String, String> _resourcePaths = {};

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

  /// The sheet layer's live extent, in logical px — the ONE extent that
  /// both drawers (Files and Insert) share: the sheet floats as its own
  /// layer pinned directly to the ribbon's top edge. null = the resting
  /// half detent (recomputed each build from the layer cake's actual
  /// space); anything else = a drag in flight or a snapped detent — from
  /// EITHER drawer's header. The settle logic (fling one detent,
  /// nearest-detent release, dismiss zone at the bottom) reads the cached
  /// [_drawerHalf]/[_drawerTall], refreshed on every build. The sheet's
  /// extent is completely independent of the filmstrip's state — the strip
  /// never takes layout space while the sheet is open, so its toggles can
  /// never move the sheet's top edge.
  double? _drawerExtent;
  double _drawerHalf = 296;
  double _drawerTall = 356;
  bool _drawerDragging = false;

  /// The sheet's entrance slide. Arriving at a sheet tab (Files or
  /// Insert), the sheet is laid out at its FULL intended height (the
  /// resting detent — never a mid-screen sliver) but translated fully
  /// below the navbar's top edge, so its first mounted frame paints
  /// nothing; the post-frame callback in [_setNavTab] then translates it
  /// up into view over the same 200ms family, clipped at the navbar
  /// boundary — the sheet emerges continuously from behind the navbar,
  /// the navbar fixed in front.
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

  /// The last settled keyboard inset (logical px, straight off the view —
  /// the editor's own subtree is keyboard-stable and sees zeroed insets,
  /// so MediaQuery here would always read 0). Only the TRANSITION from
  /// open to closed matters: the system back button can hide the IME
  /// while the text field keeps its focus, and that case has no focus
  /// event to catch it.
  double _lastInsetBottom = 0;

  /// The steady viewport height — window-resize (adjustResize) devices
  /// deliver NO viewInsets while the keyboard is open: the window itself
  /// shrinks. The open→closed transition there is the viewport returning
  /// to this height, so both signals are tracked (the same contract
  /// [KeyboardStableMetrics] uses one layer up). 0 = not yet baselined.
  double _steadyViewportHeight = 0;

  /// True while a PROGRAMMATIC resync of the live text session is running
  /// (undo/redo swapping the whole deck): the controller's own change
  /// listener would otherwise record a fake undo snapshot of the resync
  /// itself and wipe the redo stack — the exact corruption undo/redo had
  /// while a text box was being edited.
  bool _suppressSessionChange = false;

  /// True while the typing state has the sheet layer stood down (keyboard
  /// owns the bottom of the screen): the sheet slides out behind the
  /// navbar over the same 200ms family as a tab switch — never a snap —
  /// and rises back the same way when typing ends.
  bool _sheetHiddenForTyping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
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
      _drawToolbox = _drawToolbox.disarmed();
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
    final accentHex = palette['accent']?.toString();
    if (accentHex != null && accentHex.length == 6) {
      _dnaAccentHex = accentHex.toUpperCase();
    }
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
      _sheetHiddenForTyping = false;
    });
    _refreshLayout();
  }

  /// Ribbon state machine: one contextual row at a time, tapped again to
  /// collapse. Tabs that work on the canvas overlay (Insert, Draw) double
  /// as design mode, so leaving them disarms the toolbox and clears the
  /// selection — but the selection SURVIVES a Files ⇄ Insert switch (both
  /// are sheet tabs over the same design mode canvas). Entering Draw arms
  /// the toolbox (the last-used tool); Draw ⇄ Insert keeps the selection
  /// and only disarms.
  void _setNavTab(_NavTab? tab) {
    final wasSheet = _isSheetTab(_navTab);
    final willBeSheet = _isSheetTab(tab);
    final wasDraw = _navTab == _NavTab.draw;
    // The sheet's height where it stands RIGHT NOW (before the tab flips) —
    // what the exit slide holds when it reverses. ONE machinery for both
    // drawers: a held extent if one exists, the shared resting half detent
    // otherwise.
    final leavingHeight = _drawerExtent ?? _drawerHalf;
    // The strip's live height where it stands right now — read BEFORE the
    // setState rebuild, so a fold caught mid-flight freezes at its real
    // on-screen height, not its target.
    final arrivingFootprint = _liveStripFlowHeight();
    setState(() {
      _navTab = tab;
      if (willBeSheet) _lastSheetTab = tab!;
      _designMode = tab == _NavTab.insert || tab == _NavTab.draw;
      if (!_designMode) {
        _drawToolbox = _drawToolbox.disarmed();
        _selectedObjectId = null;
        _disposeTextSession();
      } else if (tab == _NavTab.draw) {
        // Entering Draw: arm the last-used tool (the pen by default) and
        // clear the selection — draw focus. The armed tool consumes
        // canvas taps, so the selection chrome would be untouchable;
        // re-tapping the active tool inside the row disarms it (select
        // mode without leaving Draw).
        _drawToolbox = _drawToolbox.rearmed();
        _selectedObjectId = null;
      } else if (wasDraw) {
        // Draw -> Insert: the same design-mode canvas. Only disarm — the
        // selection survives, exactly like Files <-> Insert.
        _drawToolbox = _drawToolbox.disarmed();
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

  /// The sheet layer's live height for the CURRENT state, for BOTH drawer
  /// surfaces (Files and Insert ride the SAME machinery verbatim — same
  /// anchor, same detents, same drag, same dismiss): a held drag/settle
  /// extent when one exists, the shared resting half detent otherwise.
  /// The Insert drawer's cards scroll inside whatever the detent gives
  /// them, exactly like the Files drawer's grid on short screens.
  double _sheetLiveHeightFor() => _drawerExtent ?? _drawerHalf;

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

  /// The Draw toolbox's one mutation point (the row's onChanged): state
  /// in, state out. Arming through a tool tap clears the selection (draw
  /// focus — the armed tool consumes canvas taps); style edits and band
  /// toggles never touch anything but the toolbox.
  void _setDrawToolbox(_DrawToolboxState next) {
    setState(() {
      final nowArmed = next.armed && !_drawToolbox.armed;
      _drawToolbox = next;
      if (nowArmed) _selectedObjectId = null;
    });
  }

  /// A stroke finished: the capture pipeline's smoothed design-space
  /// polyline ([inkCapture] — the same list the live preview painted its
  /// last frame with) lands as a plain `path` object in the deck's model,
  /// styled exactly as the preview showed it. NOT auto-selected: drawing
  /// focus — the selection chrome stays away while the tool is armed, and
  /// the stroke is selectable the moment drawing ends.
  void _onStrokeDone(List<Offset> pts) {
    final slideId = _slideId;
    if (slideId == null || pts.length < 2) return;
    final style =
        _drawToolbox.inkStyleFor(defaultPenHex: _dnaAccentHex);
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
      'opacity': style.opacity,
      'locked': false,
      'fill': {'type': 'none'},
      'stroke': {
        'color': style.colorHex,
        'width': style.width,
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
    }
  }

  // ---- object selection + the text editing session ---------------------------

  /// Selection from the canvas layer (tap): first tap selects and SHOWS
  /// the object's panel (the Insert sheet rises with it); tapping the SAME
  /// text box again re-enters typing.
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
    // The panel IS the selection's face: selecting a canvas object opens
    // the Insert sheet (rising from behind the navbar) whichever editing
    // tab was active — Draw just as Insert — while a read-only deck never
    // gets here (the stage is non-interactive in viewing).
    if (_mode == _Mode.editing && _navTab != _NavTab.insert) {
      _setNavTab(_NavTab.insert);
    }
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
    // A programmatic resync (undo/redo) is not a user edit: no undo
    // snapshot, no redo wipe, no commit — just the new state landing.
    if (_suppressSessionChange) return;
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
  /// re-read its object (the box may be gone or carry older text). The
  /// resync runs under [_suppressSessionChange]: writing `controller.text`
  /// notifies the change listener synchronously, and an unsuppressed
  /// notification would push the PRE-swap deck as an "edit" (a fake undo
  /// step) and clear `_redo` — corrupting the very history being walked.
  void _resyncTextSession() {
    final s = _textSession;
    if (s == null) return;
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isText(obj)) {
      _disposeTextSession();
      return;
    }
    final fresh = ObjectContent.textDocOf(obj) ?? RichDoc();
    _suppressSessionChange = true;
    try {
      s.controller.doc = fresh;
      s.controller.text = fresh.text;
      s.controller.refresh();
    } finally {
      _suppressSessionChange = false;
      s.undoPushed = false;
    }
  }

  // ---- the typing state --------------------------------------------------------

  @override
  void didChangeMetrics() {
    // The inset animates in steps — read the settled value after the
    // frame lands, from the view itself (never the keyboard-stable
    // subtree's MediaQuery).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final view = views.first;
      final inset = view.viewInsets.bottom / view.devicePixelRatio;
      final viewportH = view.physicalSize.height / view.devicePixelRatio;
      // First observation: baseline the steady height, nothing to compare.
      if (_steadyViewportHeight <= 0) {
        _steadyViewportHeight = viewportH;
        _lastInsetBottom = inset;
        return;
      }
      // Two delivery modes, one truth: inset-delivery keyboards animate
      // viewInsets up; adjustResize windows shrink the viewport and deliver
      // NO inset. A keyboard is open when EITHER signal moves; it closed
      // when both are back at steady. Heights LARGER than steady (bars
      // revealed, split-screen) re-baseline instead of reading as close.
      final viewportShrunk = viewportH < _steadyViewportHeight - 0.5;
      final keyboardOpen = inset > 0 || viewportShrunk;
      if (!keyboardOpen) {
        _steadyViewportHeight = viewportH;
      }
      final wasOpen = _lastInsetBottom > 0 || _lastViewportShrunk;
      _lastInsetBottom = inset;
      _lastViewportShrunk = viewportShrunk;
      if (!wasOpen || keyboardOpen || !_typing) return;
      // The keyboard closed while the field still holds focus — the
      // system back button (gesture bar / 3-button nav) hides the IME
      // WITHOUT unfocusing it, so no focus event ever fires. Left alone
      // this stranded the toolbar at the screen's bottom with the sheet
      // still hidden. Close the session exactly like the expand button
      // does: toolbar down, the drawer and its full panel return, and
      // the text/caret/selection survive in the session's controller.
      _endTyping();
    });
  }

  /// The viewport-shrunk half of the keyboard signal (see
  /// [didChangeMetrics]) — window-resize devices never raise viewInsets.
  bool _lastViewportShrunk = false;

  void _beginTyping() {
    final s = _textSession;
    if (s == null) return;
    // The field mounts focused (autofocus) — the focus listener below
    // flips the typing state, hides the sheet, shows the toolbar.
    setState(() {
      _typing = true;
      // The sheet (Files OR Insert — whichever is the active tab) stands
      // down while the keyboard owns the bottom of the screen: it slides
      // out behind the navbar over the same 200ms family a tab switch
      // uses, never a snap. The flag remembers WHO closed it so ending
      // the typing state can rise it back.
      _sheetHiddenForTyping = _mode == _Mode.editing && _isSheetTab(_navTab);
      if (_sheetHiddenForTyping) {
        if (_sheetEntering) {
          // Never rose: no pixels were ever shown — nothing to animate.
          _sheetEntering = false;
          _sheetClosing = false;
          _drawerExtent = null;
        } else if (!_sheetClosing) {
          _sheetClosing = true;
          _drawerExtent ??= _sheetLiveHeightFor(); // hold the height it stands at
        }
      }
    });
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
    setState(() {
      _typing = false;
      // If the typing state was what stood the sheet down (the keyboard
      // covered it), ending it rises the sheet back through the same
      // entrance a tab arrival uses — slide up from behind the navbar,
      // frozen strip footprint, post-frame flip into place. Only when the
      // sheet's tab is still the active one (a tab switch's own exit
      // machinery owns the layer otherwise).
      if (_sheetHiddenForTyping) {
        _sheetHiddenForTyping = false;
        if (_mode == _Mode.editing && _isSheetTab(_navTab)) {
          final resumingExit = _sheetClosing;
          _sheetClosing = false;
          _sheetEntering = !resumingExit;
          _drawerExtent = null;
          _frozenStripFootprint = _liveStripFlowHeight();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _typing ||
                !_sheetEntering ||
                !_isSheetTab(_navTab) ||
                _mode != _Mode.editing ||
                _drawerDragging) {
              return;
            }
            setState(() => _sheetEntering = false);
          });
        }
      }
    });
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
        // An EXTERNAL focus loss (this listener firing without
        // [_endTyping] — the system took the focus, another field claimed
        // it) must clear the typing state's sheet-down flag HERE too:
        // otherwise the sheet that stood down for the keyboard stays down
        // and later SNAPS into place instead of animating through the
        // entrance now. Same machinery [_endTyping] runs — only once ever,
        // because both paths clear the flag before the other checks it.
        if (_sheetHiddenForTyping) {
          _sheetHiddenForTyping = false;
          if (_mode == _Mode.editing && _isSheetTab(_navTab)) {
            final resumingExit = _sheetClosing;
            _sheetClosing = false;
            _sheetEntering = !resumingExit;
            _drawerExtent = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted ||
                  _typing ||
                  !_sheetEntering ||
                  !_isSheetTab(_navTab) ||
                  _mode != _Mode.editing ||
                  _drawerDragging) {
                return;
              }
              setState(() => _sheetEntering = false);
            });
          }
        }
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
          // Anchored to the SCREEN's bottom, not to the inset's top: the
          // toolbar sits exactly where it always did (its bottom edge at
          // the inset), and everything below it — the IME's whole reserved
          // region — is filled with the toolbar's own surface. Themed
          // keyboards reserve more window than they paint (their top band
          // is transparent), which used to show the slide peeking through
          // that band between the toolbar and the first key row; the
          // backdrop makes the toolbar read flush against the keys
          // wherever the keyboard actually starts painting (under the
          // opaque keys the backdrop is simply covered).
          //
          // NO SafeArea here, deliberately: the overlay already owns the
          // whole bottom — the backdrop carries the keyboard region and
          // the toolbar rides flush on its top — so a system-bar inset
          // applied by SafeArea would double-pad BELOW the keyboard on
          // devices that report one while the IME is up. The one inset
          // that matters (the keyboard's own) is the backdrop's height.
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
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
                  onAlign: (v) => _docMutate(
                      (doc, a, b) => doc.setParagraphAttr(a, b, 'align', v)),
                  onList: (k) => _docMutate((doc, a, b) => doc.toggleList(a, b, k)),
                  onExpand: _endTyping,
                ),
              ),
              if (bottom > 0)
                SizedBox(
                  key: const ValueKey('typing_toolbar_backdrop'),
                  width: double.infinity,
                  height: bottom,
                  child: const ColoredBox(color: kElevated),
                ),
            ],
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
      // The resolver cache is populated IMMEDIATELY: the object inserts on
      // the very next frame and the content layer reads this map
      // synchronously — a missing entry would render the just-imported
      // image as a "missing asset" card until some later rebuild.
      final resolved = _resourcePathOf(entry, brand: false);
      if (resolved != null) {
        _resourcePaths['deck:${entry['id']}'] = resolved;
      }
      if (!mounted) return;
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
      final choice = await dreamSheet<Map<String, dynamic>>(
        context,
        builder: (sheetContext) => _ImageResourceSheet(
          brand: brand,
          images: images,
          pathOf: (e) => _resourcePathOf(e, brand: brand),
        ),
      );
      if (choice == null || !mounted) return;
      // Same immediate-cache contract as a fresh import: the library pick
      // resolves the file NOW so the inserted object renders first frame.
      final resolved = _resourcePathOf(choice, brand: brand);
      if (resolved != null) {
        _resourcePaths['${brand ? 'brand' : 'deck'}:${choice['id']}'] = resolved;
      }
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
      final resolved = _resourcePathOf(entry, brand: false);
      if (resolved != null) {
        _resourcePaths['deck:${entry['id']}'] = resolved;
      }
      if (!mounted) return;
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

  /// Plays the selected media object's resolved local file with the
  /// system player through the tiny `dreamtx/media` intent channel — no
  /// bundled player SDK, no new dependency. Resolution failures surface
  /// honestly (a toast) — the button never silently does nothing.
  Future<void> _playMedia(Map<String, dynamic> obj) async {
    final content = ObjectContent.of(obj);
    if (content == null) return;
    final path = _resolveResourcePath(content);
    if (path == null) {
      _toast('That media file is no longer on this device — nothing to play.');
      return;
    }
    final mime = (content['media_kind'] ?? 'video') == 'video'
        ? 'video/*'
        : 'audio/*';
    final ok = await MediaPlayback.open(path, mime: mime);
    if (!mounted) return;
    if (!ok) {
      _toast('No player on this device can open that file.');
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

  void _objOp(Map<String, dynamic> req,
      {void Function(Map newDeck)? after}) {
    final r = Bridge.command(req);
    if (r['ok'] == true && r['deck'] is Map) {
      final newDeck = r['deck'] as Map;
      _mutate(newDeck);
      after?.call(newDeck);
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
      }, after: (newDeck) => _pruneOrphanedResources(newDeck));

  /// Deletes leave resource files orphaned on disk when nothing references
  /// them anymore (an image/media object deleted, or a whole slide). The
  /// deck's file is the reference graph — after a real deletion (never
  /// after undo/redo: undo resurrects objects and would need the files
  /// back), sweep the deck scope's assets that no object references.
  /// Brand resources are shared by every deck — never swept here.
  Future<void> _pruneOrphanedResources(Map newDeck) async {
    try {
      final referenced = <String>{};
      for (final slide in ((newDeck['slides'] as List?) ?? const [])
          .whereType<Map>()) {
        for (final obj in ((slide['objects'] as List?) ?? const [])
            .whereType<Map>()) {
          final content = obj['content'];
          if (content is! Map) continue;
          final kind = content['kind'];
          if (kind != 'image' && kind != 'media') continue;
          if (content['brand'] == true) continue; // brand scope: shared
          final rid = content['resource_id']?.toString();
          if (rid != null && rid.isNotEmpty) referenced.add(rid);
        }
      }
      final deckId = (newDeck['id'] ?? _deck['id'] ?? '').toString();
      final store = await ResourceStore.open();
      final items = await store.list(brand: false, deckId: deckId);
      for (final e in items) {
        final id = e['id']?.toString();
        if (id == null || referenced.contains(id)) continue;
        // Not referenced anywhere in the deck anymore: sweep it (the
        // object that owned it is gone — undo restores its own copy only
        // if the deck map comes back, and the resource store keeps the
        // file until the moment it is truly unreferenced).
        //
        // UNLESS the undo stack still knows it: a pending undo WILL
        // resurrect the object, and it should resurrect its asset too.
        final inUndoOrRedo = _undo.any((d) => _deckReferences(d, id)) ||
            _redo.any((d) => _deckReferences(d, id));
        if (inUndoOrRedo) continue;
        await store.remove(brand: false, deckId: deckId, id: id);
      }
    } catch (_) {
      // A failed sweep is noise on disk, never a failed delete.
    }
  }

  /// Whether a deck snapshot still references resource [id].
  bool _deckReferences(Map deck, String id) {
    for (final slide in ((deck['slides'] as List?) ?? const [])
        .whereType<Map>()) {
      for (final obj in ((slide['objects'] as List?) ?? const [])
          .whereType<Map>()) {
        final content = obj['content'];
        if (content is! Map) continue;
        if (content['brand'] == true) continue;
        if (content['resource_id']?.toString() == id) return true;
      }
    }
    return false;
  }

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
    final choice = await dreamSheet<String>(
      context,
      builder: (context) =>
          _ArchetypeSheet(suggested: suggested, archetypes: archetypes),
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
      final newDeck = r['deck'] as Map;
      _mutate(newDeck);
      _refreshLayout(); // clamps _index
      // The slide's objects are gone for good — their deck-scope resources
      // may now be orphans (the same sweep as object deletion; the undo
      // stack is respected inside).
      unawaited(_pruneOrphanedResources(newDeck));
    } else {
      _toast('Could not delete: ${r['error']}');
    }
  }

  /// Long-press menu for a filmstrip thumbnail.
  Future<void> _slideActions(int i) async {
    if (i < 0 || i >= _slides.length) return;
    final action = await dreamSheet<String>(
      context,
      builder: (context) =>
          _SlideActionsSheet(index: i, count: _slides.length),
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
    final kind = await dreamSheet<String>(
      context,
      builder: (context) => const _NewDeckSheet(),
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
      final fam = await dreamSheet<String>(
        context,
        builder: (context) => const _DesignFamilySheet(),
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
    final kind = await dreamSheet<String>(
      context,
      builder: (context) => const _OpenDeckSheet(),
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
    final choice = await dreamSheet<Map<String, dynamic>>(
      context,
      builder: (context) =>
          _RecentsSheet(decks: decks, currentId: currentId),
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
    final choice = await dreamSheet<String>(
      context,
      builder: (context) =>
          _AspectSheet(current: current, aspects: aspects),
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

  /// The image assets the exporters need, resolved from the
  /// resource store: resource id -> encoded bytes + format (+ decoded RGBA
  /// for the PDF's FlateDecode path, downscaled so a photo never ships
  /// tens of megabytes of raw pixels over the FFI boundary).
  ///
  /// ONLY image objects ship bytes — media objects render a card in every
  /// export format (the system player plays the local file; the exports
  /// never embed video/audio), so they are skipped here entirely.
  Future<Map<String, Map<String, dynamic>>> _exportImageAssets(
      {required bool withRgba}) async {
    final out = <String, Map<String, dynamic>>{};
    // resource id -> the object's OWN declared scope (brand vs deck).
    final wanted = <String, bool>{};
    for (final slide in _slides) {
      for (final obj in ((slide['objects'] as List?) ?? const [])
          .whereType<Map>()) {
        final content = obj['content'];
        if (content is! Map) continue;
        if (content['kind'] != 'image') continue;
        final id = content['resource_id']?.toString();
        if (id != null && id.isNotEmpty) {
          wanted.putIfAbsent(id, () => content['brand'] == true);
        }
      }
    }
    if (wanted.isEmpty) return out;
    final deckId = (_deck['id'] ?? '').toString();
    for (final want in wanted.entries) {
      try {
        // The object declares which scope it lives in — brand assets
        // resolve from the brand tree, deck assets from this deck's.
        final store = await ResourceStore.open();
        final path = await store.resolve(
            brand: want.value, deckId: want.value ? null : deckId, id: want.key);
        if (path == null) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        var bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final ext = path.toLowerCase().split('.').last;
        var format = switch (ext) {
          'jpg' || 'jpeg' => 'jpeg',
          'gif' => 'gif',
          'png' => 'png',
          _ => 'other', // webp/bmp/heic/… — see the re-encode below
        };
        // PPTX embeds `bytes` VERBATIM as ppt/media/imageN.<format>: a
        // webp/bmp/heic file cannot ship under a png label — that writes a
        // broken image part. Decode it and re-encode as REAL PNG bytes.
        // (The PDF path needs no re-encode: it consumes the decoded RGBA
        // pixels, never the raw file.)
        if (format == 'other' && !withRgba) {
          final png = await _encodeAsPng(path);
          if (png == null) continue; // undecodable → placeholder, never broken
          bytes = png;
          format = 'png';
        }
        if (format == 'other') {
          // The PDF path with an exotic source keeps flowing through the
          // RGBA decode below — the pixels, not the raw bytes, are what it
          // consumes; the tag stays 'png' so any bytes-only consumer on
          // that path can never claim a webp is a jpeg.
          format = 'png';
        }
        final entry = <String, dynamic>{
          'format': format,
          'bytes': base64Encode(bytes),
        };
        if (withRgba && format != 'jpeg') {
          final rgba = await _decodedRgba(path);
          if (rgba != null) {
            entry['width'] = rgba.$1;
            entry['height'] = rgba.$2;
            entry['rgba'] = base64Encode(rgba.$3);
          } else {
            // A failed decode exports a placeholder — never a broken
            // image, and never a half entry either.
            continue;
          }
        } else {
          // Even without the pixel payload the exporter needs no size
          // for pptx (the pic box is the object's own geometry).
          entry['width'] = 1;
          entry['height'] = 1;
        }
        out[want.key] = entry;
      } catch (_) {
        // One unreadable asset exports a placeholder — never a failed
        // export. See object_content_layer's missing-asset card.
      }
    }
    return out;
  }

  /// One local image file re-encoded as real PNG bytes — the PPTX exporter
  /// embeds `ppt/media/*` parts verbatim, so a webp/bmp/heic source must be
  /// decoded and PNG-encoded before it can ship (a raw file under a `png`
  /// label is a broken image part in the exported deck). Returns null when
  /// the file cannot be decoded (a placeholder follows).
  Future<Uint8List?> _encodeAsPng(String path) async {
    try {
      final data = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final bd = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bd == null) return null;
        return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Decoded RGBA of an image file, downscaled to a bounded pixel budget
  /// (design-space never shows more than ~1280px across, and the PDF page
  /// is 960pt — 1600px is already beyond what any viewer can distinguish).
  /// Returns (width, height, rgba) or null when the file cannot be decoded
  /// (a placeholder follows).
  Future<(int, int, List<int>)?> _decodedRgba(String path) async {
    try {
      final data = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        data,
        targetWidth: 1600,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final w = image.width;
        final h = image.height;
        final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (bd == null) return null;
        return (w, h, bd.buffer.asUint8List().toList());
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _export(String op, {String verb = 'Export'}) async {
    setState(() => _busy = true);
    try {
      // The exporters need the resolved image assets; the PDF request also
      // carries decoded pixels. Collecting them touches disk and decodes
      // images, so it (and the engine call itself) run without holding a
      // frame: the engine runs on a background isolate (exports zip whole
      // decks — the UI never freezes), the asset collection is async IO.
      final withRgba = op == 'export_pdf';
      final images = await _exportImageAssets(withRgba: withRgba);
      final r = await Bridge.commandHeavy({
        'op': op,
        'deck': _deck,
        if (images.isNotEmpty) 'images': images,
      });
      if (r['ok'] != true || r['base64'] is! String) {
        if (!mounted) return;
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
      if (mounted) _toast('$verb error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return; // async flows can outlive the editor
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
            // The sheet's layer is alive while a sheet tab is active (and
            // the typing state is not standing it down) OR its exit slide
            // is still running — the unmount lands when that slide
            // completes (the AnimatedPositioned's onEnd below). While the
            // user is TYPING into a text box the sheet stands down (the
            // keyboard owns the bottom of the screen and the typing
            // toolbar rides it in the root overlay) for EITHER drawer —
            // Files just as Insert — and the flow's spacer system keeps
            // the canvas's constraints frozen through that too.
            final filesOpen = _mode == _Mode.editing &&
                _navTab == _NavTab.files &&
                !_typing;
            final insertOpen = _mode == _Mode.editing &&
                _navTab == _NavTab.insert &&
                !_typing;
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
            // inside this body. From it, the two detents EITHER drawer's
            // header drag settles between — the resting HALF (floor 296 so
            // the whole 3×2 grid always fits — Files' tool tiles and
            // Insert's cards alike, ceiling 430) and the TALL sheet (~78%,
            // leaving the slide's top sliver in view). The drag handlers run
            // between builds, so both are cached per build.
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
            final sheetHeight = _sheetLiveHeightFor();
            final overlayH = math.min(stripH, sheetHeight);
            return Stack(
              children: [
                // The base layer: the editor's whole flow. While a sheet
                // (Files or Insert) is open the filmstrip is NOT in this flow (it is the
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
                                  // THE slide stage — the one layered
                                  // stage the presenter renders too:
                                  // archetype layout, then the object
                                  // layer in the deck's TRUE Z-order
                                  // (content objects and vector shapes
                                  // interleaved exactly as
                                  // `slide['objects']` lists them, so
                                  // Bring Forward / Send Backward reads
                                  // on screen), with the gesture/selection
                                  // overlay on top and the live typing
                                  // field above everything.
                                  //
                                  // Objects are SELECTABLE in every editing
                                  // mode (any tab — not only Insert/Draw):
                                  // a tap selects and opens the object's
                                  // panel, a tap on the already-selected
                                  // text box enters typing, and drag/
                                  // resize/rotate work wherever the deck
                                  // is being edited. Viewing stays
                                  // read-only.
                                  child: SlideStage(
                                    layout: _layout!,
                                    objects: _objects,
                                    designW: _designDims.$1,
                                    designH: _designDims.$2,
                                    baseColor: _baseTextColor,
                                    baseFamily: _baseTextFamily,
                                    baseFontSize: kTextBoxBaseSize,
                                    resolveResourcePath:
                                        _resolveResourcePath,
                                    selectedId: _selectedObjectId,
                                    interactive: _mode == _Mode.editing,
                                    // The Draw toolbox: the armed tool
                                    // and its style (the row under the
                                    // canvas owns the state; the preview
                                    // and the committed object agree by
                                    // construction — same InkStyle).
                                    inkTool: _drawToolbox.armed
                                        ? _drawToolbox.tool
                                        : null,
                                    inkStyle: _drawToolbox.inkStyleFor(
                                        defaultPenHex: _dnaAccentHex),
                                    onTextTap: _mode == _Mode.viewing
                                        ? null
                                        : _editText,
                                    onSelect: _onObjectSelected,
                                    onLive: _liveObject,
                                    onCommit: _commitObject,
                                    onGestureStart: _objectGestureStart,
                                    onStroke: _onStrokeDone,
                                    textController: _selectedObject != null &&
                                            ObjectContent.isText(
                                                _selectedObject!)
                                        ? _textSession?.controller
                                        : null,
                                    textFocusNode: _selectedObject != null &&
                                            ObjectContent.isText(
                                                _selectedObject!)
                                        ? _textSession?.focus
                                        : null,
                                    typing: _typing,
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
                // Draw is the one tab whose row changes height: the
                // toolbox's palette band cross-fades the band 48 <-> 94,
                // the same reveal the typing toolbar's palette row does —
                // every other tab stays a constant 48.
                Container(
                  decoration: const BoxDecoration(
                    color: kSurface,
                    border: Border(
                      top: BorderSide(color: kHairline),
                      bottom: BorderSide(color: kHairline),
                    ),
                  ),
                  height: _navTab == _NavTab.draw ? null : 48,
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
                  showTopRule: sheetOpen || _filmOpen),
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
                        // The drawer (Files' surface or Insert's — the SAME
                        // layer) floats ABOVE the canvas and rides the
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
                            // Unmount when nothing wants the layer painted:
                            // the tab left the sheet family, OR the typing
                            // state is standing it down (the keyboard owns
                            // the screen — the sheet will rise again when
                            // typing ends, [_sheetHiddenForTyping]).
                            if (!mounted ||
                                !_sheetClosing ||
                                (_isSheetTab(_navTab) &&
                                    _mode == _Mode.editing &&
                                    !_sheetHiddenForTyping)) {
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
                          // clip, same anchor, same detents, same drag
                          // (both headers forward their vertical drags to
                          // the one shared extent machinery); switching
                          // between the two sheet tabs swaps the surface
                          // without unmounting the layer, and the exit
                          // slide keeps the surface it is animating out.
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
                                  onPlayMedia: _playMedia,
                                  onObjectStyle: _liveObjectEdit,
                                  onTableCell: _editTableCell,
                                  onShowLayers: _showLayers,
                                  onEditStyleSheet: _editSelectedObjectStyle,
                                  onStartTyping: _beginTyping,
                                  // The panel's back arrow — "stop editing":
                                  // the SAME clear-selection path as
                                  // tapping empty canvas (flush + dispose
                                  // the text session, drop the id); the
                                  // object itself stays on the slide.
                                  onPanelBack: () => _onObjectSelected(null),
                                  // The SAME drag forwarding the Files
                                  // drawer's header carries: the Insert
                                  // drawer's header resizes the shared sheet
                                  // between the same detents and dismisses on
                                  // the same fling/deep-drag rules.
                                  onDragUpdate: _drawerDragUpdate,
                                  onDragSettle: _drawerDragSettle,
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

  // ---- the sheet drawers' shared layer (Files + Insert) --------------------

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
        // The toolbox: pen / highlighter with per-tool colors, the pen's
        // widths, the expandable palette band (the row lives in the
        // editor_draw_tools part file; the editor owns the ONE state).
        return _DrawToolboxRow(
          state: _drawToolbox,
          defaultPenHex: _dnaAccentHex,
          palette: _deckPalette,
          onChanged: _setDrawToolbox,
        );
      case _NavTab.design:
        final current = ((_deck['dna'] ?? const {})['family'] ?? '').toString();
        return Row(
          children: [
            const SizedBox(width: 8),
            for (final (id, label) in _designFamilies)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: DreamChoiceChip(
                    magenta: true,
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
      builder: (_) => PairSheet(deck: _deck, onDeckUpdate: _applyRemoteDeck),
    );
  }

  /// A deck payload pushed by the AI over the paired WebSocket (update /
  /// snapshot / reset): apply it as one atomic step — it lands on the
  /// canvas live, persists like any edit, and takes its place in undo
  /// history (undo reverts an AI edit like any other).
  void _applyRemoteDeck(Map<String, dynamic> deck) {
    if (!mounted) return;
    _mutate(deck);
    _styleUndoPushed = false;
    _resyncTextSession();
  }

  // ---- editor modes (More menu) ---------------------------------------------

  void _setMode(_Mode m) {
    setState(() {
      _mode = m;
      if (m == _Mode.viewing) {
        _navTab = null;
        _designMode = false;
        _drawToolbox = _drawToolbox.disarmed();
        _selectedObjectId = null;
        _sheetHiddenForTyping = false;
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
    await dreamSheet<void>(
      context,
      builder: (context) => _CommentsSheet(
        comments: _comments,
        field: _commentField,
        onPost: (text) {
          setState(() => _comments.add({'text': text}));
          _commentField.clear();
        },
      ),
    );
  }

  /// The top-bar Share button — "send a copy": no format dialog, just export
  /// the deck as .pptx and hand it straight to the system share sheet.
  /// Picking a format (pptx/pdf) is the Export menu's job; Share is the
  /// fast lane out of the app.
  Future<void> _showShareSheet() => _export('export_pptx', verb: 'Share');

  Future<void> _showExportSheet() async {
    await dreamSheet<void>(
      context,
      builder: (context) => _ExportSheet(
        busy: _busy,
        onExport: (op) => _export(op),
      ),
    );
  }
}

// ---- PowerPoint-style bottom ribbon --------------------------------------------

/// Editor chrome mode, driven by the More (⋮) menu on the top bar.
enum _Mode { editing, viewing }


// ---------------------------------------------------------------------------
// The Insert drawer's session + toolbar state adapters
// ---------------------------------------------------------------------------
