import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'island_math.dart';

/// Draw C: the island's placement is remembered per device in one small
/// JSON file. Every failure degrades to the default, never throws.
Future<File> _islandFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/island.json');
}

Future<IslandPlacement> loadIslandPlacement() async {
  try {
    final f = await _islandFile();
    if (!await f.exists()) return const IslandPlacement();
    return IslandPlacement.fromJson(jsonDecode(await f.readAsString()));
  } catch (_) {
    return const IslandPlacement();
  }
}

Future<void> saveIslandPlacement(IslandPlacement placement) async {
  try {
    final f = await _islandFile();
    await f.writeAsString(jsonEncode(placement.toJson()));
  } catch (_) {
    // Best effort: the island falls back to its default next launch.
  }
}
