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
    // shrink them themselves. The scan seam is off unless a test sets it.
    DeckStore.openBound = const Duration(seconds: 8);
    DeckStore.scanBound = const Duration(seconds: 5);
    DeckStore.debugWriteDelay = Duration.zero;
    DeckStore.debugScanOverride = null;
  });

  tearDown(() {
    Bridge.testOverride = null;
    DeckStore.debugScanOverride = null;
    _clearStorageMock();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('startup: decks load into the dashboard; a corrupt file is skipped and named, never shown as an error', (tester) async {
    // Widget tests run under the fake-async zone, where real async file IO
    // never completes — the dashboard's state machine is driven through
    // the scan seam; the store's real IO (including corrupt-file skips) is
    // covered by the plain real-async scan test below.
    DeckStore.debugScanOverride = () async => DeckScan(
        [_deckFixture('d1', 'Test deck', 2), _deckFixture('d2', 'Second deck', 5)],
        ['d3.json']);
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
    DeckStore.debugScanOverride = () async => const DeckScan([], []);
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
    DeckStore.debugScanOverride =
        () async => DeckScan([_deckFixture('d1', 'Healed deck', 1)], []);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Healed deck'), findsOneWidget);
    expect(find.text('DECKS · 1 ON THIS DEVICE'), findsOneWidget);
  });

  test('scan: real files through real async IO — decks load, corrupt files are named', () async {
    // The store's actual IO path, in the real async zone (widget tests
    // drive the UI through the scan seam — see the note above).
    final decks = Directory('${tmp.path}/decks')..createSync(recursive: true);
    File('${decks.path}/d1.json')
        .writeAsStringSync(jsonEncode(_deckFixture('d1', 'Test deck', 2)));
    File('${decks.path}/d2.json')
        .writeAsStringSync(jsonEncode(_deckFixture('d2', 'Second deck', 5)));
    File('${decks.path}/d3.json').writeAsStringSync('{ not json');
    _mockStorage(dir: tmp.path);

    final store = await DeckStore.open();
    final scan = await store.scan();

    // Newest-first ordering is timing-dependent in a test; membership is not.
    expect(scan.decks.map((d) => d['title']),
        containsAll(['Test deck', 'Second deck']));
    expect(scan.skipped, ['d3.json']);
    // The corrupt file never masquerades as an empty library.
    expect(scan.decks, hasLength(2));
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

  testWidgets('filmstrip: the integrated edge handle folds the band without moving anything', (tester) async {
    Bridge.testOverride = _fakeEngine;
    _mockStorage(dir: tmp.path);
    // Semantics on for this test: the handle's a11y contract (a button node
    // carrying the action label) is asserted through the real semantics tree.
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    // A phone-class surface (390×844 logical) — the divider's proportions
    // are right-edge-relative, so these geometry assertions are the real
    // spec numbers, not approximations.
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    // Expanded: the 48dp divider region directly above the exact 104dp
    // 2.15 band, full editor width.
    final reveal = find.byKey(const ValueKey('filmstrip_reveal'));
    final row = find.byKey(const ValueKey('filmstrip_row'));
    final handle = find.byKey(const ValueKey('filmstrip_handle'));
    final divider = find.byKey(const ValueKey('filmstrip_divider'));
    expect(tester.getSize(row), const Size(390, 104));
    expect(tester.getSize(reveal).height, 104);
    expect(tester.getSize(divider), const Size(390, 48));

    // The handle: a reserved 48×48, flush to the right edge, and fully
    // inside the divider region — no invisible target over the canvas,
    // the thumbnail row, or the ribbon.
    expect(tester.getSize(handle), const Size(48, 48));
    expect(tester.getTopRight(handle).dx, 390);
    expect(tester.getTopRight(handle).dy,
        closeTo(tester.getTopLeft(divider).dy, 0.5));
    expect(tester.getBottomRight(handle).dy,
        lessThanOrEqualTo(tester.getTopLeft(row).dy + 0.5));

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

    // The v faces DOWN while the strip is open — it signs "close". The a11y
    // contract: the tooltip carries the action label, and the real semantics
    // tree exposes it as the button's label for assistive tech.
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip && w.message == 'Collapse slides'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Collapse slides'), findsOneWidget);

    // Select slide 2 and scroll the rail — both must survive the round trip.
    await tester.tap(find.text('2. Slide 2'));
    await tester.pumpAndSettle();
    expect(find.text('Slide 2 / 8'), findsOneWidget);
    final tile1AtRest = tester.getTopLeft(find.text('1. Slide 1')).dx;
    await tester.drag(find.text('2. Slide 2'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    final tile1Scrolled = tester.getTopLeft(find.text('1. Slide 1')).dx;
    // (the drag gesture feeds ~20dp to touch slop — the rail still moved
    // well past half the throw)
    expect(tile1Scrolled, lessThan(tile1AtRest - 50));

    // Fold: the band collapses to nothing under the rule — the canvas gets
    // the space, the v flips UP, the action label flips to "Expand slides",
    // and the hidden band leaves the a11y tree.
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, 0);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.bySemanticsLabel('Expand slides'), findsOneWidget);
    final exclude = find.byKey(const ValueKey('filmstrip_strip_semantics'));
    expect(exclude, findsOneWidget);
    expect(tester.widget<ExcludeSemantics>(exclude).excluding, isTrue);

    // Unfold: back to the exact same geometry — same band, same disc spot,
    // same scroll offset, same selection.
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, 104);
    expect(discPos().left, 14);
    expect(discPos().top, 30);
    expect(tester.getTopLeft(find.text('1. Slide 1')).dx,
        closeTo(tile1Scrolled, 0.5));
    expect(find.text('Slide 2 / 8'), findsOneWidget);

    // Landscape: the right-edge geometry stays flush and usable.
    tester.view.physicalSize = const Size(1688, 780);
    await tester.pumpAndSettle();
    expect(tester.getSize(handle), const Size(48, 48));
    expect(tester.getTopRight(handle).dx, 844);
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, 0);

    // The + still works end to end (fake engine adds a blank slide). The new
    // tile lives at the rail's far end — past the viewport's lazy-build cache
    // — so drag the rail (on the row itself: its center is always on-screen
    // however far the rail has scrolled) until the tile exists.
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    for (var i = 0; i < 12 && find.text('9. Blank').evaluate().isEmpty; i++) {
      await tester.drag(
          find.byKey(const ValueKey('filmstrip_row')), const Offset(-150, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text('9. Blank'), findsOneWidget);
  });

  testWidgets('filmstrip: reduced motion collapses instantly', (tester) async {
    Bridge.testOverride = _fakeEngine;
    _mockStorage(dir: tmp.path);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 2)),
    ));
    await tester.pumpAndSettle();

    final reveal = find.byKey(const ValueKey('filmstrip_reveal'));
    expect(tester.getSize(reveal).height, 104);

    // With animations disabled the 200ms height transition must not run:
    // well before its natural end the band is already fully gone. (The
    // tap goes by key: the tooltip excludes itself from semantics, and on
    // the pinned toolchain find.byTooltip matches the semantics tooltip.)
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(reveal).height, 0);
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
