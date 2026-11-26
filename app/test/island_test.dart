import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/island_math.dart';

/// Draw C: the floating island's dock rules (pure geometry).
void main() {
  const areaH = 600.0;
  const h = 48.0;

  test('resting tops: top docks at 0, bottom docks at area - height', () {
    expect(islandBaseTop(IslandDock.top, areaH, h), 0);
    expect(islandBaseTop(IslandDock.bottom, areaH, h), 552);
  });

  test('a drag is clamped to the area, one way per dock', () {
    expect(islandDyClamp(IslandDock.top, -50, areaH, h), 0);
    expect(islandDyClamp(IslandDock.top, 300, areaH, h), 300);
    expect(islandDyClamp(IslandDock.top, 900, areaH, h), 552);
    expect(islandDyClamp(IslandDock.bottom, 50, areaH, h), 0);
    expect(islandDyClamp(IslandDock.bottom, -900, areaH, h), -552);
  });

  test('release snaps to the nearer edge by centre', () {
    // Bottom dock, dragged up past the midline: centre at 296 < 300 -> top.
    expect(islandSnap(IslandDock.bottom, -280, areaH, h), IslandDock.top);
    // Bottom dock, barely moved: centre stays low -> bottom.
    expect(islandSnap(IslandDock.bottom, -100, areaH, h), IslandDock.bottom);
    // Top dock, dragged down past the midline -> bottom.
    expect(islandSnap(IslandDock.top, 300, areaH, h), IslandDock.bottom);
    // Top dock, not moved -> top.
    expect(islandSnap(IslandDock.top, 0, areaH, h), IslandDock.top);
  });

  test('the stored dock round-trips; anything unknown is bottom', () {
    expect(islandDockFromName(islandDockName(IslandDock.top)), IslandDock.top);
    expect(islandDockFromName(islandDockName(IslandDock.bottom)),
        IslandDock.bottom);
    expect(islandDockFromName(null), IslandDock.bottom);
    expect(islandDockFromName('left'), IslandDock.bottom);
  });
}
