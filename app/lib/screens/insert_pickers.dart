part of 'insert_sheet.dart';

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
    // A DIFFERENT selection (a new insert or a canvas tap on another
    // object — not only the null -> non-null transition) replaces
    // whatever picker was open with the new object's editing panel, at
    // its first group; dropping the selection returns to the resting
    // grid. Same-id rebuilds (live style edits) keep their place.
    final newId = widget.selectedObject?['id'];
    final oldId = old.selectedObject?['id'];
    if (newId != oldId) {
      _panelGroup = 0;
      _view = _InsertView.grid;
    }
  }

  bool get _panelShown =>
      widget.selectedObject != null && _view == _InsertView.grid;

  void _back() {
    // Two different backs, one arrow: a subsection's back returns to the
    // grid; the object PANEL's back is "stop editing" — the editor drops
    // the selection (the object itself stays on the slide).
    if (_panelShown) {
      widget.onPanelBack();
      return;
    }
    setState(() => _view = _InsertView.grid);
  }

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
          DreamDrawerHeader(
            title: title,
            dragKey: const ValueKey('insert_drawer_handle'),
            // The back arrow serves every view that is NOT the resting
            // grid: the pickers (Shapes / Image / Media) AND the object
            // panel — editing a table or an icon is as deep a view as a
            // picker, and it needs the same way out.
            showBack: _view != _InsertView.grid || panel,
            backTooltip: 'Back to Insert',
            onBack: _back,
            trailing: IconButton(
              key: const ValueKey('insert_drawer_layers'),
              tooltip: 'Layers, groups, components',
              icon: const Icon(Icons.layers_outlined, size: 18),
              color: kText2,
              onPressed: widget.onShowLayers,
            ),
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
        onPlayMedia: widget.onPlayMedia,
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
          DreamTileRow(tiles: [
            DreamToolTile(
              icon: Icons.text_fields,
              label: 'Text Box',
              onTap: widget.onInsertTextBox,
            ),
            DreamToolTile(
              icon: Icons.image_outlined,
              label: 'Image',
              onTap: () => setState(() => _view = _InsertView.image),
            ),
            DreamToolTile(
              icon: Icons.category_outlined,
              label: 'Shapes',
              onTap: () => setState(() => _view = _InsertView.shapes),
            ),
          ]),
          const SizedBox(height: 10),
          DreamTileRow(tiles: [
            DreamToolTile(
              icon: Icons.grid_on,
              label: 'Table',
              onTap: widget.onInsertTable,
            ),
            DreamToolTile(
              icon: Icons.emoji_emotions_outlined,
              label: 'Icons / Stickers',
              onTap: () => showIconPicker(context,
                  onPick: widget.onInsertIcon),
            ),
            DreamToolTile(
              icon: Icons.perm_media_outlined,
              label: 'Media',
              onTap: () => setState(() => _view = _InsertView.media),
            ),
          ]),
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
          DreamTileRow(tiles: [
            DreamToolTile(
              icon: Icons.photo_library_outlined,
              label: 'Gallery',
              onTap: () => widget.onPickImage('gallery'),
            ),
            DreamToolTile(
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              onTap: () => widget.onPickImage('camera'),
            ),
            DreamToolTile(
              icon: Icons.inventory_2,
              label: 'Deck Resources',
              onTap: () => widget.onPickImage('deck'),
            ),
          ]),
          const SizedBox(height: 10),
          DreamTileRow(tiles: [
            DreamToolTile(
              icon: Icons.public,
              label: 'Brand Resources',
              onTap: () => widget.onPickImage('brand'),
            ),
          ]),
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
          DreamTileRow(tiles: [
            DreamToolTile(
              icon: Icons.movie_outlined,
              label: 'Video',
              sub: 'Import a video file',
              onTap: () => widget.onPickMedia('video'),
            ),
            DreamToolTile(
              icon: Icons.graphic_eq,
              label: 'Audio',
              sub: 'Import an audio file',
              onTap: () => widget.onPickMedia('audio'),
            ),
          ]),
        ],
      ),
    );
  }
}

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
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
            child: Row(
              children: [
                // The picker's own back arrow: the sheet is modal, but the
                // way out must never depend on knowing that — the arrow
                // pops the route like any header's back would.
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    key: const ValueKey('icon_picker_back'),
                    tooltip: 'Back to Insert',
                    icon: const Icon(Icons.arrow_back, size: 18),
                    color: kText2,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: Text('Icons / Stickers',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('${results.length}',
                      style: const TextStyle(fontSize: 12, color: kText2)),
                ),
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
                  onTap: () {
                    widget.onPick(e.name);
                    // The pick is a commitment: the sticker inserts and
                    // the sheet closes — the object's own panel takes
                    // over behind it. Staying open would bury the result
                    // of the tap behind the picker.
                    Navigator.of(context).pop();
                  },
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

/// One shape tile: the preset's own silhouette plus its label — the
/// same elevated-card language as the insert tiles, at the denser
/// 4-across grid the shape palette wants.
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
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                height: 32,
                child: CustomPaint(
                  painter: _PresetSilhouette(preset: preset, open: open),
                ),
              ),
              const SizedBox(height: 6),
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
