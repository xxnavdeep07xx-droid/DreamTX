import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/theme.dart';
import 'package:dreamtx/widgets/controls.dart';

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

  Map<String, dynamic> recordingEngine(Map<String, dynamic> req) {
    if (req['op'] == 'add_object' || req['op'] == 'update_object') {
      recordedObjectOps.add(Map<String, dynamic>.from(req));
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
    Bridge.testOverride = recordingEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: smoke.deckFixtureForProbe(3))));
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
    // The band collapsed on the pick; the compact swatch carries the pick.
    expect(find.byType(DreamColorChips), findsNothing);
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
    final wide = find.byWidgetPredicate(
        (w) => w is DreamChoiceChip && w.label == 'L');
    expect(wide, findsOneWidget);
    await tester.tap(wide);
    await tester.pumpAndSettle();
    expect(find.byType(DreamColorChips), findsNothing,
        reason: 'the pick collapses the band');
    await drawStroke(tester);
    expect((recordedObjectOps.last['shape'] as Map)['stroke']['width'], 16.0);
    expect(tester.takeException(), isNull);
  });
}
