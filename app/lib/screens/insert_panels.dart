part of 'insert_sheet.dart';

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
    required this.tableEntry,
    required this.onTableUpdate,
    required this.onTableStyle,
    required this.onEditStyleSheet,
    required this.onStartTyping,
    this.imageEntry,
    this.onImageUpdate,
    this.onReplaceImage,
    this.onPlayMedia,
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

  /// The selected table's deck-level metadata entry (merges + style),
  /// null for non-table selections (and plain, unmerged tables).
  final Map<String, dynamic>? tableEntry;

  /// Commits a table structure change (updated object + updated entry,
  /// one undo step).
  final void Function(Map<String, dynamic> obj, Map<String, dynamic>? entry)
      onTableUpdate;

  /// Applies a named table style — the editor resolves DNA colors.
  final void Function(String style) onTableStyle;

  /// The selected image's metadata entry (shape/brightness/contrast/alt),
  /// null for non-image selections. See [InsertSheet.imageEntry].
  final Map<String, dynamic>? imageEntry;

  /// Commits an image metadata change (null/empty = entry folds away).
  final void Function(Map<String, dynamic> obj, Map<String, dynamic>? entry)?
      onImageUpdate;

  /// Opens the image library to swap the selected image's asset.
  final VoidCallback? onReplaceImage;

  final VoidCallback onEditStyleSheet;
  final VoidCallback onStartTyping;

  /// Plays the media object's resolved file (media group only).
  final void Function(Map<String, dynamic> obj)? onPlayMedia;

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
        // groups of controls; the active group is highlighted. The full
        // style inspector sits right under the group buttons — never
        // pinned to the rail's bottom: the filmstrip tray (raised fold
        // arrow included) rides the sheet's lower part and would bury a
        // bottom-pinned control behind it.
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
              const SizedBox(height: 6),
              _RailButton(
                icon: Icons.tune,
                tooltip: 'Full style inspector',
                active: false,
                onTap: onEditStyleSheet,
              ),
              const Spacer(),
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
            body: (p, ctx) => _TableCells(
                obj: obj,
                onTableCell: onTableCell,
                entry: p.tableEntry,
                onTableUpdate: p.onTableUpdate),
          ),
          _PanelGroup(
            id: 'style',
            icon: Icons.palette_outlined,
            label: 'Table style',
            body: (p, ctx) => _GridStyleTools(
                obj: obj,
                onObjectStyle: onObjectStyle,
                palette: palette,
                entry: p.tableEntry,
                onTableStyle: p.onTableStyle),
          ),
        ];
      case kContentImage:
        return [
          _PanelGroup(
            id: 'frame',
            icon: Icons.image_outlined,
            label: 'Frame',
            body: (p, ctx) => _FrameTools(
                obj: obj,
                onObjectStyle: onObjectStyle,
                palette: palette,
                entry: p.imageEntry,
                onImageUpdate: p.onImageUpdate,
                onReplaceImage: p.onReplaceImage),
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
            body: (p, ctx) => _MediaInfo(
              obj: obj,
              onPlay: onPlayMedia == null
                  ? null
                  : () => onPlayMedia!(obj),
            ),
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

/// The table's Cells group: the cell grid plus the structure actions.
///
/// **Tap a cell to edit its text** (the route dialog, unchanged); **long-press
/// a cell to toggle it into a selection** (the long-press is the context
/// menu — the same governing principle the object actions live by). The
/// selection drives the structure chips below the grid: add/remove row &
/// column relative to the selection, and merge/split. A merged region
/// renders as ONE wide cell (covered cells have no button of their own).
class _TableCells extends StatefulWidget {
  const _TableCells({
    required this.obj,
    required this.onTableCell,
    required this.entry,
    required this.onTableUpdate,
  });

  final Map<String, dynamic> obj;
  final void Function(int index) onTableCell;

  /// The table's deck-level metadata entry (merges + style), or null.
  final Map<String, dynamic>? entry;

  /// Commits a structure change: updated object + updated entry, one
  /// undo step (the editor's cell-edit contract).
  final void Function(Map<String, dynamic> obj, Map<String, dynamic>? entry)
      onTableUpdate;

  @override
  State<_TableCells> createState() => _TableCellsState();
}

class _TableCellsState extends State<_TableCells> {
  /// Selected ANCHOR cell indices (a merged region selects as one unit —
  /// its anchor). Long-press toggles membership.
  final Set<int> _selected = {};

  static const _actionSpacing = EdgeInsets.only(left: 4, right: 4);

  (int, int, List<String>) get _table => ObjectContent.tableOf(widget.obj);

  List<Map<String, dynamic>> get _regions =>
      ObjectContent.tableMergesOf(widget.entry,
          rows: _table.$1, cols: _table.$2);

  /// The region whose anchor is at flat [index], or null.
  Map<String, dynamic>? _regionOfAnchor(int index) {
    final (rows, cols, _) = _table;
    if (rows == 0 || cols == 0) return null;
    final r = index ~/ cols, c = index % cols;
    for (final m in _regions) {
      if ((m['r'] as num).toInt() == r && (m['c'] as num).toInt() == c) {
        return m;
      }
    }
    return null;
  }

  /// Every (row, col) covered by the selection — anchor regions included.
  Set<(int, int)> get _selectedCells {
    final (rows, cols, _) = _table;
    final out = <(int, int)>{};
    for (final idx in _selected) {
      if (idx >= rows * cols) continue;
      final r = idx ~/ cols, c = idx % cols;
      final m = _regionOfAnchor(idx);
      if (m == null) {
        out.add((r, c));
      } else {
        final rs = (m['rs'] as num).toInt(), cs = (m['cs'] as num).toInt();
        for (var dr = 0; dr < rs; dr++) {
          for (var dc = 0; dc < cs; dc++) {
            out.add((r + dr, c + dc));
          }
        }
      }
    }
    return out;
  }

  /// The selection's bounding box, or null when nothing is selected.
  ((int, int), (int, int))? get _selectionBox {
    final cells = _selectedCells;
    if (cells.isEmpty) return null;
    var r0 = 1 << 30, r1 = -1, c0 = 1 << 30, c1 = -1;
    for (final (r, c) in cells) {
      if (r < r0) r0 = r;
      if (r > r1) r1 = r;
      if (c < c0) c0 = c;
      if (c > c1) c1 = c;
    }
    return ((r0, c0), (r1, c1));
  }

  bool get _isExactRectangle {
    final box = _selectionBox;
    if (box == null) return false;
    final ((r0, c0), (r1, c1)) = box;
    return _selectedCells.length == (r1 - r0 + 1) * (c1 - c0 + 1);
  }

  /// Can the selection merge? It must be an exact rectangle of 2+ cells,
  /// and every existing merge region must sit either fully INSIDE it (then
  /// fully selected — absorbed) or fully OUTSIDE — nothing may stick into
  /// the rectangle or fill only part of it.
  bool get _canMerge {
    final box = _selectionBox;
    if (box == null) return false;
    final ((r0, c0), (r1, c1)) = box;
    if (!_isExactRectangle || _selectedCells.length < 2) return false;
    for (final m in _regions) {
      final mr = (m['r'] as num).toInt(), mc = (m['c'] as num).toInt();
      final rs = (m['rs'] as num).toInt(), cs = (m['cs'] as num).toInt();
      var inside = 0;
      for (var dr = 0; dr < rs; dr++) {
        for (var dc = 0; dc < cs; dc++) {
          final cell = (mr + dr, mc + dc);
          final inBox = cell.$1 >= r0 &&
              cell.$1 <= r1 &&
              cell.$2 >= c0 &&
              cell.$2 <= c1;
          // Every region cell must match the box on both sides — a
          // half-in region sticks into the rectangle, an unselected
          // in-box cell leaves a hole.
          if (inBox != _selectedCells.contains(cell)) return false;
          if (inBox) inside++;
        }
      }
      if (inside > 0 && inside < rs * cs) return false;
    }
    return true;
  }

  /// Can the selection split? Some existing merge region's anchor must be
  /// selected (splitting returns its covered cells to independence).
  bool get _canSplit => _selected.any((i) => _regionOfAnchor(i) != null);

  // ---- structure transforms ----------------------------------------------

  /// Insert a row at [at]: cells shift down; regions above stay, regions
  /// spanning the seam grow by a row, regions below shift down.
  void _insertRow(int at) {
    final (rows, cols, cells) = _table;
    final out = List<String>.from(cells);
    out.insertAll(at * cols, List.filled(cols, ''));
    final merges = [
      for (final m in _regions)
        () {
          final r = (m['r'] as num).toInt();
          final rs = (m['rs'] as num).toInt();
          if (r >= at) {
            return {...m, 'r': r + 1};
          } else if (r + rs > at) {
            return {...m, 'rs': rs + 1};
          }
          return m;
        }(),
    ];
    _commit(rows + 1, cols, out, merges);
  }

  void _insertCol(int at) {
    final (rows, cols, cells) = _table;
    final out = List<String>.from(cells);
    for (var r = rows - 1; r >= 0; r--) {
      out.insert(r * cols + at, '');
    }
    final merges = [
      for (final m in _regions)
        () {
          final c = (m['c'] as num).toInt();
          final cs = (m['cs'] as num).toInt();
          if (c >= at) {
            return {...m, 'c': c + 1};
          } else if (c + cs > at) {
            return {...m, 'cs': cs + 1};
          }
          return m;
        }(),
    ];
    _commit(rows, cols + 1, out, merges);
  }

  /// Delete the rows covered by the selection. Regions on a deleted row
  /// go with it (their anchor text dies with the row, like any cell's);
  /// regions below shift up.
  void _deleteRows() {
    final (rows, cols, cells) = _table;
    final gone = _selectedCells.map(((int, int) c) => c.$1).toSet();
    if (gone.isEmpty || gone.length >= rows) return;
    final out = <String>[
      for (var r = 0; r < rows; r++)
        if (!gone.contains(r)) ...cells.sublist(r * cols, r * cols + cols),
    ];
    final merges = <Map<String, dynamic>>[];
    for (final m in _regions) {
      final r = (m['r'] as num).toInt();
      final rs = (m['rs'] as num).toInt();
      final hit = [for (var dr = 0; dr < rs; dr++) r + dr]
          .any(gone.contains);
      if (hit) continue; // a region crossing a deleted row folds away
      final shift = gone.where((g) => g < r).length;
      merges.add({...m, 'r': r - shift});
    }
    _commit(rows - gone.length, cols, out, merges);
  }

  void _deleteCols() {
    final (rows, cols, cells) = _table;
    final gone = _selectedCells.map(((int, int) c) => c.$2).toSet();
    if (gone.isEmpty || gone.length >= cols) return;
    final out = <String>[
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < cols; c++)
          if (!gone.contains(c)) cells[r * cols + c],
    ];
    final merges = <Map<String, dynamic>>[];
    for (final m in _regions) {
      final c = (m['c'] as num).toInt();
      final cs = (m['cs'] as num).toInt();
      final hit = [for (var dc = 0; dc < cs; dc++) c + dc]
          .any(gone.contains);
      if (hit) continue;
      final shift = gone.where((g) => g < c).length;
      merges.add({...m, 'c': c - shift});
    }
    _commit(rows, cols - gone.length, out, merges);
  }

  /// Merge the selection's rectangle: non-empty cell texts in the region
  /// join into the anchor (space-separated — text is never lost), covered
  /// cells empty out, regions fully inside the rectangle are absorbed.
  void _mergeSelection() {
    if (!_canMerge) return;
    final (rows, cols, cells) = _table;
    // Capture the region list ONCE — [_regions] rebuilds fresh maps per
    // call, so identity-based filtering must see the same instances.
    final regions = _regions;
    final box = _selectionBox!;
    final ((r0, c0), (r1, c1)) = box;
    final texts = <String>[];
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final t = cells[r * cols + c];
        if (t.isNotEmpty) texts.add(t);
      }
    }
    final out = List<String>.from(cells);
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        out[r * cols + c] = '';
      }
    }
    out[r0 * cols + c0] = texts.join(' ');
    final region = {'r': r0, 'c': c0, 'rs': r1 - r0 + 1, 'cs': c1 - c0 + 1};
    final absorbed = regions
        .where((m) =>
            (m['r'] as num).toInt() >= r0 &&
            (m['c'] as num).toInt() >= c0 &&
            (m['r'] as num).toInt() + (m['rs'] as num).toInt() <= r1 + 1 &&
            (m['c'] as num).toInt() + (m['cs'] as num).toInt() <= c1 + 1)
        .toList();
    final merges = [...regions.where((m) => !absorbed.contains(m)), region];
    _commit(rows, cols, out, merges);
  }

  /// Split every merged region whose anchor is selected — the anchor
  /// keeps its text; the covered cells return to independence (empty).
  void _splitSelection() {
    if (!_canSplit) return;
    final (rows, cols, cells) = _table;
    final merges = _regions
        .where((m) => !_selected
            .contains((m['r'] as num).toInt() * cols +
                (m['c'] as num).toInt()))
        .toList();
    _commit(rows, cols, cells, merges);
  }

  // ---- commit -------------------------------------------------------------

  /// One structure change = one commit: the updated object payload plus
  /// the updated metadata entry, through [widget.onTableUpdate] — one
  /// update_object = one undo step.
  void _commit(int rows, int cols, List<String> cells,
      List<Map<String, dynamic>> merges) {
    final copy = Map<String, dynamic>.from(widget.obj);
    final content =
        Map<String, dynamic>.from(copy['content'] as Map);
    content['rows'] = rows;
    content['cols'] = cols;
    content['cells'] = cells;
    copy['content'] = content;
    Map<String, dynamic>? entry;
    if (merges.isNotEmpty) {
      entry = Map<String, dynamic>.from(widget.entry ?? const {});
      entry['merges'] = merges;
    } else if (widget.entry != null &&
        ObjectContent.tableStyleOf(widget.entry) != 'plain') {
      entry = Map<String, dynamic>.from(widget.entry!)..remove('merges');
    }
    setState(() => _selected.clear());
    widget.onTableUpdate(copy, entry);
  }

  @override
  Widget build(BuildContext context) {
    final (rows, cols, cells) = _table;
    if (rows == 0 || cols == 0) return const _PanelBody(children: []);
    // Undo/redo can shrink the table under a live selection: stale
    // indices (and indices now covered by a merge) fold away.
    final covered = <int>{
      for (final m in _regions)
        for (var dr = 0; dr < (m['rs'] as num).toInt(); dr++)
          for (var dc = 0; dc < (m['cs'] as num).toInt(); dc++)
            if (dr != 0 || dc != 0)
              ((m['r'] as num).toInt() + dr) * cols +
                  (m['c'] as num).toInt() +
                  dc,
    };
    _selected.removeWhere((i) => i >= rows * cols || covered.contains(i));
    final coveredAt = <int, Map<String, dynamic>>{};
    for (final m in _regions) {
      for (var dr = 0; dr < (m['rs'] as num).toInt(); dr++) {
        for (var dc = 0; dc < (m['cs'] as num).toInt(); dc++) {
          coveredAt[((m['r'] as num).toInt() + dr) * cols +
              (m['c'] as num).toInt() +
              dc] = m;
        }
      }
    }
    final canStruct = _selected.isNotEmpty;
    final goneRows = _selectedCells.map(((int, int) c) => c.$1).toSet();
    final goneCols = _selectedCells.map(((int, int) c) => c.$2).toSet();
    return _PanelBody(
      children: [
        _PanelLabel(_selected.isEmpty
            ? 'TAP TO EDIT · LONG-PRESS TO SELECT'
            : '${_selectedCells.length} '
                'CELL${_selectedCells.length == 1 ? '' : 'S'} SELECTED'),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var c = 0; c < cols; c++)
                  () {
                    final idx = r * cols + c;
                    final m = coveredAt[idx];
                    if (m != null) {
                      final anchorIdx = (m['r'] as num).toInt() * cols +
                          (m['c'] as num).toInt();
                      // Covered cells have no button — the anchor's wide
                      // button spans their columns (flex = colSpan).
                      if (idx != anchorIdx) return const SizedBox.shrink();
                      return Expanded(
                        flex: (m['cs'] as num).toInt(),
                        child: Padding(
                          padding: _actionSpacing,
                          child: _CellButton(
                            index: idx,
                            text: cells[idx],
                            selected: _selected.contains(idx),
                            onTap: () => widget.onTableCell(idx),
                            onLongPress: () => _toggle(idx),
                          ),
                        ),
                      );
                    }
                    return Expanded(
                      child: Padding(
                        padding: _actionSpacing,
                        child: _CellButton(
                          index: idx,
                          text: cells[idx],
                          selected: _selected.contains(idx),
                          onTap: () => widget.onTableCell(idx),
                          onLongPress: () => _toggle(idx),
                        ),
                      ),
                    );
                  }(),
              ],
            ),
          ),
        const _PanelLabel('STRUCTURE'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TableActionChip(
              key: const ValueKey('table_chip_add_row'),
              label: '+ Row',
              enabled: canStruct,
              onTap: _insertRowAboveSelection,
            ),
            _TableActionChip(
              key: const ValueKey('table_chip_del_row'),
              label: '− Row',
              enabled: canStruct && goneRows.length < rows && rows > 1,
              onTap: _deleteRows,
            ),
            _TableActionChip(
              key: const ValueKey('table_chip_add_col'),
              label: '+ Col',
              enabled: canStruct,
              onTap: _insertColLeftOfSelection,
            ),
            _TableActionChip(
              key: const ValueKey('table_chip_del_col'),
              label: '− Col',
              enabled: canStruct && goneCols.length < cols && cols > 1,
              onTap: _deleteCols,
            ),
            _TableActionChip(
              key: const ValueKey('table_chip_merge'),
              label: 'Merge',
              enabled: _canMerge,
              onTap: _mergeSelection,
            ),
            _TableActionChip(
              key: const ValueKey('table_chip_split'),
              label: 'Split',
              enabled: _canSplit,
              onTap: _splitSelection,
            ),
          ],
        ),
      ],
    );
  }

  void _insertRowAboveSelection() {
    final box = _selectionBox;
    _insertRow(box?.$1.$1 ?? _table.$1);
  }

  void _insertColLeftOfSelection() {
    final box = _selectionBox;
    _insertCol(box?.$1.$2 ?? _table.$2);
  }

  void _toggle(int index) {
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }
}

class _CellButton extends StatelessWidget {
  const _CellButton({
    required this.index,
    required this.text,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final int index;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('table_cell_$index'),
      color: selected ? kPurpleWash : kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
            color: selected ? kPurple : kHairline,
            width: selected ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
    required this.entry,
    required this.onTableStyle,
  });

  final Map<String, dynamic> obj;
  final void Function(Map<String, dynamic>) onObjectStyle;
  final List<Color> palette;

  /// The table's deck-level metadata entry — the style chips read the
  /// current named style from it (and merge-aware data rides along).
  final Map<String, dynamic>? entry;

  /// Applies a named style; the editor resolves the DNA colors.
  final void Function(String style) onTableStyle;

  @override
  Widget build(BuildContext context) {
    final stroke = (obj['stroke'] as Map?) ?? const {};
    final style = ObjectContent.tableStyleOf(entry);
    return _PanelBody(
      children: [
        const _PanelLabel('TABLE STYLE'),
        // The DNA-driven presets: Plain / Header (accent fill + white
        // bold) / Banded (surface tint on alternate rows) / both. Colors
        // resolve from the deck's design DNA at apply time — one style
        // set matches every design family.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DreamChoiceChip(
              label: 'Plain',
              selected: style == 'plain',
              onTap: () => onTableStyle('plain'),
            ),
            DreamChoiceChip(
              label: 'Header',
              selected: style == 'header',
              onTap: () => onTableStyle('header'),
            ),
            DreamChoiceChip(
              label: 'Banded',
              selected: style == 'banded',
              onTap: () => onTableStyle('banded'),
            ),
            DreamChoiceChip(
              label: 'Header + band',
              selected: style == 'header_banded',
              onTap: () => onTableStyle('header_banded'),
            ),
          ],
        ),
        DreamColorChips(
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

/// A structure action chip — a [DreamChoiceChip] that can be OFF: a
/// disabled action dims and ignores taps instead of faking a press.
class _TableActionChip extends StatelessWidget {
  const _TableActionChip({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.38,
        child: DreamChoiceChip(
          label: label,
          selected: false,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _FrameTools extends StatelessWidget {
  const _FrameTools({
    required this.obj,
    required this.onObjectStyle,
    required this.palette,
    this.entry,
    this.onImageUpdate,
    this.onReplaceImage,
  });

  final Map<String, dynamic> obj;
  final void Function(Map<String, dynamic>) onObjectStyle;
  final List<Color> palette;

  /// The image's deck-level metadata entry (shape/brightness/contrast/alt)
  /// and its commit path — null outside an image selection wired by the
  /// editor (the crop-shape / adjust / alt sections hide without it).
  final Map<String, dynamic>? entry;
  final void Function(Map<String, dynamic> obj, Map<String, dynamic>? entry)?
      onImageUpdate;
  final VoidCallback? onReplaceImage;

  @override
  Widget build(BuildContext context) {
    final stroke = (obj['stroke'] as Map?) ?? const {};
    final width = ((stroke['width'] ?? 0) as num).toDouble();
    final w = ((obj['w'] as num?) ?? 480).toDouble();
    final shape = entry?['shape']?.toString();
    return _PanelBody(
      children: [
        const _PanelLabel('BORDER'),
        _PanelRow(
          children: [
            DreamChoiceChip(
              label: 'None',
              selected: width <= 0,
              onTap: () => onObjectStyle(
                  _styled(obj, stroke: {...stroke, 'width': 0.0})),
            ),
            const SizedBox(width: 8),
            DreamChoiceChip(
              label: 'Hairline',
              selected: width > 0 && width <= 2,
              onTap: () => onObjectStyle(
                  _styled(obj, stroke: {...stroke, 'width': 1.5})),
            ),
            const SizedBox(width: 8),
            DreamChoiceChip(
              label: 'Bold',
              selected: width > 2,
              onTap: () =>
                  onObjectStyle(_styled(obj, stroke: {...stroke, 'width': 4.0})),
            ),
          ],
        ),
        DreamColorChips(
          label: 'BORDER COLOR',
          palette: palette,
          selected: (stroke['color'] ?? '17181A').toString(),
          onPick: (hex) => onObjectStyle(
              _styled(obj, stroke: {...stroke, 'color': hex ?? '17181A'})),
        ),
        _OpacityControl(obj: obj, onObjectStyle: onObjectStyle),
        // ---- image depth (roadmap #11 wave 1 step 5) ----------------------
        // Crop ratios re-shape the FRAME (the engine's cover fit does the
        // center-crop); crop-to-shape, brightness/contrast and alt text are
        // app-owned metadata the core's Shape struct drops on round-trips.
        const SizedBox(height: 10),
        const _PanelLabel('CROP RATIO'),
        _PanelRow(
          children: [
            for (final (label, ratio) in const [
              ('1:1', 1.0),
              ('4:3', 4.0 / 3.0),
              ('16:9', 16.0 / 9.0),
              ('3:2', 3.0 / 2.0),
            ]) ...[
              DreamChoiceChip(
                key: ValueKey('crop_ratio_${label.replaceAll(':', '_')}'),
                label: label,
                selected: (_frameAspect(obj) - ratio).abs() < 0.02,
                onTap: () => onObjectStyle(
                    <String, dynamic>{...obj, 'h': w / ratio}),
              ),
              if (label != '3:2') const SizedBox(width: 8),
            ],
          ],
        ),
        if (onImageUpdate != null) ...[
          const SizedBox(height: 10),
          const _PanelLabel('CROP SHAPE'),
          _PanelRow(
            children: [
              DreamChoiceChip(
                key: const ValueKey('crop_shape_rect'),
                label: 'Rect',
                selected: shape == null || shape == 'rect',
                onTap: () => _commitShape(null),
              ),
              const SizedBox(width: 8),
              DreamChoiceChip(
                key: const ValueKey('crop_shape_round'),
                label: 'Round',
                selected: shape == 'round',
                onTap: () => _commitShape('round'),
              ),
              const SizedBox(width: 8),
              DreamChoiceChip(
                key: const ValueKey('crop_shape_circle'),
                label: 'Circle',
                selected: shape == 'circle',
                onTap: () => _commitShape('circle'),
              ),
            ],
          ),
          _ImageAdjust(obj: obj, entry: entry, onImageUpdate: onImageUpdate!),
          if (onReplaceImage != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('img_replace'),
                onPressed: onReplaceImage,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Replace image'),
              ),
            ),
          ],
          _AltTextField(obj: obj, entry: entry, onImageUpdate: onImageUpdate!),
        ],
      ],
    );
  }

  void _commitShape(String? shape) {
    final next = _imageEntryWith(entry, 'shape', shape);
    onImageUpdate!(obj, next.isEmpty ? null : next);
  }
}

/// The object's frame aspect (w/h); a degenerate frame reads 16:9.
double _frameAspect(Map<String, dynamic> obj) {
  final w = ((obj['w'] as num?) ?? 480).toDouble();
  final h = ((obj['h'] as num?) ?? 270).toDouble();
  if (h <= 0) return 16 / 9;
  return w / h;
}

/// Entry surgery: copy [entry], set [key] to [value] (null removes it).
Map<String, dynamic> _imageEntryWith(
    Map<String, dynamic>? entry, String key, Object? value) {
  final next = <String, dynamic>{...?entry};
  if (value == null) {
    next.remove(key);
  } else {
    next[key] = value;
  }
  return next;
}

/// Brightness / contrast sliders for the selected image. Local while
/// dragging (one gesture, one commit on release = one undo step); values
/// are −100..100, 0 omitted from the entry (absent = untouched).
class _ImageAdjust extends StatefulWidget {
  const _ImageAdjust({
    required this.obj,
    required this.entry,
    required this.onImageUpdate,
  });

  final Map<String, dynamic> obj;
  final Map<String, dynamic>? entry;
  final void Function(Map<String, dynamic> obj, Map<String, dynamic>? entry)
      onImageUpdate;

  @override
  State<_ImageAdjust> createState() => _ImageAdjustState();
}

class _ImageAdjustState extends State<_ImageAdjust> {
  late int _brightness;
  late int _contrast;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_ImageAdjust old) {
    super.didUpdateWidget(old);
    if (!identical(old.entry, widget.entry)) _read();
  }

  void _read() {
    _brightness = ((widget.entry?['brightness'] ?? 0) as num).toInt();
    _contrast = ((widget.entry?['contrast'] ?? 0) as num).toInt();
  }

  void _commit() {
    var next = _imageEntryWith(
        widget.entry, 'brightness', _brightness == 0 ? null : _brightness);
    next = _imageEntryWith(next, 'contrast', _contrast == 0 ? null : _contrast);
    widget.onImageUpdate(widget.obj, next.isEmpty ? null : next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _PanelLabel(
            'BRIGHTNESS — ${_brightness > 0 ? '+' : ''}$_brightness'),
        Slider(
          key: const ValueKey('img_brightness'),
          value: _brightness.clamp(-100, 100).toDouble(),
          min: -100,
          max: 100,
          divisions: 100,
          activeColor: kPurple,
          onChanged: (v) => setState(() => _brightness = v.round()),
          onChangeEnd: (_) => _commit(),
        ),
        _PanelLabel('CONTRAST — ${_contrast > 0 ? '+' : ''}$_contrast'),
        Slider(
          key: const ValueKey('img_contrast'),
          value: _contrast.clamp(-100, 100).toDouble(),
          min: -100,
          max: 100,
          divisions: 100,
          activeColor: kPurple,
          onChanged: (v) => setState(() => _contrast = v.round()),
          onChangeEnd: (_) => _commit(),
        ),
        if (_brightness != 0 || _contrast != 0)
          Align(
            alignment: Alignment.centerLeft,
            child: DreamChoiceChip(
              key: const ValueKey('img_adjust_reset'),
              label: 'Reset adjust',
              selected: false,
              onTap: () {
                setState(() {
                  _brightness = 0;
                  _contrast = 0;
                });
                _commit();
              },
            ),
          ),
      ],
    );
  }
}

/// Alt text for the selected image — app-side accessibility metadata the
/// exporters and the AI protocol ignore; committed on focus loss / done.
class _AltTextField extends StatefulWidget {
  const _AltTextField({
    required this.obj,
    required this.entry,
    required this.onImageUpdate,
  });

  final Map<String, dynamic> obj;
  final Map<String, dynamic>? entry;
  final void Function(Map<String, dynamic> obj, Map<String, dynamic>? entry)
      onImageUpdate;

  @override
  State<_AltTextField> createState() => _AltTextFieldState();
}

class _AltTextFieldState extends State<_AltTextField> {
  late final TextEditingController _ctrl;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.entry?['alt']?.toString() ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    if (!_dirty) return;
    _dirty = false;
    final next = _imageEntryWith(
        widget.entry, 'alt', _ctrl.text.isEmpty ? null : _ctrl.text);
    widget.onImageUpdate(widget.obj, next.isEmpty ? null : next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        key: const ValueKey('img_alt'),
        controller: _ctrl,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Alt text (description)',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => _dirty = true,
        onSubmitted: (_) => _commit(),
        onEditingComplete: () {
          _commit();
          FocusScope.of(context).unfocus();
        },
      ),
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
        DreamColorChips(
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
  const _MediaInfo({required this.obj, this.onPlay});

  final Map<String, dynamic> obj;

  /// Opens the system player on the resolved local file (null = playback
  /// unavailable — the button is not shown at all rather than shown dead).
  final VoidCallback? onPlay;

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
        if (onPlay != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('panel_play_media'),
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Play in device player'),
            ),
          ),
        ],
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
            DreamChoiceChip(
              label: 'None',
              selected: fillType == 'none',
              onTap: () => onObjectStyle(_styled(obj, fill: {'type': 'none'})),
            ),
            const SizedBox(width: 8),
            DreamChoiceChip(
              label: 'Solid',
              selected: fillType == 'solid',
              onTap: () => onObjectStyle(_styled(obj,
                  fill: {'type': 'solid', 'color': (fill['color'] ?? 'D03028')})),
            ),
          ],
        ),
        if (fillType == 'solid')
          DreamColorChips(
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
                child: DreamChoiceChip(
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
        DreamColorChips(
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
