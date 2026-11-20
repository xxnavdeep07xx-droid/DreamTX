import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// On-device resource libraries behind the Files drawer. Two scopes:
///
/// * **brand** — one library shared by every deck on this device;
/// * **deck** — one library per deck, invisible to every other deck.
///
/// Plain local files under the app's own documents directory: nothing is
/// synced, nothing is uploaded, nothing leaves the device, and everything
/// survives a restart. The library index (`library.json`) lives beside the
/// asset files in each scope's directory.
class ResourceStore {
  ResourceStore._(this._root);

  final Directory _root;

  static ResourceStore? _cached;

  static Future<ResourceStore> open() async {
    if (_cached != null) return _cached!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/resources');
    if (!root.existsSync()) root.createSync(recursive: true);
    _cached = ResourceStore._(root);
    return _cached!;
  }

  /// Test seam — the smoke tests point the platform channel at a temp dir.
  static void debugResetForTest() {
    _cached = null;
  }

  Directory _scopeDir({required bool brand, String? deckId}) => Directory(
      '${_root.path}/${brand ? 'brand' : 'decks/${_sanitize(deckId ?? '')}'}');

  /// The scope's assets, newest last. Deck scope never sees another deck's
  /// files (they live in different directories); brand scope is the same
  /// directory for every deck.
  Future<List<Map<String, dynamic>>> list(
      {required bool brand, String? deckId}) async {
    final dir = _scopeDir(brand: brand, deckId: deckId);
    final index = File('${dir.path}/library.json');
    if (!index.existsSync()) return const [];
    try {
      final decoded = jsonDecode(index.readAsStringSync());
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (_) {} // a half-written index reads as empty; files stay on disk
    return const [];
  }

  /// Copy a picked file into the scope and record it in the index.
  /// [sourcePath] is the platform picker's local copy — its bytes are
  /// duplicated into the app's documents folder so the original can be
  /// reclaimed by the system at any time.
  Future<Map<String, dynamic>> add(
      {required bool brand,
      String? deckId,
      required String sourcePath}) async {
    final dir = _scopeDir(brand: brand, deckId: deckId);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final original = _baseName(sourcePath);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final stored = original.isEmpty ? id : '$id-$_sanitize(original)';
    final target = await File(sourcePath).copy('${dir.path}/$stored');
    final entry = <String, dynamic>{
      'id': id,
      'name': original.isEmpty ? 'file' : original,
      'file': stored,
      'size': await target.length(),
      'added': id,
    };
    final items = [
      ...await list(brand: brand, deckId: deckId),
      entry,
    ];
    await _writeIndex(dir, items);
    return entry;
  }

  /// Remove one asset from the scope: the file and its index entry.
  Future<void> remove(
      {required bool brand, String? deckId, required String id}) async {
    final dir = _scopeDir(brand: brand, deckId: deckId);
    final items = await list(brand: brand, deckId: deckId);
    final victim =
        items.where((e) => e['id'] == id).toList(); // ids are unique per scope
    for (final e in victim) {
      final f = File('${dir.path}/${e['file']}');
      if (f.existsSync()) await f.delete();
    }
    await _writeIndex(dir, items.where((e) => e['id'] != id).toList());
  }

  Future<void> _writeIndex(
      Directory dir, List<Map<String, dynamic>> items) async {
    final index = File('${dir.path}/library.json');
    await index.writeAsString(const JsonEncoder.withIndent('  ').convert(items),
        flush: true);
  }

  static String _sanitize(String raw) => raw
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
      .replaceAll('..', '_');

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final base = normalized.substring(normalized.lastIndexOf('/') + 1);
    return base.length > 96 ? base.substring(base.length - 96) : base;
  }
}
