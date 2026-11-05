import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/app/app.dart';
import 'package:dreamtx/features/projects/screens/import_preview_screen.dart';
import 'package:dreamtx/features/projects/services/file_import_service.dart';
import 'package:dreamtx/shared/services/file_picker_service.dart';
import 'package:dreamtx/shared/services/services.dart';

import '../helpers/widget_test_globals.dart';

/// A picker that behaves like the native channel being unavailable
/// (non-Android host): picking always throws.
class _UnavailablePicker implements FilePickerService {
  const _UnavailablePicker();

  @override
  Future<PickedFile?> pickDocument() async =>
      throw const FilePickerUnsupportedException('no native picker');
}

void main() {
  setUp(installWidgetTestGlobals);

  Finder tap(String text) => find.text(text);

  group('CreationOptionsScreen', () {
    testWidgets('shows the headline and all three options', (tester) async {
      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();

      expect(tap("Let's create something."), findsOneWidget);
      expect(
        tap("Choose how you'd like to begin your next presentation."),
        findsOneWidget,
      );
      expect(tap('Start from Scratch'), findsOneWidget);
      expect(tap('Import a File'), findsOneWidget);
      expect(tap('Use an AI Assistant'), findsOneWidget);
      expect(tap('PPTX · PDF · DOCX'), findsOneWidget);
    });

    testWidgets('Start from Scratch opens the project configuration',
        (tester) async {
      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('option-start-from-scratch')));
      await tester.pumpAndSettle();

      expect(tap('Presentation Name'), findsOneWidget);
      expect(tap('Slide Size'), findsOneWidget);
      expect(find.byKey(const Key('create-presentation-button')), findsOneWidget);
    });

    testWidgets('AI assistant option opens the connections destination',
        (tester) async {
      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('option-ai-assistant')));
      // The mock connection repository resolves after a short delay.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(tap('Create with an AI assistant'), findsOneWidget);
      expect(find.textContaining('Connect an assistant'), findsOneWidget);
      expect(
        find.textContaining('Nothing is connected yet'),
        findsOneWidget,
      );
    });

    testWidgets(
        'import option explains itself when the native picker is unavailable',
        (tester) async {
      // Simulates the off-Android case: the native picker channel is
      // missing and FilePickerService surfaces that as an exception.
      fileImportService = const FileImportService(
        picker: _UnavailablePicker(),
      );

      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('option-import-file')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('File import is available in the Android app.'),
        findsOneWidget,
      );
      // Still on the creation options screen — nothing crashed.
      expect(tap('Start from Scratch'), findsOneWidget);
    });

    testWidgets('import option with a fake picker opens the preview',
        (tester) async {
      fileImportService = const FileImportService(
        picker: FakeFilePicker(
          nextFile: PickedFile(
            name: 'Quarterly Review.pptx',
            uri: 'content://picked/quarterly.pptx',
            sizeBytes: 4096,
          ),
        ),
      );

      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('option-import-file')));
      await tester.pumpAndSettle();

      expect(find.byType(ImportPreviewScreen), findsOneWidget);
      expect(tap('Quarterly Review.pptx'), findsOneWidget);
      expect(tap('.pptx'), findsOneWidget);
      expect(tap('PowerPoint presentation'), findsOneWidget);
    });
  });

  group('ProjectConfigurationScreen', () {
    Finder createButton() => find.byKey(const Key('create-presentation-button'));

    Future<void> openConfiguration(WidgetTester tester) async {
      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option-start-from-scratch')));
      await tester.pumpAndSettle();
    }

    testWidgets('defaults to widescreen with a create action', (tester) async {
      await openConfiguration(tester);

      expect(find.textContaining('13.33 × 7.5 in'), findsWidgets);
      expect(tester.widget<FilledButton>(createButton()).onPressed, isNotNull);
    });

    testWidgets('creates an untitled widescreen project and opens the editor',
        (tester) async {
      await openConfiguration(tester);

      await tester.tap(createButton());
      await tester.pumpAndSettle();

      expect(tap('The editor is next'), findsOneWidget);
      expect(find.textContaining('Untitled Presentation'), findsWidgets);

      final projects = await projectRepository.allProjects();
      expect(projects, hasLength(1));
      expect(projects.first.name, 'Untitled Presentation');
      expect(projects.first.slideWidthEmu, 12192000);
      expect(projects.first.slideHeightEmu, 6858000);
    });

    testWidgets('uses the entered project name', (tester) async {
      await openConfiguration(tester);

      await tester.enterText(
        find.byKey(const Key('project-name-field')),
        'Launch Narrative',
      );
      await tester.tap(createButton());
      await tester.pumpAndSettle();

      final projects = await projectRepository.allProjects();
      expect(projects.first.name, 'Launch Narrative');
      expect(find.text('Launch Narrative'), findsWidgets);
    });

    testWidgets('selecting portrait updates the visible dimensions',
        (tester) async {
      await openConfiguration(tester);

      await tester.tap(tap('Portrait'));
      await tester.pumpAndSettle();

      expect(find.textContaining('7.5 × 13.33 in'), findsWidgets);
      expect(find.textContaining('Slides will measure 7.5 × 13.33 in'),
          findsOneWidget);
    });

    testWidgets('custom size: create is disabled until dimensions are valid',
        (tester) async {
      await openConfiguration(tester);

      await tester.tap(tap('Custom'));
      await tester.pumpAndSettle();

      // No dimensions entered yet — creation must be impossible.
      expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('custom-width-field')),
        'abc',
      );
      await tester.enterText(
        find.byKey(const Key('custom-height-field')),
        '10',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);
      expect(tap('Enter a number'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('custom-width-field')),
        '8.5',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(createButton()).onPressed, isNotNull);
      expect(find.textContaining('8.5 × 10 in'), findsOneWidget);

      await tester.tap(createButton());
      await tester.pumpAndSettle();

      final projects = await projectRepository.allProjects();
      expect(projects.first.slideWidthEmu, 7772400);
      expect(projects.first.slideHeightEmu, 9144000);
    });

    testWidgets('custom size in centimetres converts to EMU', (tester) async {
      await openConfiguration(tester);

      await tester.tap(tap('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(tap('cm'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('custom-width-field')),
        '25.4',
      );
      await tester.enterText(
        find.byKey(const Key('custom-height-field')),
        '19.05',
      );
      await tester.pumpAndSettle();

      await tester.tap(createButton());
      await tester.pumpAndSettle();

      final projects = await projectRepository.allProjects();
      expect(projects.first.slideWidthEmu, 9144000);
      expect(projects.first.slideHeightEmu, 6858000);
    });

    testWidgets('back navigation keeps the entered name while on the flow',
        (tester) async {
      await openConfiguration(tester);
      await tester.enterText(
        find.byKey(const Key('project-name-field')),
        'Still here',
      );

      // Open something in front (the app bar back is system navigation, so
      // instead verify the field keeps its content after a rebuild).
      await tester.tap(tap('Portrait'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(
          find.byKey(const Key('project-name-field')),
        ).controller!.text,
        'Still here',
      );
    });

    testWidgets('no layout overflow on a small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 569));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openConfiguration(tester);

      await tester.tap(tap('Custom'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the configuration screen must not overflow');
    });

    testWidgets('keyboard does not hide the create button', (tester) async {
      await openConfiguration(tester);

      await tester.tap(find.byKey(const Key('project-name-field')));
      await tester.pump();

      expect(find.byKey(const Key('create-presentation-button')).hitTestable(),
          findsOneWidget,
          reason: 'the create action must stay visible while typing');
    });
  });

  group('ImportPreviewScreen', () {
    testWidgets('supported file: validated status and working continue',
        (tester) async {
      fileImportService = const FileImportService(
        picker: FakeFilePicker(
          nextFile: PickedFile(
            name: 'Business Strategy.pptx',
            uri: 'content://picked/strategy.pptx',
            sizeBytes: 1024 * 512,
          ),
        ),
      );

      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option-import-file')));
      await tester.pumpAndSettle();

      expect(tap('Validated · ready to import'), findsOneWidget);
      expect(find.textContaining('512 KB'), findsOneWidget);
      expect(find.byKey(const Key('import-continue-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('import-continue-button')));
      await tester.pumpAndSettle();

      expect(tap('The editor is next'), findsOneWidget);
      expect(tap('Import pending'), findsOneWidget);

      final projects = await projectRepository.allProjects();
      expect(projects, hasLength(1));
      expect(projects.first.name, 'Business Strategy');
      expect(projects.first.status.label, 'Import pending');
    });

    testWidgets('unsupported file: helpful message and disabled continue',
        (tester) async {
      fileImportService = const FileImportService(
        picker: FakeFilePicker(
          nextFile: PickedFile(
            name: 'holiday.png',
            uri: 'content://picked/holiday.png',
            sizeBytes: 900,
          ),
        ),
      );

      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option-import-file')));
      await tester.pumpAndSettle();

      expect(tap("'.png' files aren't supported yet"), findsOneWidget);
      expect(find.textContaining('PPTX, PDF and DOCX'), findsOneWidget);
      expect(tap('Choose Another File'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('import-continue-button')),
      );
      expect(button.onPressed, isNull,
          reason: 'unsupported files must not be importable');

      // Nothing was staged.
      expect(await projectRepository.allProjects(), isEmpty);
    });

    testWidgets('cancel returns without creating anything', (tester) async {
      fileImportService = const FileImportService(
        picker: FakeFilePicker(
          nextFile: PickedFile(
            name: 'deck.pdf',
            uri: 'content://picked/deck.pdf',
            sizeBytes: 10,
          ),
        ),
      );

      await tester.pumpWidget(const DreamTxApp());
      await tester.tap(find.byKey(const Key('create-presentation-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option-import-file')));
      await tester.pumpAndSettle();

      await tester.tap(tap('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportPreviewScreen), findsNothing);
      expect(await projectRepository.allProjects(), isEmpty);
    });
  });
}
