import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/features/projects/models/presentation_project.dart';
import 'package:dreamtx/features/projects/models/slide_size.dart';
import 'package:dreamtx/features/projects/repositories/project_repository.dart';
import 'package:dreamtx/features/projects/services/file_import_service.dart';
import 'package:dreamtx/features/projects/services/project_service.dart';
import 'package:dreamtx/shared/services/file_picker_service.dart';

class _FakePicker implements FilePickerService {
  const _FakePicker(this.file);

  final PickedFile? file;

  @override
  Future<PickedFile?> pickDocument() async => file;
}

ImportCandidate candidate(String name) =>
    ImportCandidate.fromPickedFile(PickedFile(
      name: name,
      uri: 'content://android/picked/$name',
      sizeBytes: 2048,
    ));

void main() {
  group('ImportCandidate validation', () {
    test('recognises the three supported formats', () {
      final pptx = candidate('Deck.PPTX');
      expect(pptx.kind, ImportFileKind.powerpoint);
      expect(pptx.isSupported, isTrue);
      expect(pptx.typeLabel, 'PowerPoint presentation');
      expect(pptx.suggestedName, 'Deck');

      final pdf = candidate('report.pdf');
      expect(pdf.kind, ImportFileKind.pdf);
      expect(pdf.typeLabel, 'PDF document');

      final docx = candidate('notes.docx');
      expect(docx.kind, ImportFileKind.word);
      expect(docx.typeLabel, 'Word document');
    });

    test('rejects unsupported extensions with helpful hints', () {
      final txt = candidate('readme.txt');
      expect(txt.isSupported, isFalse);
      expect(txt.unsupportedHint, contains('PPTX, PDF and DOCX'));

      final doc = candidate('legacy.doc');
      expect(doc.isSupported, isFalse);
      expect(doc.unsupportedHint, contains('.docx'));

      final ppt = candidate('legacy.ppt');
      expect(ppt.isSupported, isFalse);
      expect(ppt.unsupportedHint, contains('.pptx'));

      final noExt = candidate('noextension');
      expect(noExt.isSupported, isFalse);
      expect(noExt.extension, 'file');
    });

    test('suggested name handles extension-only file names', () {
      expect(candidate('.pptx').suggestedName, '');
      expect(candidate('deck.pptx').suggestedName, 'deck');
      expect(candidate('Deck.PPTX').suggestedName, 'Deck');
    });
  });

  group('FileImportService', () {
    test('returns null when the user cancels the picker', () async {
      const service = FileImportService(picker: _FakePicker(null));
      expect(await service.pickFile(), isNull);
    });

    test('returns a validated candidate for a picked file', () async {
      const service = FileImportService(
        picker: _FakePicker(
          PickedFile(name: 'Strategy.pptx', uri: 'content://x', sizeBytes: 10),
        ),
      );
      final result = await service.pickFile();
      expect(result, isNotNull);
      expect(result!.isSupported, isTrue);
      expect(result.file.name, 'Strategy.pptx');
    });
  });

  group('ProjectService.createBlankProject', () {
    late ProjectService service;
    late LocalProjectRepository repository;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dreamtx-service-test');
      repository = LocalProjectRepository(
        directoryResolver: () async => tempDir,
      );
      service = ProjectService(repository);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('stores the real selected dimensions (EMU), not a label', () async {
      final project = await service.createBlankProject(
        name: 'Portrait pitch',
        slideSize: SlideSize.portrait,
      );

      expect(project.name, 'Portrait pitch');
      expect(project.slideWidthEmu, 6858000);
      expect(project.slideHeightEmu, 12192000);
      expect(project.source, ProjectSource.blank);
      expect(project.status, ProjectStatus.active);
      expect(project.slides, isEmpty, reason: 'empty slide collection');
      expect(await File(project.filePath).exists(), isTrue);
    });

    test('custom sizes are converted to EMU', () async {
      final project = await service.createBlankProject(
        name: 'Custom',
        slideSize: SlideSize.tryCustom(widthInches: 8.5, heightInches: 11)!,
      );
      expect(project.slideWidthEmu, 7772400);
      expect(project.slideHeightEmu, 10058400);
    });

    test('falls back to "Untitled Presentation" for an empty name',
        () async {
      final project = await service.createBlankProject(
        name: '   ',
        slideSize: SlideSize.widescreen,
      );
      expect(project.name, ProjectService.fallbackName);
    });

    test('trims and clamps overly long names', () async {
      final long = 'a' * 200;
      final project = await service.createBlankProject(
        name: '  $long  ',
        slideSize: SlideSize.widescreen,
      );
      expect(project.name, hasLength(ProjectService.maxNameLength));
    });

    test('storage failures propagate — success is never simulated',
        () async {
      final broken = LocalProjectRepository(
        directoryResolver: () async =>
            throw const ProjectStorageException('storage gone'),
      );
      await expectLater(
        ProjectService(broken).createBlankProject(
          name: 'Ghost',
          slideSize: SlideSize.widescreen,
        ),
        throwsA(isA<ProjectStorageException>()),
      );
    });
  });

  group('ProjectService.importProject', () {
    late ProjectService service;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dreamtx-import-test');
      service = ProjectService(LocalProjectRepository(
        directoryResolver: () async => tempDir,
      ));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('stages a supported file as an import-pending project', () async {
      final project = await service.importProject(
        import: candidate('Business Strategy.pptx'),
      );

      expect(project.name, 'Business Strategy');
      expect(project.source, ProjectSource.imported);
      expect(project.status, ProjectStatus.importPending);
      expect(project.sourceUri, 'content://android/picked/Business Strategy.pptx');
      expect(project.slides, isEmpty);
      expect(await File(project.filePath).exists(), isTrue);
    });

    test('rejects unsupported files before touching storage', () async {
      await expectLater(
        service.importProject(import: candidate('photo.png')),
        throwsArgumentError,
      );
      expect(await LocalProjectRepository(
        directoryResolver: () async => tempDir,
      ).allProjects(), isEmpty);
    });

    test('uses a sensible fallback for files without a usable name',
        () async {
      final project = await service.importProject(
        import: candidate('.pdf'),
      );
      expect(project.name, ProjectService.importFallbackName);
    });
  });
}
