import 'package:material_ui/material_ui.dart';

import '../core/object_content.dart';
import '../theme.dart';
import '../widgets/icon_registry.dart';
import '../widgets/controls.dart';
import '../widgets/dream_drawer.dart';
import '../widgets/rich_doc.dart';
import '../widgets/shape_canvas.dart' show objectPath;
// ---- parts (one library, split by concern; private state shared) ----
part 'insert_pickers.dart';
part 'insert_text_tools.dart';
part 'insert_panels.dart';


/// The Insert tab's drawer — where things get ADDED to the slide. It is
/// the SAME sheet as Files, verbatim, with different cards inside: the
/// editor owns the layer (rides the ribbon's top edge, rises from behind
/// the navbar, the filmstrip overlays its lower part), and this widget
/// owns the surface and its contents — the same alignment, the same
/// sizing (the editor's shared detents), and the same touch slidability
/// (the header is the drag surface: up grows the sheet, down shrinks it,
/// a downward fling or a deep drag dismisses it, a plain release snaps to
/// the nearest detent). Only the working cards differ.
///
/// The resting view is the 3×2 grid:
///
/// | Text Box | Image | Shapes |
/// | Table | Icons / Stickers | Media |
///
/// There is NO right-side category rail here — the rail belongs to
/// EDITING an object, not to choosing what to insert. Chart and Link are
/// deliberate non-entries (no placeholder buttons).
///
/// Inserting (or tapping an object on the canvas) replaces the grid with
/// that object's editing panel: the slide stays fully visible and
/// interactive above the sheet; most of the panel is controls; a narrow
/// icon-only rail on the far right switches between groups of controls
/// and highlights the active group. The same panel serves text, shapes,
/// images, tables, icons and media — only tools that make sense for the
/// selected object are shown, and every one of them works.
class InsertSheet extends StatefulWidget {
  const InsertSheet({
    super.key,
    required this.selectedObject,
    required this.textController,
    required this.textActions,
    required this.deckPalette,
    required this.onInsertTextBox,
    required this.onInsertWordArt,
    required this.onPickImage,
    required this.onPickShape,
    required this.onInsertTable,
    required this.onInsertIcon,
    required this.onPickMedia,
    this.onPlayMedia,
    required this.onObjectStyle,
    required this.onTableCell,
    required this.tableEntry,
    required this.onTableUpdate,
    required this.onTableStyle,
    required this.onShowLayers,
    required this.onEditStyleSheet,
    required this.onStartTyping,
    required this.onPanelBack,
    this.bottomInset = 0,
    this.onDragUpdate,
    this.onDragSettle,
  });

  /// The live selected object (or null). Non-null → the object panel.
  final Map<String, dynamic>? selectedObject;

  /// The live text session's controller — present whenever the selected
  /// object is a text box; the panel reads and writes through it.
  final RichEditingController? textController;

  /// Text formatting actions bound to the editor's live session.
  final TextActions? textActions;

  /// The deck's color palette (deck colors first, then standards).
  final List<Color> deckPalette;

  final VoidCallback onInsertTextBox;

  /// The WordArt gallery (styled-text presets) — opens the picker sheet.
  final VoidCallback onInsertWordArt;

  /// 'gallery' | 'camera' | 'deck' | 'brand'.
  final void Function(String source) onPickImage;

  /// The [ObjectContent] kinds an object can carry.
  final void Function(String preset) onPickShape;
  final VoidCallback onInsertTable;

  /// Inserts an icon sticker by registry name.
  final void Function(String iconName) onInsertIcon;

  /// 'video' | 'audio' — imports an existing file (no recorder).
  final void Function(String kind) onPickMedia;

  /// Plays the selected media object's resolved local file with the
  /// system player (the editor owns resolution + the platform channel).
  final void Function(Map<String, dynamic> obj)? onPlayMedia;

  /// Live style application for the selected non-text object (the editor
  /// commits it with its own undo/debounce machinery).
  final void Function(Map<String, dynamic> updated) onObjectStyle;

  /// Opens the cell editor for table cell [index].
  final void Function(int index) onTableCell;

  /// The selected table's deck-level metadata entry (merges + style),
  /// or null — app-owned deck data the engine drops on round-trips and
  /// the editor carries. Non-table selections read null.
  final Map<String, dynamic>? tableEntry;

  /// Commits a table structure change: the updated object (rows/cols/
  /// cells) AND its updated metadata entry (null = the entry folds away).
  /// One call = one undo step, the cell-editor contract.
  final void Function(Map<String, dynamic> obj, Map<String, dynamic>? entry)
      onTableUpdate;

  /// Applies a named table style ('plain' | 'header' | 'banded' |
  /// 'header_banded') — the editor resolves the DNA colors at apply time.
  final void Function(String style) onTableStyle;

  /// The existing layers sheet (groups, components, z-order).
  final VoidCallback onShowLayers;

  /// Opens the existing full style inspector for the selected object.
  final VoidCallback onEditStyleSheet;

  /// "Edit text": focus the on-canvas field (keyboard opens, panel hides).
  final VoidCallback onStartTyping;

  /// The object panel's back arrow: stop editing the selection — the
  /// editor clears it (the same path as tapping empty canvas), the sheet
  /// returns to its grid, and the object stays on the slide untouched.
  final VoidCallback onPanelBack;

  /// The overlay clearance at the sheet's bottom (the editor's filmstrip
  /// tray rides the sheet's lower part): every scrollable carries it as
  /// bottom padding so the last controls can always be scrolled fully
  /// above the tray. Scroll content, never chrome.
  final double bottomInset;

  /// Live drag forwarding from the header — the same contract as the Files
  /// drawer's handle: the vertical deltas (positive = the finger moved
  /// down) and the settle velocity, both mapped by the editor onto the
  /// shared sheet extent and detents.
  final void Function(double dy)? onDragUpdate;
  final void Function(double velocityDy)? onDragSettle;

  @override
  State<InsertSheet> createState() => _InsertSheetState();
}

// ---------------------------------------------------------------------------
// Header + tiles
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// The icon picker (a modal — its search field needs the keyboard-safe route)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// The object panel
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Text panel groups
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Non-text panel groups
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Panel scaffolding widgets
// ---------------------------------------------------------------------------
