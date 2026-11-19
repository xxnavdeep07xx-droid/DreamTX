import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/decks_screen.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/screens/pair_sheet.dart';

/// Host smoke tests — the affordable self-test: no device, no emulator, the
/// real app code under the real framework. The seams are [Bridge.testOverride]
/// (an in-memory deck engine replaces the Rust core, which is not loadable in
/// a host test runner), the path_provider platform-channel mock (the storage
/// bridge runs against a temp dir, throws on demand, or stalls on demand),
/// and the DeckStore bounds/delay statics (so timeout tests run in virtual
/// milliseconds instead of production seconds).
///
/// Coverage map, per the startup spec: successful startup, empty startup,
/// thrown storage, stalled storage, Retry recovery, rapid saves with the
/// latest snapshot winning, a failed write preserving the previous file and
/// recovering, delete coordinating with pending writes, and the filmstrip
/// geometry. Pairing-sheet hardening (network bounds) is exercised to the
/// extent a host test can without a server.

// ---- fixtures -----------------------------------------------------------------

Map<String, dynamic> _deckFixture(String id, String title, int n) => {
      'id': id,
      'title': title,
      'dna': {'family': 'swiss_editorial'},
      'slides': List.generate(
          n,
          (i) => <String, dynamic>{
                'id': 's${i + 1}',
                'archetype': 'title',
                'content': {'title': 'Slide ${i + 1}'},
                'objects': <Map<String, dynamic>>[],
              }),
    };

/// In-memory deck engine for the editor screen: implements exactly the ops
/// the build path touches (meta, get_layout) plus add_slide for the + smoke.
Map<String, dynamic> _fakeEngine(Map<String, dynamic> req) {
  switch (req['op']) {
    case 'meta':
      return {
        'ok': true,
        'object_presets': <Map<String, dynamic>>[],
        'archetypes': <String>[]
      };
    case 'get_layout':
      return {
        'ok': true,
        'layout': <String, dynamic>{
          'elements': <Map<String, dynamic>>[],
        },
      };
    case 'add_slide':
      final deck = Map<String, dynamic>.from(req['deck'] as Map);
      final slides = <Map<String, dynamic>>[
        for (final m in (deck['slides'] as List? ?? []))
          Map<String, dynamic>.from(m as Map),
      ];
      slides.add(<String, dynamic>{
        'id': 's${slides.length + 1}',
        'archetype': 'blank',
        'objects': <Map<String, dynamic>>[],
      });
      deck['slides'] = slides;
      return {'ok': true, 'deck': deck};
    default:
      return {
        'ok': false,
        'error': 'unsupported in the fake engine: ${req['op']}'
      };
  }
}

// ---- platform-channel mock ----------------------------------------------------

void _mockStorage({String? dir, Object? throwFor, bool stall = false}) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (stall) {
      // A wedged platform channel: never completes, never throws. Only the
      // store's bounds can end this — exactly the device stall the spec
      // wants a visible error for, not an eternal spinner.
      await Completer<Object?>().future;
    }
    if (throwFor != null) throw throwFor;
    if (call.method == 'getApplicationDocumentsDirectory') return dir;
    throw PlatformException(
        code: 'unimplemented', message: 'unexpected method: ${call.method}');
  });
}

void _clearStorageMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
}

void main() {
  late Directory tmp;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_smoke');
    DeckStore.debugResetForTest();
    // Production bounds restored for every test; timeout-specific tests
    // shrink them themselves.
    DeckStore.openBound = const Duration(seconds: 8);
    DeckStore.scanBound = const Duration(seconds: 5);
    DeckStore.debugWriteDelay = Duration.zero;
  });

  tearDown(() {
    Bridge.testOverride = null;
    _clearStorageMock();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('startup: decks load from the storage bridge; a corrupt file is skipped and named, not shown as an error', (tester) async {
    final decks = Directory('${tmp.path}/decks')..createSync(recursive: true);
    File('${decks.path}/d1.json')
        .writeAsStringSync(jsonEncode(_deckFixture('d1', 'Test deck', 2)));
    File('${decks.path}/d2.json')
        .writeAsStringSync(jsonEncode(_deckFixture('d2', 'Second deck', 5)));
    File('${decks.path}/d3.json').writeAsStringSync('{ not json');
    _mockStorage(dir: tmp.path);

    await tester.pumpWidget(const MaterialApp(home: DecksScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Test deck'), findsOneWidget);
    expect(find.text('Second deck'), findsOneWidget);
    expect(find.text('2 slides · swiss editorial'), findsOneWidget);
    expect(find.text('5 slides · swiss editorial'), findsOneWidget);
    expect(find.text('DECKS · 2 ON THIS DEVICE'), findsOneWidget);
    // The rotten file was skipped, not fatal — and never misread as empty.
    expect(find.text('Could not read your decks'), findsNothing);
    expect(find.text('DECKS · NONE YET'), findsNothing);
  });

  testWidgets('startup: a genuinely empty library shows the empty state, and "None yet" only after a successful scan', (tester) async {
    _mockStorage(dir: tmp.path);

    await tester.pumpWidget(const MaterialApp(home: DecksScreen()));
    // While the first scan is still in flight the masthead must not claim
    // the library is empty.
    expect(find.text('DECKS · LOADING'), findsOneWidget);
    expect(find.text('DECKS · NONE YET'), findsNothing);

    await tester.pumpAndSettle();

    expect(find.text('No decks yet'), findsOneWidget);
    expect(find.text('DECKS · NONE YET'), findsOneWidget);
    expect(find.text('Could not read your decks'), findsNothing);
  });

  testWidgets('startup: thrown storage lands on the error card with the actual error; no exit, no restart, and Retry recovers', (tester) async {
    _mockStorage(
        throwFor: PlatformException(
            code: 'error',
            message: 'storage bridge refused the call'));

    await tester.pumpWidget(const MaterialApp(home: DecksScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Could not read your decks'), findsOneWidget);
    expect(find.textContaining('storage bridge refused the call'),
        findsOneWidget);
    expect(find.text('DECKS · STORAGE OFFLINE'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // The old self-heal machinery is gone entirely — no exit path exists.
    expect(find.text('Finishing the update'), findsNothing);
    expect(find.text('Restart app'), findsNothing);

    // The user's Retry is the recovery path: storage heals, list appears.
    _mockStorage(dir: tmp.path);
    final decks = Directory('${tmp.path}/decks')..createSync(recursive: true);
    File('${decks.path}/d1.json')
        .writeAsStringSync(jsonEncode(_deckFixture('d1', 'Healed deck', 1)));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Healed deck'), findsOneWidget);
    expect(find.text('DECKS · 1 ON THIS DEVICE'), findsOneWidget);
  });

  testWidgets('startup: a stalled platform channel is bounded — the spinner cannot outlive it', (tester) async {
    // Shrink the bounds so the test runs in virtual milliseconds.
    DeckStore.openBound = const Duration(milliseconds: 150);
    _mockStorage(stall: true);

    await tester.pumpWidget(const MaterialApp(home: DecksScreen()));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // The wedge never answers; the bounded attempts still end in a decision.
    expect(find.text('Could not read your decks'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('saves: rapid enqueues serialize per deck — latest snapshot wins, no temp residue', () async {
    _mockStorage(dir: tmp.path);
    final store = await DeckStore.open();
    final deck = _deckFixture('rapid', 'Rapid deck', 1);

    // 25 queued saves in a tight burst; each payload is snapshotted at
    // enqueue, writes run strictly in order, and only the last may be the
    // on-disk answer.
    for (var i = 1; i <= 25; i++) {
      deck['title'] = 'Rev $i';
      unawaited(store.save(deck));
    }
    await store.flushPendingWrites();

    final file = File('${tmp.path}/decks/rapid.json');
    expect(await file.exists(), isTrue);
    final onDisk = jsonDecode(await file.readAsString()) as Map;
    expect(onDisk['title'], 'Rev 25');
    // No temp files left behind, exactly one deck file.
    final names = Directory('${tmp.path}/decks')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList()
      ..sort();
    expect(names, ['rapid.json']);
    expect(store.lastSaveErrors, isEmpty);
  });

  test('saves: a failed write keeps the previous valid file, cleans its temp, and later saves recover', () async {
    _mockStorage(dir: tmp.path);
    final store = await DeckStore.open();
    final deck = _deckFixture('guard', 'Good save', 1);
    await store.save(deck);

    final file = File('${tmp.path}/decks/guard.json');
    final before = await file.readAsString();

    // Make the deck directory unwritable: the temp write fails, the rename
    // never happens, the prior file must survive byte-for-byte.
    final chmodOk = Process.runSync('chmod', ['555', '${tmp.path}/decks']).exitCode == 0;
    if (chmodOk) {
      deck['title'] = 'Doomed save';
      await expectLater(store.save(deck), throwsA(anything));
      expect(await file.readAsString(), before);
      expect(store.lastSaveErrors.keys, contains('guard'));
      // No temp residue from the failed write.
      expect(Directory('${tmp.path}/decks').listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')), isEmpty);
      Process.runSync('chmod', ['755', '${tmp.path}/decks']);

      // Recovery: the very next save succeeds and clears the error state.
      deck['title'] = 'Recovered';
      await store.save(deck);
      await store.flushPendingWrites();
      final after = jsonDecode(await file.readAsString()) as Map;
      expect(after['title'], 'Recovered');
      expect(store.lastSaveErrors, isEmpty);
    } else {
      // Platforms without a POSIX chmod (should not happen on CI) skip the
      // unwritable-disk simulation but still assert the happy recovery.
      deck['title'] = 'Plain save';
      await store.save(deck);
      expect(store.lastSaveErrors, isEmpty);
    }
  });

  test('saves: a delete while a write is queued never resurrects the deck', () async {
    _mockStorage(dir: tmp.path);
    final store = await DeckStore.open();
    // Deterministic interleave: the write is delayed long enough for the
    // delete to tombstone the deck first.
    DeckStore.debugWriteDelay = const Duration(milliseconds: 300);

    final deck = _deckFixture('gone', 'Doomed deck', 1);
    unawaited(store.save(deck));
    await store.delete('gone');
    await store.flushPendingWrites();

    expect(File('${tmp.path}/decks/gone.json').existsSync(), isFalse);
    expect(Directory('${tmp.path}/decks').listSync(), isEmpty);
  });

  testWidgets('filmstrip: the v-chevron folds the strip and nothing moves when it unfolds', (tester) async {
    Bridge.testOverride = _fakeEngine;
    _mockStorage(dir: tmp.path);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 3))));
    await tester.pumpAndSettle();

    final strip = find.byType(AnimatedSize);
    expect(strip, findsOneWidget);
    expect(tester.getSize(strip).height, 104); // the 2.15 band, exactly

    // The floating + at its home spot — nothing resized, nothing realigned.
    final disc = find.byIcon(Icons.add);
    expect(disc, findsOneWidget);
    Positioned discPos() => tester.widget<Positioned>(find
        .ancestor(of: find.byIcon(Icons.add), matching: find.byType(Positioned))
        .first);
    expect(discPos().left, 14);
    expect(discPos().top, 30);
    expect(find.text('1. Slide 1'), findsOneWidget);
    expect(find.text('2. Slide 2'), findsOneWidget);
    expect(find.text('3. Slide 3'), findsOneWidget);

    // The v faces DOWN while the strip is open — it signs "close".
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    // Fold it: the whole band becomes a slim handle, its v flips UP, and the
    // canvas absorbs the freed space.
    await tester.tap(find.byTooltip('Collapse slide strip'));
    await tester.pumpAndSettle();
    expect(tester.getSize(strip).height, 40);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.byIcon(Icons.add),
        findsNothing); // the strip (and its disc) is gone

    // Unfold: back to the exact same geometry — same band, same disc spot.
    await tester.tap(find.byTooltip('Show slide strip'));
    await tester.pumpAndSettle();
    expect(tester.getSize(strip).height, 104);
    expect(discPos().left, 14);
    expect(discPos().top, 30);

    // The + still works end to end (fake engine adds a blank slide).
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('4. Blank'), findsOneWidget);
  });

  testWidgets('pair sheet: renders offline, and demanding a pairing without a server URL surfaces the error instead of hanging', (tester) async {
    _mockStorage(dir: tmp.path);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PairSheet(deck: _deckFixture('p1', 'Pair deck', 1)))));
    await tester.pumpAndSettle();

    expect(find.text('Pair with your AI'), findsOneWidget);
    expect(find.text('Generate pairing code'), findsOneWidget);

    // No server URL set: the failure is immediate and visible — no network
    // call may even start (pairing is fully independent of startup state).
    await tester.tap(find.text('Generate pairing code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Set your DreamTX server URL'), findsOneWidget);
    expect(find.textContaining('pairing…'), findsNothing);
  });
}
