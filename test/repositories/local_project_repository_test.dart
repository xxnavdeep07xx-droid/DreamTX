import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/features/projects/models/presentation_project.dart';
import 'package:dreamtx/features/projects/models/slide_size.dart';
import 'package:dreamtx/features/projects/repositories/project_repository.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dreamtx-repo-test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  LocalProjectRepository newRepository() => LocalProjectRepository(
        directoryResolver: () async => tempDir,
      );

  test('add writes a document that a fresh repository can read', () async {
    final repo = newRepository();
    final created = await repo.add(
      name: 'Quantum Computing',
      slideWidthEmu: SlideSize.widescreen.widthEmu,
      slideHeightEmu: SlideSize.widescreen.heightEmu,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );

    expect(created.name, 'Quantum Computing');
    expect(created.slides, isEmpty);
    expect(created.filePath, endsWith('.dreamtx'));
    expect(await File(created.filePath).exists(), isTrue,
        reason: 'the project document must really be on disk');

    // Simulates an app restart: a brand-new instance reads the same store.
    final reloaded = await newRepository().allProjects();
    expect(reloaded, hasLength(1));
    expect(reloaded.first.id, created.id);
    expect(reloaded.first.name, 'Quantum Computing');
    expect(reloaded.first.slideWidthEmu, SlideSize.widescreen.widthEmu);
    expect(reloaded.first.slideHeightEmu, SlideSize.widescreen.heightEmu);
    expect(reloaded.first.source, ProjectSource.blank);
  });

  test('imported projects keep source URI and pending status on disk',
      () async {
    final repo = newRepository();
    final created = await repo.add(
      name: 'Imported deck',
      slideWidthEmu: SlideSize.widescreen.widthEmu,
      slideHeightEmu: SlideSize.widescreen.heightEmu,
      source: ProjectSource.imported,
      status: ProjectStatus.importPending,
      sourceUri: 'content://picked/deck.pptx',
    );

    final reloaded = await newRepository().findById(created.id);
    expect(reloaded!.source, ProjectSource.imported);
    expect(reloaded.status, ProjectStatus.importPending);
    expect(reloaded.sourceUri, 'content://picked/deck.pptx');
  });

  test('allProjects sorts by last modified, most recent first', () async {
    final repo = newRepository();
    final first = await repo.add(
      name: 'Older',
      slideWidthEmu: 9144000,
      slideHeightEmu: 6858000,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.add(
      name: 'Newer',
      slideWidthEmu: 9144000,
      slideHeightEmu: 6858000,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );

    final all = await repo.allProjects();
    expect(all.map((p) => p.name).toList(), ['Newer', 'Older']);

    final recent = await repo.recentProjects(limit: 1);
    expect(recent, hasLength(1));
    expect(recent.first.name, 'Newer');
    expect(first.name, 'Older');
  });

  test('rename persists the new name and bumps the modified time',
      () async {
    final repo = newRepository();
    final created = await repo.add(
      name: 'Before',
      slideWidthEmu: 9144000,
      slideHeightEmu: 6858000,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final renamed = await repo.rename(created.id, 'After');
    expect(renamed.name, 'After');
    expect(renamed.modifiedAt.isAfter(created.modifiedAt), isTrue);

    final reloaded = await newRepository().findById(created.id);
    expect(reloaded!.name, 'After');
  });

  test('duplicate creates an independent copy', () async {
    final repo = newRepository();
    final created = await repo.add(
      name: 'Original',
      slideWidthEmu: SlideSize.portrait.widthEmu,
      slideHeightEmu: SlideSize.portrait.heightEmu,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );

    final copy = await repo.duplicate(created.id);
    expect(copy.id, isNot(created.id));
    expect(copy.name, 'Original (Copy)');
    expect(copy.slideWidthEmu, SlideSize.portrait.widthEmu);
    expect(await File(copy.filePath).exists(), isTrue);

    final all = await newRepository().allProjects();
    expect(all, hasLength(2));
  });

  test('delete removes the document from disk', () async {
    final repo = newRepository();
    final created = await repo.add(
      name: 'Doomed',
      slideWidthEmu: 9144000,
      slideHeightEmu: 6858000,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );

    await repo.delete(created.id);
    expect(await File(created.filePath).exists(), isFalse);
    expect(await newRepository().allProjects(), isEmpty);
  });

  test('unreadable documents are skipped, not fatal', () async {
    final repo = newRepository();
    await repo.add(
      name: 'Healthy',
      slideWidthEmu: 9144000,
      slideHeightEmu: 6858000,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );

    File('${tempDir.path}/p-corrupt.dreamtx').writeAsStringSync('{oops');
    File('${tempDir.path}/p-badenum.dreamtx').writeAsStringSync(
      jsonEncode({
        'format': PresentationProject.formatIdentifier,
        'id': 'p-badenum',
        'name': 'Bad enum',
        'createdAt': '2026-01-01T00:00:00Z',
        'modifiedAt': '2026-01-01T00:00:00Z',
        'slideWidth': 9144000,
        'slideHeight': 6858000,
        'slides': <String>[],
        'source': 'mystery',
        'status': 'active',
      }),
    );

    final all = await newRepository().allProjects();
    expect(all, hasLength(1));
    expect(all.first.name, 'Healthy');
  });

  test('add reports storage failures instead of faking success', () async {
    final repo = LocalProjectRepository(
      directoryResolver: () async =>
          throw const ProjectStorageException('no native storage'),
    );
    await expectLater(
      repo.add(
        name: 'Ghost',
        slideWidthEmu: 9144000,
        slideHeightEmu: 6858000,
        source: ProjectSource.blank,
        status: ProjectStatus.active,
      ),
      throwsA(isA<ProjectStorageException>()),
    );
  });

  test('an unwritable directory surfaces as a storage exception', () async {
    final blocker = File('${tempDir.path}/blocker');
    await blocker.writeAsString('a file where a folder should be');

    final repo = LocalProjectRepository(
      directoryResolver: () async => Directory('${blocker.path}/projects'),
    );
    await expectLater(
      repo.add(
        name: 'Ghost',
        slideWidthEmu: 9144000,
        slideHeightEmu: 6858000,
        source: ProjectSource.blank,
        status: ProjectStatus.active,
      ),
      throwsA(isA<ProjectStorageException>()),
    );
  });

  test('mutations notify listeners', () async {
    final repo = newRepository();
    var notifications = 0;
    repo.addListener(() => notifications++);

    await repo.add(
      name: 'Listener',
      slideWidthEmu: 9144000,
      slideHeightEmu: 6858000,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );
    expect(notifications, 1);
  });
}
