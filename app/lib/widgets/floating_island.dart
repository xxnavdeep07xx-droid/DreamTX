import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/island_math.dart';
import '../theme.dart';

/// Draw C: a floating island over the canvas. Full mode is the toolbar
/// spanning the canvas width, docked top or bottom. Compact mode is a
/// narrow column that docks to any corner. A 500 ms hold on the grip
/// lifts it (haptic + shadow); it follows the finger; release magnets it
/// to the nearest dock and reports the placement via [onPlace].
///
/// The island lives inside the canvas area only, so it never covers the
/// ribbon or the filmstrip (the keep-outs).
///
/// Only the grip starts a drag: the toolbar's own buttons keep their taps
/// and long-presses (the pen presets remove on long-press). The one-time
/// coach mark sits beside the island until dismissed or until it's lifted.
class FloatingIsland extends StatefulWidget {
  const FloatingIsland({
    super.key,
    required this.placement,
    required this.onPlace,
    required this.child,
  });

  final IslandPlacement placement;
  final ValueChanged<IslandPlacement> onPlace;
  final Widget child;

  @override
  State<FloatingIsland> createState() => _FloatingIslandState();
}

class _FloatingIslandState extends State<FloatingIsland> {
  final _bodyKey = GlobalKey();
  bool _lifted = false;
  double _dx = 0;
  double _dy = 0;
  double _areaW = 0;
  double _areaH = 0;

  Size get _body => _bodyKey.currentContext?.size ?? const Size(360, 48);

  void _lift() {
    HapticFeedback.mediumImpact();
    setState(() {
      _lifted = true;
      _dx = 0;
      _dy = 0;
    });
    // Lifting teaches the same thing the coach mark does: retire it.
    final p = widget.placement;
    if (!p.coachSeen) widget.onPlace(p.copyWith(coachSeen: true));
  }

  void _follow(LongPressMoveUpdateDetails d) {
    final p = widget.placement;
    final b = _body;
    setState(() {
      _dx = islandDxClamp(p.side, d.offsetFromOrigin.dx, _areaW, b.width);
      _dy = islandDyClamp(p.dock, d.offsetFromOrigin.dy, _areaH, b.height);
    });
  }

  void _release() {
    final p = widget.placement;
    final b = _body;
    final IslandPlacement next;
    if (p.compact) {
      final c = islandSnapCorner(p, _dx, _dy, _areaW, _areaH, b.width, b.height);
      next = p.copyWith(dock: c.dock, side: c.side);
    } else {
      next = p.copyWith(dock: islandSnap(p.dock, _dy, _areaH, b.height));
    }
    setState(() {
      _lifted = false;
      _dx = 0;
      _dy = 0;
    });
    widget.onPlace(next);
  }

  void _dismissCoach() =>
      widget.onPlace(widget.placement.copyWith(coachSeen: true));

  Widget _coachMark() => Container(
        key: const ValueKey('island_coach'),
        margin: const EdgeInsets.only(top: 6, bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kHairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Hold the grip to move this toolbar',
                style: TextStyle(color: kText2, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: _dismissCoach,
              child: const Text('Got it'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.placement;
    final grip = GestureDetector(
      key: const ValueKey('island_grip'),
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _lift(),
      onLongPressMoveUpdate: _follow,
      onLongPressEnd: (_) => _release(),
      onLongPressCancel: () => setState(() {
        _lifted = false;
        _dx = 0;
        _dy = 0;
      }),
      child: SizedBox(
        // 40-wide hit zone (was 22 — the thinnest control in the app) with
        // the 18px glyph centered: the long-press-to-lift gesture needs a
        // landable target, and 22dp wide asked too much of a fingertip.
        width: 40,
        height: 48,
        child: Center(
          child: Icon(Icons.drag_indicator,
              size: 18,
              color: _lifted ? const Color(0xFFFFFFFF) : kText3),
        ),
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      _areaW = constraints.maxWidth;
      _areaH = constraints.maxHeight;
      final body = Transform.translate(
        offset: Offset(_dx, _dy),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kHairline),
            boxShadow: _lifted
                ? const [
                    BoxShadow(
                        color: Color(0x88000000),
                        blurRadius: 18,
                        offset: Offset(0, 6)),
                  ]
                : const [],
          ),
          child: KeyedSubtree(
            key: _bodyKey,
            child: Row(
              mainAxisSize: p.compact ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                grip,
                p.compact ? widget.child : Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      );

      // The coach mark rides the island's inner edge (toward the canvas
      // centre), so it never leaves the canvas area.
      final coach = p.coachSeen ? null : _coachMark();
      final towardCanvas = p.dock == IslandDock.top;
      // The island takes its natural height (the palette band grows it).
      // Full mode is width-bound by the canvas; compact is natural width.
      return UnconstrainedBox(
        constrainedAxis: p.compact ? null : Axis.horizontal,
        alignment: p.dock == IslandDock.top
            ? Alignment.topCenter
            : Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: p.compact && p.side == IslandSide.right
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (coach != null && towardCanvas) body,
            if (coach != null) coach,
            if (coach == null || !towardCanvas) body,
          ],
        ),
      );
    });
  }
}
