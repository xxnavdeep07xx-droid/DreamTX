import 'package:material_ui/material_ui.dart';

import '../core/object_content.dart';
import '../theme.dart';
import '../widgets/icon_registry.dart';
import '../widgets/rich_doc.dart';
import '../widgets/shape_canvas.dart' show objectPath;

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
    required this.onPickImage,
    required this.onPickShape,
    required this.onInsertTable,
    required this.onInsertIcon,
    required this.onPickMedia,
    required this.onObjectStyle,
    required this.onTableCell,
    required this.onShowLayers,
    required this.onEditStyleSheet,
    required this.onStartTyping,
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

  /// 'gallery' | 'camera' | 'deck' | 'brand'.
  final void Function(String source) onPickImage;

  final void Function(String preset) onPickShape;
  final VoidCallback onInsertTable;

  /// Inserts an icon sticker by registry name.
  final void Function(String iconName) onInsertIcon;

  /// 'video' | 'audio' — imports an existing file (no recorder).
  final void Function(String kind) onPickMedia;

  /// Live style application for the selected non-text object (the editor
  /// commits it with its own undo/debounce machinery).
  final void Function(Map<String, dynamic> updated) onObjectStyle;

  /// Opens the cell editor for table cell [index].
  final void Function(int index) onTableCell;

  /// The existing layers sheet (groups, components, z-order).
  final VoidCallback onShowLayers;

  /// Opens the existing full style inspector for the selected object.
  final VoidCallback onEditStyleSheet;

  /// "Edit text": focus the on-canvas field (keyboard opens, panel hides).
  final VoidCallback onStartTyping;

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

/// The formatting actions the panel drives on the live text session.
class TextActions {
  TextActions({
    required this.toggleFlag,
    required this.setColor,
    required this.setHighlight,
    required this.setAlign,
    required this.toggleList,
    required this.setFontFamily,
    required this.setFontSize,
    required this.clearFormatting,
    required this.setValign,
    required this.setAutofit,
    required this.setLineSpacing,
    required this.indentBy,
  });

  final void Function(String flag) toggleFlag;
  final void Function(String? hex) setColor;
  final void Function(String? hex) setHighlight;
  final void Function(String align) setAlign;
  final void Function(String kind) toggleList;
  final void Function(String? family) setFontFamily;
  final void Function(double size) setFontSize;
  final VoidCallback clearFormatting;
  final void Function(String valign) setValign;
  final void Function(String autofit) setAutofit;
  final void Function(double spacing) setLineSpacing;
  final void Function(int dir) indentBy;
}

enum _InsertView { grid, shapes, image, media }

class _InsertSheetState extends State<InsertSheet> {
  _InsertView _view = _InsertView.grid;
  int _panelGroup = 0;

  @override
  void didUpdateWidget(InsertSheet old) {
    super.didUpdateWidget(old);
    // A fresh selection (a new insert or a canvas tap) replaces whatever
    // picker was open with the object's editing panel; dropping the
    // selection returns to the resting grid.
    if (widget.selectedObject != null && old.selectedObject == null) {
      _panelGroup = 0;
      _view = _InsertView.grid;
    }
    if (widget.selectedObject == null) {
      _panelGroup = 0;
    }
  }

  bool get _panelShown =>
      widget.selectedObject != null && _view == _InsertView.grid;

  void _back() => setState(() => _view = _InsertView.grid);

  @override
  Widget build(BuildContext context) {
    final panel = _panelShown;
    final title = switch (_view) {
      _InsertView.shapes => 'Shapes',
      _InsertView.image => 'Image',
      _InsertView.media => 'Media',
      _InsertView.grid => panel
          ? ObjectContent.labelOf(widget.selectedObject!)
          : 'Insert',
    };
    return Material(
      key: const ValueKey('insert_drawer'),
      color: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: kHairline),
      ),
      child: Column(
        children: [
          _InsertHeader(
            title: title,
            showBack: !panel && _view != _InsertView.grid,
            onBack: _back,
            onLayers: widget.onShowLayers,
            onDragUpdate: widget.onDragUpdate,
            onDragSettle: widget.onDragSettle,
          ),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _body(context, panel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, bool panel) {
    if (panel) {
      final obj = widget.selectedObject!;
      return _ObjectPanel(
        key: ValueKey('panel_${ObjectContent.kindOf(obj)}_${obj['id']}'),
        obj: obj,
        textController: widget.textController,
        textActions: widget.textActions,
        palette: widget.deckPalette,
        groupIndex: _panelGroup,
        onGroup: (i) => setState(() => _panelGroup = i),
        onObjectStyle: widget.onObjectStyle,
        onTableCell: widget.onTableCell,
        onEditStyleSheet: widget.onEditStyleSheet,
        onStartTyping: widget.onStartTyping,
        bottomInset: widget.bottomInset,
      );
    }
    switch (_view) {
      case _InsertView.grid:
        return _grid(context);
      case _InsertView.shapes:
        return _shapesView();
      case _InsertView.image:
        return _imageSources();
      case _InsertView.media:
        return _mediaSources();
    }
  }

  // ---- the grid -----------------------------------------------------------

  Widget _grid(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('insert_grid'),
      padding: EdgeInsets.fromLTRB(14, 4, 14, 10 + widget.bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _InsertTile(
                  icon: Icons.text_fields,
                  label: 'Text Box',
                  onTap: widget.onInsertTextBox,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsertTile(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  onTap: () => setState(() => _view = _InsertView.image),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsertTile(
                  icon: Icons.category_outlined,
                  label: 'Shapes',
                  onTap: () => setState(() => _view = _InsertView.shapes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InsertTile(
                  icon: Icons.grid_on,
                  label: 'Table',
                  onTap: widget.onInsertTable,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsertTile(
                  icon: Icons.emoji_emotions_outlined,
                  label: 'Icons / Stickers',
                  onTap: () => showIconPicker(context,
                      onPick: widget.onInsertIcon),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsertTile(
                  icon: Icons.perm_media_outlined,
                  label: 'Media',
                  onTap: () => setState(() => _view = _InsertView.media),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- shapes picker ---------------------------------------------------------

  static const List<String> _shapePicks = [
    'rectangle', 'rounded', 'ellipse', 'line',
    'arrow_right', 'arrow_left', 'arrow_up', 'arrow_down',
    'double_arrow', 'triangle', 'diamond', 'star5',
    'heart', 'banner', 'chevron_right', 'cross',
  ];

  static const Map<String, String> _shapeLabels = {
    'rectangle': 'Rectangle', 'rounded': 'Rounded', 'ellipse': 'Circle',
    'line': 'Line', 'arrow_right': 'Arrow right', 'arrow_left': 'Arrow left',
    'arrow_up': 'Arrow up', 'arrow_down': 'Arrow down',
    'double_arrow': 'Double arrow', 'triangle': 'Triangle',
    'diamond': 'Diamond', 'star5': 'Star', 'heart': 'Heart',
    'banner': 'Banner', 'chevron_right': 'Chevron', 'cross': 'Cross',
  };

  Widget _shapesView() {
    return SingleChildScrollView(
      key: const ValueKey('insert_shapes'),
      padding: EdgeInsets.fromLTRB(14, 4, 14, 10 + widget.bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r * 4 < _shapePicks.length; r++)
            Padding(
              padding: EdgeInsets.only(bottom: r * 4 + 3 < _shapePicks.length ? 10 : 0),
              child: Row(
                children: [
                  for (var c = 0; c < 4; c++)
                    if (r * 4 + c < _shapePicks.length)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: c == 0 ? 0 : 5, right: c == 3 ? 0 : 5),
                          child: _ShapeTile(
                            preset: _shapePicks[r * 4 + c],
                            label: _shapeLabels[_shapePicks[r * 4 + c]]!,
                            onTap: () => widget.onPickShape(_shapePicks[r * 4 + c]),
                          ),
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- image sources ----------------------------------------------------------

  Widget _imageSources() {
    return SingleChildScrollView(
      key: const ValueKey('insert_image_sources'),
      padding: EdgeInsets.fromLTRB(14, 4, 14, 10 + widget.bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _InsertTile(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => widget.onPickImage('gallery'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsertTile(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera',
                  onTap: () => widget.onPickImage('camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsertTile(
                  icon: Icons.inventory_2,
                  label: 'Deck Resources',
                  onTap: () => widget.onPickImage('deck'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InsertTile(
                  icon: Icons.public,
                  label: 'Brand Resources',
                  onTap: () => widget.onPickImage('brand'),
                ),
              ),
              const Expanded(child: SizedBox()),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  // ---- media sources ------------------------------------------------------------

  Widget _mediaSources() {
    return SingleChildScrollView(
      key: const ValueKey('insert_media_sources'),
      padding: EdgeInsets.fromLTRB(14, 4, 14, 10 + widget.bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _InsertTile(
                  icon: Icons.movie_outlined,
                  label: 'Video',
                  sub: 'Import a video file',
                  onTap: () => widget.onPickMedia('video'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsertTile(
                  icon: Icons.graphic_eq,
                  label: 'Audio',
                  sub: 'Import an audio file',
                  onTap: () => widget.onPickMedia('audio'),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header + tiles
// ---------------------------------------------------------------------------

/// The drawer's header: the grab handle pill under the centered title —
/// the same header language as the Files drawer's, with the whole header
/// as the sheet's drag surface. A drag up or down streams its deltas to
/// the editor (which resizes the sheet between the shared detents); how
/// it settles — snap to a detent, or dismiss on a downward fling / deep
/// drag — is the editor's call, from the settle velocity it receives
/// here. The back and layers buttons live inside the drag surface: they
/// still take their taps (a tap never wins the vertical-drag arena), and
/// every other touch on the header is a gesture, not a press into
/// whatever the sheet is floating over.
class _InsertHeader extends StatelessWidget {
  const _InsertHeader({
    required this.title,
    required this.showBack,
    required this.onBack,
    required this.onLayers,
    this.onDragUpdate,
    this.onDragSettle,
  });

  final String title;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onLayers;
  final void Function(double dy)? onDragUpdate;
  final void Function(double velocityDy)? onDragSettle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('insert_drawer_handle'),
      // Opaque, like the Files header: a touch on the header is a gesture,
      // never a press through the sheet into the canvas below.
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDragUpdate?.call(d.delta.dy),
      onVerticalDragEnd: (d) =>
          onDragSettle?.call(d.velocity.pixelsPerSecond.dy),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 5),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: kText3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 32,
                    child: showBack
                        ? IconButton(
                            tooltip: 'Back to Insert',
                            icon: const Icon(Icons.arrow_back, size: 18),
                            color: kText2,
                            onPressed: onBack,
                          )
                        : null,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kText,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    height: 32,
                    child: IconButton(
                      tooltip: 'Layers, groups, components',
                      icon: const Icon(Icons.layers_outlined, size: 18),
                      color: kText2,
                      onPressed: onLayers,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One insert tile: icon above label — the 3-column grid's anatomy.
class _InsertTile extends StatelessWidget {
  const _InsertTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 86,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kPurpleWash,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: kPurple),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: kText,
                    height: 1.15,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    sub!,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: kText3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One shape tile: the preset's own silhouette plus its label.
class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.preset,
    required this.label,
    required this.onTap,
  });

  final String preset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final open = preset == 'line';
    return Material(
      color: kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 30,
                child: CustomPaint(
                  painter: _PresetSilhouette(preset: preset, open: open),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: kText2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetSilhouette extends CustomPainter {
  _PresetSilhouette({required this.preset, required this.open});

  final String preset;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final poly = objectPath({
      'preset': preset,
      'x': 3.0,
      'y': 3.0,
      'w': size.width - 6.0,
      'h': size.height - 6.0,
      'closed': true,
    });
    if (poly == null) return;
    if (open) {
      canvas.drawPath(
        poly,
        Paint()
          ..color = kText
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawPath(poly, Paint()..color = kText.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(_PresetSilhouette old) => old.preset != preset;
}

// ---------------------------------------------------------------------------
// The icon picker (a modal — its search field needs the keyboard-safe route)
// ---------------------------------------------------------------------------

Future<void> showIconPicker(
  BuildContext context, {
  required void Function(String name) onPick,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.72,
        child: _IconPickerSheet(onPick: onPick),
      ),
    ),
  );
}

class _IconPickerSheet extends StatefulWidget {
  const _IconPickerSheet({required this.onPick});

  final void Function(String name) onPick;

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text;
    final results =
        kIconRegistry.where((e) => e.matches(query)).toList(growable: false);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Icons / Stickers',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Text('${results.length}',
                    style: const TextStyle(fontSize: 12, color: kText2)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('icon_picker_search'),
              controller: _search,
              autofocus: false,
              style: const TextStyle(color: kText, fontSize: 14),
              cursorColor: kPurple,
              decoration: darkInput(hint: 'Search icons'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Divider(height: 16, color: kHairline),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                childAspectRatio: 0.92,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: results.length,
              itemBuilder: (context, i) {
                final e = results[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onPick(e.name),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: kHairline),
                      borderRadius: BorderRadius.circular(10),
                      color: kElevated,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Expanded(child: Icon(e.icon, size: 22, color: kText2)),
                        const SizedBox(height: 4),
                        Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: kText3),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The object panel
// ---------------------------------------------------------------------------

class _ObjectPanel extends StatelessWidget {
  const _ObjectPanel({
    super.key,
    required this.obj,
    required this.textController,
    required this.textActions,
    required this.palette,
    required this.groupIndex,
    required this.onGroup,
    required this.onObjectStyle,
    required this.onTableCell,
    required this.onEditStyleSheet,
    required this.onStartTyping,
    this.bottomInset = 0,
  });

  final Map<String, dynamic> obj;
  final RichEditingController? textController;
  final TextActions? textActions;
  final List<Color> palette;
  final int groupIndex;
  final void Function(int) onGroup;
  final void Function(Map<String, dynamic>) onObjectStyle;
  final void Function(int index) onTableCell;
  final VoidCallback onEditStyleSheet;
  final VoidCallback onStartTyping;

  /// The tray clearance for the body's scrollable (scroll content, never
  /// chrome — the same contract as the Files drawer's grid).
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final groups = _groupsFor(obj);
    final group = groups[groupIndex.clamp(0, groups.length - 1)];
    return Row(
      key: const ValueKey('insert_object_panel'),
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 10),
            child: SingleChildScrollView(
              key: ValueKey('panel_body_${group.id}'),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: group.body(this, context),
            ),
          ),
        ),
        // The narrow icon-only rail on the far right: switches between
        // groups of controls; the active group is highlighted.
        Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: kHairline)),
          ),
          width: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              for (var i = 0; i < groups.length; i++)
                _RailButton(
                  icon: groups[i].icon,
                  tooltip: groups[i].label,
                  active: i == groupIndex,
                  onTap: () => onGroup(i),
                ),
              const Spacer(),
              _RailButton(
                icon: Icons.tune,
                tooltip: 'Full style inspector',
                active: false,
                onTap: onEditStyleSheet,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  List<_PanelGroup> _groupsFor(Map<String, dynamic> obj) {
    switch (ObjectContent.kindOf(obj)) {
      case kContentText:
        final controller = textController;
        final actions = textActions;
        if (controller != null && actions != null) {
          return [
            _PanelGroup(
              id: 'quick',
              icon: Icons.format_align_center,
              label: 'Quick Tools',
              body: (p, ctx) => _TextQuickTools(
                controller: controller,
                actions: actions,
                palette: palette,
                startTyping: onStartTyping,
              ),
            ),
            _PanelGroup(
              id: 'character',
              icon: Icons.text_fields,
              label: 'Character',
              body: (p, ctx) => _TextCharacterTools(
                controller: controller,
                actions: actions,
              ),
            ),
            _PanelGroup(
              id: 'para',
              icon: Icons.subject,
              label: 'Paragraph & Box',
              body: (p, ctx) => _TextParaTools(
                controller: controller,
                actions: actions,
              ),
            ),
          ];
        }
        return [
          _PanelGroup(
            id: 'none',
            icon: Icons.hourglass_empty,
            label: 'Loading…',
            body: (p, ctx) => const _PanelBody(children: []),
          ),
        ];
      case kContentTable:
        return [
          _PanelGroup(
            id: 'cells',
            icon: Icons.grid_on,
            label: 'Cells',
            body: (p, ctx) => _TableCells(obj: obj, onTableCell: onTableCell),
          ),
          _PanelGroup(
            id: 'style',
            icon: Icons.palette_outlined,
            label: 'Grid style',
            body: (p, ctx) => _GridStyleTools(
                obj: obj, onObjectStyle: onObjectStyle, palette: palette),
          ),
        ];
      case kContentImage:
        return [
          _PanelGroup(
            id: 'frame',
            icon: Icons.image_outlined,
            label: 'Frame',
            body: (p, ctx) => _FrameTools(
                obj: obj, onObjectStyle: onObjectStyle, palette: palette),
          ),
        ];
      case kContentIcon:
        return [
          _PanelGroup(
            id: 'color',
            icon: Icons.palette_outlined,
            label: 'Color',
            body: (p, ctx) => _IconColorTools(
                obj: obj, onObjectStyle: onObjectStyle, palette: palette),
          ),
        ];
      case kContentMedia:
        return [
          _PanelGroup(
            id: 'info',
            icon: Icons.info_outline,
            label: 'Info',
            body: (p, ctx) => _MediaInfo(obj: obj),
          ),
        ];
      default:
        // A plain vector shape: the quick style group.
        return [
          _PanelGroup(
            id: 'style',
            icon: Icons.palette_outlined,
            label: 'Style',
            body: (p, ctx) => _ShapeStyleTools(
                obj: obj, onObjectStyle: onObjectStyle, palette: palette),
          ),
        ];
    }
  }
}

class _PanelGroup {
  const _PanelGroup({
    required this.id,
    required this.icon,
    required this.label,
    required this.body,
  });

  final String id;
  final IconData icon;
  final String label;
  final Widget Function(_ObjectPanel panel, BuildContext ctx) body;
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: 54,
        height: 46,
        child: Material(
          color: active ? const Color(0x1FFFFFFF) : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Icon(
              icon,
              size: 21,
              color: active ? kText : kText3,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text panel groups
// ---------------------------------------------------------------------------

class _TextQuickTools extends StatelessWidget {
  const _TextQuickTools({
    required this.controller,
    required this.actions,
    required this.palette,
    this.startTyping,
  });

  final RichEditingController controller;
  final TextActions actions;
  final List<Color> palette;
  final VoidCallback? startTyping;

  (int, int) get _sel {
    final s = controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _sel;
    final doc = controller.doc;
    final caret = (a == b) ? a : b;
    final para = doc.effectiveParaAt(caret.clamp(0, doc.text.length));
    return _PanelBody(
      children: [
        if (startTyping != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('panel_edit_text'),
              onPressed: startTyping,
              icon: const Icon(Icons.keyboard_alt_outlined, size: 16),
              label: const Text('Edit text'),
            ),
          ),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_bold,
              active: doc.isFlagActive(a, b, 'bold'),
              onTap: () => actions.toggleFlag('bold'),
            ),
            _PanelIconToggle(
              icon: Icons.format_italic,
              active: doc.isFlagActive(a, b, 'italic'),
              onTap: () => actions.toggleFlag('italic'),
            ),
            _PanelIconToggle(
              icon: Icons.format_underline,
              active: doc.isFlagActive(a, b, 'underline'),
              onTap: () => actions.toggleFlag('underline'),
            ),
          ],
        ),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_align_left,
              active: (para?.align ?? 'left') == 'left',
              onTap: () => actions.setAlign('left'),
            ),
            _PanelIconToggle(
              icon: Icons.format_align_center,
              active: (para?.align ?? 'left') == 'center',
              onTap: () => actions.setAlign('center'),
            ),
            _PanelIconToggle(
              icon: Icons.format_align_right,
              active: (para?.align ?? 'left') == 'right',
              onTap: () => actions.setAlign('right'),
            ),
            _PanelIconToggle(
              icon: Icons.format_align_justify,
              active: (para?.align ?? 'left') == 'justify',
              onTap: () => actions.setAlign('justify'),
            ),
            const Spacer(),
            _PanelIconToggle(
              icon: Icons.format_list_bulleted,
              active: (para?.list ?? 'none') == 'bullet',
              onTap: () => actions.toggleList('bullet'),
            ),
            _PanelIconToggle(
              icon: Icons.format_list_numbered,
              active: (para?.list ?? 'none') == 'number',
              onTap: () => actions.toggleList('number'),
            ),
          ],
        ),
        _ColorChips(
          label: 'TEXT COLOR',
          palette: palette,
          selected: _runAttr(a, b, (r) => r.color),
          onPick: actions.setColor,
        ),
        _ColorChips(
          label: 'HIGHLIGHT — behind the text',
          palette: palette,
          selected: _runAttr(a, b, (r) => r.highlight),
          onPick: actions.setHighlight,
        ),
      ],
    );
  }

  String? _runAttr(int a, int b, String? Function(RichRun) pick) {
    final doc = controller.doc;
    for (final r in doc.runs) {
      if (r.end <= r.start) continue;
      if (r.start < b && a < r.end) return pick(r);
    }
    return null;
  }
}

class _TextCharacterTools extends StatelessWidget {
  const _TextCharacterTools({required this.controller, required this.actions});

  final RichEditingController controller;
  final TextActions actions;

  (int, int) get _sel {
    final s = controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  double get _fontSize {
    final v = _caretAwareAttr((r) => r.fontSize);
    return v is num ? v.toDouble() : 32;
  }

  String get _family {
    final v = _caretAwareAttr((r) => r.fontFamily);
    return v is String ? v : 'sans';
  }

  /// A collapsed caret reads its TYPING SOURCE (the pending mark at the
  /// caret, else the character before it) — "affects what I type next" —
  /// while a selection reads the runs it covers.
  Object? _caretAwareAttr(Object? Function(RichRun) pick) {
    final (a, b) = _sel;
    final doc = controller.doc;
    if (a == b) {
      final src = doc.typingSourceAt(a);
      if (src != null) {
        final v = pick(src);
        if (v != null) return v;
      }
      return null;
    }
    for (final r in doc.runs) {
      if (r.end <= r.start) continue;
      if (r.start < b && a < r.end) {
        final v = pick(r);
        if (v != null) return v;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _sel;
    final doc = controller.doc;
    return _PanelBody(
      children: [
        const _PanelLabel('FONT FAMILY'),
        _PanelRow(
          children: [
            _ChoiceChip2(
              label: 'Sans',
              selected: _family == 'sans',
              onTap: () => actions.setFontFamily(null),
            ),
            const SizedBox(width: 8),
            _ChoiceChip2(
              label: 'Serif',
              selected: _family == 'serif',
              onTap: () => actions.setFontFamily('serif'),
            ),
            const SizedBox(width: 8),
            _ChoiceChip2(
              label: 'Mono',
              selected: _family == 'mono',
              onTap: () => actions.setFontFamily('mono'),
            ),
          ],
        ),
        const _PanelLabel('FONT SIZE'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              key: const ValueKey('panel_font_minus'),
              icon: Icons.remove,
              onTap: () => actions.setFontSize(
                  (_fontSize - 4).clamp(8.0, 96.0).toDouble()),
            ),
            SizedBox(
              width: 56,
              child: Center(
                child: Text(
                  _fontSize.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                ),
              ),
            ),
            _PanelIconToggle(
              key: const ValueKey('panel_font_plus'),
              icon: Icons.add,
              onTap: () => actions.setFontSize(
                  (_fontSize + 4).clamp(8.0, 96.0).toDouble()),
            ),
          ],
        ),
        const _PanelLabel('CHARACTER'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_strikethrough,
              active: doc.isFlagActive(a, b, 'strike'),
              onTap: () => actions.toggleFlag('strike'),
            ),
            _PanelIconToggle(
              icon: Icons.subscript,
              active: doc.isFlagActive(a, b, 'subscript'),
              onTap: () => actions.toggleFlag('subscript'),
            ),
            _PanelIconToggle(
              icon: Icons.superscript,
              active: doc.isFlagActive(a, b, 'superscript'),
              onTap: () => actions.toggleFlag('superscript'),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: actions.clearFormatting,
            icon: const Icon(Icons.format_clear, size: 16),
            label: const Text('Clear formatting — back to slide theme'),
          ),
        ),
      ],
    );
  }
}

class _TextParaTools extends StatelessWidget {
  const _TextParaTools({required this.controller, required this.actions});

  final RichEditingController controller;
  final TextActions actions;

  (int, int) get _sel {
    final s = controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _sel;
    final doc = controller.doc;
    final caret = (a == b) ? a : b;
    final para = doc.effectiveParaAt(caret.clamp(0, doc.text.length));
    final spacing = para?.lineSpacing ?? 1.15;
    final indent = para?.indent ?? 0;
    return _PanelBody(
      children: [
        const _PanelLabel('ALIGNMENT INSIDE THE BOX'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.vertical_align_top,
              active: doc.valign == 'top',
              onTap: () => actions.setValign('top'),
            ),
            _PanelIconToggle(
              icon: Icons.vertical_align_center,
              active: doc.valign == 'middle',
              onTap: () => actions.setValign('middle'),
            ),
            _PanelIconToggle(
              icon: Icons.vertical_align_bottom,
              active: doc.valign == 'bottom',
              onTap: () => actions.setValign('bottom'),
            ),
          ],
        ),
        const _PanelLabel('LINE SPACING'),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in const [1.0, 1.15, 1.5, 2.0])
                _ChoiceChip2(
                  label: s == 1.0 ? '1.0' : s.toString(),
                  selected: (spacing - s).abs() < 0.001,
                  onTap: () => actions.setLineSpacing(s),
                ),
            ],
          ),
        ),
        const _PanelLabel('LIST INDENT'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_indent_decrease,
              onTap: () => actions.indentBy(-1),
            ),
            SizedBox(
              width: 56,
              child: Center(
                child: Text(
                  'level $indent',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                ),
              ),
            ),
            _PanelIconToggle(
              icon: Icons.format_indent_increase,
              onTap: () => actions.indentBy(1),
            ),
          ],
        ),
        const _PanelLabel('OVERFLOW'),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ChoiceChip2(
                label: 'Shrink text on overflow',
                selected: doc.autofit == 'shrink',
                onTap: () => actions.setAutofit('shrink'),
              ),
              _ChoiceChip2(
                label: 'No autofit',
                selected: doc.autofit == 'none',
                onTap: () => actions.setAutofit('none'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Non-text panel groups
// ---------------------------------------------------------------------------

class _TableCells extends StatelessWidget {
  const _TableCells({required this.obj, required this.onTableCell});

  final Map<String, dynamic> obj;
  final void Function(int index) onTableCell;

  @override
  Widget build(BuildContext context) {
    final (rows, cols, cells) = ObjectContent.tableOf(obj);
    return _PanelBody(
      children: [
        const _PanelLabel('TAP A CELL TO EDIT ITS TEXT'),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var c = 0; c < cols; c++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: c == 0 ? 0 : 4, right: c == cols - 1 ? 0 : 4),
                      child: _CellButton(
                        index: r * cols + c,
                        text: cells[r * cols + c],
                        onTap: () => onTableCell(r * cols + c),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CellButton extends StatelessWidget {
  const _CellButton({required this.index, required this.text, required this.onTap});

  final int index;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('table_cell_$index'),
      color: kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                text.isEmpty ? '·' : text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  color: text.isEmpty ? kText3 : kText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridStyleTools extends StatelessWidget {
  const _GridStyleTools({
    required this.obj,
    required this.onObjectStyle,
    required this.palette,
  });

  final Map<String, dynamic> obj;
  final void Function(Map<String, dynamic>) onObjectStyle;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final stroke = (obj['stroke'] as Map?) ?? const {};
    return _PanelBody(
      children: [
        _ColorChips(
          label: 'GRID LINE COLOR',
          palette: palette,
          selected: (stroke['color'] ?? '17181A').toString(),
          onPick: (hex) => onObjectStyle(_styled(obj,
              stroke: {...stroke, 'color': hex ?? '17181A', 'width': (stroke['width'] ?? 1.5)})),
        ),
      ],
    );
  }
}

class _FrameTools extends StatelessWidget {
  const _FrameTools({
    required this.obj,
    required this.onObjectStyle,
    required this.palette,
  });

  final Map<String, dynamic> obj;
  final void Function(Map<String, dynamic>) onObjectStyle;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final stroke = (obj['stroke'] as Map?) ?? const {};
    final width = ((stroke['width'] ?? 0) as num).toDouble();
    return _PanelBody(
      children: [
        const _PanelLabel('BORDER'),
        _PanelRow(
          children: [
            _ChoiceChip2(
              label: 'None',
              selected: width <= 0,
              onTap: () => onObjectStyle(
                  _styled(obj, stroke: {...stroke, 'width': 0.0})),
            ),
            const SizedBox(width: 8),
            _ChoiceChip2(
              label: 'Hairline',
              selected: width > 0 && width <= 2,
              onTap: () => onObjectStyle(
                  _styled(obj, stroke: {...stroke, 'width': 1.5})),
            ),
            const SizedBox(width: 8),
            _ChoiceChip2(
              label: 'Bold',
              selected: width > 2,
              onTap: () =>
                  onObjectStyle(_styled(obj, stroke: {...stroke, 'width': 4.0})),
            ),
          ],
        ),
        _ColorChips(
          label: 'BORDER COLOR',
          palette: palette,
          selected: (stroke['color'] ?? '17181A').toString(),
          onPick: (hex) => onObjectStyle(
              _styled(obj, stroke: {...stroke, 'color': hex ?? '17181A'})),
        ),
        _OpacityControl(obj: obj, onObjectStyle: onObjectStyle),
      ],
    );
  }
}

class _IconColorTools extends StatelessWidget {
  const _IconColorTools({
    required this.obj,
    required this.onObjectStyle,
    required this.palette,
  });

  final Map<String, dynamic> obj;
  final void Function(Map<String, dynamic>) onObjectStyle;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final fill = (obj['fill'] as Map?) ?? const {};
    return _PanelBody(
      children: [
        _ColorChips(
          label: 'ICON COLOR',
          palette: palette,
          selected: (fill['color'] ?? 'F5F5F7').toString(),
          onPick: (hex) => onObjectStyle(
              _styled(obj, fill: {'type': 'solid', 'color': hex ?? 'F5F5F7'})),
        ),
        _OpacityControl(obj: obj, onObjectStyle: onObjectStyle),
      ],
    );
  }
}

class _MediaInfo extends StatelessWidget {
  const _MediaInfo({required this.obj});

  final Map<String, dynamic> obj;

  @override
  Widget build(BuildContext context) {
    final content = ObjectContent.of(obj) ?? const {};
    final name = (content['name'] ?? 'media').toString();
    final kind = (content['media_kind'] ?? 'video') == 'video'
        ? 'Video clip'
        : 'Audio clip';
    return _PanelBody(
      children: [
        const _PanelLabel('THIS SLIDE\'S MEDIA'),
        Row(
          children: [
            Icon(
              kind == 'Video clip'
                  ? Icons.videocam_outlined
                  : Icons.graphic_eq,
              size: 20,
              color: kText2,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: kText),
                  ),
                  Text(
                    '$kind · imported file (no recording)',
                    style: const TextStyle(fontSize: 11, color: kText3),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _ShapeStyleTools extends StatelessWidget {
  const _ShapeStyleTools({
    required this.obj,
    required this.onObjectStyle,
    required this.palette,
  });

  final Map<String, dynamic> obj;
  final void Function(Map<String, dynamic>) onObjectStyle;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final fill = (obj['fill'] as Map?) ?? const {};
    final fillType = (fill['type'] ?? 'none').toString();
    final stroke = (obj['stroke'] as Map?) ?? const {};
    return _PanelBody(
      children: [
        const _PanelLabel('FILL'),
        _PanelRow(
          children: [
            _ChoiceChip2(
              label: 'None',
              selected: fillType == 'none',
              onTap: () => onObjectStyle(_styled(obj, fill: {'type': 'none'})),
            ),
            const SizedBox(width: 8),
            _ChoiceChip2(
              label: 'Solid',
              selected: fillType == 'solid',
              onTap: () => onObjectStyle(_styled(obj,
                  fill: {'type': 'solid', 'color': (fill['color'] ?? 'D03028')})),
            ),
          ],
        ),
        if (fillType == 'solid')
          _ColorChips(
            label: 'FILL COLOR',
            palette: palette,
            selected: (fill['color'] ?? 'D03028').toString(),
            onPick: (hex) => onObjectStyle(
                _styled(obj, fill: {'type': 'solid', 'color': hex ?? 'D03028'})),
          ),
        const _PanelLabel('STROKE WIDTH'),
        _PanelRow(
          children: [
            for (final w in const [0.0, 1.5, 4.0, 8.0])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ChoiceChip2(
                  label: w == 0.0
                      ? 'None'
                      : w.toStringAsFixed(w == 1.5 ? 1 : 0),
                  selected:
                      (((stroke['width'] ?? 0) as num).toDouble() - w).abs() <
                          0.001,
                  onTap: () => onObjectStyle(
                      _styled(obj, stroke: {...stroke, 'width': w})),
                ),
              ),
          ],
        ),
        _ColorChips(
          label: 'STROKE COLOR',
          palette: palette,
          selected: (stroke['color'] ?? '17181A').toString(),
          onPick: (hex) => onObjectStyle(
              _styled(obj, stroke: {...stroke, 'color': hex ?? '17181A'})),
        ),
        _OpacityControl(obj: obj, onObjectStyle: onObjectStyle),
      ],
    );
  }
}

class _OpacityControl extends StatelessWidget {
  const _OpacityControl({required this.obj, required this.onObjectStyle});

  final Map<String, dynamic> obj;
  final void Function(Map<String, dynamic>) onObjectStyle;

  @override
  Widget build(BuildContext context) {
    final opacity = ((obj['opacity'] ?? 1) as num).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelLabel('OPACITY — ${(opacity * 100).round()}%'),
        Slider(
          value: opacity.clamp(0.05, 1.0),
          min: 0.05,
          max: 1.0,
          activeColor: kPurple,
          onChanged: (v) => onObjectStyle(_styled(obj, opacity: v)),
        ),
      ],
    );
  }
}

Map<String, dynamic> _styled(
  Map<String, dynamic> obj, {
  Map<String, dynamic>? fill,
  Map<String, dynamic>? stroke,
  double? opacity,
}) {
  final copy = Map<String, dynamic>.from(obj);
  if (fill != null) copy['fill'] = fill;
  if (stroke != null) copy['stroke'] = stroke;
  if (opacity != null) copy['opacity'] = opacity;
  return copy;
}

// ---------------------------------------------------------------------------
// Panel scaffolding widgets
// ---------------------------------------------------------------------------

class _PanelBody extends StatelessWidget {
  const _PanelBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 0, 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: kText3,
        ),
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(children: children),
    );
  }
}

class _PanelIconToggle extends StatelessWidget {
  const _PanelIconToggle({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = false,
  });


  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: active ? kPurpleWash : kElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: active ? kPurple : kHairline),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Icon(icon, size: 19, color: active ? kPurple : kText2),
          ),
        ),
      ),
    );
  }
}

class _ChoiceChip2 extends StatelessWidget {
  const _ChoiceChip2({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kPurpleWash : kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? kPurple : kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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

class _ColorChips extends StatelessWidget {
  const _ColorChips({
    required this.label,
    required this.palette,
    required this.selected,
    required this.onPick,
  });

  final String label;
  final List<Color> palette;
  final String? selected;
  final void Function(String? hex) onPick;

  static String _hexKey(Color c) =>
      ((c.r * 255).round() << 16 |
              (c.g * 255).round() << 8 |
              (c.b * 255).round())
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelLabel(label),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _clearChip(),
              for (final c in palette)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(_hexKey(c)),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected == _hexKey(c) ? kMagenta : kHairline,
                        width: selected == _hexKey(c) ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _clearChip() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(null),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected == null ? kMagenta : kHairline,
            width: selected == null ? 2 : 1,
          ),
        ),
        child: const Icon(Icons.block, size: 14, color: kText3),
      ),
    );
  }
}
