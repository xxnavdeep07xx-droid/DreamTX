part of 'editor_screen.dart';

/// The editor's primary navigation — a PowerPoint-style ribbon, horizontally
/// scrollable so all twelve tabs sit one thumb away: AI · Files · Home ·
/// Insert · Draw · Design · Transitions · Animations · Slide show · Review ·
/// View · Help. Material-3 navigation proportions: 76dp tall, a 24dp icon in
/// a stadium pill when active, an 11sp label below, and edge fades so tabs
/// melt into the surface instead of clipping. The active tab's contextual
/// action row renders between the canvas and the filmstrip.
/// The filmstrip's boundary rule and its built-in edge handle.
///
/// One continuous rule runs the editor's full width directly above the strip
/// band — or, when the strip is collapsed, directly above the ribbon. Near
/// the right edge it ramps up into a short horizontal ledge that runs flush
/// to the screen edge, and the chevron sits centered in the pocket under
/// that ledge: a toggle built into the boundary itself — no detached
/// floating button, no rectangular outline. The drawn tab keeps one
/// silhouette in both states; the state reads three ways (chevron direction,
/// the line's color, the a11y label), with color reinforcing but never
/// carrying the state alone:
///
/// * collapsed — a cool light neutral rule (kText2) and an up chevron;
/// * expanded — the signature gradient sweep and a down chevron that is a
///   miniature of the + disc's own gradient.
///
/// The accent took three rounds to settle by the user's eye: a warm red
/// (kAccent) read off-theme, and a flat single purple still read off — so
/// the open boundary now wears the exact three stops the + disc wears
/// (kPurple → kMagenta → kOrange): [ruleSweep] runs them left → right
/// along the rule (quiet purple along the flat baseline, warming through
/// magenta, arriving at orange exactly where the ramp lifts into the
/// ledge), and the chevron glyph repeats the disc's own diagonal
/// kInkGradient through a srcIn ShaderMask. The collapsed state stays the
/// cool neutral — the boundary earns the signature colors only while the
/// strip is worth looking at — and kAccent stays reserved for
/// destructive/live semantics.
///
/// The rule is drawn by [_FilmstripDividerPainter] from the same geometry
/// constants that place the handle, so the chevron is always optically
/// centered in the pocket at every width — the numbers are right-edge
/// relative, which keeps the handle right-aligned on any screen.
///
/// The tap target is a reserved 48 × 48 box at the right edge while the drawn
/// tab itself stays ~30dp tall. The hit box lives entirely inside the 48dp
/// header region — it never overlaps the canvas, the thumbnail row, or the
/// ribbon, and the decorative painting below it never claims taps.
class _FilmstripDivider extends StatelessWidget {
  const _FilmstripDivider({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  // ---- shared geometry (logical px, right-edge relative) ---------------------
  //
  //   0 ........................ W-92   W-70 ................. W
  //   ───────────────────────────╱──────── ledge, y = 18 ─────┐ edge
  //   baseline, y = 46         ╱        ^ chevron (20dp)      │
  //
  /// The compact header region — exactly the 48dp hit target's height.
  static const double regionHeight = 48;

  /// The raised ledge: 28dp above the baseline (the spec's 24–30 rise).
  static const double ledgeY = 18;

  /// The flat rule — 2dp in from the region's bottom so the stroke never
  /// bleeds into the strip/ribbon below; it sits directly above both.
  static const double baselineY = 46;

  /// The ramp starts this far from the right edge.
  static const double rampFromRight = 92;

  /// ...and climbs the full rise over these many horizontal pixels.
  static const double rampRun = 22;

  static const double chevronSize = 20;

  /// The reserved tap target. The drawn tab stays ~30dp tall.
  static const double hitSize = 48;

  static const double stroke = 1.8;

  /// The open rule's sweep — the signature family's three stops run flat
  /// along the boundary: quiet purple at the left edge, warming through
  /// magenta, arriving at orange exactly where the ramp lifts into the
  /// ledge and the chevron sits. Same three stops as the + disc's
  /// kInkGradient, laid out horizontally for a wide thin rule.
  static const LinearGradient ruleSweep = LinearGradient(
    colors: [kPurple, kMagenta, kOrange],
  );

  @override
  Widget build(BuildContext context) {
    final String label = expanded ? 'Collapse slides' : 'Expand slides';
    // Chevron center: horizontally the middle of the flat ledge (the ledge
    // spans the last rampFromRight - rampRun = 70dp), vertically the optical
    // middle of the pocket between ledge and baseline — both expressed as
    // padding inside the 48×48 hit box at the right edge.
    const double chevronLeft =
        hitSize - (rampFromRight - rampRun) / 2 - chevronSize / 2;
    const double chevronTop =
        (ledgeY + baselineY) / 2 - chevronSize / 2;
    return SizedBox(
      height: regionHeight,
      child: Stack(
        children: [
          // The rule: one continuous baseline → ramp → ledge. Decorative
          // painting only — no child, so it can never capture a tap. Open,
          // the stroke carries the signature sweep; collapsed, the same
          // path wears the cool light neutral.
          Positioned.fill(
            child: CustomPaint(
              key: const ValueKey('filmstrip_divider'),
              painter: _FilmstripDividerPainter(
                color: kText2,
                sweep: expanded ? ruleSweep : null,
              ),
            ),
          ),
          // The handle: the whole reserved 48×48 at the right edge toggles,
          // carrying the chevron centered in its pocket. The tooltip serves
          // long-press/hover discovery; the Semantics node carries the action
          // (and exposes the expanded state) for assistive tech.
          Positioned(
            right: 0,
            top: 0,
            child: SizedBox(
              key: const ValueKey('filmstrip_handle'),
              width: hitSize,
              height: hitSize,
              child: Semantics(
                button: true,
                label: label,
                value: expanded ? 'expanded' : 'collapsed',
                onTap: onToggle,
                child: Tooltip(
                  message: label,
                  excludeFromSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          chevronLeft, chevronTop, 0, 0),
                      // Open, the chevron is a miniature of the + disc: the
                      // disc's own diagonal kInkGradient applied to the glyph
                      // through a srcIn ShaderMask (the white base supplies
                      // only the alpha the shader fills). Collapsed it stays
                      // the cool light neutral.
                      child: expanded
                          ? ShaderMask(
                              shaderCallback: kInkGradient.createShader,
                              blendMode: BlendMode.srcIn,
                              child: const Icon(
                                Icons.keyboard_arrow_down,
                                size: chevronSize,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.keyboard_arrow_up,
                              size: chevronSize,
                              color: kText2,
                            ),
                    ),
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

/// Draws the filmstrip's boundary: the flat baseline from the editor's left
/// edge (no side padding), the ramp up near the right edge, and the ledge
/// running flush to the right edge — one path, one stroke, rounded joins.
///
/// Beneath that same geometry the painter first fills the tray's SILHOUETTE
/// with the tray's own charcoal (kFilmstrip): the full-width strip from the
/// baseline down to the region's floor, plus the raised tab above it — the
/// ramp's triangle and the ledge's pocket behind the chevron. The fill and
/// the gradient stroke share one geometry, so there is no seam: the stroked
/// boundary lies exactly on the fill's top edge, and the charcoal runs
/// unbroken from the rule down into the band's own fill below the region.
/// Only the raised tab projects above the baseline — the fill never paints a
/// full-width rectangle above the line — so the divider keeps its transparent
/// window left of the ramp (whatever surface sits behind the tray shows
/// through there, by design), while the sloped ramp and the chevron's pocket
/// are fully opaque: the Files sheet's tiles can never show through the tab.
/// The chevron and the sweep ride on top of it all.
///
/// The stroke is the collapsed cool neutral ([color]) or, when the strip is
/// open, the signature [sweep]: its shader spans the path's own bounds, so
/// t maps purely to x — the three stops land the same at every width.
class _FilmstripDividerPainter extends CustomPainter {
  _FilmstripDividerPainter({required this.color, this.sweep});

  /// The collapsed stroke color.
  final Color color;

  /// The open stroke's gradient (kPurple → kMagenta → kOrange); null when
  /// collapsed.
  final LinearGradient? sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // The silhouette beneath the boundary path — the SAME geometry the
    // stroke below traces, closed down to the region's floor so the fill
    // and the stroke share one edge (no seam), and so the charcoal meets
    // the band's own fill flush at the region's bottom edge.
    final silhouette = Path()
      ..moveTo(0, _FilmstripDivider.baselineY)
      ..lineTo(
          w - _FilmstripDivider.rampFromRight, _FilmstripDivider.baselineY)
      ..lineTo(w - _FilmstripDivider.rampFromRight + _FilmstripDivider.rampRun,
          _FilmstripDivider.ledgeY)
      ..lineTo(w, _FilmstripDivider.ledgeY)
      ..lineTo(w, _FilmstripDivider.regionHeight)
      ..lineTo(0, _FilmstripDivider.regionHeight)
      ..close();
    canvas.drawPath(
        silhouette,
        Paint()
          ..color = kFilmstrip
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
    );
    final path = Path()
      ..moveTo(0, _FilmstripDivider.baselineY)
      ..lineTo(
          w - _FilmstripDivider.rampFromRight, _FilmstripDivider.baselineY)
      ..lineTo(w - _FilmstripDivider.rampFromRight + _FilmstripDivider.rampRun,
          _FilmstripDivider.ledgeY)
      ..lineTo(w, _FilmstripDivider.ledgeY);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _FilmstripDivider.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final sweep = this.sweep;
    if (sweep == null) {
      paint.color = color;
    } else {
      // The shader rect is the path's own bounds (ledge top → baseline):
      // over that rect the horizontal sweep maps t to x alone, so the left
      // edge is purple and the ramp/ledge zone arrives at orange at any
      // width or region height.
      paint.shader = sweep.createShader(Rect.fromLTWH(
          0,
          _FilmstripDivider.ledgeY,
          w,
          _FilmstripDivider.baselineY - _FilmstripDivider.ledgeY));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FilmstripDividerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sweep != sweep;
}

/// Clips the sheet's moving layer at the navbar's top boundary: while the
/// entrance or exit slide runs, the sheet is translated so that part of its
/// body sits below the navbar's top edge — but it may never PAINT (or
/// hit-test) there. The clip keeps the navbar fixed in front of the moving
/// layer and the sheet emerging continuously from behind it.
///
/// [boundary] is the navbar's top edge measured up from the clip box's
/// bottom (the same [sheetAnchor] the sheet rides) — a constant, so the clip
/// never moves; the tray's own box ends exactly at this edge and is
/// untouched by it.
class _SheetPortalClipper extends CustomClipper<Rect> {
  _SheetPortalClipper({required this.boundary});

  /// The navbar's top edge, as an inset from the clip box's bottom.
  final double boundary;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
      0, 0, size.width, math.max(0.0, size.height - boundary));

  @override
  bool shouldReclip(_SheetPortalClipper oldClipper) =>
      oldClipper.boundary != boundary;
}

/// One item of the filmstrip rail: a slide card (carrying its TRUE slide
/// index — the rail is a flattened view that omits folded sections'
/// slides, so a list position is never a slide index) or a section divider
/// (carrying its marker).
class _RailItem {
  const _RailItem.section(this.section) : slideIndex = -1;
  const _RailItem.slide(this.slideIndex) : section = null;

  /// The section marker this divider renders; null on a slide card.
  final Map<String, dynamic>? section;

  /// The slide's index in the deck; -1 on a section divider.
  final int slideIndex;

  bool get isSection => section != null;
}

/// A section divider in the filmstrip rail — structure, not content: a
/// slim card over the charcoal band carrying the signature gradient as
/// its left edge strip (the boundary rule's own three stops, run
/// vertically) and the section's name rotated to read top-to-bottom — the
/// rail's one text axis. Tap folds the section's slides out of the rail
/// and folds a head-count pill in; tap again restores them. Long-press
/// renames or removes. The card deliberately reads quieter than the white
/// slide cards — translucent fill, hairline border, secondary type — a
/// boundary the eye files as chrome, not content.
class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.id,
    required this.name,
    required this.collapsed,
    required this.count,
    required this.onToggle,
    required this.onLongPress,
  });

  /// The section marker id (also the widget key's suffix).
  final String id;

  /// The section's display name (rotated).
  final String name;

  /// Folded state: the section's slides are out of the rail.
  final bool collapsed;

  /// How many slides the section owns (the folded pill's head-count).
  final int count;

  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  /// The edge strip: the divider rule's three stops (kPurple → kMagenta →
  /// kOrange) run VERTICALLY — the chip is the rule's own child.
  static const LinearGradient _edgeSweep = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [kPurple, kMagenta, kOrange],
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        key: ValueKey('section_chip_$id'),
        width: 44,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggle,
          onLongPress: onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kHairline),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  children: [
                    // The signature edge: 3dp of the rule's own sweep,
                    // flush to the card's left side.
                    const Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(gradient: _edgeSweep),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 3, 4),
                      child: Column(
                        children: [
                          // The rotated name — pre-rotation width is the
                          // vertical run, capped at 52dp (the name's
                          // budget under the affordance) with an ellipsis.
                          Expanded(
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 52),
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        color: kText2,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // The fold state's affordance: a chevron while
                          // open, the hidden head-count while folded.
                          if (collapsed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color:
                                    Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$count',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      height: 1.2,
                                      color: kText2,
                                      fontWeight: FontWeight.w700)),
                            )
                          else
                            const Icon(Icons.chevron_right,
                                size: 14, color: kText2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}
