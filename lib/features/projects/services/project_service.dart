import '../models/presentation_project.dart';
import '../models/slide_size.dart';
import '../repositories/project_repository.dart';
import 'file_import_service.dart';

/// Orchestrates project creation: validation, defaults and persistence.
///
/// Screens call this service instead of touching the repository directly,
/// keeping presentation logic out of widgets and leaving room for the
/// future editor / conversion engine to hook in.
class ProjectService {
  const ProjectService(this._repository);

  static const int maxNameLength = 80;
  static const String fallbackName = 'Untitled Presentation';
  static const String importFallbackName = 'Imported Presentation';

  final ProjectRepository _repository;

  /// Creates a blank presentation with an empty slide collection.
  ///
  /// An empty [name] falls back to "Untitled Presentation". Throws
  /// [ProjectStorageException] when the document cannot be persisted —
  /// callers must surface that instead of faking success.
  Future<PresentationProject> createBlankProject({
    required String name,
    required SlideSize slideSize,
  }) {
    return _repository.add(
      name: _cleanName(name, fallback: fallbackName),
      slideWidthEmu: slideSize.widthEmu,
      slideHeightEmu: slideSize.heightEmu,
      source: ProjectSource.blank,
      status: ProjectStatus.active,
    );
  }

  /// Stages an imported document as a new project.
  ///
  /// The project is created with [ProjectStatus.importPending] because the
  /// document conversion engine ships separately — nothing pretends the
  /// file was converted. Slide dimensions default to widescreen until the
  /// converter reports the real values.
  Future<PresentationProject> importProject({
    required ImportCandidate import,
  }) async {
    if (!import.isSupported) {
      throw ArgumentError(
        'Cannot import .${import.extension} files',
        'import',
      );
    }
    return _repository.add(
      name: _cleanName(import.suggestedName, fallback: importFallbackName),
      slideWidthEmu: SlideSize.widescreen.widthEmu,
      slideHeightEmu: SlideSize.widescreen.heightEmu,
      source: ProjectSource.imported,
      status: ProjectStatus.importPending,
      sourceUri: import.file.uri,
    );
  }

  String _cleanName(String raw, {required String fallback}) {
    var name = raw.trim().replaceAll('\n', ' ');
    if (name.isEmpty) return fallback;
    if (name.length > maxNameLength) {
      name = name.substring(0, maxNameLength);
    }
    return name;
  }
}
