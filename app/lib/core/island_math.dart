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
