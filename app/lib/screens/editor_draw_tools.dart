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

/// The Draw toolbox's immutable state — the ONE editor field for the Draw
/// tab (replacing the old `_scribbleMode` bool). Everything the tab needs:
/// the armed bit, the last tool, the per-tool color memory, the pen width,
/// and the palette band's expansion.
///
/// [penColorHex] stays null until the user picks one — null means "follow
/// the deck's DNA accent" (`resolve_dna`, resolved for display and capture
/// by [colorHexFor] / [inkStyleFor] against the accent the editor passes).
class _DrawToolboxState {
  const _DrawToolboxState({
    this.armed = false,
    this.tool = InkTool.pen,
    this.penColorHex,
    this.hlColorHex = 'FFD400',
    this.penWidth = 8.0,
    this.expanded = false,
  });

  final bool armed;
  final InkTool tool;

  /// The pen's color (RRGGBB) — null = follow the deck's DNA accent.
  final String? penColorHex;

  /// The highlighter's own color (the studio yellow by default).
  final String hlColorHex;

  /// The pen's width in design px (one of [_kPenWidths]).
  final double penWidth;

  /// Whether the palette band under the tool row is open.
  final bool expanded;

  /// The active tool's display color, with an unpicked pen color resolved
  /// against the deck's DNA accent.
  String colorHexFor({required String defaultPenHex}) =>
      tool == InkTool.pen ? (penColorHex ?? defaultPenHex) : hlColorHex;

  /// The committed style for the armed tool — exactly what the live
  /// preview paints with and what `_onStrokeDone` commits.
  InkStyle inkStyleFor({required String defaultPenHex}) => switch (tool) {
        InkTool.pen => InkStyle(
            colorHex: penColorHex ?? defaultPenHex, width: penWidth),
        InkTool.highlighter => InkStyle(
            colorHex: hlColorHex,
            width: _kHighlighterWidth,
            opacity: _kHighlighterOpacity,
          ),
        // The eraser never commits a stroke — its sweep deletes path
        // objects (step C); this entry exists so the switch stays total.
        InkTool.eraser => const InkStyle(colorHex: 'D03028', width: 24.0),
      };

  // ---- pure transitions: the row calls these, the editor applies -------

  /// A tool tap: switch tools. Tapping the ARMED tool disarms it — select
  /// mode inside Draw (the canvas regains taps; the knobs return). Arming
  /// through a tap is the moment the editor clears the selection: the
  /// armed tool consumes canvas taps, so the chrome would be untouchable.
  _DrawToolboxState toolTapped(InkTool t) =>
      armed && tool == t ? _copy(armed: false) : _copy(armed: true, tool: t);

  /// A palette pick in the expanded band: the ACTIVE tool's color memory,
  /// and the band collapses (the design: chip pick collapses).
  _DrawToolboxState colorPicked(String hex) => tool == InkTool.pen
      ? _copy(penColorHex: hex, expanded: false)
      : _copy(hlColorHex: hex, expanded: false);

  /// A pen-width pick (only offered while the pen is active): sets the
  /// width, collapses the band.
  _DrawToolboxState widthPicked(double w) =>
      _copy(penWidth: w, expanded: false);

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
    String? penColorHex,
    String? hlColorHex,
    double? penWidth,
    bool? expanded,
  }) =>
      _DrawToolboxState(
        armed: armed ?? this.armed,
        tool: tool ?? this.tool,
        penColorHex: penColorHex ?? this.penColorHex,
        hlColorHex: hlColorHex ?? this.hlColorHex,
        penWidth: penWidth ?? this.penWidth,
        expanded: expanded ?? this.expanded,
      );
}

/// The Draw tab's contextual row: the compact 48dp tool line (pen /
/// highlighter | color chip | width chip) plus the expandable palette band
/// that grows the band 48 -> 94dp — cross-faded the same way the typing
/// toolbar's palette row opens above the keyboard. A pure widget: the
/// state comes in, the transitions go out through [onChanged].
class _DrawToolboxRow extends StatelessWidget {
  const _DrawToolboxRow({
    required this.state,
    required this.defaultPenHex,
    required this.palette,
    required this.onChanged,
  });

  final _DrawToolboxState state;

  /// The deck's DNA accent (RRGGBB) — what an unpicked pen color follows.
  final String defaultPenHex;

  /// The deck palette + the studio swatches (the same list the Insert
  /// sheet and the style inspector pick from).
  final List<Color> palette;

  final ValueChanged<_DrawToolboxState> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      // The band above gives unbounded height; the toolbox sizes itself
      // (48 + the cross-faded band), never tries to fill it.
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 48, width: double.infinity, child: _toolRow()),
        // The expandable palette band: 0 <-> 46dp — the typing toolbar's
        // palette-row reveal (the tool row stays ONE instance; only the
        // band cross-fades, so tooltips/semantics never duplicate).
        AnimatedCrossFade(
          key: const ValueKey('draw_palette_band'),
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOutCubic,
          crossFadeState: state.expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(height: 0, width: double.infinity),
          secondChild: SizedBox(
            height: 46,
            width: double.infinity,
            child: _paletteBand(),
          ),
        ),
      ],
    );
  }

  // ---- the compact 48dp tool line ------------------------------------------

  Widget _toolRow() => SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 8),
            _DrawToolButton(
              icon: Icons.edit,
              tooltip: 'Pen',
              active: state.armed && state.tool == InkTool.pen,
              onTap: () => onChanged(state.toolTapped(InkTool.pen)),
            ),
            _DrawToolButton(
              icon: Icons.highlight,
              tooltip: 'Highlighter',
              active: state.armed && state.tool == InkTool.highlighter,
              onTap: () => onChanged(state.toolTapped(InkTool.highlighter)),
            ),
            // The hairline that separates tools from settings.
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 1,
              height: 26,
              color: kHairline,
            ),
            _ColorChipButton(
              colorHex: state.colorHexFor(defaultPenHex: defaultPenHex),
              tooltip: state.tool == InkTool.pen
                  ? 'Pen color'
                  : 'Highlighter color',
              onTap: () => onChanged(state.bandToggled()),
            ),
            // The width chip is the pen's: the highlighter is fixed-width
            // by design, so its settings are just the color.
            if (state.tool == InkTool.pen)
              _WidthChipButton(
                label: _penWidthLabel(state.penWidth),
                onTap: () => onChanged(state.bandToggled()),
              ),
          ],
        ),
      );

  // ---- the expanded palette band (46dp) -------------------------------------

  Widget _paletteBand() => SizedBox(
        height: 46,
        child: Row(
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
            if (state.tool == InkTool.pen)
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
        ),
      );
}

String _penWidthLabel(double w) => w <= 4 ? 'S' : (w <= 8 ? 'M' : 'L');

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

/// The compact row's width chip: the pen's current S/M/L; tapping opens
/// (or closes) the palette band, which carries the width presets.
class _WidthChipButton extends StatelessWidget {
  const _WidthChipButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Pen width',
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
