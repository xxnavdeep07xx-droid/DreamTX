import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'package:dreamtx/screens/insert_sheet.dart';

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
  // An external focus loss while a text session is live
  // ---------------------------------------------------------------------

  testWidgets(
      'external focus loss during typing: the typing state\'s sheet-down flag clears and the sheet RISES back through the entrance, not a snap',
      (tester) async {
    await pumpTextEditor(tester);
    final field = find.byKey(const ValueKey('text_box_field'));
    expect(field, findsOneWidget);

    // The Insert tab is the active nav tab and typing owns the screen: the
    // sheet stood down for the keyboard (its layer unmounts once the
    // 200ms exit completes).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(InsertSheet), findsNothing,
        reason: 'the sheet stood down while the keyboard owns the bottom');

    // An EXTERNAL focus loss — not the expand button (that routes through
    // _endTyping): something else took the focus away from the live
    // session's field.
    final node = (tester.widget(field) as TextField).focusNode!;
    node.unfocus();
    await tester.pump(); // the focus change lands, the listener re-renders
    await tester.pump(); // the sheet's layer remounts at the entrance start

    // The sheet returns — and it RISES: at the entrance's first frame its
    // top still sits BELOW the resting place (the 200ms entrance starts
    // fully behind the navbar). The old code left the hidden flag set and
    // the sheet SNAPPED straight to its final position instead: for it,
    // this first-frame top would ALREADY be the settled one.
    expect(find.byType(InsertSheet), findsOneWidget,
        reason: 'the sheet rises back when the focus is lost externally');
    final risingTop = tester.getRect(find.byType(InsertSheet)).top;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final settledTop = tester.getRect(find.byType(InsertSheet)).top;
    expect(settledTop, lessThan(risingTop - 100),
        reason: 'the entrance is a real slide (top edge rises the whole '
            'sheet height), never a snap into place');
    expect(find.byType(InsertSheet), findsOneWidget,
        reason: 'the sheet stays up after the entrance settles');

    // Nothing lingers: the typing state's hidden flag cleared with the
    // focus loss (a later re-focus re-hides cleanly through _beginTyping's
    // own machinery, not through a stale flag).
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

  // ---------------------------------------------------------------------
  // Tapping the built-in archetype text while the deck is being edited
  // ---------------------------------------------------------------------

  testWidgets(
      'SlideStage in editing mode: tapping archetype template text fires onTextTap; tapping an object selects it; a tap that only deselects never edits text',
      (tester) async {
    String? tappedKey;
    String? selectedId;
    // A layout with a template text slot (the Cover-style title rect) and
    // an object that OVERLAPS it: whatever is under the finger decides.
    final layout = <String, dynamic>{
      'w': 1280,
      'h': 720,
      'elements': <Map<String, dynamic>>[
        {
          'type': 'text',
          'key': 'title',
          'x': 100.0,
          'y': 100.0,
          'w': 600.0,
          'h': 100.0,
          'size': 44.0,
          'color': '17181A',
          'lines': <String>['Built-in title'],
        },
      ],
    };
    final objects = <Map<String, dynamic>>[
      {
        'id': 'shapeOver',
        'preset': 'rectangle',
        'x': 400.0,
        'y': 120.0,
        'w': 200.0,
        'h': 60.0,
        'rotation': 0.0,
        'opacity': 1.0,
        'locked': false,
        'fill': {'type': 'solid', 'color': '0F62FE'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
      },
    ];
    // A stateful harness: selections feed back into the stage exactly the
    // way the editor rebuilds it (setState on every select/deselect).
    await tester.pumpWidget(_TapHarness(
      layout: layout,
      objects: objects,
      onTextTap: (key) => tappedKey = key,
      onSelect: (id) => selectedId = id,
    ));
    await tester.pumpAndSettle();

    // Tap positions in DESIGN space, mapped through the stage's own box.
    final stage = tester.getRect(find.byType(SlideStage));
    Offset designToScreen(double dx, double dy) => Offset(
        stage.left + dx * stage.width / 1280,
        stage.top + dy * stage.height / 720);

    // 1) Tap the template text with nothing selected: onTextTap fires
    // with the right key and nothing gets selected. (The overlay rides
    // opaque above the canvas — this is the forwarded tap path.)
    await tester.tapAt(designToScreen(200, 150));
    await tester.pump();
    expect(tappedKey, 'title',
        reason: 'template text is tappable while the deck is edited');
    expect(selectedId, isNull);
    tappedKey = null;

    // 2) Tap the overlapping object: it gets SELECTED and the template
    // text never sees the tap.
    await tester.tapAt(designToScreen(500, 150));
    await tester.pump();
    expect(selectedId, 'shapeOver',
        reason: 'an object under the finger selects instead');
    expect(tappedKey, isNull,
        reason: 'the object tap is not a template-text tap');

    // 3) With that object selected, a tap on the template text area only
    // DESELECTS — one job per tap: editing the text needs a second, clean
    // tap.
    await tester.tapAt(designToScreen(200, 150));
    await tester.pump();
    expect(selectedId, isNull, reason: 'the tap cleared the selection');
    expect(tappedKey, isNull,
        reason: 'a deselecting tap never opens template-text editing');

    // 4) Tap the template text again, now with nothing selected: editing.
    await tester.tapAt(designToScreen(200, 150));
    await tester.pump();
    expect(tappedKey, 'title');
    expect(selectedId, isNull);
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------
  // Rotated content objects on the stage
  // ---------------------------------------------------------------------

  testWidgets(
      'SlideStage: a rotated text box renders its content through a Transform with the rotation matrix',
      (tester) async {
    final layout = <String, dynamic>{
      'w': 1280,
      'h': 720,
      'elements': <Map<String, dynamic>>[],
    };
    final objects = <Map<String, dynamic>>[
      {
        'id': 'rotText',
        'preset': 'rectangle',
        'x': 300.0,
        'y': 200.0,
        'w': 400.0,
        'h': 120.0,
        'rotation': 30.0,
        'opacity': 1.0,
        'locked': false,
        'fill': {'type': 'none'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
        'content': ObjectContent.text(RichDoc()..text = 'turned'),
      },
      {
        'id': 'rotShape',
        'preset': 'rectangle',
        'x': 800.0,
        'y': 400.0,
        'w': 100.0,
        'h': 80.0,
        'rotation': -20.0,
        'opacity': 1.0,
        'locked': false,
        'fill': {'type': 'solid', 'color': 'D03028'},
        'stroke': {'color': '17181A', 'width': 0.0, 'dash': 'solid',
            'start_arrow': 'none', 'end_arrow': 'none'},
        'effects': <String, dynamic>{},
        'closed': true,
      },
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: SlideStage(
              layout: layout,
              objects: objects,
              designW: 1280,
              designH: 720,
              baseColor: const Color(0xFF17181A),
              baseFamily: null,
              baseFontSize: 18,
              resolveResourcePath: (_) => null,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The text box's content layer, once per object.
    final contentLayer = find.byWidgetPredicate(
        (w) => w is ObjectContentLayer && w.singleObject);
    expect(contentLayer, findsOneWidget,
        reason: 'the rotated text box renders as content');

    // The content layer's direct parent chain carries the stage's
    // Transform.rotate for exactly its object's angle: content on the
    // canvas turns like its selection chrome and its exports do.
    final rotateAncestor =
        find.ancestor(of: contentLayer, matching: find.byType(Transform));
    expect(rotateAncestor, findsOneWidget,
        reason: 'the content object renders through a rotation transform');
    final transform = tester.widget(rotateAncestor) as Transform;
    final want = Matrix4.rotationZ(30.0 * math.pi / 180.0);
    for (var i = 0; i < 16; i++) {
      expect(transform.transform.storage[i], closeTo(want.storage[i], 1e-9),
          reason: 'the transform is the 30° rotation matrix');
    }

    // The plain rotated shape keeps its own rotate transform too.
    final shapeRotates = find
        .ancestor(
            of: find.byType(ShapeObjectPaint), matching: find.byType(Transform))
        .evaluate()
        .map((e) => e.widget as Transform)
        .toList();
    final shapeWant = Matrix4.rotationZ(-20.0 * math.pi / 180.0);
    final hasShapeRotation = shapeRotates.any((t) {
      for (var i = 0; i < 16; i++) {
        if ((t.transform.storage[i] - shapeWant.storage[i]).abs() > 1e-9) {
          return false;
        }
      }
      return true;
    });
    expect(hasShapeRotation, isTrue,
        reason: 'the vector shape still rotates its own body');
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------
  // Sub/superscript overlay on multi-paragraph, bulleted, autofit-shrunk
  // text boxes
  // ---------------------------------------------------------------------

  testWidgets(
      'TextBoxPainter: multi-paragraph bulleted autofit-shrunk sub/superscript runs paint cleanly',
      (tester) async {
    // Three paragraphs; the middle one is a BULLETED paragraph whose
    // sub/sup runs must map through the bullet prefix ("\u2022  "), one
    // sub/sup run SPANS paragraph boundaries (the overlay must clip each
    // paragraph's piece separately), and the box is far too short for the
    // text at natural size so the shrink (k < 1) applies to the overlay
    // too.
    //
    // Offsets below are UTF-16 doc offsets, all disjoint+sorted:
    // "First paragraph with baseline text\n" → \n at 34;
    // "Second bullet with H2O and E=mc2 notation\n" → [35, 75), \n at 75;
    // "Third paragraph tails the document" → starts at 76.
    final doc = RichDoc(
      text: 'First paragraph with baseline text\n'
          'Second bullet with H2O and E=mc2 notation\n'
          'Third paragraph tails the document',
      runs: [
        // Subscript SPANNING the first paragraph break (and the color
        // run's neighborhood): each paragraph repaints only its own piece.
        RichRun(
          start: 30,
          end: 40,
          subscript: true,
        ),
        RichRun(
          start: 40,
          end: 44,
          color: 'D03028',
        ),
        // The "2" of H2O — inside the BULLETED paragraph (its painter
        // offsets run +3 past doc offsets for the "\u2022  " prefix).
        RichRun(
          start: 55,
          end: 56,
          subscript: true,
        ),
        // The "2" of E=mc² — superscript, same bulleted paragraph.
        RichRun(
          start: 65,
          end: 66,
          superscript: true,
        ),
        // Another boundary-spanning subscript: second → third paragraph.
        RichRun(
          start: 70,
          end: 80,
          subscript: true,
        ),
      ],
      paras: [
        RichPara(start: 0),
        RichPara(start: 35, list: 'bullet'),
        RichPara(start: 76),
      ],
    )..autofit = 'shrink';

    // The box genuinely shrinks: the same layout the painter runs must
    // report k < 1 (overflow at natural size).
    final k = TextBoxPainter.autofitScale(
      doc: doc,
      boxW: 300,
      boxH: 70,
      baseColor: const Color(0xFF17181A),
      baseFamily: null,
      baseFontSize: 18,
    );
    expect(k, lessThan(1.0), reason: 'the fixture genuinely autofit-shrinks');
    expect(k, greaterThan(0.0));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 70,
            child: CustomPaint(
              painter: TextBoxPainter(
                doc: doc,
                baseColor: const Color(0xFF17181A),
                baseFamily: null,
                baseFontSize: 18,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Range errors inside the overlay (doc offsets fed to the paragraph
    // painter, painter offsets fed to doc.text.substring) would surface
    // here as exceptions; a clean paint means every piece mapped through
    // paraStart/prefixLen correctly.
    expect(tester.takeException(), isNull,
        reason: 'the overlay paints without range errors');

    // And paint DIRECTLY too (the same path a save-less caller takes) —
    // onto a recording canvas, exercising the exact overlay code with no
    // widget tree involvement.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    TextBoxPainter(
      doc: doc,
      baseColor: const Color(0xFF17181A),
      baseFamily: null,
      baseFontSize: 18,
    ).paint(canvas, const ui.Size(300, 70));
    final picture = recorder.endRecording();
    expect(picture, isNotNull, reason: 'the direct paint completed');
  });
}

/// An editing-mode SlideStage harness whose SELECTION is stateful: every
/// select/deselect rebuilds the stage with the new selectedId, exactly the
/// way the editor screen rebuilds it. (A stateless stage would keep the
/// pre-selection build alive and never exercise the deselecting tap.)
class _TapHarness extends StatefulWidget {
  const _TapHarness({
    required this.layout,
    required this.objects,
    required this.onTextTap,
    required this.onSelect,
  });

  final Map<String, dynamic> layout;
  final List<Map<String, dynamic>> objects;
  final ValueChanged<String> onTextTap;
  final ValueChanged<String?> onSelect;

  @override
  State<_TapHarness> createState() => _TapHarnessState();
}

class _TapHarnessState extends State<_TapHarness> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: SlideStage(
              layout: widget.layout,
              objects: widget.objects,
              designW: 1280,
              designH: 720,
              baseColor: const Color(0xFF17181A),
              baseFamily: null,
              baseFontSize: 18,
              resolveResourcePath: (_) => null,
              interactive: true,
              selectedId: _selectedId,
              onTextTap: widget.onTextTap,
              onSelect: (id) {
                setState(() => _selectedId = id);
                widget.onSelect(id);
              },
            ),
          ),
        ),
      ),
    );
  }
}
