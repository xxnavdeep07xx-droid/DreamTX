import 'dart:math' as math;

/// Draw C: the floating island. Pure geometry, so the dock rules are
/// unit-tested. The island spans the canvas width and docks to the top or
/// the bottom edge of the canvas area.
enum IslandDock { top, bottom }

/// The island's resting top for [dock], before any drag offset: its top
/// edge at the area's top, or its bottom edge at the area's bottom.
double islandBaseTop(IslandDock dock, double areaH, double h) =>
    dock == IslandDock.top ? 0.0 : math.max(0.0, areaH - h);

/// Clamp a drag offset [dy] so the island stays inside the area.
/// Dragging from the top dock can only go down; from the bottom, only up.
double islandDyClamp(IslandDock dock, double dy, double areaH, double h) {
  final slack = math.max(0.0, areaH - h);
  return dock == IslandDock.top
      ? dy.clamp(0.0, slack).toDouble()
      : dy.clamp(-slack, 0.0).toDouble();
}

/// Where a released island docks: the nearer edge by its centre. The
/// island's centre is measured from its dragged position.
IslandDock islandSnap(IslandDock from, double dy, double areaH, double h) {
  final top = islandBaseTop(from, areaH, h) + dy;
  final centre = top + h / 2;
  return centre < areaH / 2 ? IslandDock.top : IslandDock.bottom;
}

/// The stored dock name. Anything unknown (or missing) is the default,
/// bottom, so a corrupt file never strands the island off-screen.
IslandDock islandDockFromName(String? name) =>
    name == 'top' ? IslandDock.top : IslandDock.bottom;

String islandDockName(IslandDock dock) => dock.name;

/// Which side a compact island hugs. Full-width islands ignore it.
enum IslandSide { left, right }

/// The island's whole placement: the vertical dock, the side (compact
/// only), and whether it shows the compact column or the full toolbar.
class IslandPlacement {
  const IslandPlacement({
    this.dock = IslandDock.bottom,
    this.side = IslandSide.right,
    this.compact = false,
    this.coachSeen = false,
  });

  final IslandDock dock;
  final IslandSide side;
  final bool compact;

  /// Draw C-3: the one-time coach mark has been dismissed (or the island
  /// was lifted once, which teaches the same thing).
  final bool coachSeen;

  IslandPlacement copyWith({
    IslandDock? dock,
    IslandSide? side,
    bool? compact,
    bool? coachSeen,
  }) =>
      IslandPlacement(
        dock: dock ?? this.dock,
        side: side ?? this.side,
        compact: compact ?? this.compact,
        coachSeen: coachSeen ?? this.coachSeen,
      );

  Map<String, Object> toJson() => {
        'dock': islandDockName(dock),
        'side': side.name,
        'compact': compact,
        'coachSeen': coachSeen,
      };

  /// Anything missing or unknown falls back to the default field by field.
  static IslandPlacement fromJson(Object? j) {
    if (j is! Map) return const IslandPlacement();
    return IslandPlacement(
      dock: islandDockFromName(j['dock'] as String?),
      side: j['side'] == 'left' ? IslandSide.left : IslandSide.right,
      compact: j['compact'] == true,
      coachSeen: j['coachSeen'] == true,
    );
  }
}

/// Clamp a horizontal drag [dx] so a compact island stays inside the area.
double islandDxClamp(IslandSide side, double dx, double areaW, double w) {
  final slack = math.max(0.0, areaW - w);
  return side == IslandSide.left
      ? dx.clamp(0.0, slack).toDouble()
      : dx.clamp(-slack, 0.0).toDouble();
}

/// Where a released compact island lands: the nearer corner by its centre.
({IslandDock dock, IslandSide side}) islandSnapCorner(
  IslandPlacement from,
  double dx,
  double dy,
  double areaW,
  double areaH,
  double w,
  double h,
) {
  final left = (from.side == IslandSide.left ? 0.0 : areaW - w) + dx;
  final top = islandBaseTop(from.dock, areaH, h) + dy;
  final cx = left + w / 2;
  final cy = top + h / 2;
  return (
    dock: cy < areaH / 2 ? IslandDock.top : IslandDock.bottom,
    side: cx < areaW / 2 ? IslandSide.left : IslandSide.right,
  );
}
