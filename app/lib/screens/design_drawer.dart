import 'package:material_ui/material_ui.dart';

import '../core/color_utils.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/dream_drawer.dart';

/// The Design drawer: the docked sheet the Design tab opens, built on the
/// same chrome as the Files and Insert drawers (one surface, the shared
/// grab-handle header, the same drag and detents, the same 3-across tiles).
///
/// Sections, top to bottom:
///  * Theme: one tile per family (the current one is outlined), and a
///    Shuffle tile for a new variant of the current family;
///  * Variants: the current family's variants as palette swatches;
///  * This slide: hide graphics, back to the deck background, and apply the
///    slide's background to every slide;
///  * Background: the deck's palette swatches for this slide.
///
/// The drawer holds no deck state of its own: the editor passes the data
/// and the callbacks, the same way the other drawers are driven.
class DesignDrawer extends StatelessWidget {
  const DesignDrawer({
    super.key,
    required this.families,
    required this.currentFamily,
    required this.onFamily,
    required this.onShuffle,
    required this.variants,
    required this.currentSeed,
    required this.onVariant,
    required this.hideGraphics,
    required this.onToggleGraphics,
    required this.palette,
    required this.slideBackground,
    required this.onBackground,
    required this.onApplyAll,
    this.bottomInset = 0,
    this.onDragUpdate,
    this.onDragSettle,
  });

  /// (id, label) for each family, in the order the chips show them.
  final List<(String, String)> families;

  /// The deck's family id, outlined in the Theme section.
  final String currentFamily;
  final void Function(String id) onFamily;

  /// A new variant of the current family.
  final VoidCallback onShuffle;

  /// Each variant: `seed` (int) and `palette` (bg, accent hex strings).
  final List<Map<String, dynamic>> variants;

  /// The deck's seed, reduced to the strip's range, to outline its variant.
  final int? currentSeed;
  final void Function(int seed) onVariant;

  final bool hideGraphics;
  final VoidCallback onToggleGraphics;

  /// The deck's own colors, offered as slide backgrounds.
  final List<Color> palette;

  /// This slide's background (6 hex digits), or null for the deck background.
  final String? slideBackground;
  final void Function(String? hex) onBackground;
  final void Function(String? hex) onApplyAll;

  /// The overlay clearance at the sheet's bottom (the filmstrip tray), kept
  /// as scroll padding so the last section can always scroll clear of it.
  final double bottomInset;

  final void Function(double dy)? onDragUpdate;
  final void Function(double velocityDy)? onDragSettle;

  static const Map<String, IconData> _familyIcons = {
    'swiss_editorial': Icons.grid_view,
    'cinematic': Icons.movie,
    'magazine_serif': Icons.menu_book,
    'bold': Icons.format_bold,
    'pastel': Icons.brush,
  };

  @override
  Widget build(BuildContext context) {
    final familyTiles = <Widget>[
      for (final (id, label) in families)
        DreamToolTile(
          key: ValueKey('design_family_$id'),
          icon: _familyIcons[id] ?? Icons.palette,
          label: label,
          sub: id == currentFamily ? 'Current' : null,
          selected: id == currentFamily,
          onTap: () => onFamily(id),
        ),
      DreamToolTile(
        key: const ValueKey('design_shuffle'),
        icon: Icons.shuffle,
        label: 'Shuffle',
        sub: 'New variant',
        onTap: onShuffle,
      ),
    ];

    return Material(
      key: const ValueKey('design_drawer'),
      // The same surface as the Files and Insert drawers.
      color: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: kHairline),
      ),
      child: Column(
        children: [
          DreamDrawerHeader(
            title: 'Design',
            dragKey: const ValueKey('design_drawer_handle'),
            onDragUpdate: onDragUpdate,
            onDragSettle: onDragSettle,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 10 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Theme'),
                  _TileGrid(tiles: familyTiles),
                  const SizedBox(height: 14),
                  const _SectionLabel('Variants'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final v in variants)
                        DesignSwatch(
                          key: ValueKey('design_variant_${v['seed']}'),
                          bg: hexToColor(v['palette']['bg'] as String),
                          accent: hexToColor(v['palette']['accent'] as String),
                          selected: (v['seed'] as num).toInt() == currentSeed,
                          onTap: () => onVariant((v['seed'] as num).toInt()),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _SectionLabel('This slide'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DreamChoiceChip(
                        magenta: true,
                        label: 'Hide graphics',
                        selected: hideGraphics,
                        onTap: onToggleGraphics,
                      ),
                      DreamChoiceChip(
                        magenta: true,
                        label: 'Default bg',
                        selected: slideBackground == null,
                        onTap: () => onBackground(null),
                      ),
                      DreamChoiceChip(
                        magenta: true,
                        label: 'Apply to all',
                        selected: false,
                        onTap: () => onApplyAll(slideBackground),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _SectionLabel('Background'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in palette.take(7))
                        DesignSwatch(
                          bg: c,
                          selected: slideBackground == colorToHex(c),
                          onTap: () => onBackground(colorToHex(c)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 3-across grid of [DreamToolTile]s, rows separated by 10px.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 3) {
      final end = (i + 3 < tiles.length) ? i + 3 : tiles.length;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(DreamTileRow(tiles: tiles.sublist(i, end)));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.6,
          color: kText3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A round colour swatch: the background colour, an optional accent dot,
/// and an accent ring when it is the current choice.
class DesignSwatch extends StatelessWidget {
  const DesignSwatch({
    super.key,
    required this.bg,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final Color bg;
  final Color? accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? kAccent : kText3,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: accent == null
            ? null
            : Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
      ),
    );
  }
}
