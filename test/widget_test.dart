import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/app/app.dart';

import 'helpers/widget_test_globals.dart';

void main() {
  setUp(installWidgetTestGlobals);

  group('DreamTxApp', () {
    testWidgets('renders the dashboard sections', (tester) async {
      // Phone-like tall surface so every dashboard section is built.
      await tester.binding.setSurfaceSize(const Size(412, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const DreamTxApp());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Create something remarkable.'), findsOneWidget);
      expect(find.text('New Presentation'), findsOneWidget);
      expect(find.text('Recent Projects'), findsOneWidget);
      expect(find.text('Explore Design'), findsOneWidget);
      expect(find.text('AI & MCP Connections'), findsOneWidget);
    });

    testWidgets('recent projects shows the honest empty state on a fresh install',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const DreamTxApp());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('No presentations yet'), findsOneWidget);
      expect(find.text('Create Presentation'), findsOneWidget);
    });

    testWidgets('bottom navigation switches destinations', (tester) async {
      await tester.pumpWidget(const DreamTxApp());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('All your presentations, ready to open.'),
        findsOneWidget,
      );
      expect(find.text('Your library is empty'), findsOneWidget);
    });

    testWidgets('create card opens the creation options experience',
        (tester) async {
      await tester.pumpWidget(const DreamTxApp());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();

      expect(find.text("Let's create something."), findsOneWidget);
      expect(find.text('Start from Scratch'), findsOneWidget);
    });

    testWidgets('dashboard scrolls without overflow on a small screen',
        (tester) async {
      // Small Android device (320x569 logical).
      await tester.binding.setSurfaceSize(const Size(320, 569));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const DreamTxApp());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Scrolling to the very end builds every section; any RenderFlex
      // overflow would throw and fail this test.
      await tester.scrollUntilVisible(
        find.text('Crafted for storytellers'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    });
  });
}
