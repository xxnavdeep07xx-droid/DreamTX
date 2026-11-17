import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local deck store — one JSON file per deck (the Rust core's serialized
/// model). Cloud sync (Deck DO) layers on top in M2; local files stay the
/// offline cache.
class DeckStore {
  DeckStore._(this._dir);

  final Directory _dir;

  static DeckStore? _cached;

  static Future<DeckStore> open() async {
    if (_cached != null) return _cached!;
    final dir = await getApplicationDocumentsDirectory();
    final decks = Directory('${dir.path}/decks');
    if (!decks.existsSync()) decks.createSync(recursive: true);
    _cached = DeckStore._(decks);
    return _cached!;
  }

  Future<List<Map<String, dynamic>>> list() async {
    final files = _dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files
        .map((f) {
      try {
        final decoded = jsonDecode(f.readAsStringSync());
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
      return null;
    })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> save(Map<String, dynamic> deck) async {
    final id = (deck['id'] ?? 'unknown').toString();
    final safe = Map<String, dynamic>.from(deck)..remove('__file');
    final file = File('${_dir.path}/$id.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(safe));
  }

  Future<void> delete(String id) async {
    final file = File('${_dir.path}/$id.json');
    if (file.existsSync()) await file.delete();
  }
}
