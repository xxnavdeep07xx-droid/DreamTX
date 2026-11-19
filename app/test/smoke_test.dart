import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/restart.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/decks_screen.dart';
import 'package:dreamtx/screens/editor_screen.dart';

/// Host smoke tests — the affordable self-test: no device, no emulator, the
/// real app code under the real framework. The two seams are
/// [Bridge.testOverride] (an in-memory deck engine replaces the Rust core,
/// which is not loadable in a host test runner) and the path_provider
/// platform-channel mock (the storage bridge runs against a temp dir, or
/// throws the exact stale-classloader signature for the self-heal case).

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

/// The exact error the app sees after an APK is sideloaded over a still-live
/// process: the first Java class a plugin lazily loads is gone from the stale
/// dex path.
const _staleDexMessage =
    "Exception in Java: java.lang.ClassNotFoundException: Didn't find class "
    '"Landroid/content/Context;" on path: DexPathList[[zip file '
    '"/data/app/~~gA==/com.dreamtx-hQ==/base.apk"],nativeLibraryDirectory=[/data/app/~~gA==/com.dreamtx-hQ==/lib/arm64"]]';

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

void _mockStorage({String? dir, Object? throwFor}) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (throwFor != null) throw throwFor;
    if (call.method == 'getApplicationDocumentsDirectory') return dir;
    throw PlatformException(
        code: 'unimplemented', message: 'unexpected method: ${call.method}');
  });
}

void main() {
  late Directory tmp;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_smoke');
    DeckStore.debugResetForTest();
    StaleProcessRestart.armed = false;
  });

  tearDown(() {
    Bridge.testOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('dashboard loads decks from the storage bridge (happy path)',
      (tester) async {
    final decks = Directory('${tmp.path}/decks')..createSync(recursive: true);
    File('${decks.path}/d1.json')
        .writeAsStringSync(jsonEncode(_deckFixture('d1', 'Test deck', 2)));
    File('${decks.path}/d2.json')
        .writeAsStringSync(jsonEncode(_deckFixture('d2', 'Second deck', 5)));
    _mockStorage(dir: tmp.path);

    await tester.pumpWidget(const MaterialApp(home: DecksScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Test deck'), findsOneWidget);
    expect(find.text('Second deck'), findsOneWidget);
    expect(find.text('2 slides · swiss editorial'), findsOneWidget);
    expect(find.text('5 slides · swiss editorial'), findsOneWidget);
    expect(find.text('DECKS · 2 ON THIS DEVICE'), findsOneWidget);
  });

  testWidgets(
      'stale dex after an in-place update: calm notice, then ONE self-restart',
      (tester) async {
    final realKill = StaleProcessRestart.kill;
    final kills = <String>[];
    StaleProcessRestart.kill = () => kills.add('exit(0)');
    addTearDown(() => StaleProcessRestart.kill = realKill);
    _mockStorage(
        throwFor: PlatformException(code: 'error', message: _staleDexMessage));

    await tester.pumpWidget(const MaterialApp(home: DecksScreen()));
    // The stale signature skips the retry delays — the notice is immediate.
    await tester.pump();
    expect(find.text('Finishing the update'), findsOneWidget);
    expect(find.text('DECKS · FINISHING UPDATE'), findsOneWidget);
    expect(find.text('Restart app'),
        findsNothing); // no button: it restarts itself
    expect(kills, isEmpty); // ...but only after the visible beat

    await tester.pump(const Duration(milliseconds: 1600));
    expect(kills, ['exit(0)']); // exactly one kill, then never again
    expect(StaleProcessRestart.armed, isTrue);

    // The latch: a (practically impossible) second detection in the same
    // process falls back to the manual card instead of looping.
    kills.clear();
    // (A keyed tree, so this really mounts a NEW screen state rather than
    // reusing the identical const widget above.)
    await tester.pumpWidget(const MaterialApp(key: Key('stale-second'), home: DecksScreen()));
    await tester.pump();
    expect(find.text('DreamTX needs a quick restart'), findsOneWidget);
    expect(find.text('Restart app'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(kills, isEmpty);
  });

  testWidgets(
      'filmstrip: the v-chevron folds the strip and nothing moves when it unfolds',
      (tester) async {
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
}
