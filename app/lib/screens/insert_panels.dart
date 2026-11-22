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
    required this.onEditStyleSheet,
    required this.onStartTyping,
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
