import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'island_math.dart';

/// Draw C: the island's dock is remembered per device in one small JSON
/// file. Every failure degrades to the default (bottom), never throws.
Future<File> _islandFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/island.json');
}

Future<IslandDock> loadIslandDock() async {
  try {
    final f = await _islandFile();
    if (!await f.exists()) return IslandDock.bottom;
    final j = jsonDecode(await f.readAsString());
    return islandDockFromName(j is Map ? j['dock'] as String? : null);
  } catch (_) {
    return IslandDock.bottom;
  }
}

Future<void> saveIslandDock(IslandDock dock) async {
  try {
    final f = await _islandFile();
    await f.writeAsString(jsonEncode({'dock': islandDockName(dock)}));
  } catch (_) {
    // Best effort: the island simply docks to its default next launch.
  }
}
