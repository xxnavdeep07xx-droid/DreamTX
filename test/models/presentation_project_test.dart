import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/features/projects/models/presentation_project.dart';
import 'package:dreamtx/features/projects/models/slide_size.dart';

PresentationProject _sample() => PresentationProject(
      id: 'p-sample',
      name: 'Quantum Review',
      createdAt: DateTime.utc(2026, 11, 5, 9, 30),
      modifiedAt: DateTime.utc(2026, 11, 5, 10, 15),
      slideWidthEmu: SlideSize.widescreen.widthEmu,
      slideHeightEmu: SlideSize.widescreen.heightEmu,
      slides: const <String>[],
      source: ProjectSource.blank,
      status: ProjectStatus.active,
      filePath: '/data/projects/p-sample.dreamtx',
      sourceUri: null,
    );

void main() {
  group('PresentationProject JSON round-trip', () {
    test('restores every persisted field', () {
      final original = _sample();
      final restored = PresentationProject.fromJson(
        original.toJson(),
        filePath: original.filePath,
      );

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.createdAt, original.createdAt);
      expect(restored.modifiedAt, original.modifiedAt);
      expect(restored.slideWidthEmu, original.slideWidthEmu);
      expect(restored.slideHeightEmu, original.slideHeightEmu);
      expect(restored.slides, isEmpty);
      expect(restored.slideCount, 0);
      expect(restored.source, ProjectSource.blank);
      expect(restored.status, ProjectStatus.active);
      expect(restored.filePath, original.filePath);
      expect(restored.sourceUri, isNull);
    });

    test('keeps imported metadata through a round-trip', () {
      final original = _sample().copyWith();
      const uri = 'content://com.android.providers/42';
      final imported = PresentationProject.fromJson(
        {
          ...original.toJson(),
          'source': 'imported',
          'status': 'importPending',
          'sourceUri': uri,
        },
        filePath: original.filePath,
      );
      final restored = PresentationProject.fromJson(
        imported.toJson(),
        filePath: original.filePath,
      );

      expect(restored.source, ProjectSource.imported);
      expect(restored.sourceLabel, 'Imported file');
      expect(restored.status, ProjectStatus.importPending);
      expect(restored.statusLabel, 'Import pending');
      expect(restored.sourceUri, uri);
    });
  });

  group('PresentationProject malformed documents', () {
    test('rejects an unknown format identifier', () {
      expect(
        () => PresentationProject.fromJson(
          <String, dynamic>{'format': 'something.else'},
          filePath: '/x',
        ),
        throwsFormatException,
      );
    });

    test('rejects a missing id', () {
      final json = _sample().toJson()..remove('id');
      expect(
        () => PresentationProject.fromJson(json, filePath: '/x'),
        throwsFormatException,
      );
    });

    test('rejects an unknown enum value', () {
      final json = _sample().toJson();
      json['source'] = 'carrierPigeon';
      expect(
        () => PresentationProject.fromJson(json, filePath: '/x'),
        throwsFormatException,
      );
    });

    test('rejects a malformed timestamp', () {
      final json = _sample().toJson();
      json['createdAt'] = 'not-a-date';
      expect(
        () => PresentationProject.fromJson(json, filePath: '/x'),
        throwsFormatException,
      );
    });
  });

  group('PresentationProject helpers', () {
    test('slide count and labels', () {
      final project = _sample();
      expect(project.slideCountLabel, '0 slides');
      expect(project.aspectRatio, closeTo(16 / 9, 1e-9));
      expect(project.slideSize.preset, SlideSizePreset.widescreen);
    });

    test('copyWith only changes the requested fields', () {
      final project = _sample();
      final renamed = project.copyWith(name: 'Renamed');
      expect(renamed.name, 'Renamed');
      expect(renamed.id, project.id);
      expect(renamed.createdAt, project.createdAt);
      expect(renamed.modifiedAt, project.modifiedAt);
      expect(renamed.slides, project.slides);
    });

    test('equality is by id', () {
      final a = _sample();
      final b = _sample().copyWith(name: 'Different name');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
