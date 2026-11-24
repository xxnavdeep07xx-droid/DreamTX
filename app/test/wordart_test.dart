import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';

import 'smoke_test.dart' as smoke;

/// Roadmap #11, Wave 1 step 3 — WordArt: the seventh Insert card. Six
/// styled-text presets assembled ENTIRELY from the model's own powers —
/// per-run character formatting (size, weight, italic, color, highlight)
/// plus the object chrome both exporters already render (the box's solid
/// fill, the soft shadow, the accent glow). An insert IS a text box with
/// a preset: it lands selected with the keyboard open on placeholder
/// text; 'accent' presets resolve to the deck's DNA accent at insert
/// time (the fake resolve_dna answers C25E00).
void main() {
  late Directory tmp;
  final recordedObjectOps = <Map<String, dynamic>>[];

  Map<String, dynamic> recordingEngine(Map<String, dynamic> req) {
    if (req['op'] == 'add_object' || req['op'] == 'update_object') {
      recordedObjectOps.add(Map<String, dynamic>.from(req));
    }
    return smoke.testFakeEngine(req);
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_wordart');
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
        home: EditorScreen(deck: smoke.deckFixtureForProbe(1))));
    await tester.pumpAndSettle();
  }

  /// Open the Insert drawer and tap the WordArt card (the seventh tile —
  /// it may ride below the drawer's fold, so reveal it first).
  Future<void> openGallery(WidgetTester tester) async {
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('WordArt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WordArt'));
    await tester.pumpAndSettle();
  }

  /// The ops that ADDED objects. The typing session's opening commit
  /// fires one update_object right after any startTyping insert (the
  /// focus flush — pre-existing behavior, same for the Text Box card),
  /// so the insert itself is always read as the add.
  Iterable<Map<String, dynamic>> addOps() =>
      recordedObjectOps.where((op) => op['op'] == 'add_object');

  /// The inserted preset's shape payload.
  Map<String, dynamic> lastShape() =>
      addOps().last['shape'] as Map<String, dynamic>;

  /// The inserted preset's text doc.
  Map<String, dynamic> lastDoc() =>
      lastShape()['content']['doc'] as Map<String, dynamic>;

  /// The doc's single preset run.
  Map<String, dynamic> lastRun() =>
      (lastDoc()['runs'] as List).first as Map<String, dynamic>;

  testWidgets('the WordArt tile opens the six-preset gallery',
      (tester) async {
    await pumpEditor(tester);
    await openGallery(tester);
    for (final label
        in ['Headline', 'Accent', 'Glow', 'Highlight', 'Badge', 'Watermark']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(recordedObjectOps, isEmpty, reason: 'nothing inserted yet');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Headline preset: styled run, soft shadow, keyboard open',
      (tester) async {
    await pumpEditor(tester);
    await openGallery(tester);
    await tester.tap(find.text('Headline'));
    await tester.pumpAndSettle();
    expect(addOps(), hasLength(1));
    final shape = lastShape();
    expect(shape['preset'], 'rectangle');
    expect((shape['fill'] as Map)['type'], 'none');
    expect((shape['effects'] as Map)['shadow'], isNotNull,
        reason: 'the soft drop shadow rides the object chrome');
    final doc = lastDoc();
    expect(doc['text'], 'Your text here');
    final run = lastRun();
    expect(run['bold'], true);
    expect(run['font_size'], 58.0);
    expect(run['color'], '17181A');
    // It landed as a live text box: the WYSIWYG field, focused, holding
    // the placeholder — the first keystrokes make it yours.
    final field = find.byKey(const ValueKey('text_box_field'));
    expect(field, findsOneWidget);
    expect((tester.widget(field) as TextField).controller!.text,
        'Your text here');
    expect((tester.widget(field) as TextField).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Badge preset: the DNA accent fills the box, the run stays white',
      (tester) async {
    await pumpEditor(tester);
    await openGallery(tester);
    await tester.tap(find.text('Badge'));
    await tester.pumpAndSettle();
    final shape = lastShape();
    expect((shape['fill'] as Map)['type'], 'solid');
    expect((shape['fill'] as Map)['color'], 'C25E00',
        reason: 'the resolved DNA accent (the fake resolve_dna)');
    expect(lastRun()['color'], 'FFFFFF');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Highlight preset carries the marker run', (tester) async {
    await pumpEditor(tester);
    await openGallery(tester);
    await tester.tap(find.text('Highlight'));
    await tester.pumpAndSettle();
    final shape = lastShape();
    expect((shape['effects'] as Map), isEmpty);
    expect(lastRun()['highlight'], 'FFD400');
    expect(lastRun()['font_size'], 38.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Glow preset resolves the accent into run and glow',
      (tester) async {
    await pumpEditor(tester);
    await openGallery(tester);
    await tester.tap(find.text('Glow'));
    await tester.pumpAndSettle();
    final shape = lastShape();
    final glow = (shape['effects'] as Map)['glow'] as Map;
    expect(glow['color'], 'C25E00');
    expect(lastRun()['color'], 'C25E00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Watermark preset: huge, italic, translucent',
      (tester) async {
    await pumpEditor(tester);
    await openGallery(tester);
    await tester.tap(find.text('Watermark'));
    await tester.pumpAndSettle();
    final shape = lastShape();
    expect(shape['opacity'], 0.35,
        reason: 'the translucency rides the object opacity, exactly like '
            'the highlighter ink');
    final run = lastRun();
    expect(run['italic'], true);
    expect(run['font_size'], 84.0);
    expect(run['color'], '6B6E76');
    expect(tester.takeException(), isNull);
  });
}
