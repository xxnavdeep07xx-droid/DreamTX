import 'package:material_ui/material_ui.dart';

import '../core/color_utils.dart';
import '../theme.dart';

/// The shared panel controls — one implementation of the two widgets every
/// drawer/panel/sheet was rebuilding by hand:
///
///  * [DreamChoiceChip] — the capsule chip (font family, width, spacing…
///    single-choice rows). The Insert panel's `_ChoiceChip2`, the editor's
///    `_DesignChip` and the inspector's wrapped `ChoiceChip`s are this.
///  * [DreamColorChips] — the label + "no color" + swatch row the typing
///    toolbar, the object panels and the style inspector each carried
///    their own copy of.
class DreamChoiceChip extends StatelessWidget {
  const DreamChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.magenta = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The accent variant: the editor's design-family chips wear the
  /// magenta edge (their historical look) instead of the purple one.
  final bool magenta;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? (magenta ? kElevated : kPurpleWash) : (magenta ? kBg : kElevated),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected
                ? (magenta ? kMagenta : kPurple)
                : kHairline,
            width: selected && magenta ? 1.4 : 1),
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
              color: selected ? kText : (magenta ? kText2 : kText2),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label + "no color" chip + swatch circles row. Wraps by default (the
/// panel contract); [horizontal] scrolls in one line instead (the typing
/// toolbar's palette contract above the keyboard).
class DreamColorChips extends StatelessWidget {
  const DreamColorChips({
    super.key,
    required this.palette,
    required this.selected,
    required this.onPick,
    this.label,
    this.horizontal = false,
    this.chipSize = 28,
    this.noneTooltip = 'No color',
    this.hideNone = false,
  });

  /// The palette to show (deck colors + the studio standards).
  final List<Color> palette;

  /// The currently selected RRGGBB (null = nothing selected).
  final String? selected;

  /// `onPick(hexOrNull)` — null is the "no color" chip.
  final void Function(String? hex) onPick;

  /// The section label (omitted in the toolbar's horizontal mode).
  final String? label;

  /// One-line scrolling layout instead of wrapping.
  final bool horizontal;

  /// The chip circle size (28 in panels, 30 in the toolbar).
  final double chipSize;

  /// The "no color" chip's tooltip.
  final String noneTooltip;

  /// Hide the "no color" chip entirely — for pickers where a null pick is
  /// meaningless (ink has no "no color"); the row starts at the swatches.
  final bool hideNone;

  @override
  Widget build(BuildContext context) {
    final chips = [
      if (!hideNone)
        _NoColorChip(
          size: chipSize,
          selected: selected == null,
          tooltip: noneTooltip,
          onTap: () => onPick(null),
        ),
      for (final c in palette)
        _SwatchChip(
          color: c,
          size: chipSize,
          label: '#${hexKeyOf(c)}',
          selected: selected == hexKeyOf(c),
          onTap: () => onPick(hexKeyOf(c)),
        ),
    ];
    if (horizontal) {
      return SizedBox(
        height: chipSize + 16,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          children: chips,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) _SectionLabel(label!),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        ),
      ],
    );
  }
}

/// The tiny uppercase section label every panel shares.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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

class _NoColorChip extends StatelessWidget {
  const _NoColorChip({
    required this.size,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final double size;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? kMagenta : kHairline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Icon(Icons.block, size: size * 0.5, color: kText3),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(message: tooltip, child: chip),
    );
  }
}

class _SwatchChip extends StatelessWidget {
  const _SwatchChip({
    required this.color,
    required this.size,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;

  /// The swatch's name (its hex) — color-only circles are mute for screen
  /// readers and unguessable on long-press; the label makes each one
  /// announceable and explainable.
  final String label;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? kMagenta : kHairline,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shared opacity control — one label-with-percentage + slider, the
/// same geometry the Insert panels' `_OpacityControl` and the style
/// inspector's Opacity row carried separately.
class DreamOpacityControl extends StatelessWidget {
  const DreamOpacityControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'OPACITY',
  });

  /// 0.05..1 — the object's opacity.
  final double value;
  final void Function(double) onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label — ${(value * 100).round()}%',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: kText3,
          ),
        ),
        Slider(
          value: value.clamp(0.05, 1.0),
          min: 0.05,
          max: 1.0,
          activeColor: kPurple,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
