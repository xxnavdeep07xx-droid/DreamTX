import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local deck store — one JSON file per deck (the Rust core's serialized
/// model). Cloud sync (Deck DO) layers on top in M2; local files stay the
/// offline cache.
///
/// Two hardening layers, both device-tested needs:
///  1. **Bounded, nonblocking startup.** `open()` bounds the path_provider
///     platform-channel call (it can transiently stall right after an
///     in-place app update); `scan()` lists and reads the store with the
///     async `dart:io` API only — directory listing, `stat`, reads — so no
///     synchronous filesystem work ever blocks the UI isolate, and every
///     step is bounded by [scanBound]. A scan always ends in a real answer:
///     the deck list, a genuinely empty library, or a throw.
///  2. **Reliable saves.** Writes are serialized per deck, the payload is
///     snapshotted at enqueue time, and every write lands in a temp file in
///     the same directory before an atomic rename replaces the target — a
///     failed write can never leave a torn or truncated deck behind, and the
///     prior valid file survives untouched. A failure never blocks the next
///     save (recovery is automatic) but does surface to the awaiting caller.
///     Deletes are coordinated with in-flight writes via tombstones, so a
///     stale queued save can never resurrect a deleted deck.
class DeckStore {
  DeckStore._(this._dir);

  final Directory _dir;

  static DeckStore? _cached;

  // ---- bounds & test seams --------------------------------------------------

  /// Bound on the path_provider platform-channel call inside [open]. The
  /// underlying channel can stall; the UI must not wait forever.
  static Duration openBound = const Duration(seconds: 8);

  /// Bound on one full store scan. Async IO cannot block the UI isolate, but
  /// a wedged read must still end in a visible failure rather than a spinner.
  static Duration scanBound = const Duration(seconds: 5);

  /// Test seam only: artificial delay inside a write, so tests can interleave
  /// delete-with-save-in-flight deterministically. Production leaves zero.
  static Duration debugWriteDelay = Duration.zero;

  /// Test seam: clears the process-wide cache so a test can rerun the full
  /// open() path (and hit whatever platform-channel mock is installed).
  /// Production never calls this.
  static void debugResetForTest() => _cached = null;

  /// Opens the store: resolves the app-private documents directory over the
  /// platform channel (bounded) and makes sure the deck folder exists.
  /// Throwing is part of the contract — the dashboard turns it into the
  /// error-with-Retry card; nothing here can hang forever.
  static Future<DeckStore> open() async {
    final cached = _cached;
    if (cached != null) return cached;
    final dir =
        await getApplicationDocumentsDirectory().timeout(openBound);
    final decks = Directory('${dir.path}/decks');
    if (!await decks.exists()) {
      await decks.create(recursive: true);
    }
    final store = DeckStore._(decks);
    _cached = store;
    return store;
  }

  /// Reads every deck, newest first, entirely through nonblocking calls.
  ///
  /// Unreadable/corrupt files are skipped and *named* in [DeckScan.skipped]
  /// so logs can tell "3 files were unreadable" apart from "your library is
  /// empty" — the two must never be conflated.
  Future<DeckScan> scan() {
    // Test seam (see the doc on debugScanOverride): widget tests under the
    // fake-async zone answer from the override; production never sets it.
    final override = debugScanOverride;
    if (override != null) return override();
    return _scan().timeout(scanBound);
  }

  /// Test seam: when set, [scan] answers from this instead of the real
  /// filesystem. Widget tests run under Flutter's fake-async zone, where
  /// real async file IO never completes — so the dashboard's widget tests
  /// drive the UI states (loading / list / empty / error / retry) through
  /// this seam, while the store's actual IO behavior (scan, saves, deletes,
  /// atomic writes) is covered by the plain real-async store tests in the
  /// same suite. Production never sets it.
  static Future<DeckScan> Function()? debugScanOverride;

  Future<DeckScan> _scan() async {
    final entities = await _dir.list().toList();
    final files = entities
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    // Newest first; a file we cannot even stat falls to the very back.
    final stamps = <File, DateTime>{};
    for (final f in files) {
      try {
        stamps[f] = await f.lastModified();
      } catch (e) {
        print('[deck-store] could not stat ${f.path}: $e');
        stamps[f] = DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    files.sort((a, b) => stamps[b]!.compareTo(stamps[a]!));
    final decks = <Map<String, dynamic>>[];
    final skipped = <String>[];
    for (final f in files) {
      try {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map<String, dynamic>) {
          decks.add(decoded);
          continue;
        }
        skipped.add(_basename(f));
      } catch (e) {
        // One rotten file must never hide the rest of the library.
        print('[deck-store] skipped unreadable deck file ${f.path}: $e');
        skipped.add(_basename(f));
      }
    }
    return DeckScan(decks, skipped);
  }

  String _basename(File f) =>
      f.uri.pathSegments.isEmpty ? f.path : f.uri.pathSegments.last;

  // ---- serialized, atomic saves ----------------------------------------------

  /// Per-deck write chains: the value is the tail of that deck's save queue
  /// (always completes without throwing — see [save]).
  final Map<String, Future<void>> _chains = {};

  /// Decks deleted while writes were queued or in flight. A queued write
  /// checks this before touching the disk, so a stale save can never
  /// recreate a deleted deck.
  final Set<String> _tombstones = {};

  /// Last write failure per deck (diagnostics; cleared by the next success).
  final Map<String, Object> _saveErrors = {};

  /// Last save failure per deck id — an empty map means every write so far
  /// landed. Read by tests; the UI surfaces failures through the future
  /// [save] returns instead of polling this.
  Map<String, Object> get lastSaveErrors => Map.unmodifiable(_saveErrors);

  /// Queue one save for [deck]. The payload is serialized *now* — the
  /// caller's live map may mutate the moment this returns, and only the
  /// enqueue-time snapshot is allowed on disk. Writes for the same deck run
  /// strictly in order (latest snapshot wins); the returned future completes
  /// when this particular write lands, and rethrows if it failed.
  Future<void> save(Map<String, dynamic> deck) {
    final id = (deck['id'] ?? 'unknown').toString();
    final safe = Map<String, dynamic>.from(deck)..remove('__file');
    final payload = const JsonEncoder.withIndent('  ').convert(safe);
    final prev = _chains[id] ?? Future<void>.value();
    // A failed earlier write never blocks later ones: recovery is automatic.
    final task = prev
        .catchError((_) {})
        .then((_) => _writeDeck(id, payload));
    // The chain itself never throws — it swallows this write's failure so
    // the next save still runs — but `task` is handed to the caller.
    _chains[id] = task.catchError((_) {});
    return task;
  }

  Future<void> _writeDeck(String id, String payload) async {
    if (debugWriteDelay > Duration.zero) {
      await Future<void>.delayed(debugWriteDelay);
    }
    // Deleted while queued: this save is dead, never resurrect the deck.
    if (_tombstones.contains(id)) return;
    final file = File('${_dir.path}/$id.json');
    final tmp = File('${_dir.path}/.$id.json.tmp'); // same directory: the
    // rename below is then atomic within one filesystem.
    try {
      await tmp.writeAsString(payload, flush: true);
      // Deleted while the temp file was being written: drop it, write nothing.
      if (_tombstones.contains(id)) {
        try {
          await tmp.delete();
        } catch (_) {}
        return;
      }
      await tmp.rename(file.path); // atomic replace; prior file survives any failure below
      _saveErrors.remove(id);
    } catch (e, st) {
      _saveErrors[id] = e;
      print('[deck-store] save failed for deck "$id": $e\n$st');
      // Clean up the partial temp write; the prior valid file was never touched.
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow; // surfaced to the awaiting caller; the chain already swallowed it
    }
  }

  /// Wait until every queued write has landed (or failed and been logged).
  /// The dashboard calls this before scanning, so the list it shows after
  /// returning from the editor can never be out of date.
  Future<void> flushPendingWrites() async {
    final pending = [for (final f in _chains.values) f.catchError((_) {})];
    await Future.wait(pending);
  }

  /// Delete a deck, coordinated with any in-flight writes: the tombstone is
  /// set *before* waiting, so a queued save cannot slip past the delete and
  /// recreate the file. Throws if the file cannot be removed — callers
  /// surface that instead of a silent "deleted" that lied.
  Future<void> delete(String id) async {
    _tombstones.add(id);
    final tail = _chains[id];
    if (tail != null) {
      try {
        await tail;
      } catch (_) {}
    }
    final file = File('${_dir.path}/$id.json');
    try {
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      print('[deck-store] delete failed for deck "$id": $e\n$st');
      _tombstones.remove(id);
      rethrow;
    }
    _tombstones.remove(id);
    _saveErrors.remove(id);
    _chains.remove(id);
  }
}

/// One scan's full answer: the readable decks (newest first) plus the names
/// of files that were skipped as unreadable — diagnostics keep "your library
/// is empty" and "your library is unreadable" strictly apart.
class DeckScan {
  const DeckScan(this.decks, this.skipped);

  final List<Map<String, dynamic>> decks;
  final List<String> skipped;
}
