part of 'editor_screen.dart';

/// The ribbon tabs, in PowerPoint order. Each swaps in a contextual tool row
/// under the canvas; the remaining tabs get their toolboxes spec'd next.
enum _NavTab {
  ai,
  files,
  insert,
  draw,
  design,
  transitions,
  animations,
  slideshow,
  review,
  view,
  help,
}

/// One ribbon tab's footprint — twelve at this width overflow any phone, so
/// the bar scrolls and centers the active tab.
const double _navItemWidth = 66;

class _EditorNavBar extends StatelessWidget {
  const _EditorNavBar(
      {required this.active,
      required this.controller,
      required this.onSelect,
      this.showTopRule = true});

  final _NavTab? active;
  final ScrollController controller;
  final void Function(_NavTab) onSelect;

  /// Whether to draw the ribbon's own top hairline. The integrated filmstrip
  /// divider already paints the boundary directly above the ribbon while the
  /// strip is collapsed; showing this rule too would double the line.
  final bool showTopRule;

  static const _icons = {
    _NavTab.ai: Icons.auto_awesome,
    _NavTab.files: Icons.folder,
    _NavTab.insert: Icons.add_box,
    _NavTab.draw: Icons.gesture,
    _NavTab.design: Icons.palette,
    _NavTab.transitions: Icons.swap_horiz,
    _NavTab.animations: Icons.animation,
    _NavTab.slideshow: Icons.slideshow,
    _NavTab.review: Icons.rate_review,
    _NavTab.view: Icons.visibility,
    _NavTab.help: Icons.help,
  };
  static const _labels = {
    _NavTab.ai: 'AI',
    _NavTab.files: 'Files',
    _NavTab.insert: 'Insert',
    _NavTab.draw: 'Draw',
    _NavTab.design: 'Design',
    _NavTab.transitions: 'Transitions',
    _NavTab.animations: 'Animations',
    _NavTab.slideshow: 'Slide show',
    _NavTab.review: 'Review',
    _NavTab.view: 'View',
    _NavTab.help: 'Help',
  };

  @override
  Widget build(BuildContext context) {
    // The ONE stadium pill, shared across tabs: it glides to the active
    // slot (260ms ease-out) ONLY when switching between two open tabs; on
    // open/collapse it mounts/unmounts in place — no fade, no sweep, no
    // blink. Slot math: item pitch _navItemWidth, pill 58 wide, pill top =
    // item padding (6) + centered column gap (5).
    final double? slot = active == null
        ? null
        : _NavTab.values.indexOf(active!) * _navItemWidth +
            (_navItemWidth - 58) / 2;
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        // The hairline is a PAINT choice, never a layout one: the border's
        // 1dp inset exists in EVERY state (transparent while the filmstrip
        // divider's own rule owns the boundary) so the band's total height
        // is a constant 77dp — nothing above it (the canvas's constraints,
        // the sheet's anchor, the strip's flow spot) can ever move by the
        // hairline's own pixel when a tab or the tray toggles it.
        border: Border(
          top: BorderSide(
              color: showTopRule ? kHairline : Colors.transparent),
        ),
      ),
      // Material-3 NavigationBar anatomy, trimmed 80 -> 76dp because our
      // labels are single-line: a 24dp icon in a stadium pill, an 11sp label
      // under it, real vertical breathing room — and the ribbon melts into
      // the surface at both ends instead of hard-clipping half an icon.
      // (The 1dp border inset above brings the whole band to its constant
      // 77dp.)
      child: SizedBox(
        height: 76,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  children: [
                    // Behind the icons: the shared active pill. It mounts
                    // directly at its slot when the ribbon opens and
                    // unmounts on collapse — the only time it MOVES is a
                    // tab-to-tab switch (the glide). No fade, no sweep from
                    // the far-left edge: that was the blink.
                    if (slot != null)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        top: 11,
                        left: slot,
                        width: 58,
                        height: 34,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: kActiveWash,
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        for (final t in _NavTab.values)
                          SizedBox(
                            width: _navItemWidth,
                            child: _NavItemButton(
                              icon: _icons[t]!,
                              label: _labels[t]!,
                              active: active == t,
                              onTap: () => onSelect(t),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Edge fades, the PowerPoint-ribbon affordance: 12dp of surface
            // gradient over each end so tabs glide under instead of slicing.
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 12,
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
              width: 12,
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
      ),
    );
  }
}

class _NavItemButton extends StatelessWidget {
  const _NavItemButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? kText : kText3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // No rectangular ripple: on the dark bar the default splash paints
        // as an unclipped WHITE SQUARE around the tap point, which reads as
        // a glitch next to the round pill. The active state is carried by
        // the shared gliding pill + color switch instead — no ink needed.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The icon slot exactly matches the shared pill's footprint
              // (58 x 34), so the gliding pill lands dead-center behind the
              // icon. Fixed label height pins the math (6 + 5 = pill top 11).
              SizedBox(
                width: 58,
                height: 34,
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 16,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.2,
                      color: active ? kText : kText3,
                    ),
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

const List<(String, String)> _designFamilies = [
  ('swiss_editorial', 'Swiss editorial'),
  ('cinematic', 'Cinematic'),
  ('magazine_serif', 'Magazine serif'),
  ('bold', 'Bold'),
  ('pastel', 'Pastel'),
];

const TextStyle _rowHint = TextStyle(fontSize: 10.5, color: kText2);
