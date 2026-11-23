import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/object_content.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/theme.dart';
import 'package:dreamtx/widgets/controls.dart';
import 'package:dreamtx/widgets/rich_doc.dart';
import 'package:dreamtx/widgets/shape_canvas.dart';

import 'smoke_test.dart' as smoke;

/// The Draw tab's toolbox (step B of the Draw design): the ribbon's Draw
/// row swaps the single freehand toggle for the toolbox — pen and
/// highlighter with their own defaults, the expandable palette band, the
/// tab state machine (arm on entry, disarm on leave, tap-the-armed-tool
/// to disarm inside Draw, the tool remembered across Draw <-> Insert),
/// and strokes committing exactly as the preview painted them (the step
/// A contract, now fed by the toolbox).
void main() {
  late Directory tmp;
  // The engine recorder: the fake engine plus a capture of every
  // add/update_object request — deck-level assertions read the exact
  // payloads the production engine would receive.
  final recordedObjectOps = <Map<String, dynamic>>[];
  final recordedDeletes = <Map<String, dynamic>>[];

  Map<String, dynamic> recordingEngine(Map<String, dynamic> req) {
    if (req['op'] == 'add_object' || req['op'] == 'update_object') {
      recordedObjectOps.add(Map<String, dynamic>.from(req));
    }
    if (req['op'] == 'delete_object') {
      recordedDeletes.add(Map<String, dynamic>.from(req));
    }
    return smoke.testFakeEngine(req);
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_draw');
    DeckStore.debugResetForTest();
    ResourceStore.debugResetForTest();
    smoke.mockStorageForInsert(tmp.path);
    ImagePickers.testOverride = null;
    recordedObjectOps.clear();
    recordedDeletes.clear();
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
    Bridge.testOverride = recordingEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: deck ?? smoke.deckFixtureForProbe(3))));
    await tester.pumpAndSettle();
  }

  /// A horizontal scribble at (x, 300), 200x40 — polyline at y=320.
  Map<String, dynamic> scribble(String id, {required double x}) =>
      <String, dynamic>{
        'id': id,
        'preset': 'path',
        'x': x,
        'y': 300.0,
        'w': 200.0,
        'h': 40.0,
        'rotation': 0.0,
        'opacity': 1.0,
        'locked': false,
        'fill': {'type': 'none'},
        'stroke': {
          'color': 'C25E00',
          'width': 8.0,
          'dash': 'solid',
          'start_arrow': 'none',
          'end_arrow': 'none'
        },
        'effects': <String, dynamic>{},
        'points': [
          {'x': 0.0, 'y': 0.5},
          {'x': 0.5, 'y': 0.5},
          {'x': 1.0, 'y': 0.5},
        ],
        'closed': false,
      };

  /// Slide 1 carries two scribbles (y 300-340) with a TEXT BOX between
  /// them in the same band — the eraser sweep must pass straight through
  /// the content and take only the ink.
  Map<String, dynamic> deckWithInk() {
    final deck = smoke.deckFixtureForProbe(1);
    final slide = (deck['slides'] as List)[0] as Map;
    slide['objects'] = <Map<String, dynamic>>[
      scribble('ink1', x: 400),
      <String, dynamic>{
        'id': 'tb1',
        'preset': 'rectangle',
        'x': 700.0,
        'y': 300.0,
        'w': 200.0,
        'h': 40.0,
        'rotation': 0.0,
        'opacity': 1.0,
        'locked': false,
        'fill': {'type': 'none'},
        'stroke': {
          'color': '17181A',
          'width': 0.0,
          'dash': 'solid',
          'start_arrow': 'none',
          'end_arrow': 'none'
        },
        'effects': <String, dynamic>{},
        'closed': true,
        'content': ObjectContent.text(RichDoc()..text = 'note'),
      },
      scribble('ink2', x: 1000),
    ];
    return deck;
  }

  /// Design-space -> logical position on the canvas: the [ShapesLayer]'s
  /// own rect IS the stage's design frame (the enclosing AspectRatio is
  /// the canvas CARD, not the frame — its rect carries the card's inset).
  Offset Function(double dx, double dy) designToLogical(
      WidgetTester tester) {
    final rect = tester.getRect(find.byType(ShapesLayer));
    final scale = rect.width / 1280;
    return (dx, dy) => Offset(rect.left + dx * scale, rect.top + dy * scale);
  }

  /// The eraser's signature sweep: from over ink1 (x 500), through the
  /// text box, to ink2 (x 1100) — all on the y=320 polyline band.
  Future<void> eraseSweep(WidgetTester tester) async {
    final at = designToLogical(tester);
    final g = await tester.startGesture(at(500, 320));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(46, 0)); // ~153 design px per step
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  /// A stroke across the canvas: pointer down at the canvas's mid-left,
  /// three curved moves (each far enough to survive the 6px design-space
  /// thinning), pointer up — the event stream a finger produces.
  Future<void> drawStroke(WidgetTester tester) async {
    final c = tester.getCenter(find.byType(AspectRatio));
    final g = await tester.startGesture(Offset(c.dx - 60, c.dy - 10));
    await g.moveBy(const Offset(30, 6));
    await g.moveBy(const Offset(12, 28));
    await g.moveBy(const Offset(28, -12));
    await g.up();
    await tester.pumpAndSettle();
  }

  Icon penIcon(WidgetTester tester) => tester.widget<Icon>(find.descendant(
      of: find.byTooltip('Pen'), matching: find.byIcon(Icons.edit)));

  Icon hlIcon(WidgetTester tester) => tester.widget<Icon>(find.descendant(
      of: find.byTooltip('Highlighter'),
      matching: find.byIcon(Icons.highlight)));

  Icon erIcon(WidgetTester tester) => tester.widget<Icon>(find.descendant(
      of: find.byTooltip('Eraser'),
      matching: find.byIcon(Icons.backspace_outlined)));

  /// The palette band's cross-fade state — the honest observable for the
  /// band's expansion (the faded-out child stays mounted in the tree, so
  /// finders can't be used for this).
  CrossFadeState bandState(WidgetTester tester) =>
      tester.widget<AnimatedCrossFade>(
          find.byKey(const ValueKey('draw_palette_band'))).crossFadeState;

  testWidgets('entering Draw arms the pen and swaps the toggle for the toolbox',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    // The old single-button row is gone; the toolbox renders and the PEN
    // is armed on entry (its icon lit).
    expect(find.byTooltip('Freehand draw'), findsNothing,
        reason: 'the old single-button row is gone');
    expect(find.byTooltip('Pen'), findsOneWidget);
    expect(find.byTooltip('Highlighter'), findsOneWidget);
    expect(penIcon(tester).color, kText, reason: 'the pen is armed');
    expect(hlIcon(tester).color, kText2, reason: 'the highlighter is not');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pen stroke commits in the preview exact style, no auto-select',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await drawStroke(tester);
    // The stroke landed: exactly one add_object, in the armed tool's
    // style — the DNA accent (the fake resolve_dna answers C25E00),
    // width 8, opacity 1.0, the pipeline's smoothed normalized points.
    expect(recordedObjectOps, hasLength(1));
    expect(recordedObjectOps.last['slide_id'], 's1');
    final shape = recordedObjectOps.last['shape'] as Map;
    expect(shape['preset'], 'path');
    expect(shape['closed'], false);
    expect(shape['opacity'], 1.0);
    expect((shape['stroke'] as Map)['color'], 'C25E00');
    expect((shape['stroke'] as Map)['width'], 8.0);
    final pts = shape['points'] as List;
    expect(pts.length, greaterThanOrEqualTo(2));
    for (final p in pts.whereType<Map>()) {
      expect((p['x'] as num), inInclusiveRange(0, 1));
      expect((p['y'] as num), inInclusiveRange(0, 1));
    }
    // NOT auto-selected: the Draw tab stays put (the toolbox still
    // renders — a selection would have flipped the ribbon to Insert's
    // object panel and replaced the band).
    expect(find.byTooltip('Pen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the highlighter: its own color, width and translucency',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Highlighter'));
    await tester.pumpAndSettle();
    expect(hlIcon(tester).color, kText, reason: 'armed');
    await drawStroke(tester);
    expect(recordedObjectOps, hasLength(1));
    final shape = recordedObjectOps.last['shape'] as Map;
    expect((shape['stroke'] as Map)['color'], 'FFD400');
    expect((shape['stroke'] as Map)['width'], 28.0);
    expect(shape['opacity'], 0.35,
        reason: 'the translucency rides the object opacity the exporters '
            'already multiply into stroke color');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the armed tool disarms — the canvas stops inking',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Highlighter'));
    await tester.pumpAndSettle();
    // Tap the ARMED highlighter again: disarm (select mode inside Draw).
    await tester.tap(find.byTooltip('Highlighter'));
    await tester.pumpAndSettle();
    expect(hlIcon(tester).color, kText2, reason: 'the highlighter disarmed');
    expect(penIcon(tester).color, kText2);
    // A canvas drag now selects/drags instead of inking: no stroke op.
    await drawStroke(tester);
    expect(recordedObjectOps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Draw <-> Insert: disarm on leave, arm on return, tool remembered',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Highlighter'));
    await tester.pumpAndSettle();
    // Insert: the sheet drawer opens, the toolbox disarms (its row is
    // replaced by the drawer's surface).
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pen'), findsNothing);
    expect(find.byKey(const ValueKey('insert_drawer')), findsOneWidget);
    // Back to Draw: armed again, and the HIGHLIGHTER is remembered.
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(hlIcon(tester).color, kText,
        reason: 're-armed with the remembered tool');
    expect(find.byKey(const ValueKey('insert_drawer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the palette band: open, pick a color, collapse, ink in it',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    // Open the band from the compact color chip.
    await tester.tap(find.byTooltip('Pen color'));
    await tester.pumpAndSettle();
    expect(bandState(tester), CrossFadeState.showSecond);
    expect(find.byType(DreamColorChips), findsOneWidget);
    expect(find.byType(DreamChoiceChip), findsNWidgets(3),
        reason: 'the pen width presets S/M/L ride the band');
    // The deck's muted gray (resolve_dna's `muted` — index 3, visible in
    // the band's first screenful, and unique in the palette: the studio
    // swatches carry no 6B6E76).
    final muted = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final d = w.decoration;
      return d is BoxDecoration && d.color == const Color(0xFF6B6E76);
    });
    expect(muted, findsOneWidget);
    await tester.tap(muted);
    await tester.pumpAndSettle();
    // The band collapsed on the pick.
    expect(bandState(tester), CrossFadeState.showFirst);
    // The pen inks in the picked color now.
    await drawStroke(tester);
    expect(recordedObjectOps, hasLength(1));
    expect((recordedObjectOps.last['shape'] as Map)['stroke']['color'],
        '6B6E76');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pen width presets: S/M/L swap the committed width',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pen color'));
    await tester.pumpAndSettle();
    expect(bandState(tester), CrossFadeState.showSecond);
    final wide = find.byWidgetPredicate(
        (w) => w is DreamChoiceChip && w.label == 'L');
    expect(wide, findsOneWidget);
    await tester.tap(wide);
    await tester.pumpAndSettle();
    expect(bandState(tester), CrossFadeState.showFirst,
        reason: 'the pick collapses the band');
    await drawStroke(tester);
    expect((recordedObjectOps.last['shape'] as Map)['stroke']['width'], 16.0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('the eraser: sweeps scribbles only, content is immune, deletes fire on release', (tester) async {
    await pumpEditor(tester, deck: deckWithInk());
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eraser'));
    await tester.pumpAndSettle();
    expect(erIcon(tester).color, kText, reason: 'the eraser is armed');
    // The eraser has no settings: the color/width chips are hidden.
    expect(find.byTooltip('Pen color'), findsNothing);

    final at = designToLogical(tester);
    final g = await tester.startGesture(at(500, 320));
    await g.moveBy(const Offset(46, 0));
    await g.moveBy(const Offset(46, 0));
    // Mid-sweep: nothing is deleted yet — the batch fires on pointer-up.
    expect(recordedDeletes, isEmpty,
        reason: 'the layer only marks; the deletes wait for release');
    await g.moveBy(const Offset(46, 0));
    await g.moveBy(const Offset(46, 0));
    await g.up();
    await tester.pumpAndSettle();

    // Exactly the two scribbles — the text box the sweep passed THROUGH
    // (same y band, x 700..900) is untouched.
    expect(recordedDeletes, hasLength(2));
    final ids = recordedDeletes.map((d) => d['object_id']).toList();
    expect(ids, containsAll(['ink1', 'ink2']));
    expect(ids, isNot(contains('tb1')));
    expect(recordedDeletes.first['slide_id'], 's1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the eraser: one undo step restores the whole sweep', (tester) async {
    await pumpEditor(tester, deck: deckWithInk());
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eraser'));
    await tester.pumpAndSettle();
    await eraseSweep(tester);
    expect(recordedDeletes, hasLength(2));

    // ONE undo (a single deck snapshot for the whole sweep) brings both
    // scribbles back — proven by erasing them both again.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    await eraseSweep(tester);
    expect(recordedDeletes, hasLength(4),
        reason: 'both scribbles were restored by the single undo');
    expect(
        recordedDeletes.map((d) => d['object_id']).where((id) => id == 'ink1'),
        hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the eraser: a stationary tap on a scribble erases it', (tester) async {
    await pumpEditor(tester, deck: deckWithInk());
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eraser'));
    await tester.pumpAndSettle();
    // Tap straight onto ink1's polyline (y=320).
    final at = designToLogical(tester);
    await tester.tapAt(at(500, 320));
    await tester.pumpAndSettle();
    expect(recordedDeletes, hasLength(1));
    expect(recordedDeletes.first['object_id'], 'ink1');
    expect(tester.takeException(), isNull);
  });
}
