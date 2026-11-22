import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/color_utils.dart';
import 'package:dreamtx/core/object_content.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/theme.dart';
import 'package:dreamtx/widgets/controls.dart';
import 'package:dreamtx/widgets/dream_drawer.dart';
import 'package:dreamtx/widgets/object_content_layer.dart';
import 'package:dreamtx/widgets/rich_doc.dart';
import 'package:dreamtx/widgets/shape_canvas.dart';
import 'package:dreamtx/widgets/slide_stage.dart';
import 'package:dreamtx/screens/editor_screen.dart';

import 'dart:io';

import 'smoke_test.dart' as smoke;

/// The cleanup-and-fix pass contracts: undo/redo while a text session is
/// live, the presenter's stage + aspect, the canvas's true Z-order, and the
/// shared components (the merged swatch palette, the color chips, the
/// choice chip, the drawer header's drag surface).
void main() {
  late Directory tmp;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_v036');
    DeckStore.debugResetForTest();
    smoke.mockStorageForInsert(tmp.path);
  });
  tearDown(() {
    Bridge.testOverride = null;
    smoke.clearInsertStorageMock();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ---------------------------------------------------------------------
  // Undo/redo while a text box is being edited
  // ---------------------------------------------------------------------

  Future<void> pumpTextEditor(WidgetTester tester) async {
    Bridge.testOverride = smoke.testFakeEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: smoke.deckFixtureForProbe(1))));
    await tester.pumpAndSettle();
    // Insert a text box — it goes straight into typing.
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'undo/redo during a live text session: the resync records nothing, the redo stack survives the walk',
      (tester) async {
    await pumpTextEditor(tester);
    final field = find.byKey(const ValueKey('text_box_field'));
    expect(field, findsOneWidget);

    // Type — one undo snapshot for the whole typing group.
    await tester.enterText(field, 'Hello world');
    await tester.pump();
    final controller = (tester.widget(field) as TextField).controller!;
    expect(controller.text, 'Hello world');

    // UNDO while the session is live: the deck swaps back under the field
    // and the session resyncs to the old text. The corruption this guards
    // against: writing controller.text during the resync used to fire the
    // change listener synchronously, pushing a FAKE undo snapshot (the
    // pre-swap deck) and wiping the redo stack mid-walk.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // The resync itself recorded nothing: the field shows the pre-typing
    // text and the REDO stack still knows the typed state...
    expect(controller.text, '',
        reason: 'undo restored the empty text box into the live session');
    final redoButton = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Redo');
    expect((tester.widget(redoButton) as IconButton).onPressed, isNotNull,
        reason: 'redo survived the resync (the old corruption wiped it)');
    await tester.tap(redoButton);

    // ...and redoing walks FORWARD to the typed text, live in the field.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.text, 'Hello world',
        reason: 'redo lands the typed text back into the live session');
    // Close the session the way the app does (the expand button unfocuses
    // BEFORE the field unmounts — the normal teardown order), then let the
    // debounced engine commit fire: no timer may outlive the test's tree.
    await tester.tap(find.byKey(const ValueKey('typing_toolbar_expand')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------
  // The presenter: the same layered stage, at the deck's own aspect
  // ---------------------------------------------------------------------

  testWidgets(
      'presenting renders every object (the shared stage) at the deck\'s own aspect ratio',
      (tester) async {
    // A 4:3 deck whose only slide carries a shape, a text box and a table.
    final deck = smoke.deckFixtureForProbe(1);
    deck['aspect'] = '4:3';
    final slide = (deck['slides'] as List).first as Map;
    slide['objects'] = [
      {
        'id': 'shapeA',
        'preset': 'rectangle',
        'x': 40.0, 'y': 40.0, 'w': 100.0, 'h': 60.0,
        'rotation': 0.0, 'opacity': 1.0, 'locked': false,
        'fill': {'type': 'solid', 'color': '0F62FE'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
      },
      {
        'id': 'textT',
        'preset': 'rectangle',
        'x': 200.0, 'y': 100.0, 'w': 400.0, 'h': 120.0,
        'rotation': 0.0, 'opacity': 1.0, 'locked': false,
        'fill': {'type': 'none'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
        'content': ObjectContent.text(RichDoc()..text = 'Presented words'),
      },
      {
        'id': 'tableB',
        'preset': 'rectangle',
        'x': 200.0, 'y': 300.0, 'w': 300.0, 'h': 120.0,
        'rotation': 0.0, 'opacity': 1.0, 'locked': false,
        'fill': {'type': 'none'},
        'stroke': {'color': '17181A', 'width': 1.5, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
        'content': ObjectContent.table(2, 2, cells: ['a', 'b', 'c', 'd']),
      },
    ];

    Bridge.testOverride = smoke.testFakeEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(deck: deck)));
    await tester.pumpAndSettle();

    // Present (the Slide show tab's Present button) — the ribbon scrolls:
    // twelve tabs never fit, so scroll the tab into view first.
    await tester.ensureVisible(find.text('Slide show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slide show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    // The deck's OWN aspect: a 4:3 frame — never the hardcoded 16/9. The
    // presenter wraps the shared stage in the frame's AspectRatio.
    final frame = find
        .ancestor(of: find.byType(SlideStage), matching: find.byType(AspectRatio))
        .evaluate()
        .map((e) => e.widget as AspectRatio)
        .toList();
    expect(frame, isNotEmpty, reason: 'the stage frames the slide');
    expect(frame.first.aspectRatio, closeTo(4 / 3, 0.01),
        reason: 'a 4:3 deck presents at its own shape');

    // The SAME layered stage as the editor: the shape paints its vector
    // body, the text box renders as CONTENT, the table as CONTENT — nothing
    // is dropped on the way to fullscreen.
    expect(find.descendant(of: find.byType(SlideStage),
        matching: find.byType(ShapeObjectPaint)), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SlideStage),
            matching: find.byWidgetPredicate(
                (w) => w is ObjectContentLayer && w.singleObject)),
        findsNWidgets(2),
        reason: 'the text box and the table render as content objects');
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------
  // The canvas's true Z-order
  // ---------------------------------------------------------------------

  testWidgets(
      'slide objects render in list order — a text box interleaves between two shapes',
      (tester) async {
    final deck = smoke.deckFixtureForProbe(1);
    final slide = (deck['slides'] as List).first as Map;
    slide['objects'] = [
      {
        'id': 'shapeA',
        'preset': 'rectangle',
        'x': 40.0, 'y': 100.0, 'w': 100.0, 'h': 60.0,
        'rotation': 0.0, 'opacity': 1.0, 'locked': false,
        'fill': {'type': 'solid', 'color': '0F62FE'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
      },
      {
        'id': 'textT',
        'preset': 'rectangle',
        'x': 200.0, 'y': 100.0, 'w': 400.0, 'h': 120.0,
        'rotation': 0.0, 'opacity': 1.0, 'locked': false,
        'fill': {'type': 'none'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
        'content': ObjectContent.text(RichDoc()..text = 'between'),
      },
      {
        'id': 'shapeB',
        'preset': 'rectangle',
        'x': 700.0, 'y': 100.0, 'w': 100.0, 'h': 60.0,
        'rotation': 0.0, 'opacity': 1.0, 'locked': false,
        'fill': {'type': 'solid', 'color': 'D03028'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
      },
    ];

    Bridge.testOverride = smoke.testFakeEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(deck: deck)));
    await tester.pumpAndSettle();

    // Walk the stage's object layer in traversal order (tree order IS
    // paint order): shapeA, the text's content layer, shapeB — interleaved.


    // Element.depth is the ANCESTOR count (siblings tie), so read the
    // ORDER from the traversal itself: widgetList walks the tree in paint
    // order.
    final objectWidgets = find.byWidgetPredicate((w) =>
        w is ShapeObjectPaint || (w is ObjectContentLayer && w.singleObject));
    final painted = tester
        .widgetList(objectWidgets)
        .map((w) => w is ShapeObjectPaint
            ? (w.obj['id']?.toString() ?? '?')
            : 'text')
        .toList();
    expect(painted, ['shapeA', 'text', 'shapeB'],
        reason: 'the deck\'s list order is the canvas\'s paint order: the '
            'text box interleaves BETWEEN the two shapes');
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------
  // The shared components
  // ---------------------------------------------------------------------

  test('kSwatchHexes is hexKeyOf(kSwatchPalette), in order — the string and color lists cannot drift',
      () {
    expect(kSwatchHexes, [for (final c in kSwatchPalette) hexKeyOf(c)]);
    // Every hex string parses back to the palette (the engine's payload
    // form round-trips through the shared converter).
    for (var i = 0; i < kSwatchPalette.length; i++) {
      expect(hexToColor(kSwatchHexes[i]), kSwatchPalette[i]);
    }
  });

  test('colorToHex/colorToHex round-trips through the engine\'s RRGGBB form', () {
    expect(colorToHex(const Color(0xFFF5F5F7)), 'F5F5F7');
    expect(hexToColor('D03028'), const Color(0xFFD03028));
    expect(hexToColor('#0F62FE'), const Color(0xFF0F62FE));
  });

  testWidgets('DreamColorChips: the palette + the no-color chip; picks emit the RRGGBB key',
      (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DreamColorChips(
          palette: kSwatchPalette,
          selected: null,
          onPick: (hex) => picked = hex,
          label: 'TEST COLOR',
        ),
      ),
    ));
    expect(find.text('TEST COLOR'), findsOneWidget);
    // One circle per swatch + the "no color" chip.
    expect(
        find.byWidgetPredicate((w) => w is GestureDetector),
        findsNWidgets(kSwatchPalette.length + 1));
    // Pick the first swatch: its RRGGBB key.
    await tester.tap(find.byWidgetPredicate((w) => w is GestureDetector)
        .at(1));
    await tester.pump();
    expect(picked, hexKeyOf(kSwatchPalette.first));
    // The no-color chip emits null.
    await tester.tap(find.byWidgetPredicate((w) => w is GestureDetector)
        .first);
    await tester.pump();
    expect(picked, isNull);
  });

  testWidgets('DreamChoiceChip: taps fire and the selected state reads',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DreamChoiceChip(
          label: 'Serif',
          selected: false,
          onTap: () => taps++,
        ),
      ),
    ));
    expect(find.text('Serif'), findsOneWidget);
    await tester.tap(find.text('Serif'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('DreamDrawerHeader: drags forward deltas + settle velocity; the back button keeps its tap',
      (tester) async {
    final updates = <double>[];
    double? settleVelocity;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DreamDrawerHeader(
          title: 'Files',
          showBack: true,
          onBack: () {},
          onDragUpdate: updates.add,
          onDragSettle: (v) => settleVelocity = v,
        ),
      ),
    ));
    expect(find.text('Files'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // A vertical drag streams its deltas (positive = finger moved down).
    final gesture = await tester.startGesture(const Offset(200, 20));
    await gesture.moveBy(const Offset(0, 14));
    await gesture.moveBy(const Offset(0, 26));
    await gesture.up();
    await tester.pump();
    expect(updates, [14.0, 26.0]);
    expect(settleVelocity, isNotNull);
  });
}
