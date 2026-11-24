import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/aspects.dart';
import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/decks_screen.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/screens/pair_sheet.dart';
import 'package:dreamtx/theme.dart';

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

Map<String, dynamic> deckFixtureForProbe(int n) => _deckFixture('d1', 'Test deck', n);

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
/// the build path touches (meta, get_layout with the deck's frame dims) plus
/// add_slide for the + smoke and set_aspect for the Files drawer's ratio
/// tool.
Map<String, dynamic> testFakeEngine(Map<String, dynamic> req) {
  switch (req['op']) {
    case 'meta':
      return {
        'ok': true,
        'object_presets': <Map<String, dynamic>>[],
        'archetypes': <String>[],
        'aspects': <String>['16:9', '16:10', '4:3', '1:1'],
      };
    case 'resolve_dna':
      // The deck's palette (deck colors) + the text boxes' slide-theme base.
      return {
        'ok': true,
        'dna': {
          'palette': {
            'bg': 'FFFFFF',
            'surface': 'F7F6F3',
            'fg': '17181A',
            'muted': '6B6E76',
            'accent': 'C25E00',
          },
          'body_font': 'sans',
          'display_font': 'sans',
        },
      };
    case 'add_object':
      return _fakeObjectOp(req, adding: true);
    case 'update_object':
      return _fakeObjectOp(req, adding: false);
    case 'delete_object':
      final deck = Map<String, dynamic>.from(req['deck'] as Map);
      _fakeForEachSlide(deck, req['slide_id'].toString(), (slide) {
        slide['objects'] = [
          for (final o in (slide['objects'] as List? ?? const []))
            if ((o as Map)['id'] != req['object_id']) Map<String, dynamic>.from(o),
        ];
      });
      return {'ok': true, 'deck': _fakeBump(deck)};
    case 'move_object_z':
      final deck = Map<String, dynamic>.from(req['deck'] as Map);
      var ok = false;
      _fakeForEachSlide(deck, req['slide_id'].toString(), (slide) {
        final objs = [
          for (final o in (slide['objects'] as List? ?? const []))
            Map<String, dynamic>.from(o as Map)
        ];
        final idx = objs.indexWhere((o) => o['id'] == req['object_id']);
        if (idx >= 0) {
          final moved = objs.removeAt(idx);
          objs.insert(((req['to_index'] as num).toInt()).clamp(0, objs.length), moved);
          slide['objects'] = objs;
          ok = true;
        }
      });
      return ok
          ? {'ok': true, 'deck': _fakeBump(deck)}
          : {'ok': false, 'error': 'object not found'};
    case 'get_layout':
      final deck = req['deck'] as Map?;
      final (w, h) = deckDimsOf(deck?['aspect'] as String?);
      return {
        'ok': true,
        'layout': <String, dynamic>{
          'elements': <Map<String, dynamic>>[],
          'w': w,
          'h': h,
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
    case 'delete_slide':
      // One slide out, by id — the filmstrip's Delete action.
      final deck = Map<String, dynamic>.from(req['deck'] as Map);
      deck['slides'] = [
        for (final m in (deck['slides'] as List? ?? []))
          if ((m as Map)['id'] != req['slide_id'])
            Map<String, dynamic>.from(m),
      ];
      return {'ok': true, 'deck': _fakeBump(deck)};
    case 'set_aspect':
      final deck = Map<String, dynamic>.from(req['deck'] as Map);
      deck['aspect'] = req['aspect'];
      return {'ok': true, 'deck': deck};
    default:
      return {
        'ok': false,
        'error': 'unsupported in the fake engine: ${req['op']}'
      };
  }
}

// ---- fake-engine object helpers (Dart maps keep unknown fields, so the
// ---- `content` payloads round-trip exactly like the Rust core does) ------

Map<String, dynamic> _fakeBump(Map<String, dynamic> deck) {
  deck['version'] = ((deck['version'] as num?)?.toInt() ?? 0) + 1;
  return deck;
}

/// One slide, copied one level deep (fresh objects list + fresh object
/// maps) — the unit of the fake engine's copy semantics.
Map<String, dynamic> _fakeSlideCopy(Map s) =>
    Map<String, dynamic>.from(s)..['objects'] = [
      for (final o in (s['objects'] as List? ?? const []))
        if (o is Map) Map<String, dynamic>.from(o),
    ];

void _fakeForEachSlide(Map<String, dynamic> deck, String slideId,
    void Function(Map<String, dynamic> slide) fn) {
  // The REAL engine round-trips every command through JSON — the deck it
  // returns never aliases the caller's maps. The object ops below MUTATE
  // the slide they are handed, so they get a COPY here, re-linked into a
  // fresh slides list; the caller's own slide instances (and any deck
  // snapshot sharing them — the editor's undo stack) are never touched.
  final out = <Map<String, dynamic>>[];
  for (final s in (deck['slides'] as List? ?? const [])) {
    if (s is! Map) continue;
    final copy = _fakeSlideCopy(s);
    if (s['id'] == slideId) fn(copy);
    out.add(copy);
  }
  deck['slides'] = out;
}

Map<String, dynamic> _fakeObjectOp(Map<String, dynamic> req,
    {required bool adding}) {
  final deck = Map<String, dynamic>.from(req['deck'] as Map);
  final slideId = req['slide_id'].toString();
  final shape = Map<String, dynamic>.from(req['shape'] as Map);
  final objectId = (adding ? shape['id'] : req['object_id']).toString();
  var ok = false;
  _fakeForEachSlide(deck, slideId, (slide) {
    final objs = [
      for (final o in (slide['objects'] as List? ?? const []))
        Map<String, dynamic>.from(o as Map)
    ];
    if (adding) {
      objs.add(shape);
      ok = true;
    } else {
      final idx = objs.indexWhere((o) => o['id'] == objectId);
      if (idx >= 0) {
        shape['id'] = objectId;
        objs[idx] = shape;
        ok = true;
      }
    }
    slide['objects'] = objs;
  });
  return ok
      ? {'ok': true, 'deck': _fakeBump(deck)}
      : {'ok': false, 'error': 'object not found'};
}

// ---- platform-channel mock ----------------------------------------------------

/// Public wrappers for sibling test files (the insert suite reuses the
/// same platform-channel mock).
void mockStorageForInsert(String dir) => _mockStorage(dir: dir);
void clearInsertStorageMock() => _clearStorageMock();

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
    ResourceStore.debugResetForTest();
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
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    // Semantics on for this test: the handle's a11y contract (a button node
    // carrying the action label) is asserted through the real semantics tree.
    // Disposed at the end of the body — the binding verifies handle disposal
    // before it runs addTearDown callbacks.
    final semantics = tester.ensureSemantics();
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
    semantics.dispose();
  });

  testWidgets('filmstrip: reduced motion collapses instantly', (tester) async {
    Bridge.testOverride = testFakeEngine;
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

  testWidgets('files drawer: floats over an intact filmstrip with all six tools — the strip stays laid out AND live while the sheet is open', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    // Before: the ribbon's Files tab, a laid-out filmstrip, and a scrolled
    // rail — the state the sheet must never disturb.
    expect(find.text('Files'), findsOneWidget);
    final row = find.byKey(const ValueKey('filmstrip_row'));
    expect(tester.getSize(row), const Size(390, 104));
    await tester.drag(find.byKey(const ValueKey('filmstrip_row')),
        const Offset(-120, 0));
    await tester.pumpAndSettle();
    // The scroll marker is the CARD, not its text: selecting another slide
    // mid-open legitimately swaps the card's selection-ring padding (2.5 →
    // 1), which nudges the text INSIDE the card — the card's own position
    // is the honest measure of the rail's scroll offset.
    final slide1Card = find
        .ancestor(
            of: find.text('1. Slide 1'),
            matching: find.byType(AnimatedContainer))
        .first;
    final scrolled = tester.getTopLeft(slide1Card).dx;

    // Open: tapping Files in the ribbon mounts the sheet as its own layer.
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    // The drawer's heading joins the ribbon's tab — two 'Files' texts now.
    expect(find.text('Files'), findsNWidgets(2));
    // All six tools, in the spec's grid order (row-major position checks).
    final newC = tester.getCenter(find.text('New'));
    final openC = tester.getCenter(find.text('Open'));
    final renameC = tester.getCenter(find.text('Rename'));
    final aspectC = tester.getCenter(find.text('Aspect ratio'));
    final deckRes = tester.getCenter(find.text('Deck resources'));
    final brandRes = tester.getCenter(find.text('Brand resources'));
    expect(newC.dx, lessThan(openC.dx));
    expect(openC.dx, lessThan(renameC.dx));
    expect(aspectC.dy, greaterThan(newC.dy));
    expect(aspectC.dx, lessThan(deckRes.dx));
    expect(deckRes.dx, lessThan(brandRes.dx));
    // Supporting labels; the storage footer is gone by request.
    expect(find.text('Blank · Template'), findsOneWidget);
    expect(find.text('Recents · Browse'), findsOneWidget);
    expect(find.text('This deck only'), findsOneWidget);
    expect(find.text('All decks'), findsOneWidget);
    expect(find.text('Resources stored on this device'), findsNothing);
    // The slide's top sliver and the ribbon both stay on screen.
    expect(find.text('Slide 1 / 8'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    // THE LAYER CONTRACT: the sheet rides the RIBBON's top edge — the
    // exact line the tray's bottom edge rides — and the tray overlays the
    // sheet's LOWER part: the strip is laid out INSIDE the sheet's bounds,
    // same 390×104 geometry, same scroll, nothing unmounted, nothing
    // hidden, and the sheet's surface fills the whole region behind the
    // tray (no spacer of any kind between it and the ribbon).
    expect(tester.getSize(row), const Size(390, 104));
    expect(tester.getTopLeft(slide1Card).dx, closeTo(scrolled, 0.5));
    // And it stays LIVE: tapping a miniature while the sheet is open
    // selects that slide — no closing required.
    await tester.tap(find.text('2. Slide 2'));
    await tester.pumpAndSettle();
    expect(find.text('Slide 2 / 8'), findsOneWidget);
    final sheet = find.byKey(const ValueKey('files_drawer'));
    expect(tester.getRect(sheet).bottom,
        closeTo(tester.getRect(row).bottom, 0.5));
    expect(tester.getRect(row).top, greaterThan(tester.getRect(sheet).top));
    expect(
        tester.takeException(), isNull, reason: 'no layout errors while open');

    // Close: the ribbon's Files again — the FIRST of the two in tree order
    // (the base Column renders before the sheet's overlay layer, so the
    // tab is first and the drawer's own heading second).
    await tester.tap(find.text('Files').first);
    await tester.pumpAndSettle();
    expect(find.text('Files'), findsOneWidget);
    // The strip was never disturbed — geometry, scroll, selection, disc.
    expect(tester.getSize(row), const Size(390, 104));
    expect(tester.getTopLeft(slide1Card).dx, closeTo(scrolled, 0.5));
    expect(find.text('Slide 2 / 8'), findsOneWidget);
    final disc = tester.widget<Positioned>(find
        .ancestor(of: find.byIcon(Icons.add), matching: find.byType(Positioned))
        .first);
    expect(disc.left, 14);
    expect(disc.top, 30);
  });

  testWidgets('files drawer: the Aspect tile applies the ratio to the deck, and the canvas frame follows', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    // The canvas starts at the classic ratio.
    final canvasAspect = find.byType(AspectRatio);
    expect(canvasAspect, findsOneWidget);
    expect(tester.widget<AspectRatio>(canvasAspect).aspectRatio,
        closeTo(16 / 9, 0.001));

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    // The tile's supporting label shows the live ratio.
    expect(find.text('16:9'), findsOneWidget);

    // The tray overlays the sheet's lower part, so the resting second row
    // of tiles sits under it — fold the tray before tapping the covered
    // row's tile (the clearance path is the dedicated overlay test).
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    await tester.tap(find.text('Aspect ratio'));
    await tester.pumpAndSettle();
    // The sheet states the current ratio and the supported presets.
    expect(find.text('Current: 16:9 · 1280 × 720'), findsOneWidget);
    expect(find.text('16:10'), findsOneWidget);
    expect(find.text('4:3'), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);
    // These slides have no drawn objects → no re-framing dialog, the choice
    // applies directly.
    await tester.tap(find.text('4:3').last);
    await tester.pumpAndSettle();
    expect(find.text('Current: 16:9 · 1280 × 720'), findsNothing);

    // The deck carries the ratio: the canvas frame re-ratios, and the
    // drawer's tile now reads 4:3.
    expect(tester.widget<AspectRatio>(canvasAspect).aspectRatio,
        closeTo(4 / 3, 0.001));
    expect(find.text('4:3'), findsOneWidget);
  });

  testWidgets('files drawer: the header drags the sheet between its detents, and a deep downward drag dismisses it', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('filmstrip_row'));
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    // The resting detent: the lower half of the space above the RIBBON
    // (this viewport leaves 710dp there — the app bar is 57dp with its
    // hairline, so the body is 787; the strip no longer takes layout space
    // while the sheet is open, and 45% of 710 is 319.5).
    final sheet = find.byKey(const ValueKey('files_drawer'));
    final handle = find.byKey(const ValueKey('files_drawer_handle'));
    expect(tester.getSize(sheet).height, closeTo(319.5, 0.1));

    // A slow drag up (no fling): the edge tracks the finger, then settles
    // to the NEAREST detent — tall, ~78% of the space above the ribbon
    // (553.8 here).
    await tester.timedDrag(handle, const Offset(0, -180),
        const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final tall = tester.getSize(sheet).height;
    expect(tall, greaterThan(540));
    expect(tall, lessThan(570));

    // A slow deep drag down: past the dismiss zone (below ~70% of half),
    // so the sheet closes outright — unmounted cleanly at its slot, and
    // the Files tab releases with it. The filmstrip never knew any of it
    // happened.
    await tester.timedDrag(handle, const Offset(0, 340),
        const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing);
    expect(find.text('Files'), findsOneWidget); // only the ribbon tab remains
    expect(tester.getSize(row), const Size(390, 104));
    expect(tester.takeException(), isNull);
  });

  testWidgets('files drawer: the filmstrip is an independent overlay over the sheet — toggling the tray moves nothing, covered tools stay inert, and the last row clears the tray', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Semantics on for the overlay's a11y contract: the tray blocks only
    // the sheet it covers — the ribbon and the top bar keep their nodes.
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('filmstrip_row'));
    final sheet = find.byKey(const ValueKey('files_drawer'));
    final handle = find.byKey(const ValueKey('files_drawer_handle'));
    final stripHandle = find.byKey(const ValueKey('filmstrip_handle'));
    final canvas = find.byType(AspectRatio);

    // Open Files — the strip becomes the foreground overlay over the
    // sheet's lower part — then drag to a custom height (the tall detent).
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Files'), findsNWidgets(2));
    await tester.timedDrag(handle, const Offset(0, -180),
        const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // THE INDEPENDENCE CONTRACT: toggling the tray, repeatedly, never moves
    // the sheet's top edge, the slide preview, or the bottom ribbon.
    final sheetTop = tester.getRect(sheet).top;
    final canvasRect = tester.getRect(canvas);
    final ribbonMark = tester.getRect(find.text('AI'));
    for (var i = 0; i < 2; i++) {
      await tester.tap(stripHandle); // collapse
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, sheetTop);
      expect(tester.getRect(canvas), canvasRect);
      expect(tester.getRect(find.text('AI')), ribbonMark);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      await tester.tap(stripHandle); // expand
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, sheetTop);
      expect(tester.getRect(canvas), canvasRect);
      expect(tester.getRect(find.text('AI')), ribbonMark);
      expect(tester.getSize(row), const Size(390, 104));
    }

    // The rail's scroll survives the toggles — the reveal never unmounts.
    final slide1Card = find
        .ancestor(
            of: find.text('1. Slide 1'),
            matching: find.byType(AnimatedContainer))
        .first;
    final railAtRest = tester.getTopLeft(slide1Card).dx;
    await tester.drag(row, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final railScrolled = tester.getTopLeft(slide1Card).dx;
    expect(railScrolled, lessThan(railAtRest - 50));
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(slide1Card).dx, closeTo(railScrolled, 0.5));

    // Back down to the resting half detent — where the tray covers the
    // sheet's lower part and the resting second row of tiles sits under it.
    await tester.timedDrag(handle, const Offset(0, 240),
        const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final sheetTopAtHalf = tester.getRect(sheet).top;

    // Tap another slide mid-open: the preview, the counter, and the
    // selection update — Files stays open, the tray stays open.
    await tester.tap(find.text('2. Slide 2'));
    await tester.pumpAndSettle();
    expect(find.text('Slide 2 / 8'), findsOneWidget);
    expect(find.text('Files'), findsNWidgets(2));
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    // THE HIT WALL: the covered 'Aspect ratio' tile cannot be triggered —
    // the tap lands on the tray, and nothing happens at all. (The tap aims
    // at the covered tile's text on purpose and warns that the hit lands
    // elsewhere — that is the contract under test, so the warning is
    // silenced.)
    expect(find.text('Current: 16:9 · 1280 × 720'), findsNothing);
    await tester.tap(find.text('Aspect ratio'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Current: 16:9 · 1280 × 720'), findsNothing);
    expect(find.text('Files'), findsNWidgets(2));
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    // The a11y contract, both directions on one label: while the tray
    // covers the sheet, the sheet's own heading ('Files') leaves the
    // semantics tree and only the RIBBON's tab keeps it — the block
    // dropped the covered sheet without leaking past the boundary to
    // the base flow.
    expect(find.bySemanticsLabel('Collapse slides'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);

    // THE CLEARANCE: scroll the grid's last row fully above the tray...
    await tester.drag(sheet, const Offset(0, -320));
    await tester.pumpAndSettle();
    // ...all six tools clear the whole overlay — the raised handle's zone
    // included (the divider's top edge IS the overlay's top).
    final divider = find.byKey(const ValueKey('filmstrip_divider'));
    for (final label in const [
      'New',
      'Open',
      'Rename',
      'Aspect ratio',
      'Deck resources',
      'Brand resources'
    ]) {
      final tile = find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first;
      expect(tester.getRect(tile).bottom,
          lessThanOrEqualTo(tester.getRect(divider).top + 0.5),
          reason: '$label clears the tray');
    }
    // ...and the last row actually works once it is above the tray.
    await tester.tap(find.text('Brand resources'));
    await tester.pumpAndSettle();
    expect(find.text('Available from every deck on this device'), findsOneWidget);
    await tester.tapAt(const Offset(195, 100)); // the modal barrier closes it
    await tester.pumpAndSettle();

    // Collapse: the covered area is revealed without a jump — the grid's
    // scroll position and every tile's place are untouched, and the sheet
    // never moved.
    final before = <String, Rect>{
      for (final label in const ['New', 'Aspect ratio', 'Brand resources'])
        label: tester.getRect(find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first),
    };
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();
    for (final e in before.entries) {
      expect(
          tester.getRect(find
              .ancestor(of: find.text(e.key), matching: find.byType(Material))
              .first),
          e.value);
    }
    expect(tester.getRect(sheet).top, sheetTopAtHalf);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    // ...and with the tray collapsed the block lifts: the sheet's own
    // 'Files' heading is back in the semantics tree alongside the tab.
    expect(find.bySemanticsLabel('Files'), findsNWidgets(2));
    // The collapsed divider sits immediately above the fixed bottom ribbon.
    expect(tester.getRect(sheet).bottom,
        closeTo(tester.getRect(divider).bottom, 0.5));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('files drawer: a short viewport constrains the tray to the sheet, and closing Files restores the plain flow', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    // 390×297 logical: the app bar is 57dp (56 + its hairline), so the body
    // is 240dp — the plain flow still fits the expanded strip (229dp) with
    // room to spare, while the space above the ribbon (163dp) caps the
    // resting sheet at 151dp: one dp UNDER the tray's full height, so the
    // overlay itself is constrained by the sheet — the tray never intrudes
    // past the sheet's top edge into the slide preview. (On any shorter
    // viewport the plain flow overflows before Files ever opens — a
    // pre-existing flow limit, out of this change's scope.)
    tester.view.physicalSize = const Size(780, 594);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('filmstrip_row'));
    final reveal = find.byKey(const ValueKey('filmstrip_reveal'));

    // Open Files with the tray expanded: the sheet rests at the capped
    // half detent (151dp).
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('files_drawer'));
    expect(tester.getSize(sheet).height, closeTo(151, 0.5));
    // THE CAP: the overlay's own box height never exceeds the sheet's —
    // the tray is constrained to the available space, not extended into
    // the preview.
    final overlayBox = find
        .ancestor(of: row, matching: find.byType(AnimatedPositioned))
        .first;
    final overlayHeight =
        tester.widget<AnimatedPositioned>(overlayBox).height;
    expect(overlayHeight, lessThanOrEqualTo(tester.getSize(sheet).height + 0.5));
    expect(overlayHeight, lessThan(152));
    // The visible tray stays within the sheet's bounds.
    expect(tester.getRect(row).top,
        greaterThanOrEqualTo(tester.getRect(sheet).top - 0.5));
    expect(tester.takeException(), isNull);

    // Close: the strip returns to the plain flow exactly as it left it —
    // the same expanded band, same geometry, the divider back above the
    // ribbon.
    await tester.tap(find.text('Files').first);
    await tester.pumpAndSettle();
    expect(find.text('Files'), findsOneWidget);
    expect(tester.getSize(row), const Size(390, 104));
    expect(tester.getSize(reveal).height, 104);
    expect(tester.takeException(), isNull);
  });

  test('resources: the two scopes stay separate, and everything persists on disk', () async {
    _mockStorage(dir: tmp.path);
    final store = await ResourceStore.open();
    final src = File('${tmp.path}/source.bin')..writeAsStringSync('payload');
    await store.add(brand: true, sourcePath: src.path);
    await store.add(brand: false, deckId: 'd1', sourcePath: src.path);
    await store.add(brand: false, deckId: 'd2', sourcePath: src.path);

    // Scope separation: brand never lists deck assets, a deck never lists
    // another deck's or the brand's.
    final brandItems = await store.list(brand: true);
    expect(brandItems, hasLength(1));
    expect(await store.list(brand: false, deckId: 'd1'), hasLength(1));
    expect(await store.list(brand: false, deckId: 'd2'), hasLength(1));

    // Real files on real disk, under the app's own documents tree.
    expect(
        Directory('${tmp.path}/resources/brand')
            .listSync()
            .whereType<File>()
            .length,
        2, // library.json + the copied asset
        reason: 'brand scope stores its index + asset files');
    expect(File('${tmp.path}/resources/decks/d1/library.json').existsSync(),
        isTrue);

    // Removal is scoped: the brand item goes, both deck libraries intact.
    await store.remove(brand: true, id: brandItems.first['id'].toString());
    expect(await store.list(brand: true), isEmpty);
    expect(await store.list(brand: false, deckId: 'd1'), hasLength(1));

    // Persistence across a "restart": a fresh store instance over the same
    // documents directory reads the same libraries back.
    ResourceStore.debugResetForTest();
    final reopened = await ResourceStore.open();
    expect(await reopened.list(brand: false, deckId: 'd1'), hasLength(1));
    expect(await reopened.list(brand: true), isEmpty);

    _clearStorageMock();
  });

  test('resources: a whole folder imports in one gesture — every file tagged with its folder, scopes still separate', () async {
    _mockStorage(dir: tmp.path);
    // A brand folder with a nested subfolder, one dot-file (skipped), and
    // one library index (never imported back into itself).
    final brand = Directory('${tmp.path}/BrandA');
    final sub = Directory('${brand.path}/sub');
    sub.createSync(recursive: true);
    File('${brand.path}/logo.png').writeAsStringSync('logo');
    File('${brand.path}/palette.json').writeAsStringSync('{}');
    File('${sub.path}/font.ttf').writeAsStringSync('font');
    File('${brand.path}/.DS_Store').writeAsStringSync('skip me');
    File('${brand.path}/library.json').writeAsStringSync('[]');

    final store = await ResourceStore.open();
    final added = await store.addFilesFromDirectory(brand: true, dir: brand);
    expect(added, hasLength(3));
    expect(added.map((e) => e['name'].toString()).toSet(),
        {'logo.png', 'palette.json', 'font.ttf'});
    // Every entry carries the folder it arrived through.
    expect(added.every((e) => e['folder'] == 'BrandA'), isTrue);
    // Real files on real disk under the brand scope: 3 assets + the index.
    expect(
        Directory('${tmp.path}/resources/brand')
            .listSync()
            .whereType<File>()
            .length,
        4);

    // Folder imports respect the scope walls exactly like single files.
    final deck = Directory('${tmp.path}/DeckOnly')..createSync();
    File('${deck.path}/note.txt').writeAsStringSync('n');
    await store.addFilesFromDirectory(brand: false, deckId: 'd9', dir: deck);
    expect(await store.list(brand: true), hasLength(3));
    final deckItems = await store.list(brand: false, deckId: 'd9');
    expect(deckItems, hasLength(1));
    expect(deckItems.first['folder'], 'DeckOnly');
    expect(await store.list(brand: false, deckId: 'd1'), isEmpty);

    // A tight import loop mints unique ids: a second identical folder import
    // doubles the entries instead of overwriting the first pass's files.
    final again = await store.addFilesFromDirectory(brand: true, dir: brand);
    expect(again, hasLength(3));
    expect(await store.list(brand: true), hasLength(6));
    final ids = (await store.list(brand: true)).map((e) => e['id']).toSet();
    expect(ids, hasLength(6));

    _clearStorageMock();
  });

  // ---- the sheet's entrance/exit slide + the preview lock ----------------------

  testWidgets('files drawer: the sheet slides up from behind the navbar — the preview, the ribbon, and the tray never move', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('files_drawer'));
    final row = find.byKey(const ValueKey('filmstrip_row'));
    final canvas = find.byType(AspectRatio);
    final ribbon = find.text('AI');

    // THE PREVIEW LOCK, part one: the bounds before the sheet ever exists.
    final preview0 = tester.getRect(canvas);
    final ribbon0 = tester.getRect(ribbon);
    final tray0 = tester.getRect(row); // the tray's flow spot

    // THE FIRST FRAME: the sheet mounts at its FULL intended height (the
    // resting half detent — never a mid-screen sliver), translated fully
    // below the navbar's top edge. The tray is already mounted, expanded,
    // and in place in the overlay — its box is the same one it had in the
    // flow (the ribbon's band is a constant 77dp, hairline or not, so the
    // reparent moves nothing).
    await tester.tap(find.text('Files'));
    await tester.pump();
    final boundary = tester.getRect(row).bottom; // the navbar's top edge
    final halfH = tester.getSize(sheet).height;
    expect(halfH, closeTo(319.5, 0.1));
    expect(tester.getRect(sheet).top, greaterThanOrEqualTo(boundary - 0.5),
        reason: 'the mount frame is fully below the navbar\'s top edge');
    expect(tester.getRect(sheet).bottom, greaterThanOrEqualTo(boundary - 0.5));
    expect(tester.getRect(canvas), preview0,
        reason: 'the preview never moved on the mount frame');
    expect(tester.getRect(ribbon), ribbon0);
    expect(tester.getRect(row).top, closeTo(tray0.top, 0.5));
    expect(tester.getRect(row).bottom, closeTo(tray0.bottom, 0.5));

    // THE SLIDE, frame by frame (60 FPS steps): the sheet emerges
    // CONTINUOUSLY from behind the navbar — the top edge starts at the
    // boundary and rises monotonically (no teleport: the eased cubic's
    // steepest 16ms step is ~77dp), the bottom edge never lifts above the
    // boundary, and the preview, the ribbon, and the tray never move a
    // single pixel.
    await tester.pump(const Duration(milliseconds: 16)); // the retarget frame
    var lastTop = tester.getRect(sheet).top;
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final r = tester.getRect(sheet);
      expect(r.top, lessThanOrEqualTo(lastTop + 0.25),
          reason: 'frame $i: the sheet rises monotonically');
      expect(r.top, greaterThan(lastTop - 90),
          reason: 'frame $i: no teleport');
      if (i == 0) {
        expect(r.top, greaterThan(boundary - 50),
            reason: 'the slide starts AT the navbar\'s edge, not mid-screen');
      }
      expect(r.bottom, greaterThanOrEqualTo(boundary - 0.5),
          reason: 'frame $i: the sheet emerges from behind the navbar, '
              'never above its edge');
      expect(tester.getRect(canvas), preview0,
          reason: 'frame $i: the preview stays locked through the slide');
      expect(tester.getRect(ribbon), ribbon0);
      expect(tester.getRect(row).top, closeTo(tray0.top, 0.5));
      expect(tester.getRect(row).bottom, closeTo(tray0.bottom, 0.5));
      lastTop = r.top;
    }
    // The first risen frame is barely off the boundary — the slide starts
    // AT the navbar's edge, not mid-screen.
    await tester.pumpAndSettle();
    final settled = tester.getRect(sheet);
    expect(settled.top, closeTo(boundary - halfH, 0.5));
    expect(settled.bottom, closeTo(boundary, 0.5));
    expect(tester.getRect(canvas), preview0);

    // THE PREVIEW LOCK, part two: toggling the tray over the OPEN sheet
    // moves nothing (the flow's spacer is frozen).
    final stripHandle = find.byKey(const ValueKey('filmstrip_handle'));
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();
    expect(tester.getRect(canvas), preview0);
    expect(tester.getRect(ribbon), ribbon0);
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();
    expect(tester.getRect(canvas), preview0);
    expect(tester.getRect(ribbon), ribbon0);

    // THE EXIT — the entrance's exact reverse: the sheet sinks back behind
    // the navbar monotonically (its bottom edge never lifting above the
    // boundary), and the layer unmounts when the slide completes. The
    // preview and the ribbon still never move.
    await tester.tap(find.text('Files').first);
    await tester.pump();
    lastTop = tester.getRect(sheet).top;
    for (var i = 0; i < 11; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final r = tester.getRect(sheet);
      expect(r.top, greaterThanOrEqualTo(lastTop - 0.25),
          reason: 'frame $i: the sheet sinks monotonically');
      expect(r.bottom, greaterThanOrEqualTo(boundary - 0.5),
          reason: 'frame $i: the sheet leaves behind the navbar');
      expect(tester.getRect(canvas), preview0,
          reason: 'frame $i: the preview stays locked through the exit');
      expect(tester.getRect(ribbon), ribbon0);
      lastTop = r.top;
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing);
    // The strip is back in the plain flow — same expanded band, same spot
    // — and the preview still has its original bounds after everything.
    expect(tester.getRect(row).top, closeTo(tray0.top, 0.5));
    expect(tester.getRect(row).bottom, closeTo(tray0.bottom, 0.5));
    expect(tester.getRect(canvas), preview0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('files drawer: with the tray collapsed, the sheet still rises from behind the navbar behind the stationary divider', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('files_drawer'));
    final divider = find.byKey(const ValueKey('filmstrip_divider'));
    final canvas = find.byType(AspectRatio);
    final ribbon = find.text('AI');

    // Fold the tray in the plain flow first — the collapsed state the
    // entrance must leave exactly as it found it.
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    final preview0 = tester.getRect(canvas);
    final ribbon0 = tester.getRect(ribbon);
    final divider0 = tester.getRect(divider);

    // The entrance, with the tray collapsed: the sheet mounts fully below
    // the navbar's top edge (the divider's own bottom edge rides the
    // boundary), the collapsed divider is stationary from the first frame,
    // and the preview never moved (the spacer froze the COLLAPSED
    // footprint — the canvas never grew).
    await tester.tap(find.text('Files'));
    await tester.pump();
    final boundary = tester.getRect(divider).bottom;
    expect(tester.getRect(sheet).top, greaterThanOrEqualTo(boundary - 0.5));
    expect(tester.getRect(canvas), preview0);
    expect(tester.getRect(ribbon), ribbon0);
    expect(tester.getRect(divider).top, closeTo(divider0.top, 0.5));
    expect(tester.getRect(divider).bottom, closeTo(divider0.bottom, 0.5));

    // The rise: monotone, from behind the boundary, with everything else
    // fixed.
    await tester.pump(const Duration(milliseconds: 16));
    var lastTop = tester.getRect(sheet).top;
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final r = tester.getRect(sheet);
      expect(r.top, lessThanOrEqualTo(lastTop + 0.25),
          reason: 'frame $i: monotone rise');
      expect(r.top, greaterThan(lastTop - 90),
          reason: 'frame $i: no teleport');
      expect(r.bottom, greaterThanOrEqualTo(boundary - 0.5));
      expect(tester.getRect(canvas), preview0);
      expect(tester.getRect(ribbon), ribbon0);
      expect(tester.getRect(divider).top, closeTo(divider0.top, 0.5));
      lastTop = r.top;
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet).bottom, closeTo(boundary, 0.5));
    expect(tester.getRect(canvas), preview0);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    // Close: reverse the same motion, the divider stays put, and the strip
    // returns to its flow spot still collapsed.
    await tester.tap(find.text('Files').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(tester.getRect(divider).top, closeTo(divider0.top, 0.5));
    expect(tester.getRect(canvas), preview0);
    expect(tester.getRect(ribbon), ribbon0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('files drawer: interrupted and reversed slides continue from the current visible position', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('files_drawer'));
    final row = find.byKey(const ValueKey('filmstrip_row'));
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    final boundary = tester.getRect(row).bottom;
    final halfH = tester.getSize(sheet).height;

    // REVERSED EXIT: start closing, interrupt the slide mid-flight, reopen
    // — the sheet continues UP from wherever it stands. The reversal
    // registers one frame later (the exit keeps running through the input
    // latency), so at most ONE 16ms exit-step passes between the interrupt
    // and the retarget — but never a reset to the hidden mount, never a
    // jump to the resting spot, and from there it rises monotonically home.
    await tester.tap(find.text('Files').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // mid-slide-down
    final mid = tester.getRect(sheet);
    expect(mid.top, greaterThan(boundary - halfH + 0.5),
        reason: 'the sheet has left its resting spot (its top sank)');
    expect(mid.top, lessThan(boundary),
        reason: 'and it is still visibly on screen, mid-flight');
    // The ribbon's tab is the FIRST 'Files' in tree order (the base layer
    // renders before the sheet's overlay, whose heading is the second).
    await tester.tap(find.text('Files').first);
    await tester.pump(const Duration(milliseconds: 16));
    final resumed = tester.getRect(sheet);
    expect(resumed.top, greaterThan(mid.top),
        reason: 'one exit frame of input latency — the reversal is one '
            'frame behind the tap');
    expect(resumed.top, lessThan(mid.top + 90),
        reason: 'at most one 16ms exit step — no teleport, no reset to the '
            'hidden mount');
    expect(resumed.top, lessThan(boundary), reason: 'never reset to hidden');
    var lastRise = resumed.top;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final t = tester.getRect(sheet).top;
      expect(t, lessThanOrEqualTo(lastRise + 0.25),
          reason: 'frame $i: rises monotonically home after the reversal');
      lastRise = t;
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet).top, closeTo(boundary - halfH, 0.5));

    // THE NEVER-ROSE EDGE: a second tab tap landing before the entrance's
    // post-frame flip (two taps inside one frame gap) hits the defensive
    // branch — no pixel of the sheet was ever rendered, so there is
    // nothing to animate out: the layer unmounts at once, no half-slide
    // flash, and the Draw tab lands live in its place.
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing);
    await tester.tap(find.text('Files'));
    await tester.tap(find.text('Draw')); // before the entrance ever renders
    await tester.pump();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing,
        reason: 'the never-rose sheet unmounts immediately — nothing shown, '
            'nothing to animate');
    await tester.pumpAndSettle();
    expect(find.text('Draw'), findsOneWidget);

    // INTERRUPTED ENTRANCE: start a fresh entrance, switch tabs mid-rise —
    // the sheet reverses from the position it had reached (plus at most
    // one 16ms entrance step of input latency), never resetting to the
    // hidden mount, and sinks monotonically away.
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing);
    await tester.tap(find.text('Files'));
    await tester.pump(); // the mount frame — fully below the navbar
    await tester.pump(const Duration(milliseconds: 16)); // the retarget frame
    await tester.pump(const Duration(milliseconds: 100)); // mid-rise
    final rising = tester.getRect(sheet);
    expect(rising.top, lessThan(boundary),
        reason: 'the sheet is partially visible mid-rise');
    expect(rising.top, greaterThan(boundary - halfH),
        reason: 'but not yet in place');
    await tester.tap(find.text('Draw'));
    await tester.pump(const Duration(milliseconds: 16));
    final reversing = tester.getRect(sheet);
    expect(reversing.top, lessThanOrEqualTo(rising.top + 0.25),
        reason: 'at most one 16ms entrance step of latency past the '
            'interrupt (no jump, no reset to hidden)');
    expect(reversing.top, greaterThan(rising.top - 90),
        reason: 'and never a teleport');
    expect(reversing.top, greaterThan(boundary - halfH),
        reason: 'still away from the resting spot — the reversal continues '
            'from the current position');
    var lastSink = reversing.top;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final t = tester.getRect(sheet).top;
      expect(t, greaterThanOrEqualTo(lastSink - 0.25),
          reason: 'frame $i: sinks monotonically away after the reversal');
      lastSink = t;
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing);
    expect(find.text('Draw'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('files drawer: toggling the tray over the open sheet, then closing, hands the space back without a jump', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8))));
    await tester.pumpAndSettle();

    final canvas = find.byType(AspectRatio);
    final ribbon = find.text('AI');
    final stripHandle = find.byKey(const ValueKey('filmstrip_handle'));

    // The two references the close must land on: the plain flow's
    // collapsed preview bounds, and the expanded ones.
    final expandedPreview = tester.getRect(canvas);
    final ribbon0 = tester.getRect(ribbon);
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();
    final collapsedPreview = tester.getRect(canvas);
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();

    // Open Files with the tray expanded; toggle the tray over the sheet —
    // the preview keeps its EXPANDED-flow bounds (the spacer is frozen);
    // then close with the tray collapsed: the spacer hands the space back
    // to the collapsed strip CONTINUOUSLY, and the preview settles at the
    // collapsed-flow reference — no jump at any frame.
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(tester.getRect(canvas), expandedPreview);
    await tester.tap(stripHandle);
    await tester.pumpAndSettle();
    expect(tester.getRect(canvas), expandedPreview,
        reason: 'the frozen spacer: toggling the tray over the open sheet '
            'never moves the preview');
    expect(tester.getRect(ribbon), ribbon0);

    await tester.tap(find.text('Files').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    var lastTop = tester.getRect(canvas).top;
    for (var i = 0; i < 11; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final r = tester.getRect(canvas);
      expect(r.top, greaterThanOrEqualTo(lastTop - 0.25),
          reason: 'frame $i: the canvas reclaims continuously, no jump');
      expect(lastTop - r.top, lessThan(30),
          reason: 'frame $i: and smoothly');
      // The ribbon rides the flow's bottom edge — fixed through the
      // reclaim (the comparison carries a half-pixel tolerance for the
      // floating-point artifacts of the spacer's mid-flight fractional
      // heights).
      expect(tester.getRect(ribbon).top, closeTo(ribbon0.top, 0.5));
      expect(tester.getRect(ribbon).bottom, closeTo(ribbon0.bottom, 0.5));
      lastTop = r.top;
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files_drawer')), findsNothing);
    expect(tester.getRect(canvas), collapsedPreview,
        reason: 'the close lands on the plain collapsed-flow bounds');
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filmstrip divider: the raised tab is fully opaque — nothing behind it shows through', (tester) async {
    Bridge.testOverride = testFakeEngine;
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The bright-icon-behind-the-tab probe, rendered: a full-screen raster
    // at 1:1 logical resolution, sampled inside the tab zone (right of the
    // ramp, clear of the chevron glyph and both stroked lines).
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('capture_root'),
        child: MaterialApp(
            home: EditorScreen(deck: _deckFixture('d1', 'Test deck', 8)))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    final divider = find.byKey(const ValueKey('filmstrip_divider'));
    final dRect = tester.getRect(divider);
    final root =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture_root')));
    // The rasterization is a REAL engine call — runAsync is required inside
    // the test binding's fake clock, or the future never completes.
    late ui.Image image;
    late ByteData bytes;
    await tester.runAsync(() async {
      image = await root.toImage(pixelRatio: 1);
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    Color px(double x, double y) {
      final i = (y.round() * image.width + x.round()) * 4;
      return Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1),
          bytes.getUint8(i + 2));
    }
    // Component comparisons in the Color 0..1 domain (the legacy .red/.green
    // accessors are deprecated in this SDK); a 0.02 window is ~5/255 —
    // generous for an exact-token match, tight against the sheet's own
    // palette (kSurface/kElevated sit 6+ counts away per channel).
    void expectFilmstrip(Color got, String where) {
      expect((got.r - kFilmstrip.r).abs(), lessThan(0.02), reason: where);
      expect((got.g - kFilmstrip.g).abs(), lessThan(0.02), reason: where);
      expect((got.b - kFilmstrip.b).abs(), lessThan(0.02), reason: where);
    }

    // The tab zone: x between the ramp's end (the ledge starts at 320) and
    // the handle's 48-wide box (starting at 342) — the only tab real estate
    // that no other layer ever paints in. The chevron's glyph itself is
    // excluded: its Icon box is deflated by the handle's tight constraints
    // (padding (3,22) in a forced 48×48), so the glyph centers near the
    // handle's own middle — the exclusion is the whole icon box
    // [345..390]×[22..48], covering the glyph wherever the font puts it.
    // Every sample must be the tray's charcoal, so the sheet's tiles
    // (bright icons included) can never show through the sloped ramp or the
    // pocket behind the chevron.
    for (final x in const [324, 332, 340]) {
      for (final y in const [21, 27, 33, 39]) {
        expectFilmstrip(
            px(dRect.left + x, dRect.top + y), 'tab sample ($x, $y)');
      }
    }
    // The ramp's interior (below the slope line, above the baseline) and
    // the baseline's bridge (full width under the rule) — same charcoal,
    // meeting the band's own fill flush at the region's floor.
    expectFilmstrip(px(dRect.left + 310, dRect.top + 34), 'ramp interior');
    expectFilmstrip(px(dRect.left + 200, dRect.top + 47), 'baseline bridge');
    expectFilmstrip(px(dRect.left + 316, dRect.top + 47), 'bridge under the ramp');

    // CONTROL — left of the ramp, ABOVE the baseline: not filled (the
    // divider's transparent window is by design; only the raised tab
    // projects above the line). Whatever surface sits behind the tray
    // shows through there, and none of the sheet's palette is the tray's
    // charcoal.
    final control = px(dRect.left + 100, dRect.top + 30);
    expect((control.r - kFilmstrip.r).abs() +
            (control.g - kFilmstrip.g).abs() +
            (control.b - kFilmstrip.b).abs(),
        greaterThan(0.03),
        reason: 'the zone left of the ramp stays transparent by design');
    expect(tester.takeException(), isNull);
  });
}
