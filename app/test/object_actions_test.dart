import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/widgets/shape_canvas.dart';

import 'smoke_test.dart' as smoke;

/// Roadmap #11, Wave 1 step 1 — object actions: the long-press is the
/// object's context menu (the mobile answer to PowerPoint's right-click).
/// An object long-press selects it WITHOUT entering typing and opens the
/// actions sheet — copy (to the editor's object clipboard), duplicate, the
/// format painter (copy style / apply style over the universal chrome
/// fields), delete; an empty-canvas long-press pastes the clipboard with
/// its top-left at the pressed point. Every action routes through the same
/// engine ops and undo machinery the layers sheet already uses — nothing
/// here touches the model.
void main() {
  late Directory tmp;
  // The engine recorder: the fake engine plus a capture of every
  // add/update/delete object request — assertions read the exact payloads
  // the production engine would receive.
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
    tmp = Directory.systemTemp.createTempSync('dreamtx_objactions');
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

  /// A preset shape with the full chrome — a known bbox to long-press.
  Map<String, dynamic> shape(String id,
      {required String preset,
      required double x,
      required Map<String, dynamic> fill,
      required Map<String, dynamic> effects}) {
    return <String, dynamic>{
      'id': id,
      'preset': preset,
      'x': x,
      'y': 380.0,
      'w': 220.0,
      'h': 140.0,
      'rotation': 0.0,
      'opacity': 1.0,
      'locked': false,
      'fill': fill,
      'stroke': {
        'color': '17181A',
        'width': 2.0,
        'dash': 'solid',
        'start_arrow': 'none',
        'end_arrow': 'none'
      },
      'effects': effects,
      'closed': true,
    };
  }

  /// Slide 1 with two clean targets: a solid rectangle (x 200–420) and a
  /// bare ellipse (x 700–920), both on the y 380–520 band, far from the
  /// archetype's own text slots. The rectangle carries the distinctive
  /// chrome the format painter must transfer.
  Map<String, dynamic> deckWithShapes() {
    final deck = smoke.deckFixtureForProbe(1);
    final slide = (deck['slides'] as List)[0] as Map;
    slide['objects'] = <Map<String, dynamic>>[
      shape('rect1',
          preset: 'rectangle',
          x: 200,
          fill: {'type': 'solid', 'color': 'C25E00'},
          effects: {'shadow': true}),
      shape('ell1',
          preset: 'ellipse',
          x: 700,
          fill: {'type': 'none'},
          effects: <String, dynamic>{}),
    ];
    return deck;
  }

  /// Design-space -> logical position on the canvas (the [ShapesLayer]'s
  /// own rect IS the stage's design frame) — the draw suite's proven map.
  Offset Function(double dx, double dy) designToLogical(
      WidgetTester tester) {
    final rect = tester.getRect(find.byType(ShapesLayer));
    final scale = rect.width / 1280;
    return (dx, dy) => Offset(rect.left + dx * scale, rect.top + dy * scale);
  }

  testWidgets('long-press an object: the sheet acts on the pressed object',
      (tester) async {
    await pumpEditor(tester, deck: deckWithShapes());
    final at = designToLogical(tester);
    // Hold on the rectangle (center 310, 450).
    await tester.longPressAt(at(310, 450));
    await tester.pumpAndSettle();
    expect(find.text('Object actions'), findsOneWidget);
    // The pressed object became the selection — its panel is up.
    expect(find.byKey(const ValueKey('insert_drawer')), findsOneWidget);
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    // One add_object: same preset and size, a FRESH id, the +24/+24 offset
    // (the layers sheet's duplicate semantics, unchanged).
    expect(recordedObjectOps, hasLength(1));
    final shape = recordedObjectOps.last['shape'] as Map;
    expect(shape['preset'], 'rectangle');
    expect((shape['x'] as num), 224.0);
    expect((shape['y'] as num), 404.0);
    expect(shape['id'], isNot('rect1'));
    expect(recordedDeletes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy, then long-press empty canvas: paste lands at the press',
      (tester) async {
    await pumpEditor(tester, deck: deckWithShapes());
    final at = designToLogical(tester);
    await tester.longPressAt(at(310, 450)); // the rectangle
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(recordedObjectOps, isEmpty,
        reason: 'copy only fills the clipboard');
    // Long-press empty canvas high above the object band (y 380–520).
    await tester.longPressAt(at(100, 120));
    await tester.pumpAndSettle();
    expect(recordedObjectOps, hasLength(1));
    final shape = recordedObjectOps.last['shape'] as Map;
    expect(shape['preset'], 'rectangle');
    expect(shape['id'], isNot('rect1'));
    expect((shape['x'] as num).toDouble(), closeTo(100.0, 0.5),
        reason: 'the top-left lands at the press (design<->logical '
            'round-trip tolerance)');
    expect((shape['y'] as num).toDouble(), closeTo(120.0, 0.5));
    // Paste is silent — no second sheet, no deletes.
    expect(find.text('Object actions'), findsNothing);
    expect(recordedDeletes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the format painter: copy style, then apply it', (tester) async {
    await pumpEditor(tester, deck: deckWithShapes());
    final at = designToLogical(tester);
    // Pickup on the rectangle: solid C25E00 fill, shadow effect.
    await tester.longPressAt(at(310, 450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy style'));
    await tester.pumpAndSettle();
    expect(recordedObjectOps, isEmpty,
        reason: 'the pickup is editor state, no engine op');
    // Apply on the ellipse.
    await tester.longPressAt(at(810, 450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply style'));
    await tester.pumpAndSettle();
    expect(recordedObjectOps, hasLength(1));
    final req = recordedObjectOps.last;
    expect(req['op'], 'update_object');
    expect(req['object_id'], 'ell1');
    final shape = req['shape'] as Map;
    expect((shape['fill'] as Map)['type'], 'solid');
    expect((shape['fill'] as Map)['color'], 'C25E00');
    expect((shape['effects'] as Map)['shadow'], true);
    expect(shape['id'], 'ell1',
        reason: 'the update carries the target, not the source');
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete from the sheet fires delete_object on the pressed object',
      (tester) async {
    await pumpEditor(tester, deck: deckWithShapes());
    final at = designToLogical(tester);
    await tester.longPressAt(at(810, 450)); // the ellipse
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(recordedDeletes, hasLength(1));
    expect(recordedDeletes.first['object_id'], 'ell1');
    expect(recordedObjectOps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an armed Draw tool consumes the long-press', (tester) async {
    await pumpEditor(tester, deck: deckWithShapes());
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    final at = designToLogical(tester);
    await tester.longPressAt(at(310, 450));
    await tester.pumpAndSettle();
    // The armed tool owns the canvas — no menu, no ops, no ink from a hold.
    expect(find.text('Object actions'), findsNothing);
    expect(recordedObjectOps, isEmpty);
    expect(recordedDeletes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
