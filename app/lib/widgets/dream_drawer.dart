import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// The shared bottom-drawer vocabulary — the ONE implementation behind
/// both the Files drawer and the Insert drawer:
///
///  * [DreamDrawerHeader] — the grab-handle + centered title band that is
///    the sheet's drag surface (vertical deltas + settle velocity flow to
///    the editor's shared extent machinery), with the optional left back
///    button and the optional right action button riding inside the drag
///    surface (a tap never loses to the vertical-drag arena);
///  * [DreamToolTile] — the 112-tall elevated card (36 icon chip on the
///    purple wash, a 2-line label, an optional sublabel) both grids' tiles
///    share, so a card in one drawer IS a card in the other;
///  * [DreamTileRow] — the 3-across row of equal tiles (equal Expanded
///    columns, 10 between), so neither drawer builds its grid by hand.
///
/// The drawers themselves (FilesDrawer / InsertSheet) keep their content;
/// the chrome and cards are one language now.

/// The drawer's header/drag surface.
///
/// The whole band is the drag surface — up grows the sheet, down shrinks
/// it toward closing, a downward fling or deep drag dismisses, a plain
/// release snaps to the nearest detent (the editor owns that decision from
/// the settle velocity). Opaque: a touch on the header is a gesture, never
/// a press through the sheet into whatever it floats over.
class DreamDrawerHeader extends StatelessWidget {
  const DreamDrawerHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.backTooltip = 'Back',
    this.onBack,
    this.trailing,
    this.trailingTooltip,
    this.onDragUpdate,
    this.onDragSettle,
    this.dragKey,
  });

  /// The centered title.
  final String title;

  /// Whether the left back affordance shows (subsection and panel views).
  final bool showBack;

  /// The back button's tooltip.
  final String backTooltip;

  /// The back arrow's tap.
  final VoidCallback? onBack;

  /// The right slot (e.g. the layers button); width-matched to the back
  /// slot so the title stays optically centered whether either shows.
  final Widget? trailing;

  final String? trailingTooltip;

  /// Live drag forwarding: vertical deltas (positive = finger moved down)
  /// and the settle velocity, both mapped by the editor onto the shared
  /// sheet extent and detents.
  final void Function(double dy)? onDragUpdate;
  final void Function(double velocityDy)? onDragSettle;

  /// The handle's key (tests find the drag surface by it).
  final Key? dragKey;

  @override
  Widget build(BuildContext context) {
    Widget? trailingChild = trailing;
    if (trailingChild != null && trailingTooltip != null) {
      trailingChild = Tooltip(
        message: trailingTooltip!,
        child: trailingChild,
      );
    }
    return GestureDetector(
      key: dragKey,
      // Opaque: the pill AND the heading are the drag surface, and the
      // header eats its own taps.
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDragUpdate?.call(d.delta.dy),
      onVerticalDragEnd: (d) => onDragSettle?.call(d.velocity.pixelsPerSecond.dy),
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
                  // The affordance: one shade clearer than a hairline so
                  // the pill reads as a handle, never as decoration.
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
                            tooltip: backTooltip,
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
                    child: trailingChild ??
                        (showBack
                            ? null
                            : const SizedBox.shrink()),
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

/// One tool tile: the SAME card for the Files grid and the Insert grid —
/// elevated a deliberate step above the sheet's own surface, hairline
/// edge, the icon in its washed-purple chip above the label — with the
/// SAME footprint (112 tall, 36-chip, the same inner breathing room), so
/// both grids read as one language and neither set of cards looks
/// squeezed or pressed relative to the other.
class DreamToolTile extends StatelessWidget {
  const DreamToolTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  /// Marks the card as the current choice (an accent border), e.g. the
  /// Design drawer's active family.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      // The card: kElevated over the drawer's kSurface, so the grid reads
      // as raised controls rather than more of the panel behind it. The
      // Material (not a decorated Container) carries the ink — the press
      // ripple lands ON the elevated fill instead of hiding under it.
      color: kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? kAccent : kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          // Fixed height keeps every row's tiles equal; two label lines
          // ("Aspect ratio", "Deck resources") fit with the chip on board.
          height: 112,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  // The signature color, quiet: the glyph sits in its own
                  // washed-purple field — highlighted without borrowing the
                  // gradient the app reserves for create-moments.
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kPurpleWash,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 19, color: kPurple),
                ),
                const SizedBox(height: 6),
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

/// A 3-across row of equal [DreamToolTile]s with the standard 10 between
/// — the one grid primitive both drawers' cards lay out with (empty
/// columns hold the row's shape, matching the historical hand-built
/// rows).
class DreamTileRow extends StatelessWidget {
  const DreamTileRow({super.key, required this.tiles});

  /// Exactly the row's tiles (usually 3; fewer fill from the left).
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final cols = tiles.length;
    return Row(
      children: [
        // The historical geometry verbatim: real tiles separated by one
        // 10px gap each, trailing columns filled to keep the row's shape.
        for (var i = 0; i < 3; i++) ...[
          if (i > 0 && i < cols) const SizedBox(width: 10),
          Expanded(child: i < cols ? tiles[i] : const SizedBox.shrink()),
        ],
      ],
    );
  }
}
