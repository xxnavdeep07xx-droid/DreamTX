import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/widgets/rich_doc.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/screens/editor_screen.dart';

import 'smoke_test.dart' as smoke;

/// The Insert drawer + the full Text Box flow — the contract of the Insert
/// update: Home removed without a gap; Insert as a compact drawer over the
/// navbar with the six real tools; the object panel with its right rail;
/// the two-state text flow (typing toolbar above the keyboard, full panel
/// when closed); persistence; undo/redo; filmstrip independence over the
/// sheet; slide-switch selection clearing.
void main() {
  late Directory tmp;
  // The engine recorder: the fake engine plus a capture of every
  // add/update_object request, so deck-level assertions read the exact
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
    tmp = Directory.systemTemp.createTempSync('dreamtx_insert');
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

  Future<void> pumpEditor(WidgetTester tester, {int slides = 3}) async {
    Bridge.testOverride = recordingEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: smoke.deckFixtureForProbe(slides))));
    await tester.pumpAndSettle();
  }

  testWidgets('Home is gone from the ribbon — no tab, no blank gap, no Home panel', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Home'), findsNothing, reason: 'the tab is gone');
    // The ribbon renders the remaining eleven tabs in order, no gap.
    final expected = [
      'AI', 'Files', 'Insert', 'Draw', 'Design', 'Transitions',
      'Animations', 'Slide show', 'Review', 'View', 'Help',
    ];
    for (final label in expected) {
      expect(find.text(label), findsOneWidget, reason: '$label renders');
    }
    // A layout gap would show as dead width: the Insert tile sits exactly
    // where Home used to (third slot) and tapping it opens the drawer.
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_drawer')), findsOneWidget);
    expect(find.text('Text Box'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Shapes'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Icons / Stickers'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    // No placeholder buttons for the later tools.
    expect(find.text('Chart'), findsNothing);
    expect(find.text('Link'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('insert drawer: rises from behind the navbar like Files — preview never moves', (tester) async {
    await pumpEditor(tester);
    final canvas = find.byType(AspectRatio);
    final ribbon = find.text('AI');
    final preview0 = tester.getRect(canvas);
    final ribbon0 = tester.getRect(ribbon);

    await tester.tap(find.text('Insert'));
    await tester.pump(); // the mount frame — fully below the navbar
    final sheet = find.byKey(const ValueKey('insert_drawer'));
    final boundary = tester.getRect(find.byKey(const ValueKey('filmstrip_row'))).bottom;
    final sheetH = tester.getSize(sheet).height;
    // The first visible frame sits exactly on the navbar boundary — never
    // a mid-screen pop-in.
    expect(tester.getRect(sheet).top, boundary,
        reason: 'the mount frame is exactly at the navbar boundary');
    var lastTop = tester.getRect(sheet).top;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final t = tester.getRect(sheet).top;
      expect(t, lessThanOrEqualTo(lastTop + 0.25),
          reason: 'frame $i: rises monotonically from behind the navbar');
      expect(tester.getRect(canvas), preview0,
          reason: 'frame $i: the slide preview never moves');
      expect(tester.getRect(ribbon), ribbon0);
      lastTop = t;
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet).top, closeTo(boundary - sheetH, 0.5));
    expect(tester.getRect(canvas), preview0);

    // Toggling the filmstrip over the open drawer moves nothing and never
    // closes the drawer (the panel is not resized either).
    final handle = find.byKey(const ValueKey('filmstrip_handle'));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_drawer')), findsOneWidget,
        reason: 'the tray overlays the drawer without closing it');
    expect(tester.getSize(sheet).height, sheetH,
        reason: 'the drawer is never resized by the tray');
    expect(tester.getRect(canvas), preview0);
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(tester.getRect(canvas), preview0);

    // Rapid open/close: the never-rose branch unmounts instantly.
    await tester.tap(find.text('Insert').first);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_drawer')), findsNothing);
    await tester.tap(find.text('Insert'));
    await tester.tap(find.text('Insert'));
    await tester.pump();
    expect(find.byKey(const ValueKey('insert_drawer')), findsNothing,
        reason: 'two taps inside one frame gap: nothing ever shown, the layer '
            'unmounts at once');
    expect(tester.takeException(), isNull);
  });

  testWidgets('insert drawer: the SAME sheet as Files — same anchor and sizing, the header drags it between the same detents, a deep drag dismisses it', (tester) async {
    await pumpEditor(tester);
    final row = find.byKey(const ValueKey('filmstrip_row'));
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();

    // The same resting detent Files rests at (the machinery is shared:
    // 45% of the 710dp above the ribbon = 319.5), at the same anchor —
    // the ribbon's top edge.
    final sheet = find.byKey(const ValueKey('insert_drawer'));
    final handle = find.byKey(const ValueKey('insert_drawer_handle'));
    expect(tester.getSize(sheet).height, closeTo(319.5, 0.1));
    expect(tester.getRect(sheet).bottom, closeTo(767, 0.1));
    final insertRect = tester.getRect(sheet);

    // Measured head-to-head: the Files drawer occupies the EXACT same rect
    // on the same viewport — same alignment, same sizing. (`.first` — the
    // open drawer's own header title carries the same text as the tab.)
    await tester.tap(find.text('Insert').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_drawer')), findsNothing);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('files_drawer'))),
        insertRect,
        reason: 'Files and Insert rest on the identical rect — one sheet');
    await tester.tap(find.text('Files').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();

    // Touch slidability: a slow drag up (no fling) tracks the finger, then
    // settles to the NEAREST detent — tall, ~78% of the space above the
    // ribbon (553.8 here). The header IS the drag surface.
    await tester.timedDrag(handle, const Offset(0, -180),
        const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final tall = tester.getSize(sheet).height;
    expect(tall, greaterThan(540));
    expect(tall, lessThan(570));

    // A slow deep drag down: past the dismiss zone (below ~70% of half),
    // so the sheet closes outright — unmounted cleanly at its slot, the
    // Insert tab releasing with it. The filmstrip never knew.
    await tester.timedDrag(handle, const Offset(0, 340),
        const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_drawer')), findsNothing);
    expect(find.text('Insert'), findsOneWidget,
        reason: 'only the ribbon tab remains after the dismiss');
    expect(tester.getSize(row), const Size(390, 104));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text box: insert selects it, opens the keyboard, typing toolbar rides above it', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The object exists, is selected, and is a text box mid-slide.
    final added = recordedObjectOps.firstWhere(
        (op) => op['op'] == 'add_object', orElse: () => <String, dynamic>{});
    final shape = added['shape'] as Map?;
    expect(shape?['content']?['kind'], 'text');
    final (dw, dh) = (1280.0, 720.0);
    expect(((shape?['x'] as num?)?.toDouble() ?? -1) +
            ((shape?['w'] as num?)?.toDouble() ?? -1) / 2,
        closeTo(dw / 2, 1));
    expect(((shape?['y'] as num?)?.toDouble() ?? -1) +
            ((shape?['h'] as num?)?.toDouble() ?? -1) / 2,
        closeTo(dh / 2, 1));

    // The typing state: the WYSIWYG field is mounted and focused, the
    // toolbar rides above the keyboard, the drawer hides.
    final field = find.byKey(const ValueKey('text_box_field'));
    expect(field, findsOneWidget);
    expect((tester.widget(field) as TextField).focusNode!.hasFocus, isTrue,
        reason: 'the keyboard opens immediately');
    expect(find.byKey(const ValueKey('typing_toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('insert_drawer')), findsNothing,
        reason: 'the full panel hides while typing');

    // Type into it — the toolbar carries bold/italic/underline/color/
    // highlight/alignment/lists/expand.
    await tester.enterText(field, 'Hello world');
    await tester.pump();
    expect(find.byKey(const ValueKey('typing_toolbar')), findsOneWidget);
    expect(find.byIcon(Icons.format_bold), findsOneWidget);
    expect(find.byIcon(Icons.format_italic), findsOneWidget);
    expect(find.byIcon(Icons.format_underline), findsOneWidget);
    expect(find.byIcon(Icons.format_color_text), findsOneWidget);
    expect(find.byIcon(Icons.highlight), findsOneWidget);
    expect(find.byIcon(Icons.format_align_left), findsOneWidget);
    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
    expect(find.byIcon(Icons.format_list_numbered), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text box: typing → bold the selection → type more — the marks follow', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byKey(const ValueKey('text_box_field'));
    await tester.enterText(field, 'Hello world');
    await tester.pump();

    // Select "world" and tap Bold on the toolbar.
    final controller = (tester.widget(field) as TextField).controller!;
    controller.selection =
        const TextSelection(baseOffset: 6, extentOffset: 11);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.format_bold).first);
    await tester.pump();

    // Type more at the end of the bold run — the run extends.
    controller.selection = const TextSelection.collapsed(offset: 11);
    await tester.pump();
    await tester.enterText(field, 'Hello worlds');
    await tester.pump();

    // Let the debounced engine commit land.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final updated = recordedObjectOps
        .where((op) => op['op'] == 'update_object')
        .lastOrNull;
    final doc = (updated?['shape'] as Map?)?['content']?['doc'] as Map?;
    expect(doc?['text'], 'Hello worlds');
    final runs = (doc?['runs'] as List?) ?? const [];
    expect(runs, isNotEmpty, reason: 'the bold mark committed with the deck');
    final boldRun =
        runs.whereType<Map>().firstWhere((r) => r['bold'] == true, orElse: () => const {});
    expect(boldRun['start'], 6);
    expect(boldRun['end'], 12, reason: "'worlds' — the run extends over the typed 's'");
    expect(tester.takeException(), isNull);
  });

  testWidgets('text box: expand button hides the keyboard and opens the full panel without losing anything', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byKey(const ValueKey('text_box_field'));
    await tester.enterText(field, 'Keep me');
    final controller = (tester.widget(field) as TextField).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();

    // EXPAND: the keyboard hides, the full panel opens.
    await tester.tap(find.byKey(const ValueKey('typing_toolbar_expand')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('typing_toolbar')), findsNothing);
    expect(find.byKey(const ValueKey('insert_drawer')), findsOneWidget,
        reason: 'the full panel returns');
    // The three right-rail tabs.
    expect(find.byTooltip('Quick Tools'), findsOneWidget);
    expect(find.byTooltip('Character'), findsOneWidget);
    expect(find.byTooltip('Paragraph & Box'), findsOneWidget);
    expect(find.byKey(const ValueKey('panel_body_quick')), findsOneWidget);

    // Nothing lost: tap "Edit text" to re-enter typing — the text and the
    // selection survive the round trip.
    await tester.tap(find.byKey(const ValueKey('panel_edit_text')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('text_box_field')), findsOneWidget);
    final reController =
        (tester.widget(find.byKey(const ValueKey('text_box_field'))) as TextField)
            .controller!;
    expect(reController.text, 'Keep me');
    expect(reController.selection.baseOffset, 0);
    expect(reController.selection.extentOffset, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text box: the panel drives character and paragraph formatting into the deck', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byKey(const ValueKey('text_box_field'));
    await tester.enterText(field, 'Center me\nsecond line');
    final controller = (tester.widget(field) as TextField).controller!;
    // A SELECTION (character formatting affects it; a bare caret would
    // only format what is typed next — which never serializes).
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('typing_toolbar_expand')));
    await tester.pumpAndSettle();

    // Fold the tray: the sheet rests at the shared half detent, so its
    // lower part (the panel's deeper controls) sits under the open tray —
    // the same clearance the Files grid lives by.
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();

    // Quick Tools: center the paragraph + highlight palette chips exist.
    await tester.tap(find.byIcon(Icons.format_align_center).first);
    await tester.pump();
    expect(find.text('TEXT COLOR'), findsOneWidget);
    expect(find.text('HIGHLIGHT — BEHIND THE TEXT'), findsOneWidget);

    // Character: font family + size stepper + clear formatting.
    await tester.tap(find.byTooltip('Character'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel_body_character')), findsOneWidget);
    await tester.tap(find.text('Serif').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('panel_font_plus')));
    await tester.pump();
    expect(find.text('36'), findsOneWidget, reason: 'the size stepper reads 36');

    // Paragraph & Box: vertical alignment, line spacing, indent, autofit.
    // (The sheet rides the shared detents — the shorter resting height
    // scrolls the panel's deeper controls; the test scrolls the minimum a
    // user would, bringing each control into view before tapping it.)
    await tester.tap(find.byTooltip('Paragraph & Box'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel_body_para')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.vertical_align_center).first);
    await tester.pump();
    // Bring the lower controls into the panel body's viewport (the tray
    // covers the sheet's lower part; the user scrolls, the test drives the
    // scrollable minimally).
    await tester.ensureVisible(find.text('1.5').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5').first);
    await tester.pump();
    await tester.ensureVisible(find.text('Shrink text on overflow').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shrink text on overflow').first);
    await tester.pump();

    await tester.pumpAndSettle(const Duration(seconds: 1));
    final updated = recordedObjectOps
        .where((op) => op['op'] == 'update_object')
        .lastOrNull;
    final doc = (updated?['shape'] as Map?)?['content']?['doc'] as Map?;
    expect(doc?['text'], 'Center me\nsecond line');
    expect(doc?['valign'], 'middle');
    expect(doc?['autofit'], 'shrink');
    final paras = (doc?['paras'] as List?) ?? const [];
    final firstPara =
        paras.whereType<Map>().firstWhere((p) => (p['start'] ?? -1) == 0, orElse: () => const {});
    expect(firstPara['align'], 'center');
    expect((firstPara['line_spacing'] as num?)?.toDouble(), 1.5);
    final runs = (doc?['runs'] as List?) ?? const [];
    final serifRun =
        runs.whereType<Map>().firstWhere((r) => r['font_family'] == 'serif', orElse: () => const {});
    expect((serifRun['font_size'] as num?)?.toDouble(), 36);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text box: formatting survives reopening the deck', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byKey(const ValueKey('text_box_field'));
    await tester.enterText(field, 'Persistent');
    final controller = (tester.widget(field) as TextField).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.format_bold).first);
    await tester.pump();
    // Let the commit land, then build a fresh editor over the same deck
    // payload the engine saw.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final updated = recordedObjectOps
        .where((op) => op['op'] == 'update_object')
        .lastOrNull;
    final shape = Map<String, dynamic>.from(updated?['shape'] as Map? ?? {});
    final reopenedDeck = smoke.deckFixtureForProbe(2);
    (reopenedDeck['slides'] as List)[0] = Map<String, dynamic>.from({
      ...(reopenedDeck['slides'] as List)[0] as Map,
      'objects': [shape],
    });

    await tester.pumpWidget(
        MaterialApp(home: EditorScreen(deck: reopenedDeck)));
    await tester.pumpAndSettle();
    // Open Insert (its design mode turns the object layer interactive)…
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_grid')), findsOneWidget);
    // …then tap the text box's mid-slide spot to select it.
    final center = tester.getRect(find.byType(AspectRatio)).center;
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quick Tools'), findsOneWidget,
        reason: 'the reopened text box selected → the object panel');
    await tester.tap(find.byKey(const ValueKey('panel_edit_text')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final reopened = (tester
            .widget(find.byKey(const ValueKey('text_box_field'))) as TextField)
        .controller as RichEditingController;
    expect(reopened.text, 'Persistent');
    final boldRun = reopened.doc.runs.where((r) => r.bold == true).firstOrNull;
    expect(boldRun?.start, 0);
    expect(boldRun?.end, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('undo/redo work over a typing session', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byKey(const ValueKey('text_box_field'));
    await tester.enterText(field, 'Typed');
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The undo button is live; one step returns the box to its empty,
    // untyped state (one undo snapshot per session).
    expect(find.byIcon(Icons.undo), findsOneWidget);
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.redo));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching slides clears the old slide\'s selection', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('typing_toolbar_expand')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quick Tools'), findsOneWidget,
        reason: 'the object panel is open for slide 1\'s text box');

    // Tap slide 2 in the filmstrip — the selection clears, the panel goes.
    await tester.tap(find.text('2. Slide 2'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quick Tools'), findsNothing,
        reason: 'the old slide\'s object selection is cleared');
    expect(find.byKey(const ValueKey('insert_drawer')), findsOneWidget);
    expect(find.byKey(const ValueKey('insert_grid')), findsOneWidget,
        reason: 'the drawer returns to its grid');
    expect(tester.takeException(), isNull);
  });

  testWidgets('table: 3×3 with editable cells', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    // The drawer rests at the SAME detent as Files, so its lower part sits
    // under the open filmstrip tray — fold the tray before tapping the
    // covered second row's tile, the same clearance path the Files
    // drawer's covered row takes.
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();

    final added = recordedObjectOps.firstWhere(
        (op) => op['op'] == 'add_object', orElse: () => <String, dynamic>{});
    final shape = added['shape'] as Map?;
    expect(shape?['content']?['kind'], 'table');
    expect(shape?['content']?['rows'], 3);
    expect(shape?['content']?['cols'], 3);
    expect((shape?['content']?['cells'] as List).length, 9);

    // The panel shows the Cells group; tap a cell, edit it through the
    // route dialog, and the committed shape carries the text.
    expect(find.byTooltip('Cells'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('table_cell_0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Revenue');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final updated = recordedObjectOps
        .where((op) => op['op'] == 'update_object')
        .lastOrNull;
    final cells = (updated?['shape'] as Map?)?['content']?['cells'] as List?;
    expect(cells?.first, 'Revenue');
    expect(tester.takeException(), isNull);
  });

  testWidgets('shapes: the grid inserts a shape and selects it', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_shapes')), findsOneWidget);
    expect(find.text('Rectangle'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
    expect(find.text('Line'), findsOneWidget);
    expect(find.text('Arrow right'), findsOneWidget);

    await tester.tap(find.text('Rectangle'));
    await tester.pumpAndSettle();
    final added = recordedObjectOps.firstWhere(
        (op) => op['op'] == 'add_object', orElse: () => <String, dynamic>{});
    expect((added['shape'] as Map?)?['preset'], 'rectangle');
    expect((added['shape'] as Map?)?['content'], isNull,
        reason: 'a plain shape carries no content');
    // Selected → the object panel with its style group.
    expect(find.byTooltip('Style'), findsOneWidget);
    expect(find.byKey(const ValueKey('panel_body_style')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('icons: the searchable picker inserts an icon sticker', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    // The covered second row: fold the tray first (the shared detent puts
    // the drawer's lower part under it at rest).
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Icons / Stickers'));
    await tester.pumpAndSettle();

    // The picker is a modal (its search field needs the keyboard-safe
    // route) with a live search.
    expect(find.byKey(const ValueKey('icon_picker_search')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('icon_picker_search')), 'heart');
    await tester.pump();
    expect(find.text('favorite'), findsOneWidget);
    expect(find.text('rocket_launch'), findsNothing,
        reason: 'the search filters');

    await tester.tap(find.text('favorite'));
    await tester.pumpAndSettle();
    final added = recordedObjectOps.firstWhere(
        (op) => op['op'] == 'add_object', orElse: () => <String, dynamic>{});
    final shape = added['shape'] as Map?;
    expect(shape?['content']?['kind'], 'icon');
    expect(shape?['content']?['name'], 'favorite');
    // Selected → the icon's color panel.
    expect(find.byTooltip('Color'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image: gallery pick imports the file into the deck scope and places it', (tester) async {
    // A real image file on disk for the picker to return; the store's add
    // is overridden to the entry the editor would persist (the stored
    // file is pre-written where the entry points).
    final img = File('${tmp.path}/gallery.png');
    img.writeAsBytesSync(_tinyPngBytes);
    ImagePickers.testOverride = (source, kind) async => img.path;
    ResourceStore.debugAddOverride = ({required brand, deckId, required sourcePath, folder}) async =>
            {'id': 'img1', 'name': 'gallery.png', 'file': 'img1-gallery.png'};
    Directory('${tmp.path}/resources/decks/d1').createSync(recursive: true);
    File('${tmp.path}/resources/decks/d1/img1-gallery.png')
        .writeAsBytesSync(_tinyPngBytes);

    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_image_sources')), findsOneWidget);

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final added = recordedObjectOps.firstWhere(
        (op) => op['op'] == 'add_object', orElse: () => <String, dynamic>{});
    final shape = added['shape'] as Map?;
    expect(shape?['content']?['kind'], 'image');
    expect(shape?['content']?['brand'], false);
    expect((shape?['content']?['name'] as String?)?.isNotEmpty, isTrue);
    // The resource landed in the deck's scope and the canvas resolved it.
    expect(find.byType(Image), findsOneWidget,
        reason: 'the picked image renders on the canvas');
    // Selected → the frame panel.
    expect(find.byTooltip('Frame'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('media: importing a video file places a media object (no recorder anywhere)', (tester) async {
    final clip = File('${tmp.path}/clip.mp4');
    clip.writeAsBytesSync(List.filled(64, 0));
    ImagePickers.testOverride = (source, kind) async => clip.path;
    ResourceStore.debugAddOverride = ({required brand, deckId, required sourcePath, folder}) async =>
            {'id': 'med1', 'name': 'clip.mp4', 'file': 'med1-clip.mp4'};

    await pumpEditor(tester);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    // The covered second row: fold the tray first.
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insert_media_sources')), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    // No recording affordance of any kind.
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.text('Record'), findsNothing);

    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final added = recordedObjectOps.firstWhere(
        (op) => op['op'] == 'add_object', orElse: () => <String, dynamic>{});
    final shape = added['shape'] as Map?;
    expect(shape?['content']?['kind'], 'media');
    expect(shape?['content']?['media_kind'], 'video');
    expect(find.byTooltip('Info'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// A minimal valid PNG (1×1 transparent) — enough for FileImage to decode.
final List<int> _tinyPngBytes = () {
  const hex = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT
    0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND
    0x42, 0x60, 0x82,
  ];
  return hex;
}();
