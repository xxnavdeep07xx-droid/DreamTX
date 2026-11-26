part of 'editor_screen.dart';

// ---------------------------------------------------------------------------
// The Draw tab's toolbox — the contextual band under the canvas (the
// Draw-toolbox design, step B). State comes in, changes go out: the editor
// owns the ONE field (_drawToolbox), this file owns the surface (the PR #6
// part-file discipline — the state class grows by nothing).
// ---------------------------------------------------------------------------

/// The pen's width presets: S 4 / M 8 / L 16 design px (about 1.2 / 2.5 /
/// 5dp on screen for a 16:9 deck) — widths are design px, so they are
/// zoom-proof by definition (the editor canvas is fit-scaled).
const List<(String, double)> _kPenWidths = [
  ('S', 4.0),
  ('M', 8.0),
  ('L', 16.0),
];

/// The highlighter: a wide translucent stroke. Fixed width (28 design px
/// ≈ 8.7dp on screen) — it is a marker, not a pen; the translucency rides
/// the object's `opacity`, which the PPTX and PDF exporters already
/// multiply into stroke color, so highlighter ink exports translucent with
/// zero exporter changes.
const double _kHighlighterWidth = 28.0;
const double _kHighlighterOpacity = 0.35;

/// The eraser's reach presets (design px, the sweep corridor radius):
/// S 12 / M 24 (the default, [kInkEraserRadius]) / L 40.
const List<(String, double)> _kEraserSizes = [
  ('S', 12.0),
  ('M', 24.0),
  ('L', 40.0),
];

/// The Draw toolbox's immutable state — the ONE editor field for the Draw
/// tab. Everything the tab needs: the armed bit, the last tool, the pen
/// tip (ballpoint or pencil), the per-tool color memory, the pen width,
/// the eraser reach, the palette band's expansion, and the saved presets.
///
/// [penColorHex] stays null until the user picks one — null means "follow
/// the deck's DNA accent" (`resolve_dna`, resolved for display and capture
/// by [colorHexFor] / [inkStyleFor] against the accent the editor passes).
class _DrawToolboxState {
  const _DrawToolboxState({
    this.armed = false,
    this.tool = InkTool.pen,
    this.pencil = false,
    this.penColorHex,
    this.hlColorHex = 'FFD400',
    this.penWidth = 8.0,
    this.eraserRadius = kInkEraserRadius,
    this.expanded = false,
    this.presets = const [],
    this.ruler = false,
    this.inkToShape = false,
  });

  final bool armed;
  final InkTool tool;

  /// The pen family's tip: false = the ballpoint pen, true = the pencil.
  /// Only meaningful while [tool] is the pen.
  final bool pencil;

  /// The pen's color (RRGGBB) — null = follow the deck's DNA accent.
  final String? penColorHex;

  /// The highlighter's own color (the studio yellow by default).
  final String hlColorHex;

  /// The pen's width in design px (one of [_kPenWidths]).
  final double penWidth;

  /// The eraser's reach in design px (one of [_kEraserSizes]).
  final double eraserRadius;

  /// Whether the palette band under the tool row is open.
  final bool expanded;

  /// Saved tool styles, session-scoped, capped at [kInkPresetCap].
  final List<InkPreset> presets;

  /// Draw R: the ruler overlay on the slide (editor-only, never exported).
  final bool ruler;

  /// Draw D: when on, a pen stroke that reads as a line, rectangle,
  /// ellipse or triangle commits as that shape instead of a freehand path.
  final bool inkToShape;

  /// The lasso's band is always open while it is armed (its controls ARE
  /// the selection's face); the other tools open it by a chip tap.
  bool get bandOpen => expanded || (armed && tool == InkTool.lasso);

  /// The S/M/L pen width chip and presets belong to the ballpoint only:
  /// the pencil's width is fixed by design, the highlighter's too.
  bool get penWidthsVisible => tool == InkTool.pen && !pencil;

  /// The active tool's display color, with an unpicked pen color resolved
  /// against the deck's DNA accent.
  String colorHexFor({required String defaultPenHex}) =>
      tool == InkTool.pen ? (penColorHex ?? defaultPenHex) : hlColorHex;

  /// The committed style for the armed tool — exactly what the live
  /// preview paints with and what `_onStrokeDone` commits.
  InkStyle inkStyleFor({required String defaultPenHex}) => switch (tool) {
        InkTool.pen when pencil => InkStyle(
            colorHex: penColorHex ?? defaultPenHex,
            width: kInkPencilWidth,
            opacity: kInkPencilOpacity,
          ),
        InkTool.pen => InkStyle(
            colorHex: penColorHex ?? defaultPenHex,
            width: penWidth,
          ),
        InkTool.highlighter => InkStyle(
            colorHex: hlColorHex,
            width: _kHighlighterWidth,
            opacity: _kHighlighterOpacity,
          ),
        // The eraser never commits a stroke — its sweep deletes path
        // objects; this entry exists so the switch stays total.
        InkTool.eraser => const InkStyle(colorHex: 'D03028', width: 24.0),
        // The lasso never commits a stroke either: its loop is a selection.
        InkTool.lasso => const InkStyle(colorHex: 'D03028', width: 2.0),
      };

  /// The preset the current tool would save, or null for the eraser
  /// (the eraser is never a preset).
  InkPreset? presetFor({required String defaultPenHex}) => switch (tool) {
        InkTool.pen when pencil => InkPreset(
            kind: InkPresetKind.pencil,
            colorHex: penColorHex ?? defaultPenHex,
          ),
        InkTool.pen => InkPreset(
            kind: InkPresetKind.pen,
            colorHex: penColorHex ?? defaultPenHex,
            width: penWidth,
          ),
        InkTool.highlighter => InkPreset(
            kind: InkPresetKind.highlighter,
            colorHex: hlColorHex,
          ),
        InkTool.eraser || InkTool.lasso => null,
      };

  // ---- pure transitions: the row calls these, the editor applies -------

  /// A tool tap (highlighter or eraser): switch tools. Tapping the ARMED
  /// tool disarms it — select mode inside Draw (the canvas regains taps;
  /// the knobs return). Arming through a tap is the moment the editor
  /// clears the selection: the armed tool consumes canvas taps.
  _DrawToolboxState toolTapped(InkTool t) => armed && tool == t
      ? _copy(armed: false, expanded: false)
      : _copy(armed: true, tool: t, expanded: false);

  /// The pen family's two buttons: the ballpoint (pencil: false) and the
  /// pencil (pencil: true). Tapping the ARMED one disarms; tapping the
  /// other switches the tip without disarming.
  _DrawToolboxState penTapped({required bool pencilTip}) =>
      armed && tool == InkTool.pen && pencil == pencilTip
          ? _copy(armed: false, expanded: false)
          : _copy(
              armed: true,
              tool: InkTool.pen,
              pencil: pencilTip,
              expanded: false,
            );

  /// A palette pick in the expanded band: the ACTIVE tool's color memory,
  /// and the band collapses (the design: chip pick collapses).
  _DrawToolboxState colorPicked(String hex) => tool == InkTool.pen
      ? _copy(penColorHex: hex, expanded: false)
      : _copy(hlColorHex: hex, expanded: false);

  /// A pen-width pick (only offered while the ballpoint is active): sets
  /// the width, collapses the band.
  _DrawToolboxState widthPicked(double w) =>
      _copy(penWidth: w, expanded: false);

  /// An eraser-size pick (only offered while the eraser is active): sets
  /// the reach, collapses the band.
  _DrawToolboxState eraserSizePicked(double r) =>
      _copy(eraserRadius: r, expanded: false);

  /// A saved preset tapped: arm its tool with its style. Applying a preset
  /// is a tool pick, so the band collapses.
  _DrawToolboxState presetApplied(InkPreset p) => switch (p.kind) {
        InkPresetKind.pen => _copy(
            armed: true,
            tool: InkTool.pen,
            pencil: false,
            penColorHex: p.colorHex,
            penWidth: p.width ?? penWidth,
            expanded: false,
          ),
        InkPresetKind.pencil => _copy(
            armed: true,
            tool: InkTool.pen,
            pencil: true,
            penColorHex: p.colorHex,
            expanded: false,
          ),
        InkPresetKind.highlighter => _copy(
            armed: true,
            tool: InkTool.highlighter,
            hlColorHex: p.colorHex,
            expanded: false,
          ),
      };

  /// The preset list after a save or remove (the list rules live in
  /// ink_math: [inkSavePreset], [inkRemovePresetAt]).
  _DrawToolboxState withPresets(List<InkPreset> next) =>
      _copy(presets: next);

  /// The ruler toggle: never disarms — the ruler is a view aid, not a tool.
  _DrawToolboxState rulerToggled() => _copy(ruler: !ruler);

  /// The ink→shape toggle: a setting, not a tool — it never disarms.
  _DrawToolboxState inkToShapeToggled() => _copy(inkToShape: !inkToShape);

  /// The compact row's color/width chip tap: toggle the band.
  _DrawToolboxState bandToggled() => _copy(expanded: !expanded);

  /// Leaving Draw by any route: disarm; the tool and colors persist for
  /// the return.
  _DrawToolboxState disarmed() => armed ? _copy(armed: false) : this;

  /// Entering Draw: arm the last-used tool (the pen by default).
  _DrawToolboxState rearmed() => armed ? this : _copy(armed: true);

  _DrawToolboxState _copy({
    bool? armed,
    InkTool? tool,
    bool? pencil,
    String? penColorHex,
    String? hlColorHex,
    double? penWidth,
    double? eraserRadius,
    bool? expanded,
    List<InkPreset>? presets,
    bool? ruler,
    bool? inkToShape,
  }) =>
      _DrawToolboxState(
        armed: armed ?? this.armed,
        tool: tool ?? this.tool,
        pencil: pencil ?? this.pencil,
        penColorHex: penColorHex ?? this.penColorHex,
        hlColorHex: hlColorHex ?? this.hlColorHex,
        penWidth: penWidth ?? this.penWidth,
        eraserRadius: eraserRadius ?? this.eraserRadius,
        expanded: expanded ?? this.expanded,
        presets: presets ?? this.presets,
        ruler: ruler ?? this.ruler,
        inkToShape: inkToShape ?? this.inkToShape,
      );
}

/// The Draw tab's contextual row: the compact 48dp tool line (pen /
/// pencil / highlighter / eraser, then the settings chips) plus the
/// expandable band under it. The band grows 0 -> 86dp for the pen family
/// and the highlighter (a color/width row over a preset strip) and 0 -> 46dp
/// for the eraser (its sizes). A pure widget: the state comes in, the
/// transitions go out through [onChanged].
class _DrawToolboxRow extends StatelessWidget {
  const _DrawToolboxRow({
    required this.state,
    required this.defaultPenHex,
    required this.palette,
    required this.onChanged,
    this.onClearAll,
    this.onReplayInk,
    this.onNotice,
    this.lassoCount = 0,
    this.onLassoColor,
    this.onLassoDelete,
    this.onLassoClear,
  });

  final _DrawToolboxState state;

  /// The deck's DNA accent (RRGGBB) — what an unpicked pen color follows.
  final String defaultPenHex;

  /// The deck palette + the studio swatches (the same list the Insert
  /// sheet and the style inspector pick from).
  final List<Color> palette;

  final ValueChanged<_DrawToolboxState> onChanged;

  /// "Erase all ink on slide" — the eraser's clear button. Null hides it.
  final VoidCallback? onClearAll;

  /// Draw E: replay the slide's ink in draw order. Null hides the button.
  final VoidCallback? onReplayInk;

  /// A short confirmation or limit message (save / duplicate / full /
  /// removed). Null drops the notices silently.
  final ValueChanged<String>? onNotice;

  /// Draw B: how many objects the lasso selected, and the selection's
  /// actions (recolor, delete, clear). Only read while the lasso is armed.
  final int lassoCount;
  final ValueChanged<String>? onLassoColor;
  final VoidCallback? onLassoDelete;
  final VoidCallback? onLassoClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      // The band above gives unbounded height; the toolbox sizes itself
      // (48 + the cross-faded band), never tries to fill it.
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 48, width: double.infinity, child: _toolRow()),
        // The expandable band: the typing toolbar's palette-row reveal (the
        // tool row stays ONE instance; only the band cross-fades, so
        // tooltips/semantics never duplicate).
        AnimatedCrossFade(
          key: const ValueKey('draw_palette_band'),
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOutCubic,
          crossFadeState: state.bandOpen
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(height: 0, width: double.infinity),
          secondChild: _paletteBand(),
        ),
      ],
    );
  }

  // ---- the compact 48dp tool line ------------------------------------------

  Widget _toolRow() => SizedBox(
        height: 48,
        // Horizontally scrollable: the row gained the lasso and the ruler, and
        // must still fit a 360dp phone without clipping.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
          children: [
            const SizedBox(width: 8),
            _DrawToolButton(
              icon: Icons.edit,
              tooltip: 'Pen',
              active: state.armed &&
                  state.tool == InkTool.pen &&
                  !state.pencil,
              onTap: () => onChanged(state.penTapped(pencilTip: false)),
            ),
            _DrawToolButton(
              icon: Icons.create_outlined,
              tooltip: 'Pencil',
              active: state.armed && state.tool == InkTool.pen && state.pencil,
              onTap: () => onChanged(state.penTapped(pencilTip: true)),
            ),
            _DrawToolButton(
              icon: Icons.highlight,
              tooltip: 'Highlighter',
              active: state.armed && state.tool == InkTool.highlighter,
              onTap: () => onChanged(state.toolTapped(InkTool.highlighter)),
            ),
            _DrawToolButton(
              icon: Icons.backspace_outlined,
              tooltip: 'Eraser',
              active: state.armed && state.tool == InkTool.eraser,
              onTap: () => onChanged(state.toolTapped(InkTool.eraser)),
            ),
            _DrawToolButton(
              icon: Icons.highlight_alt,
              tooltip: 'Lasso select',
              active: state.armed && state.tool == InkTool.lasso,
              onTap: () => onChanged(state.toolTapped(InkTool.lasso)),
            ),
            // The hairline and the settings belong to the ink tools only.
            if (state.tool != InkTool.lasso)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 1,
                height: 26,
                color: kHairline,
              ),
            if (state.tool == InkTool.pen || state.tool == InkTool.highlighter)
              _ColorChipButton(
                colorHex: state.colorHexFor(defaultPenHex: defaultPenHex),
                tooltip: state.tool == InkTool.pen
                    ? 'Pen color'
                    : 'Highlighter color',
                onTap: () => onChanged(state.bandToggled()),
              ),
            // The width chip is the ballpoint's: the pencil and the
            // highlighter are fixed-width by design.
            if (state.penWidthsVisible)
              _WidthChipButton(
                label: inkPenSizeLabel(state.penWidth),
                tooltip: 'Pen width',
                onTap: () => onChanged(state.bandToggled()),
              ),
            // Ink → shape: the pen's setting (the pencil's strokes recognize
            // too — both are the pen family).
            if (state.tool == InkTool.pen)
              _DrawToolButton(
                icon: Icons.auto_fix_high,
                tooltip: 'Ink to shape',
                active: state.inkToShape,
                onTap: () => onChanged(state.inkToShapeToggled()),
              ),
            // The eraser's settings: its reach and the clear-all button.
            if (state.tool == InkTool.eraser) ...[
              _WidthChipButton(
                label: _eraserSizeLabel(state.eraserRadius),
                tooltip: 'Eraser size',
                onTap: () => onChanged(state.bandToggled()),
              ),
              if (onClearAll != null)
                _DrawToolButton(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: 'Erase all ink on this slide',
                  active: false,
                  onTap: onClearAll!,
                ),
            ],
            _DrawToolButton(
              icon: Icons.straighten,
              tooltip: 'Ruler',
              active: state.ruler,
              onTap: () => onChanged(state.rulerToggled()),
            ),
            if (onReplayInk != null)
              _DrawToolButton(
                icon: Icons.replay,
                tooltip: 'Replay ink',
                active: false,
                onTap: onReplayInk!,
              ),
          ],
        ),
          ),
      );

  // ---- the expanded band ----------------------------------------------------

  Widget _paletteBand() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 46,
            width: double.infinity,
            child: switch (state.tool) {
              InkTool.lasso => _lassoRow(),
              InkTool.eraser => _eraserSizesRow(),
              _ => _colorAndWidthRow(),
            },
          ),
          if (state.tool == InkTool.pen || state.tool == InkTool.highlighter)
            SizedBox(
              height: 40,
              width: double.infinity,
              child: _presetStrip(),
            ),
        ],
      );

  Widget _eraserSizesRow() => Row(
        children: [
          const SizedBox(width: 8),
          for (final (label, r) in _kEraserSizes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DreamChoiceChip(
                label: label,
                selected: state.eraserRadius == r,
                onTap: () => onChanged(state.eraserSizePicked(r)),
              ),
            ),
        ],
      );

  Widget _colorAndWidthRow() => Row(
        children: [
          Expanded(
            // The SAME horizontal chip row the typing toolbar uses
            // (one implementation, 30px chips); "no color" is hidden —
            // ink without a color is not a thing.
            child: DreamColorChips(
              palette: palette,
              selected: state.colorHexFor(defaultPenHex: defaultPenHex),
              onPick: (hex) {
                if (hex != null) onChanged(state.colorPicked(hex));
              },
              horizontal: true,
              chipSize: 30,
              hideNone: true,
            ),
          ),
          if (state.penWidthsVisible)
            for (final (label, w) in _kPenWidths)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DreamChoiceChip(
                  label: label,
                  selected: state.penWidth == w,
                  onTap: () => onChanged(state.widthPicked(w)),
                ),
              ),
        ],
      );

  /// The lasso's band: the selection's face. Empty = the hint; otherwise
  /// the count, a recolor palette (strokes and outlines), delete and clear.
  Widget _lassoRow() => Row(
        children: [
          const SizedBox(width: 8),
          ...(lassoCount == 0 ? _lassoHint() : _lassoControls()),
        ],
      );

  List<Widget> _lassoHint() => const [
        Expanded(
          child: Text(
            'Draw a loop around objects to select them',
            style: TextStyle(fontSize: 12, color: kText2),
          ),
        ),
      ];

  List<Widget> _lassoControls() => [
        Text(
          '$lassoCount selected',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kText,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DreamColorChips(
            palette: palette,
            selected: null,
            onPick: (hex) {
              if (hex != null) onLassoColor?.call(hex);
            },
            horizontal: true,
            chipSize: 30,
            hideNone: true,
          ),
        ),
        if (onLassoDelete != null)
          _DrawToolButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete selection',
            active: false,
            onTap: onLassoDelete!,
          ),
        if (onLassoClear != null)
          _DrawToolButton(
            icon: Icons.close,
            tooltip: 'Clear selection',
            active: false,
            onTap: onLassoClear!,
          ),
      ];

  /// The preset strip: "Save" first, then the saved styles. A tap applies
  /// one; a long-press removes it. The chip matching the current tool is
  /// highlighted.
  Widget _presetStrip() {
    final current = state.presetFor(defaultPenHex: defaultPenHex);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _PresetChip(
          label: 'Save',
          leading: const Icon(Icons.add, size: 14, color: kText2),
          onTap: () => _savePreset(current),
        ),
        for (final p in state.presets)
          _PresetChip(
            label: p.label,
            colorHex: p.colorHex,
            selected: p == current,
            onTap: () => onChanged(state.presetApplied(p)),
            onLongPress: () => _removePreset(p),
          ),
      ],
    );
  }

  void _savePreset(InkPreset? p) {
    if (p == null) return;
    final r = inkSavePreset(state.presets, p);
    switch (r.result) {
      case InkSaveResult.saved:
        onChanged(state.withPresets(r.presets));
        onNotice?.call('Saved ${p.label}');
      case InkSaveResult.duplicate:
        onNotice?.call('${p.label} is already saved');
      case InkSaveResult.full:
        onNotice?.call(
            'Up to $kInkPresetCap presets — long-press one to remove it');
    }
  }

  void _removePreset(InkPreset p) {
    final i = state.presets.indexOf(p);
    if (i < 0) return;
    onChanged(state.withPresets(inkRemovePresetAt(state.presets, i)));
    onNotice?.call('Removed ${p.label}');
  }
}

String _eraserSizeLabel(double r) => r <= 12 ? 'S' : (r <= 24 ? 'M' : 'L');

/// A toolbox tool button — the typing toolbar's exact button geometry:
/// 44x48 compact IconButton, the active state carried by color + the soft
/// highlight background (no ripple chrome on the dark band).
class _DrawToolButton extends StatelessWidget {
  const _DrawToolButton({
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
    final color = active ? kText : kText2;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: SizedBox(
        width: 44,
        height: 48,
        child: IconButton(
          icon: Icon(icon, size: 22, color: color),
          color: color,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: active ? const Color(0x1FFFFFFF) : null,
          ),
        ),
      ),
    );
  }
}

/// The compact row's color chip: a 26dp swatch of the active tool's color;
/// tapping opens (or closes) the palette band.
class _ColorChipButton extends StatelessWidget {
  const _ColorChipButton({
    required this.colorHex,
    required this.tooltip,
    required this.onTap,
  });

  final String colorHex;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 48,
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: hexToColor(colorHex),
                shape: BoxShape.circle,
                border: Border.all(color: kHairline),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact row's width chip: the current S/M/L; tapping opens (or
/// closes) the palette band, which carries the presets for that setting.
class _WidthChipButton extends StatelessWidget {
  const _WidthChipButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 48,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kText2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A saved preset chip: an optional color dot, a label, a pill outline.
/// Selected = the same style as the current tool (soft highlight + brighter
/// border). Long-press removes; the "Save" chip has no color and a leading
/// glyph instead.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onTap,
    this.colorHex,
    this.leading,
    this.selected = false,
    this.onLongPress,
  });

  final String label;
  final String? colorHex;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final hex = colorHex;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0x1FFFFFFF) : null,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: selected ? kText2 : kHairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hex != null) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: hexToColor(hex),
                    shape: BoxShape.circle,
                    border: Border.all(color: kHairline),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
