import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/widgets/controls.dart';
import 'package:dreamtx/widgets/shape_canvas.dart';

import 'smoke_test.dart' as smoke;

/// The Animations tab — the formerly dead ribbon tab is now a real surface:
/// per-object entrance effects (app-owned `deck['animations']`, the sections
/// carry contract) with a selection-driven chip row, a live Preview on the
/// editor's own canvas, one undo step a pick — and the selection keeps the
/// tab (the row reads it) instead of jumping to the Insert panel.
void main() {
  late Directory tmp;

  /// The real Rust core drops app-owned keys on round-trips — mirrored so
  /// the carry contract is genuinely exercised.
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
    tmp = Directory.systemTemp.createTempSync('dreamtx_animations');
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

  /// A rectangle with a known bbox (x 200–420, y 380–520) far from the
  /// archetype's text slots — the object-actions suite's proven target.
  Map<String, dynamic> deckWithShape() {
    final deck = smoke.deckFixtureForProbe(2);
    final slide = (deck['slides'] as List)[0] as Map;
    slide['objects'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'rect1',
        'preset': 'rectangle',
        'x': 200.0,
        'y': 380.0,
        'w': 220.0,
        'h': 140.0,
        'rotation': 0.0,
        'opacity': 1.0,
        'locked': false,
        'fill': {'type': 'solid', 'color': 'C25E00'},
        'closed': true,
      },
    ];
    return deck;
  }

  Future<void> pumpEditor(WidgetTester tester,
      {Map<String, dynamic>? deck}) async {
    Bridge.testOverride = droppingEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: deck ?? deckWithShape())));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  DreamChoiceChip chip(WidgetTester tester, String kind) =>
      tester.widget(find.byKey(ValueKey('entrance_chip_$kind')))
          as DreamChoiceChip;

  /// Design-space -> logical position on the canvas (the ShapesLayer's own
  /// rect IS the stage's design frame).
  Offset Function(double, double) designToLogical(WidgetTester tester) {
    final rect = tester.getRect(find.byType(ShapesLayer));
    final scale = rect.width / 1280;
    return (dx, dy) => Offset(rect.left + dx * scale, rect.top + dy * scale);
  }

  testWidgets('nothing selected: one actionable hint, never filler',
      (tester) async {
    await pumpEditor(tester);
    await openTab(tester, 'Animations');
    expect(
        find.text('Select an object on the slide, then give it an entrance.'),
        findsOneWidget);
    expect(find.text('ENTERS BY'), findsNothing,
        reason: 'the chip strip waits for a selection');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting an object on the tab keeps the tab; picking Pop '
      'is one undo step and survives the engine drop', (tester) async {
    await pumpEditor(tester);
    await openTab(tester, 'Animations');
    final at = designToLogical(tester);
    // A plain tap on the rectangle: the selection drives the chips, and
    // the tab STAYS (it is the selection's face here).
    await tester.tapAt(at(310, 450));
    await tester.pumpAndSettle();
    expect(find.text('ENTERS BY'), findsOneWidget,
        reason: 'the selection brought the chip strip up');
    expect(chip(tester, 'none').selected, isTrue,
        reason: 'a plain object enters by nothing');

    final popChip = find.byKey(const ValueKey('entrance_chip_pop'));
    await tester.ensureVisible(popChip);
    await tester.pumpAndSettle();
    await tester.tap(popChip);
    await tester.pumpAndSettle();
    expect(chip(tester, 'pop').selected, isTrue);
    expect(find.text('1 animated'), findsOneWidget);

    // An engine round-trip drops the app-owned key — the carry holds it.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    // The added slide is current and has no objects — the hint reads again.
    expect(
        find.text('Select an object on the slide, then give it an entrance.'),
        findsOneWidget);
    // Back to slide 1 and reselect the rectangle: Pop survived.
    await tester.tap(find.text('1. Slide 1'));
    await tester.pumpAndSettle();
    await tester.tapAt(at(310, 450));
    await tester.pumpAndSettle();
    expect(chip(tester, 'pop').selected, isTrue,
        reason: 'the entrance survived the round-trip through the carry');

    // Undo: the add_slide first, then the Pop pick itself.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'pop').selected, isTrue,
        reason: 'undoing the add left the Pop pick alone');
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'none').selected, isTrue,
        reason: 'the Pop pick was one undo step');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Preview replays the build; with no entrances it says so',
      (tester) async {
    await pumpEditor(tester);
    await openTab(tester, 'Animations');
    // Nothing animated yet — the preview is honest about it.
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(
        find.text('No entrances on this slide yet — animate an object first.'),
        findsOneWidget);

    // Animate the rectangle, then preview: the clock runs and settles
    // cleanly (no exception, the row keeps its count).
    final at = designToLogical(tester);
    await tester.tapAt(at(310, 450));
    await tester.pumpAndSettle();
    final riseChip = find.byKey(const ValueKey('entrance_chip_rise'));
    await tester.ensureVisible(riseChip);
    await tester.pumpAndSettle();
    await tester.tap(riseChip);
    await tester.pumpAndSettle();
    expect(find.text('1 animated'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('1 animated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
