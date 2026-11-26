import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/island_math.dart';
import '../theme.dart';

/// Draw C: a floating island — the contextual toolbar lifted off the
/// band. It docks to the canvas's top or bottom edge. A 500 ms hold on
/// the grip lifts it (haptic + shadow); it follows the finger; release
/// magnets it to the nearer edge and reports the dock via [onDock].
///
/// Only the grip starts a drag: the toolbar's own buttons keep their
/// taps and long-presses (the pen presets remove on long-press).
class FloatingIsland extends StatefulWidget {
  const FloatingIsland({
    super.key,
    required this.dock,
    required this.onDock,
    required this.child,
  });

  final IslandDock dock;
  final ValueChanged<IslandDock> onDock;
  final Widget child;

  @override
  State<FloatingIsland> createState() => _FloatingIslandState();
}

class _FloatingIslandState extends State<FloatingIsland> {
  final _bodyKey = GlobalKey();
  bool _lifted = false;
  double _dy = 0;
  double _areaH = 0;

  double get _h => _bodyKey.currentContext?.size?.height ?? 48;

  void _lift() {
    HapticFeedback.mediumImpact();
    setState(() {
      _lifted = true;
      _dy = 0;
    });
  }

  void _follow(LongPressMoveUpdateDetails d) {
    setState(() {
      _dy = islandDyClamp(widget.dock, d.offsetFromOrigin.dy, _areaH, _h);
    });
  }

  void _release() {
    final next = islandSnap(widget.dock, _dy, _areaH, _h);
    setState(() {
      _lifted = false;
      _dy = 0;
    });
    widget.onDock(next);
  }

  @override
  Widget build(BuildContext context) {
    final grip = GestureDetector(
      key: const ValueKey('island_grip'),
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _lift(),
      onLongPressMoveUpdate: _follow,
      onLongPressEnd: (_) => _release(),
      onLongPressCancel: () => setState(() {
        _lifted = false;
        _dy = 0;
      }),
      child: SizedBox(
        width: 22,
        child: Icon(Icons.drag_indicator,
            size: 18,
            color: _lifted ? const Color(0xFFFFFFFF) : const Color(0xFF6B6B74)),
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      // The area's height is the Stack's; the island's own height is
      // measured on its body after layout (see [_h]).
      _areaH = constraints.maxHeight;
      return Transform.translate(
        offset: Offset(0, _dy),
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
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  grip,
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
