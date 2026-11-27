import 'package:material_ui/material_ui.dart';

import '../core/color_utils.dart';
import '../theme.dart';
import '../widgets/dream_drawer.dart';

/// The Design drawer: the docked sheet the Design tab opens, built on the
/// same chrome as the Files and Insert drawers (one surface, the shared
/// grab-handle header, the same drag and detents).
///
/// This is the one place in the studio where the deck's visual IDENTITY is
/// chosen, so the panel is a style gallery — every choice is SHOWN, never
/// described. Three sections:
///
///  * Theme — a horizontally swiping carousel of live preview cards. Each
///    card paints a miniature slide from the family's own DNA constants
///    (its paper/dark/yellow field, its accent, serif or sans, its corner
///    language and its signature motifs), so Swiss editorial, Cinematic and
///    Bold read apart at a glance instead of being five identical icon
///    tiles. The current family's card repaints with the deck's ACTUAL
///    resolved variant palette (WYSIWYG for the active choice), carries
///    the accent edge plus a check badge, and a tap applies that family.
///    The whole section fits the resting detent — the carousel, not the
///    panel, is what scrolls.
///  * Variants — the current family's variants as little slides (each one
///    the variant's own bg with its accent as an edge bar), led by the ONE
///    gradient Shuffle chip: a new variant is a create-moment, the only
///    place in this drawer the signature gradient appears.
///  * Background — this slide's background, one control: the deck-default
///    chip first (back to the DNA background — the old 'Default bg' chip,
///    moved to where the rest of the background lives), then the deck's
///    palette as swatches, then the two slide tools — hide the background
///    graphics, and apply this slide's background to every slide.
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

  /// (id, label) for each family, in the order the carousel shows them.
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

  /// The five families' representative looks — VERBATIM from the engine's
  /// own curated pools (core/crates/deck-core/src/dna.rs): each family's
  /// first background and first accent, its display font role (serif or
  /// sans — the same `fontFamily: 'serif'` spelling the slide canvas
  /// itself uses), and its corner-radius language, so a preview card is
  /// what the family actually renders, not an artist's impression.
  static const Map<String,
          ({String bg, String fg, String accent, bool serif, double corner})>
      _familyLooks = {
    'swiss_editorial': (
      bg: 'F7F6F3',
      fg: '17181A',
      accent: 'D03028',
      serif: false,
      corner: 2
    ),
    'cinematic': (
      bg: '0D1117',
      fg: 'F2F0EC',
      accent: 'F5A623',
      serif: false,
      corner: 6
    ),
    'magazine_serif': (
      bg: 'F4EFE6',
      fg: '17181A',
      accent: '7A1E2E',
      serif: true,
      corner: 3
    ),
    'bold': (
      bg: 'FFE14D',
      fg: '17181A',
      accent: 'E63946',
      serif: false,
      corner: 0
    ),
    'pastel': (
      bg: 'F3E9F7',
      fg: '17181A',
      accent: '7B5EA7',
      serif: true,
      corner: 12
    ),
  };

  /// The look for a family id the engine has never named: neutral paper,
  /// the studio's purple, sans, softly rounded. Never shown for the five
  /// real families — belt and braces for a future sixth.
  static const ({
    String bg,
    String fg,
    String accent,
    bool serif,
    double corner
  }) _fallbackLook =
      (bg: 'FFFFFF', fg: '17181A', accent: 'A855F7', serif: false, corner: 6);

  /// The deck's own resolved palette — the variant entry whose seed IS the
  /// deck's seed — for painting the current family's card with the deck's
  /// actual colors. (Null when the strip has no matching entry; the
  /// representative look stands in.)
  ({String bg, String accent})? get _livePalette {
    for (final v in variants) {
      if ((v['seed'] as num?)?.toInt() != currentSeed) continue;
      final p = v['palette'];
      if (p is! Map) return null;
      final bg = (p['bg'] as String?)?.toUpperCase();
      final accent = (p['accent'] as String?)?.toUpperCase();
      if (bg == null || accent == null) return null;
      return (bg: bg, accent: accent);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final live = _livePalette;

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
              padding: EdgeInsets.fromLTRB(14, 2, 14, 12 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Theme'),
                  _Carousel(
                    height: 112,
                    children: [
                      for (final (id, label) in families)
                        _ThemeCard(
                          key: ValueKey('design_family_$id'),
                          id: id,
                          label: label,
                          selected: id == currentFamily,
                          // ONLY the current family's card repaints with
                          // the deck's live palette — the other families
                          // show their own representative look.
                          liveBg: id == currentFamily ? live?.bg : null,
                          liveAccent: id == currentFamily ? live?.accent : null,
                          onTap: () => onFamily(id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('Variants'),
                  _Carousel(
                    height: 32,
                    children: [
                      _ShuffleChip(
                        key: const ValueKey('design_shuffle'),
                        onTap: onShuffle,
                      ),
                      for (final v in variants)
                        _VariantChip(
                          key: ValueKey('design_variant_${v['seed']}'),
                          bg: hexToColor(v['palette']['bg'] as String),
                          accent: hexToColor(v['palette']['accent'] as String),
                          selected: (v['seed'] as num).toInt() == currentSeed,
                          label: 'Variant ${v['seed']}',
                          onTap: () => onVariant((v['seed'] as num).toInt()),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('Background'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _DeckChip(
                        key: const ValueKey('design_deck_default'),
                        selected: slideBackground == null,
                        onTap: () => onBackground(null),
                      ),
                      for (final c in palette.take(7)) _backgroundSwatch(c),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SlideTool(
                          key: const ValueKey('design_hide_graphics'),
                          icon: Icons.visibility_off,
                          label: 'Hide graphics',
                          selected: hideGraphics,
                          onTap: onToggleGraphics,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SlideTool(
                          key: const ValueKey('design_apply_all'),
                          icon: Icons.copy_all,
                          label: 'Apply to all',
                          selected: false,
                          onTap: () => onApplyAll(slideBackground),
                        ),
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

  /// One palette colour as a background swatch, with its hex for the
  /// tooltip and the selected ring when it is this slide's background.
  Widget _backgroundSwatch(Color c) {
    final hex = colorToHex(c);
    return DesignSwatch(
      bg: c,
      label: '#$hex',
      selected: slideBackground == hex,
      onTap: () => onBackground(hex),
    );
  }
}

/// A horizontally swiping strip — the drawer's gallery idiom. A fixed
/// height, one row of cards/chips with 10 between, and the ribbon's own
/// edge-fade affordance over both ends (the same surface gradient the nav
/// bar paints) so content reads as gliding under, never as sliced. The
/// strip scrolls INSTEAD of the panel: every section keeps its full width
/// at any sheet height, and the resting detent shows the whole Theme
/// section without touching the sheet's own scroll.
class _Carousel extends StatelessWidget {
  const _Carousel({required this.height, required this.children});

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [kSurface, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [kSurface, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One family's card: the miniature slide painted in the family's own
/// look, with its name below. The elevated card treatment the tool grids
/// use (12 radius, hairline edge), the accent edge and a check badge when
/// it is the current family, and — for the current family — the preview
/// repaints with the deck's own resolved variant palette so the selected
/// card is what the deck actually looks like right now.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
    this.liveBg,
    this.liveAccent,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The deck's resolved bg/accent hexes, for the CURRENT family's card.
  final String? liveBg;
  final String? liveAccent;

  @override
  Widget build(BuildContext context) {
    final spec = DesignDrawer._familyLooks[id] ?? DesignDrawer._fallbackLook;
    final bg = hexToColor(liveBg ?? spec.bg);
    final accent = hexToColor(liveAccent ?? spec.accent);
    final fg = hexToColor(spec.fg);

    return Material(
      // The same card language as the Files/Insert tool tiles: elevated a
      // step above the sheet's surface, hairline edge, ink on the fill.
      color: kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? kAccent : kHairline,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 124,
          height: 112,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(spec.corner),
                        child: _FamilyPreview(
                          id: id,
                          bg: bg,
                          fg: fg,
                          accent: accent,
                          serif: spec.serif,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // The label centres itself in whatever height is left —
                    // the card stays a fixed 112-tall rhythm and the name
                    // never rides the card's bottom edge.
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? kText : kText2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // The current family's badge: the accent dot + check, the
              // filmstrip's selected-thumb language in miniature.
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: kAccent,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The miniature slide: the family's field painted with its own motifs —
/// nothing but Containers and one 'Aa', so the card stays honest at 108x72.
/// Each case mirrors the family's DNA constants from the engine: Swiss's
/// grid rule and number stamps on paper, Cinematic's dark field with an
/// amber edge bar, Magazine's serif masthead over an oxblood rule, Bold's
/// yellow field with a hard accent bar and a big black glyph, Pastel's soft
/// rounds. The serif families spell their 'Aa' in the same
/// `fontFamily: 'serif'` the slide canvas itself uses for them.
class _FamilyPreview extends StatelessWidget {
  const _FamilyPreview({
    required this.id,
    required this.bg,
    required this.fg,
    required this.accent,
    required this.serif,
  });

  final String id;
  final Color bg;
  final Color fg;
  final Color accent;
  final bool serif;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: bg,
      child: SizedBox(
        height: 72,
        width: double.infinity,
        child: Stack(
          children: _motifs(),
        ),
      ),
    );
  }

  List<Widget> _motifs() {
    switch (id) {
      case 'cinematic':
        return [
          // The dark field's letterbox strip along the top edge.
          Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: Container(height: 3, color: fg.withValues(alpha: 0.08))),
          Positioned(
              left: 14,
              top: 16,
              child: Text('Aa', style: _display(20, FontWeight.w600))),
          Positioned(
              left: 14,
              bottom: 23,
              child: Container(
                  width: 58, height: 2, color: fg.withValues(alpha: 0.25))),
          // The signature amber edge bar, low and left.
          Positioned(
            left: 14,
            bottom: 12,
            child: Container(
                width: 26,
                height: 4,
                decoration: BoxDecoration(
                    color: accent, borderRadius: BorderRadius.circular(2))),
          ),
        ];
      case 'magazine_serif':
        return [
          Positioned(
              left: 14,
              top: 12,
              child: Text('Aa', style: _display(23, FontWeight.w700))),
          // The oxblood rule under the masthead.
          Positioned(
              left: 14,
              top: 42,
              child: Container(width: 44, height: 1.5, color: accent)),
          Positioned(
              left: 14,
              right: 14,
              bottom: 24,
              child: Container(height: 1, color: fg.withValues(alpha: 0.14))),
          Positioned(
              left: 14,
              bottom: 11,
              child: Text('Aa',
                  style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: fg.withValues(alpha: 0.5),
                      height: 1,
                      fontFamily: serif ? 'serif' : null))),
        ];
      case 'bold':
        return [
          // The hard accent bar down the left edge.
          Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 5, color: accent)),
          Positioned(
              left: 15,
              top: 10,
              child: Text('Aa', style: _display(27, FontWeight.w700))),
          Positioned(
              right: 13,
              bottom: 11,
              child: Container(width: 11, height: 11, color: fg)),
        ];
      case 'pastel':
        return [
          Positioned(
              left: 14,
              top: 12,
              child: Text('Aa', style: _display(21, FontWeight.w600))),
          // The soft rounds: an accent disc and a washed pill.
          Positioned(
              right: 13,
              top: 13,
              child: Container(
                  width: 20,
                  height: 20,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle))),
          Positioned(
            left: 14,
            bottom: 11,
            child: Container(
                width: 30,
                height: 7,
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4))),
          ),
        ];
      default:
        // swiss_editorial — and any family the app has not met: the grid
        // rule, the accent square, the number stamps.
        return [
          Positioned(
              left: 14,
              top: 12,
              child: Text('Aa', style: _display(22, FontWeight.w700))),
          Positioned(
              right: 12,
              top: 12,
              child: Container(width: 10, height: 10, color: accent)),
          Positioned(
              left: 14,
              right: 12,
              bottom: 23,
              child: Container(height: 1, color: fg.withValues(alpha: 0.25))),
          Positioned(
              left: 14,
              bottom: 10,
              child: Text('01',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: fg.withValues(alpha: 0.55),
                      height: 1))),
          Positioned(
              right: 12,
              bottom: 10,
              child: Text('02',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: fg.withValues(alpha: 0.3),
                      height: 1))),
        ];
    }
  }

  /// The display glyph in the family's own font role.
  TextStyle _display(double size, FontWeight weight) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: fg,
        height: 1,
        fontFamily: serif ? 'serif' : null,
      );
}

/// The Variants strip's lead: the ONE gradient chip in the drawer — a new
/// variant is a create-moment, and the signature gradient is reserved for
/// exactly those. A shuffle glyph on the gradient, tooltip and semantics
/// carried like every other control.
class _ShuffleChip extends StatelessWidget {
  const _ShuffleChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: kInkGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.shuffle, size: 14, color: Colors.white),
      ),
    );
    return Tooltip(
      message: 'New variant of this theme',
      child:
          Semantics(button: true, label: 'Shuffle — new variant', child: chip),
    );
  }
}

/// One variant: a little 16:9-ish slide — the variant's own background
/// with its accent as the DNA edge bar down the left — so a variant is
/// picked by what it looks like, not by a bare colour dot. The accent ring
/// marks the deck's current variant.
class _VariantChip extends StatelessWidget {
  const _VariantChip({
    super.key,
    required this.bg,
    required this.accent,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final Color bg;
  final Color accent;
  final bool selected;

  /// The variant's name ('Variant 5') — spoken and shown on long-press.
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 32,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? kAccent : kHairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: accent),
            ),
          ],
        ),
      ),
    );
    return Tooltip(
      message: label,
      child: Semantics(
          button: true, selected: selected, label: label, child: chip),
    );
  }
}

/// The Background row's first chip: back to the deck's own DNA background.
/// The old 'Default bg' text chip, moved to where the rest of the
/// background lives and given a glyph — a style-card icon on the elevated
/// fill, the accent ring when the slide is on the deck background.
class _DeckChip extends StatelessWidget {
  const _DeckChip({super.key, required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kElevated,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? kAccent : kHairline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Icon(Icons.style, size: 16, color: selected ? kText : kText2),
      ),
    );
    return Tooltip(
      message: 'Deck background',
      child: Semantics(
          button: true,
          selected: selected,
          label: 'Deck background',
          child: chip),
    );
  }
}

/// One of the two slide tools under Background: an icon-and-label chip the
/// width of half the drawer, carrying the magenta edge language the
/// drawer's stateful chips have always worn. 'Hide graphics' toggles;
/// 'Apply to all' is a plain action (it spreads this slide's background —
/// or the deck default — to every slide).
class _SlideTool extends StatelessWidget {
  const _SlideTool({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? kMagenta : kHairline,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? kMagenta : kText2),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? kText : kText2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
/// and an accent ring when it is the current choice. [label] names the
/// swatch for tooltips and screen readers — a color-only circle is mute
/// otherwise.
class DesignSwatch extends StatelessWidget {
  const DesignSwatch({
    super.key,
    required this.bg,
    required this.selected,
    required this.onTap,
    this.accent,
    this.label,
  });

  final Color bg;
  final Color? accent;
  final bool selected;
  final VoidCallback onTap;

  /// Optional name (e.g. '#0F62FE' or 'Variant 3'); spoken and shown when
  /// known, omitted silently when the caller has no name to give.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final swatch = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          // A faint WHITE ring, not the panel's own hairline grey: on the
          // dark sheet a near-black swatch has to stay visible inside its
          // own ring, and a light swatch is already visible against the
          // charcoal without help — one quiet rule serves both.
          border: Border.all(
            color: selected ? kAccent : Colors.white.withValues(alpha: 0.22),
            width: selected ? 2.5 : 1,
          ),
        ),
        child: accent == null
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
      ),
    );
    final l = label;
    if (l == null) return swatch;
    return Tooltip(
      message: l,
      child:
          Semantics(button: true, selected: selected, label: l, child: swatch),
    );
  }
}