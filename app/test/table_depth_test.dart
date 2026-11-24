import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/object_content.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';
import 'package:dreamtx/widgets/controls.dart';
import 'package:dreamtx/widgets/shape_canvas.dart';

import 'smoke_test.dart' as smoke;

/// Roadmap #11, Wave 1 step 4 — table depth: the cell editor gains
/// add/remove row & column, merge/split (cell selection), and DNA-driven
/// table style chips. Zero core changes: merges and styles live as
/// app-owned deck metadata (`deck['tables']`), carried through engine
/// round-trips the same way filmstrip sections are. Every action is one
/// update_object = one undo step.
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
    tmp = Directory.systemTemp.createTempSync('dreamtx_tabledepth');
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

  /// Opens Insert, folds the filmstrip tray (the Table tile sits in the
  /// covered second row), and inserts a 3×3 table.
  Future<void> insertTable(WidgetTester tester) async {
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cells'), findsOneWidget);
  }

  /// Tap-to-edit a cell's text through the route dialog (the unchanged
  /// cell-editing contract).
  Future<void> editCell(WidgetTester tester, int index, String text) async {
    await tester.ensureVisible(find.byKey(ValueKey('table_cell_$index')));
    await tester.tap(find.byKey(ValueKey('table_cell_$index')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget,
        reason: 'the cell editor dialog is up');
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  /// Long-press toggles a cell into (or out of) the selection.
  Future<void> selectCell(WidgetTester tester, int index) async {
    await tester.ensureVisible(find.byKey(ValueKey('table_cell_$index')));
    await tester.longPress(find.byKey(ValueKey('table_cell_$index')));
    await tester.pumpAndSettle();
  }

  /// The structure chip's enabled state, read through its public opacity
  /// animation (1.0 = enabled, 0.38 = disabled and tap-ignored).
  Future<bool> chipEnabled(WidgetTester tester, String key) async {
    final finder = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(AnimatedOpacity));
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    return tester.widget<AnimatedOpacity>(finder).opacity > 0.9;
  }

  Future<void> tapChip(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic>? lastShape() =>
      (recordedObjectOps.lastOrNull?['shape'] as Map<String, dynamic>?);

  test('table style entries resolve DNA colors at apply time', () {
    const dna = {'accent': 'C25E00', 'surface': 'F7F6F3'};
    // Plain carries no fields — a plain table keeps no entry.
    expect(ObjectContent.tableStyleFields('plain', dna), isNull);
    // Header: the DNA accent fill; the luminance picks white text on it.
    expect(ObjectContent.tableStyleFields('header', dna), {
      'style': 'header',
      'accent': 'C25E00',
      'on_accent': 'FFFFFF',
    });
    // Banded: the DNA surface tint on alternate rows.
    expect(ObjectContent.tableStyleFields('banded', dna),
        {'style': 'banded', 'band': 'F7F6F3'});
    // Both together.
    expect(ObjectContent.tableStyleFields('header_banded', dna), {
      'style': 'header_banded',
      'accent': 'C25E00',
      'on_accent': 'FFFFFF',
      'band': 'F7F6F3',
    });
    // A light accent flips the header text to the deck ink.
    final light = ObjectContent.tableStyleFields(
        'header', {'accent': 'F7F6F3', 'surface': 'F7F6F3'})!;
    expect(light['on_accent'], '17181A');
  });

  testWidgets('long-press selects cells; tap still edits text', (tester) async {
    await pumpEditor(tester);
    await insertTable(tester);
    // Nothing selected: every structure chip is off; merge needs cells,
    // split needs an existing merge.
    expect(await chipEnabled(tester, 'table_chip_add_row'), isFalse);
    expect(await chipEnabled(tester, 'table_chip_merge'), isFalse);
    expect(await chipEnabled(tester, 'table_chip_split'), isFalse);
    // Long-press cell 0 → it joins the selection; row/col chips light up,
    // merge stays off (one cell).
    await selectCell(tester, 0);
    expect(find.text('1 CELL SELECTED'), findsOneWidget);
    expect(await chipEnabled(tester, 'table_chip_add_row'), isTrue);
    expect(await chipEnabled(tester, 'table_chip_del_row'), isTrue);
    expect(await chipEnabled(tester, 'table_chip_add_col'), isTrue);
    expect(await chipEnabled(tester, 'table_chip_merge'), isFalse,
        reason: 'merging needs two or more cells');
    // Tap still OPENS the text editor — the two gestures never collide,
    // and the selection survives the edit.
    await editCell(tester, 0, 'A');
    expect(lastShape()?['content']?['cells']?.first, 'A');
    expect(find.text('1 CELL SELECTED'), findsOneWidget);
    // Long-press the same cell again → toggles OFF, chips go quiet.
    await selectCell(tester, 0);
    expect(await chipEnabled(tester, 'table_chip_add_row'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('structure: rows and columns add and remove around the '
      'selection', (tester) async {
    await pumpEditor(tester);
    await insertTable(tester);
    await editCell(tester, 0, 'A');
    // '+ Row' inserts ABOVE the selection's row: the typed cell drops to
    // row 2 (index 3), a blank row sits at the top.
    await selectCell(tester, 0);
    await tapChip(tester, 'table_chip_add_row');
    expect(lastShape()?['content']?['rows'], 4);
    expect(lastShape()?['content']?['cells'], hasLength(12));
    expect((lastShape()?['content']?['cells'] as List).sublist(0, 3),
        everyElement(''),
        reason: 'a blank row was inserted above');
    expect((lastShape()?['content']?['cells'] as List)[3], 'A');
    // '− Row' removes the rows the selection covers — delete an EMPTY row
    // (row 3): the typed text stays, three rows remain.
    await selectCell(tester, 6);
    await tapChip(tester, 'table_chip_del_row');
    expect(lastShape()?['content']?['rows'], 3);
    expect(lastShape()?['content']?['cells'], hasLength(9));
    expect((lastShape()?['content']?['cells'] as List)[3], 'A',
        reason: 'the typed cell survived — only the empty row went');
    // Columns mirror the same contract.
    await selectCell(tester, 0);
    await tapChip(tester, 'table_chip_add_col');
    expect(lastShape()?['content']?['cols'], 4);
    expect(lastShape()?['content']?['cells'], hasLength(12));
    await selectCell(tester, 1);
    await tapChip(tester, 'table_chip_del_col');
    expect(lastShape()?['content']?['cols'], 3);
    expect(lastShape()?['content']?['cells'], hasLength(9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('merge joins a rectangle; split restores the cells',
      (tester) async {
    await pumpEditor(tester);
    await insertTable(tester);
    await editCell(tester, 0, 'A');
    await editCell(tester, 1, 'B');
    // Select the first row's two cells → Merge lights up → the region's
    // texts join into the anchor, covered cells vanish from the grid.
    await selectCell(tester, 0);
    await selectCell(tester, 1);
    expect(await chipEnabled(tester, 'table_chip_merge'), isTrue);
    await tapChip(tester, 'table_chip_merge');
    expect(find.byKey(const ValueKey('table_cell_1')), findsNothing,
        reason: 'the covered cell has no button of its own');
    expect(find.byKey(const ValueKey('table_cell_0')), findsOneWidget);
    expect(lastShape()?['content']?['cells']?[0], 'A B',
        reason: 'merge never loses text — covered texts join the anchor');
    // Split: select the merged region's anchor (it IS the wide button),
    // Split lights, and the covered cells return to independence.
    await selectCell(tester, 0);
    expect(await chipEnabled(tester, 'table_chip_split'), isTrue);
    await tapChip(tester, 'table_chip_split');
    expect(find.byKey(const ValueKey('table_cell_1')), findsOneWidget);
    expect(lastShape()?['content']?['cells']?[0], 'A B',
        reason: 'split keeps the merged text in the top-left cell');
    expect(tester.takeException(), isNull);
  });

  testWidgets('merge needs an exact rectangle', (tester) async {
    await pumpEditor(tester);
    await insertTable(tester);
    // An L-shape (cells 0, 1 and 3): three cells, not a rectangle.
    await selectCell(tester, 0);
    await selectCell(tester, 1);
    await selectCell(tester, 3);
    expect(find.text('3 CELLS SELECTED'), findsOneWidget);
    expect(await chipEnabled(tester, 'table_chip_merge'), isFalse,
        reason: 'the L-shape is not a rectangle');
    // Complete the rectangle → merge lights.
    await selectCell(tester, 4);
    expect(find.text('4 CELLS SELECTED'), findsOneWidget);
    expect(await chipEnabled(tester, 'table_chip_merge'), isTrue);
    await tapChip(tester, 'table_chip_merge');
    // A 2×2 region: the anchor button spans two columns of the first row;
    // six buttons remain (0, 2, 5, 6, 7, 8).
    expect(find.byKey(const ValueKey('table_cell_1')), findsNothing);
    expect(find.byKey(const ValueKey('table_cell_3')), findsNothing);
    expect(find.byKey(const ValueKey('table_cell_4')), findsNothing);
    expect(find.byKey(const ValueKey('table_cell_8')), findsOneWidget);
    // Merge AROUND a prior merge: select the merged region's anchor plus
    // the two cells to its right (2 and 5) → a clean 2×3 rectangle that
    // absorbs the 2×2 region into one 2×3.
    await selectCell(tester, 0);
    await selectCell(tester, 2);
    await selectCell(tester, 5);
    expect(await chipEnabled(tester, 'table_chip_merge'), isTrue);
    await tapChip(tester, 'table_chip_merge');
    expect(lastShape()?['content']?['cells']?[0], '',
        reason: 'both regions were empty — nothing to join');
    expect(tester.takeException(), isNull);
  });

  testWidgets('table style chips are DNA-driven', (tester) async {
    await pumpEditor(tester);
    await insertTable(tester);
    // The style group is the panel's second group.
    await tester.tap(find.byTooltip('Table style'));
    await tester.pumpAndSettle();
    // Plain is the resting state.
    expect(tester.widget<DreamChoiceChip>(
            find.widgetWithText(DreamChoiceChip, 'Plain')).selected, isTrue);
    // Header resolves the deck DNA at apply time (the fake DNA's accent
    // is C25E00) and routes through update_object — one mutate, one undo
    // step, uniform with every other table action.
    await tester.tap(find.text('Header'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<DreamChoiceChip>(
            find.widgetWithText(DreamChoiceChip, 'Header')).selected, isTrue);
    expect(
        tester.widget<DreamChoiceChip>(
            find.widgetWithText(DreamChoiceChip, 'Plain')).selected, isFalse);
    expect(lastShape()?['content']?['rows'], 3,
        reason: 'a style change never touches the table geometry');
    // And plain again — the entry folds away entirely.
    await tester.tap(find.text('Plain'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<DreamChoiceChip>(
            find.widgetWithText(DreamChoiceChip, 'Plain')).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the table object folds its metadata away',
      (tester) async {
    await pumpEditor(tester);
    await insertTable(tester);
    // Style it (the entry exists), then delete the table itself through
    // the object actions sheet (the long-press context menu).
    await tester.tap(find.byTooltip('Table style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Header'));
    await tester.pumpAndSettle();
    // The table sits centered in the design frame (330..950 × 190..530):
    // long-press its upper band — high enough to clear the open sheet's
    // own overlay, deep enough to be inside the object.
    final rect = tester.getRect(find.byType(ShapesLayer));
    final scale = rect.width / 1280;
    await tester.longPressAt(
        Offset(rect.left + 640 * scale, rect.top + 220 * scale));
    await tester.pumpAndSettle();
    expect(find.text('Object actions'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(recordedDeletes, hasLength(1));
    // The orphan sweep: the next op's request deck carries NO tables
    // metadata (the entry went with its object).
    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rectangle'));
    await tester.pumpAndSettle();
    final deck = recordedObjectOps.last['deck'] as Map;
    expect(deck['tables'], isNull,
        reason: 'the deleted table took its metadata with it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('undo restores a table edit as one step', (tester) async {
    await pumpEditor(tester);
    await insertTable(tester);
    await selectCell(tester, 0);
    await tapChip(tester, 'table_chip_add_row');
    expect(find.byKey(const ValueKey('table_cell_11')), findsOneWidget,
        reason: 'the fourth row landed');
    // One undo step returns the 3×3 (the metadata and the cells came back
    // from the same snapshot).
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('table_cell_9')), findsNothing,
        reason: 'back to three rows');
    expect(find.byKey(const ValueKey('table_cell_8')), findsOneWidget);
    // Redo walks it forward again.
    await tester.tap(find.byIcon(Icons.redo));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('table_cell_11')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
