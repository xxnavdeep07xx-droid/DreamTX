import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/island_math.dart';

/// Draw C: the floating island's rules (pure geometry).
void main() {
  // Full-width island (C-1): top/bottom dock.
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

  // Compact island (C-2): a narrow column that docks to any corner.
  const cW = 400.0;
  const cH = 600.0;
  const cw = 60.0;
  const ch = 200.0;

  test('a compact drag is clamped horizontally, one way per side', () {
    expect(islandDxClamp(IslandSide.left, -20, cW, cw), 0);
    expect(islandDxClamp(IslandSide.left, 500, cW, cw), 340);
    expect(islandDxClamp(IslandSide.right, 20, cW, cw), 0);
    expect(islandDxClamp(IslandSide.right, -500, cW, cw), -340);
  });

  test('a released compact island docks to the nearest corner', () {
    const right =
        IslandPlacement(side: IslandSide.right, dock: IslandDock.bottom);
    // Rests bottom-right; dragged up-left past both midlines -> top-left.
    final tl = islandSnapCorner(right, -300, -400, cW, cH, cw, ch);
    expect(tl.dock, IslandDock.top);
    expect(tl.side, IslandSide.left);
    // Rests bottom-right and barely moved -> stays bottom-right.
    final br = islandSnapCorner(right, -10, -10, cW, cH, cw, ch);
    expect(br.dock, IslandDock.bottom);
    expect(br.side, IslandSide.right);
  });

  test('placement round-trips and tolerates a bad file field by field', () {
    const p = IslandPlacement(
        dock: IslandDock.top, side: IslandSide.left, compact: true);
    final back = IslandPlacement.fromJson(p.toJson());
    expect(back.dock, IslandDock.top);
    expect(back.side, IslandSide.left);
    expect(back.compact, isTrue);

    final junk = IslandPlacement.fromJson(
        {'dock': 'middle', 'side': 'up', 'compact': 'yes'});
    expect(junk.dock, IslandDock.bottom);
    expect(junk.side, IslandSide.right);
    expect(junk.compact, isFalse);

    expect(IslandPlacement.fromJson(null).dock, IslandDock.bottom);

    // The coach mark is off until dismissed, and survives a round trip.
    expect(IslandPlacement.fromJson(null).coachSeen, isFalse);
    const seen = IslandPlacement(coachSeen: true);
    expect(IslandPlacement.fromJson(seen.toJson()).coachSeen, isTrue);
  });
}
