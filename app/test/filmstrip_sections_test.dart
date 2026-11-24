import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';

import 'smoke_test.dart' as smoke;

/// Roadmap #11, Wave 1 step 2 — filmstrip sections. A section is a named
/// divider in the rail, started from the slide actions sheet and anchored
/// to the slide it opens. The markers are app-owned deck metadata
/// (`deck['sections']`): the Rust core's Deck struct has no such field and
/// drops it on every op response, so the editor carries its own forward in
/// `_setDeck` — the critical regression here — sanitizes markers whose
/// start slide is gone, and snapshots them through undo/redo via the
/// deck's JSON copy. Folding is UI state, per session. Zero model changes.
void main() {
  late Directory tmp;

  Map<String, dynamic> coreLikeEngine(Map<String, dynamic> req) {
    final r = smoke.testFakeEngine(req);
    // The REAL core's Deck struct has no `sections` field and drops it on
    // every response; the Dart fake keeps unknown keys. Strip it so the
    // editor's carry-forward logic runs under the same truth as
    // production.
    if (r['deck'] is Map) (r['deck'] as Map).remove('sections');
    return r;
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_sections');
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

  Future<void> pumpEditor(WidgetTester tester) async {
    Bridge.testOverride = coreLikeEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: smoke.deckFixtureForProbe(3))));
    await tester.pumpAndSettle();
  }

  /// Start a section named [name] at slide 2, through the real UI: the
  /// slide's long-press sheet → "Start section here" → the name dialog.
  Future<void> startSectionAtSlide2(
      WidgetTester tester, String name) async {
    await tester.longPress(find.text('2. Slide 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start section here'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, name);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
  }

  /// Drag the rail left until [label]'s card is built — off-viewport
  /// cards are simply not in the tree (the smoke suite's own reveal
  /// pattern; the rail's viewport is narrow in the test window).
  Future<void> revealCard(WidgetTester tester, String label) async {
    for (var i = 0; i < 10 && find.text(label).evaluate().isEmpty; i++) {
      await tester.drag(
          find.byKey(const ValueKey('filmstrip_row')), const Offset(-160, 0));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a section starts from the slide actions sheet, between its neighbors',
      (tester) async {
    await pumpEditor(tester);
    await startSectionAtSlide2(tester, 'Intro');
    // The chip renders the section's name, and the section is OPEN: the
    // cards in view are still in the rail.
    expect(find.text('Intro'), findsOneWidget);
    expect(find.text('1. Slide 1'), findsOneWidget);
    expect(find.text('2. Slide 2'), findsOneWidget);
    // The chip sits between slide 1's card and slide 2's — the divider
    // leads the section, it does not follow it.
    final chipX = tester.getTopLeft(find.text('Intro')).dx;
    expect(chipX,
        greaterThan(tester.getTopLeft(find.text('1. Slide 1')).dx));
    expect(chipX, lessThan(tester.getTopLeft(find.text('2. Slide 2')).dx));
    // Slide 3's card rides past the viewport's right edge — reveal it.
    await revealCard(tester, '3. Slide 3');
    expect(find.text('3. Slide 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sections survive an engine round-trip (the core drops the field)',
      (tester) async {
    await pumpEditor(tester);
    await startSectionAtSlide2(tester, 'Intro');
    // Any engine op: duplicate slide 3. The fake strips `sections` from
    // the response exactly like the Rust core does — the chip can only
    // still be there because the editor carried its own forward.
    await revealCard(tester, '3. Slide 3');
    expect(find.text('Intro'), findsOneWidget,
        reason: 'the chip rides in view beside the revealed card');
    await tester.longPress(find.text('3. Slide 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('Intro'), findsOneWidget,
        reason: 'the marker survived the engine round-trip');
    await revealCard(tester, '4. Blank');
    expect(find.text('4. Blank'), findsOneWidget,
        reason: 'the duplicate landed (the fake engine appends blank '
            'copies — the app-level duplicate flow)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('folding a section hides its slides and counts them',
      (tester) async {
    await pumpEditor(tester);
    await startSectionAtSlide2(tester, 'Intro');
    // One scroll puts the chip, its two slides, and slide 1 in one view
    // — the fold below then proves BUILT cards leave the rail.
    await tester.drag(
        find.byKey(const ValueKey('filmstrip_row')), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(find.text('3. Slide 3'), findsOneWidget);
    await tester.tap(find.text('Intro'));
    await tester.pumpAndSettle();
    // The section owns slides 2–3: both leave the rail, slide 1 stays,
    // and the folded pill carries the head-count.
    expect(find.text('2. Slide 2'), findsNothing);
    expect(find.text('3. Slide 3'), findsNothing);
    expect(find.text('1. Slide 1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget,
        reason: 'the folded head-count pill');
    // Unfold: everyone comes back. (The fold clamped the scroll offset
    // back to 0 — slide 3 needs revealing again.)
    await tester.tap(find.text('Intro'));
    await tester.pumpAndSettle();
    expect(find.text('2. Slide 2'), findsOneWidget);
    await revealCard(tester, '3. Slide 3');
    expect(find.text('3. Slide 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renaming a section retitles the chip', (tester) async {
    await pumpEditor(tester);
    await startSectionAtSlide2(tester, 'Intro');
    await tester.longPress(find.text('Intro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename section'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Opening');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Opening'), findsOneWidget);
    expect(find.text('Intro'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a section keeps the slides', (tester) async {
    await pumpEditor(tester);
    await startSectionAtSlide2(tester, 'Intro');
    await tester.longPress(find.text('Intro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove section'));
    await tester.pumpAndSettle();
    // The tombstone: a removal must not resurrect on the carry.
    expect(find.text('Intro'), findsNothing);
    expect(find.text('2. Slide 2'), findsOneWidget,
        reason: 'the slides were never part of the divider');
    await revealCard(tester, '3. Slide 3');
    expect(find.text('3. Slide 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the start slide folds the orphaned marker away',
      (tester) async {
    await pumpEditor(tester);
    await startSectionAtSlide2(tester, 'Intro');
    await tester.longPress(find.text('2. Slide 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // The marker's anchor is gone: no chip haunting the rail, the
    // remaining slides renumber cleanly.
    expect(find.text('Intro'), findsNothing);
    expect(find.text('1. Slide 1'), findsOneWidget);
    expect(find.text('2. Slide 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
