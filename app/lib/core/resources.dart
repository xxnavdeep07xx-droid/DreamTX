import 'dart:convert';
import 'dart:collection';
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
///
/// Files arrive one at a time or a whole folder at once: entries imported
/// through a folder carry its name in their `folder` field, so the library
/// can show them as shelves instead of one undifferentiated pile.
class ResourceStore {
  /// Hard cap on one folder import — a whole user folder in one gesture,
  /// bounded so a runaway pick (or a pathological tree) can never flood
  /// the app's documents directory or wedge the import session.
  static const int importCap = 400;

  ResourceStore._(this._root);

  final Directory _root;

  static ResourceStore? _cached;

  /// Strictly monotonic ids even inside a tight import loop — a folder
  /// import copies many files back-to-back and several can land in the
  /// same millisecond, where a plain timestamp would mint one shared id
  /// and let the copies overwrite each other. Kept time-ordered so the
  /// "newest last" listing order stays true; [add]'s 'added' field stays
  /// in plain milliseconds for the recency formatter.
  static int _lastStamp = 0;

  static String _freshId() {
    var now = DateTime.now().microsecondsSinceEpoch;
    if (now <= _lastStamp) now = _lastStamp + 1;
    _lastStamp = now;
    return now.toString();
  }

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
    debugAddOverride = null;
  }

  /// Test seam: replaces [add] wholesale (the widget-test runner cannot
  /// complete real file IO inside the fake-async zone). Production never
  /// sets it.
  static Future<Map<String, dynamic>> Function({
    required bool brand,
    String? deckId,
    required String sourcePath,
    String? folder,
  })? debugAddOverride;

  /// The cached instance without opening storage (null when not yet
  /// opened) — for sync path building where the root is already known.
  static ResourceStore? peek() => _cached;

  /// The scope directory's path, public for sync path building.
  String scopeDirPath({required bool brand, String? deckId}) =>
      _scopeDir(brand: brand, deckId: deckId).path;

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

  /// Resolve an asset id to its readable file path in the scope, or null
  /// when it is gone — the object layer's image rendering.
  Future<String?> resolve(
      {required bool brand, String? deckId, required String id}) async {
    final items = await list(brand: brand, deckId: deckId);
    for (final e in items) {
      if (e['id'].toString() == id) {
        final f = File(
            '${_scopeDir(brand: brand, deckId: deckId).path}/${e['file']}');
        return f.existsSync() ? f.path : null;
      }
    }
    return null;
  }

  /// Copy a picked file into the scope and record it in the index.
  /// [sourcePath] is the platform picker's local copy — its bytes are
  /// duplicated into the app's documents folder so the original can be
  /// reclaimed by the system at any time. [folder], when set, tags the
  /// entry with the folder it arrived through, so folder imports group.
  Future<Map<String, dynamic>> add(
      {required bool brand,
      String? deckId,
      required String sourcePath,
      String? folder}) async {
    final override = debugAddOverride;
    if (override != null) {
      return override(
          brand: brand, deckId: deckId, sourcePath: sourcePath,
          folder: folder);
    }
    final dir = _scopeDir(brand: brand, deckId: deckId);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final entry = await _copyInto(dir, sourcePath,
        folder: folder == null || folder.isEmpty ? null : folder);
    final items = [
      ...await list(brand: brand, deckId: deckId),
      entry,
    ];
    await _writeIndex(dir, items);
    return entry;
  }

  /// Import a whole folder in one gesture — every file under [dir],
  /// subfolders included, becomes an entry tagged with the folder's name,
  /// so a shelf of brand folders (logos, palettes, fonts, each folder one
  /// brand) lands in one pick instead of file after file. Dot-entries and
  /// the libraries' own index files are skipped; the walk stops at
  /// [importCap] files; one unreadable file never aborts the rest. The
  /// index is written once at the end, not once per file.
  Future<List<Map<String, dynamic>>> addFilesFromDirectory(
      {required bool brand, String? deckId, required Directory dir}) async {
    final folder = _baseName(dir.path);
    final files = <File>[];
    final queue = ListQueue<Directory>()..add(dir);
    while (queue.isNotEmpty && files.length < importCap) {
      final current = queue.removeFirst();
      for (final entry in current.listSync(followLinks: false)) {
        if (files.length >= importCap) break;
        final name = _baseName(entry.path);
        if (name.isEmpty || name.startsWith('.') || name == 'library.json') {
          continue;
        }
        if (entry is Directory) {
          queue.add(entry);
        } else if (entry is File) {
          files.add(entry);
        }
      }
    }
    final scope = _scopeDir(brand: brand, deckId: deckId);
    if (files.isNotEmpty && !scope.existsSync()) {
      scope.createSync(recursive: true);
    }
    final entries = <Map<String, dynamic>>[
      for (final f in files)
        await _copyInto(scope, f.path, folder: folder),
    ];
    if (entries.isNotEmpty) {
      await _writeIndex(
          scope, [...await list(brand: brand, deckId: deckId), ...entries]);
    }
    return entries;
  }

  /// The shared copy: duplicates one source file into the scope's directory
  /// and returns the index entry for it.
  Future<Map<String, dynamic>> _copyInto(Directory dir, String sourcePath,
      {String? folder}) async {
    final original = _baseName(sourcePath);
    final id = _freshId();
    final stored = original.isEmpty ? id : '$id-$_sanitize(original)';
    final target = await File(sourcePath).copy('${dir.path}/$stored');
    return <String, dynamic>{
      'id': id,
      'name': original.isEmpty ? 'file' : original,
      'file': stored,
      'size': await target.length(),
      'added': DateTime.now().millisecondsSinceEpoch.toString(),
      if (folder != null) 'folder': folder,
    };
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
