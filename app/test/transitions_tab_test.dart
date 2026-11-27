import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/widgets/controls.dart';
import 'package:dreamtx/widgets/slide_stage.dart';

import 'smoke_test.dart' as smoke;

/// The Transitions tab — the formerly dead ribbon tab is now a real surface:
/// per-slide arrival kinds (app-owned `deck['transitions']`, the sections
/// carry contract), carried through engine round-trips, one undo step a
/// pick, and the presenter honors the target slide's kind (push keeps the
/// classic slide-along; fade / zoom / rise land through their own entrance).
void main() {
  late Directory tmp;

  /// The real Rust core parses the deck into its structs and re-serializes —
  /// app-owned keys it has no field for are DROPPED on every round-trip.
  /// This wrapper gives the fake engine exactly that behavior, so the
  /// editor's carry contract is genuinely exercised.
  Map<String, dynamic> droppingEngine(Map<String, dynamic> req) {
    final r = smoke.testFakeEngine(req);
    final deck = r['deck'];
    if (deck is Map) {
      deck.remove('transitions');
      deck.remove('animations');
      deck.remove('sections');
      deck.remove('tables');
      deck.remove('imageMeta');
      deck.remove('furniture');
    }
    return r;
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_transitions');
    DeckStore.debugResetForTest();
    ResourceStore.debugResetForTest();
    smoke.mockStorageForInsert(tmp.path);
    ImagePickers.testOverride = null;
  });

  tearDown(() {
    Bridge.testOverride = null;
    ImagePickers.testOverride = null;
    smoke.clearInsertStorageMock();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpEditor(WidgetTester tester,
      {Map<String, dynamic>? deck}) async {
    Bridge.testOverride = droppingEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: deck ?? smoke.deckFixtureForProbe(3))));
    await tester.pumpAndSettle();
  }

  /// The ribbon's tabs never fit a phone — scroll the far ones into view.
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  DreamChoiceChip chip(WidgetTester tester, String kind) =>
      tester.widget(find.byKey(ValueKey('transition_chip_$kind')))
          as DreamChoiceChip;

  testWidgets('the tab opens a chip strip — the band is no longer dead',
      (tester) async {
    await pumpEditor(tester);
    await openTab(tester, 'Transitions');
    // The lead label and every kind chip render; Push (the default) is
    // the selected one on an untouched deck.
    expect(find.text('THIS SLIDE ARRIVES BY'), findsOneWidget);
    for (final label in ['Push', 'Fade', 'Zoom', 'Rise', 'Cut']) {
      expect(find.text(label), findsOneWidget, reason: '$label chip renders');
    }
    expect(find.text('All slides'), findsOneWidget);
    expect(chip(tester, 'push').selected, isTrue,
        reason: 'the untouched default is selected');
    expect(chip(tester, 'fade').selected, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking Fade is one undo step and survives the engine drop',
      (tester) async {
    await pumpEditor(tester);
    await openTab(tester, 'Transitions');
    // The chip strip scrolls — bring the Fade chip into view, then pick it.
    final fadeChip = find.byKey(const ValueKey('transition_chip_fade'));
    await tester.ensureVisible(fadeChip);
    await tester.pumpAndSettle();
    await tester.tap(fadeChip);
    await tester.pumpAndSettle();
    expect(chip(tester, 'fade').selected, isTrue,
        reason: 'slide 1 now arrives by Fade');

    // An engine round-trip (the + disc's add_slide) DROPS the app-owned
    // key — the carry in _setDeck must hold the entry. The new slide
    // becomes current and reads the default push.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(chip(tester, 'push').selected, isTrue,
        reason: 'the freshly added slide defaults to push');

    // Back to slide 1: its Fade held through the dropping round-trip.
    await tester.tap(find.text('1. Slide 1'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'fade').selected, isTrue,
        reason: 'slide 1 kept its Fade across the round-trip');

    // Undo the add_slide (slide 1 still Fade), then the Fade pick itself —
    // one undo step per pick.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'fade').selected, isTrue,
        reason: 'undoing the add left the Fade pick alone');
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'push').selected, isTrue,
        reason: 'the Fade pick was one undo step');
    expect(tester.takeException(), isNull);
  });

  testWidgets('presenting honors the target slide\u2019s kind: fade lands, '
      'the counter advances', (tester) async {
    final deck = smoke.deckFixtureForProbe(2);
    await pumpEditor(tester, deck: deck);
    // Slide 2 arrives by Fade.
    await tester.tap(find.text('2. Slide 2'));
    await tester.pumpAndSettle();
    await openTab(tester, 'Transitions');
    final fadeChip = find.byKey(const ValueKey('transition_chip_fade'));
    await tester.ensureVisible(fadeChip);
    await tester.pumpAndSettle();
    await tester.tap(fadeChip);
    await tester.pumpAndSettle();
    // Back to slide 1, then present.
    await tester.tap(find.text('1. Slide 1'));
    await tester.pumpAndSettle();
    await openTab(tester, 'Slide show');
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget,
        reason: 'presenting opens on slide 1');

    // Tap the right edge: slide 2's fade carries the arrival (the jump is
    // instant, the entrance effect animates, the settle completes).
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width - 20, size.height / 2));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget,
        reason: 'the right tap zone advanced to slide 2');
    // The stage stayed mounted and sane through the effect.
    expect(find.byType(SlideStage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
