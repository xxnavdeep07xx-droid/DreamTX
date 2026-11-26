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
import '../core/island_math.dart';
import '../core/island_store.dart';
import '../core/media_pickers.dart';
import '../core/media_playback.dart';
import '../core/object_content.dart';
import '../core/resources.dart';
import '../core/store.dart';
import '../theme.dart';
import '../widgets/content_editor.dart';
import '../widgets/controls.dart';
import '../widgets/design_sheets.dart';
import '../widgets/floating_island.dart';
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
part 'editor_lasso_flow.dart';
part 'editor_deck_flow.dart';
part 'editor_session_flow.dart';
part 'editor_insert_flow.dart';
part 'editor_object_ops.dart';
part 'editor_slide_flow.dart';
part 'editor_design_flow.dart';
part 'editor_build_flow.dart';
part 'editor_chrome.dart';


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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late Map<String, dynamic> _deck;
  int _index = 0;

  /// Draw E: the ink replay clock. Idle at 1 (every scribble whole); a
  /// replay runs it 0 → 1 (see [_replayInk]).
  late final AnimationController _inkReplay =
      AnimationController(vsync: this, value: 1.0);

  /// Draw C: where the Draw island sits and what it shows (per device).
  IslandPlacement _island = const IslandPlacement();
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

  /// Draw B: the lasso selection (object ids). Read through
  /// [_liveLassoIds], which drops ids that no longer exist.
  Set<String> _lassoIds = {};
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

  /// The resolved DNA palette in RRGGBB hex ('bg', 'surface', 'fg',
  /// 'muted', 'accent') — the table style chips resolve their colors from
  /// here at apply time (the WordArt rule).
  Map<String, String> _dnaHexes = const {};

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

  /// Collapsed filmstrip sections, by section id — pure UI state, per
  /// session (the deck file records the sections themselves, never the
  /// fold; PowerPoint's filmstrip behaves the same).
  final Set<String> _collapsedSections = {};

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
    loadIslandPlacement().then((placement) {
      if (mounted) setState(() => _island = placement);
    });
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
    _inkReplay.dispose();
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

  /// The copied object, deep-copied at copy time (JSON round-trip — the
  /// same trip every engine op takes, so later edits of the original can
  /// never alias into the clipboard). Paste assigns a fresh id.
  Map<String, dynamic>? _objectClipboard;

  /// The format painter's pickup: the universal shape chrome (`fill`,
  /// `stroke`, `opacity`, `effects`) — the fields every object carries and
  /// both exporters already render. Text typography (RichDoc spans) is a
  /// v2 pickup; v1 paints chrome only.
  Map<String, dynamic>? _styleClipboard;

  /// Save-failure toast throttle (see _warnSaveFailed).
  DateTime? _lastSaveToastAt;


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


  /// The part-file extensions' setState gateway: an extension's members
  /// are not instance members of a State subclass to the analyzer, so a
  /// direct setState there reads as a protected-member violation. One
  /// indirection on the class restores the legal path for every part.
  void _setState(VoidCallback fn) => setState(fn);

  // ---- build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => _buildBody(context);
}

// ---- PowerPoint-style bottom ribbon --------------------------------------------

/// Editor chrome mode, driven by the More (⋮) menu on the top bar.
enum _Mode { editing, viewing }


// ---------------------------------------------------------------------------
// The Insert drawer's session + toolbar state adapters
// ---------------------------------------------------------------------------
