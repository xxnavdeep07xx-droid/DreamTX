import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/core/media_pickers.dart';
import 'package:dreamtx/core/resources.dart';
import 'package:dreamtx/core/store.dart';
import 'package:dreamtx/screens/editor_screen.dart';

import 'smoke_test.dart' as smoke;

/// The Help tab — the formerly dead ribbon tab is now a real surface: the
/// app's own guide (build a deck, the gestures that have no button, the
/// ribbon map, export), in the shared modal sheet chrome.
void main() {
  late Directory tmp;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('dreamtx_help');
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

  Future<void> pumpEditor(WidgetTester tester) async {
    Bridge.testOverride = smoke.testFakeEngine;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(deck: smoke.deckFixtureForProbe(3))));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('the tab carries an Open help button — the band is alive',
      (tester) async {
    await pumpEditor(tester);
    await openTab(tester, 'Help');
    expect(find.text('Open help'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet opens with the guide\u2019s sections and closes',
      (tester) async {
    await pumpEditor(tester);
    await openTab(tester, 'Help');
    await tester.tap(find.text('Open help'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('help_list')), findsOneWidget);

    // The guide's sections render (the ListView builds lazily — assert
    // each while it is in view), and the gesture rows actually say
    // something actionable.
    expect(find.text('BUILD A DECK'), findsOneWidget);
    expect(find.text('GESTURES'), findsOneWidget);
    expect(find.textContaining('long-press a deck card'), findsOneWidget);
    // The ListView builds lazily — drag down to build and reveal the
    // lower sections instead of ensureVisible (which needs an element
    // already in the tree).
    final list = find.descendant(
        of: find.byKey(const ValueKey('help_list')),
        matching: find.byType(Scrollable));
    // The list builds lazily — scroll each target into existence
    // (scrollUntilVisible walks the scrollable until the finder lands).
    Future<void> reveal(Finder f) async {
      await tester.scrollUntilVisible(f, 160, scrollable: list);
      await tester.pumpAndSettle();
    }

    await reveal(find.textContaining('edge-swipe'));
    expect(find.textContaining('edge-swipe'), findsOneWidget);

    await reveal(find.text('THE RIBBON'));
    expect(find.text('THE RIBBON'), findsOneWidget);
    // The ribbon map covers every tab, including the three this work
    // turned from dead into surfaces.
    await reveal(find.textContaining('Transitions — how each slide arrives'));
    expect(find.textContaining('Transitions — how each slide arrives'),
        findsOneWidget);
    await reveal(find.textContaining('Animations — entrance effects per object'));
    expect(find.textContaining('Animations — entrance effects per object'),
        findsOneWidget);
    await reveal(find.textContaining('Help — this guide'));
    expect(find.textContaining('Help — this guide'), findsOneWidget);

    await reveal(find.text('EXPORT'));
    expect(find.text('EXPORT'), findsOneWidget);

    // Dismiss: the sheet is gone, the editor intact.
    await tester.tapAt(const Offset(20, 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('help_list')), findsNothing);
    expect(find.text('Open help'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
