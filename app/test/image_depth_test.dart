// Image depth (roadmap #11, wave 1 step 5): crop ratios, shape masks,
// brightness/contrast, alt text, replace, orphan sweep and the renderer.
//
// The flow is driven through the editor UI where it is visible (the ratio
// row, the shape chips, a drag, the alt field); when a payload needs
// reading, a cheap probe edit's request deck carries the live one.
import 'dart:convert';
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

void main() {
  late Directory tmp;
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
    tmp = Directory.systemTemp.createTempSync('dreamtx_imagedepth');
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

  /// The deck-scope library the Deck Resources sheet lists from. Written
  /// BEFORE the sheet opens — `ResourceStore.list` reads only the index.
  void writeDeckLibrary() {
    final scope = '${tmp.path}/resources/decks/d1';
    Directory(scope).createSync(recursive: true);
    File('$scope/photo.png').writeAsBytesSync(_tinyPng);
    File('$scope/img2.png').writeAsBytesSync(_tinyPng);
    File('$scope/library.json').writeAsStringSync(jsonEncode([
      {
        'id': 'img1',
        'name': 'photo.png',
        'file': 'photo.png',
        'mime': 'image/png',
        'w': 10,
        'h': 10
      },
      {
        'id': 'img2',
        'name': 'photo2.png',
        'file': 'img2.png',
        'mime': 'image/png',
        'w': 10,
        'h': 10
      },
    ]));
  }

  /// Insert → Image → Deck Resources → pick → the image panel is open
  /// (the Frame tab, proven by the crop row on it).
  Future<void> insertImage(WidgetTester tester) async {
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_image_sources')), findsOneWidget);
    writeDeckLibrary();
    await tester.tap(find.text('Deck Resources'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('photo.png'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_object_panel')), findsOneWidget,
        reason: 'the image panel opens on selection');
    expect(find.byKey(const ValueKey('crop_ratio_1_1')), findsOneWidget,
        reason: 'the crop row is on the image panel');
  }

  /// A cheap style edit whose request carries the live deck.
  Future<void> probeDeck(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Hairline'));
    await tester.tap(find.text('Hairline'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  }

  Map<String, dynamic> lastDeck() =>
      recordedObjectOps.lastOrNull?['deck'] as Map<String, dynamic>? ?? {};

  String? imageId(Map<String, dynamic> deck) {
    final meta = deck['imageMeta'];
    if (meta is! Map || meta.isEmpty) return null;
    return meta.keys.first as String;
  }

  /// The crop row changes the object's FRAME (the engine's cover fit does
  /// the center-crop) — an engine-level edit, one undo step.
  testWidgets('image panel: a ratio chip resizes the frame', (tester) async {
    await pumpEditor(tester);
    await insertImage(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('crop_ratio_16_9')));
    await tester.tap(find.byKey(const ValueKey('crop_ratio_16_9')));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final shape =
        recordedObjectOps.lastOrNull?['shape'] as Map<String, dynamic>?;
    expect(shape?['w'], 480, reason: 'the frame keeps its width');
    expect(shape?['h'], 270, reason: 'h follows w for 16:9');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(DreamChoiceChip, '16:9');
    expect((chip.evaluate().first.widget as DreamChoiceChip).selected, isFalse,
        reason: 'undo walks the ratio back');
  });

  /// The shape chips are the mask contract; read the payload, not pixels.
  testWidgets('image panel: shape chips write the mask into imageMeta',
      (tester) async {
    await pumpEditor(tester);
    await insertImage(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('crop_shape_circle')));
    await tester.tap(find.byKey(const ValueKey('crop_shape_circle')));
    await tester.pumpAndSettle();
    await probeDeck(tester);

    final deck = lastDeck();
    final meta = deck['imageMeta'];
    expect(meta, isNotNull, reason: 'imageMeta is on the wire');
    expect((meta as Map)[imageId(deck)!]['shape'], 'circle');

    // Two undo steps: the probe edit, then the chip itself.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(DreamChoiceChip, 'Circle');
    expect((chip.evaluate().first.widget as DreamChoiceChip).selected, isFalse,
        reason: 'undo walks the mask back');
  });

  /// Brightness/contrast commit on release, not per tick.
  testWidgets('image panel: the adjust sliders commit on release',
      (tester) async {
    await pumpEditor(tester);
    await insertImage(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('img_brightness')));
    await tester.drag(
        find.byKey(const ValueKey('img_brightness')), const Offset(48, 0));
    await tester.pumpAndSettle();

    // The commit is app-owned (local _mutate, like sections) — read it
    // off the probe's request deck, which carries the live one.
    await probeDeck(tester);
    final deck = lastDeck();
    final meta = deck['imageMeta'];
    expect(meta, isNotNull, reason: 'the commit landed in the deck');
    expect(((meta as Map)[imageId(deck)!]['brightness'] as num).abs(),
        greaterThan(0));

    // Two undo steps: the probe edit, then the drag commit.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    final slider =
        tester.widget<Slider>(find.byKey(const ValueKey('img_brightness')));
    expect(slider.value, 0, reason: 'undo walks the commit back');
  });

  /// Alt text commits when typing ends (keyboard/dismiss), not per keystroke.
  testWidgets('image panel: alt text commits with the editor', (tester) async {
    await pumpEditor(tester);
    await insertImage(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('img_alt')));
    await tester.enterText(
        find.byKey(const ValueKey('img_alt')), 'A red square');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The commit is app-owned — read it off the probe's request deck.
    await probeDeck(tester);
    final deck = lastDeck();
    final meta = deck['imageMeta'];
    expect(meta, isNotNull, reason: 'the commit landed in the deck');
    expect(((meta as Map)[imageId(deck)!]['alt'] as String), 'A red square');
  });

  /// Replace swaps the resource, keeps the frame, and drops the old image.
  testWidgets('image panel: replace swaps the resource and keeps the frame',
      (tester) async {
    await pumpEditor(tester);
    await insertImage(tester); // writes the two-entry library

    await tester.ensureVisible(find.byKey(const ValueKey('img_replace')));
    await tester.tap(find.byKey(const ValueKey('img_replace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('photo2.png'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final shape =
        recordedObjectOps.lastOrNull?['shape'] as Map<String, dynamic>?;
    expect(shape?['resource_id'], 'img2', reason: 'the new id landed');
    expect(shape?['w'], 480, reason: 'the frame survived the swap');
  });

  /// Deleting an image sweeps its entry — no orphan meta on the wire.
  testWidgets('deck: deleting an image sweeps its imageMeta entry',
      (tester) async {
    await pumpEditor(tester);
    await insertImage(tester);

    // Create an entry first, so the sweep has something to remove.
    await tester.ensureVisible(find.byKey(const ValueKey('crop_shape_circle')));
    await tester.tap(find.byKey(const ValueKey('crop_shape_circle')));
    await tester.pumpAndSettle();

    final image = find.descendant(
        of: find.byType(SlideStage), matching: find.byType(Image));
    expect(image, findsOneWidget);
    await tester.longPress(image);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(recordedDeletes, isNotEmpty, reason: 'the delete went to the engine');

    // Probe with a fresh insert; the recorded deck is the live one.
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final deck = lastDeck();
    expect(deck['imageMeta'], isNot(isA<Map>()),
        reason: 'the entry is swept with the image');
  });

  /// The renderer: shape mask + adjustment filters, without a golden.
  testWidgets('renderer: shape mask and adjustments are applied',
      (tester) async {
    await pumpEditor(tester);
    await insertImage(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('crop_shape_circle')));
    await tester.tap(find.byKey(const ValueKey('crop_shape_circle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('img_contrast')));
    await tester.drag(
        find.byKey(const ValueKey('img_contrast')), const Offset(-240, 0));
    await tester.pumpAndSettle();

    final img = find.descendant(
        of: find.byType(SlideStage), matching: find.byType(Image));
    expect(img, findsOneWidget, reason: 'the image renders in the stage');
    expect(
      find.ancestor(of: img, matching: find.byType(ClipOval)),
      findsOneWidget,
      reason: 'the circle mask wraps the image',
    );
    expect(
      find.ancestor(of: img, matching: find.byType(ColorFiltered)),
      findsOneWidget,
      reason: 'the contrast adjustment reaches the renderer',
    );
  });
}

/// A valid 1×1 PNG — enough for FileImage to decode.
final List<int> _tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
