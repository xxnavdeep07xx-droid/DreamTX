import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../shared/services/app_storage.dart';
import '../models/presentation_project.dart';

/// Thrown when a project cannot be persisted to or read from local
/// storage. Screens surface this honestly instead of faking success.
class ProjectStorageException implements Exception {
  const ProjectStorageException(this.message);

  final String message;

  @override
  String toString() => 'ProjectStorageException: $message';
}

/// Contract for project persistence.
///
/// The UI only ever talks to this interface, so the local JSON-file
/// implementation can be swapped for a database or the future native core
/// without touching a single screen. Implementations notify listeners when
/// the data set changes.
abstract class ProjectRepository extends ChangeNotifier {
  Future<List<PresentationProject>> recentProjects({int limit = 8});
  Future<List<PresentationProject>> allProjects();
  Future<PresentationProject?> findById(String id);

  /// Persists a new project document and returns the stored project
  /// (including its generated id, timestamps and file location).
  Future<PresentationProject> add({
    required String name,
    required int slideWidthEmu,
    required int slideHeightEmu,
    required ProjectSource source,
    required ProjectStatus status,
    String? sourceUri,
  });

  Future<PresentationProject> rename(String id, String newName);
  Future<PresentationProject> duplicate(String id);
  Future<void> delete(String id);
}

/// File-backed repository storing one JSON document per project inside a
/// `projects` folder of the app's internal storage.
///
/// Reading is resilient: a document that cannot be parsed is skipped (and
/// reported to the debug log) so one damaged file never hides the rest of
/// the library.
class LocalProjectRepository extends ProjectRepository {
  LocalProjectRepository({Future<Directory> Function()? directoryResolver})
      : _resolveDirectory = directoryResolver ?? _defaultDirectory;

  static const String documentExtension = '.dreamtx';

  /// Resolves the platform storage directory. Android only — tests and
  /// hosts without the platform channel get a [ProjectStorageException].
  static Future<Directory> _defaultDirectory() async {
    final directory = await AppStorage.projectsDirectory();
    if (directory == null) {
      throw const ProjectStorageException(
        'Local storage is not available on this platform',
      );
    }
    return directory;
  }

  final Future<Directory> Function() _resolveDirectory;
  Directory? _directoryCache;
  final Random _random = Random();

  Future<Directory> get _directory async {
    if (_directoryCache != null) return _directoryCache!;
    try {
      final directory = await _resolveDirectory();
      await directory.create(recursive: true);
      return _directoryCache = directory;
    } on ProjectStorageException {
      rethrow;
    } on FileSystemException catch (e) {
      throw ProjectStorageException('Storage directory unavailable: $e');
    }
  }

  String _documentPath(Directory directory, String id) =>
      '${directory.path}/$id$documentExtension';

  @override
  Future<List<PresentationProject>> allProjects() async {
    final directory = await _directory;
    final projects = <PresentationProject>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith(documentExtension)) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        projects.add(PresentationProject.fromJson(json, filePath: entity.path));
      } on FormatException catch (e) {
        _log('Skipping unreadable project document ${entity.path}: $e');
      } on FileSystemException catch (e) {
        _log('Skipping inaccessible project document ${entity.path}: $e');
      }
    }
    projects.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return projects;
  }

  @override
  Future<List<PresentationProject>> recentProjects({int limit = 8}) async {
    final projects = await allProjects();
    return projects.length <= limit
        ? projects
        : projects.sublist(0, limit);
  }

  @override
  Future<PresentationProject?> findById(String id) async {
    final projects = await allProjects();
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  @override
  Future<PresentationProject> add({
    required String name,
    required int slideWidthEmu,
    required int slideHeightEmu,
    required ProjectSource source,
    required ProjectStatus status,
    String? sourceUri,
  }) async {
    final directory = await _directory;
    final now = DateTime.now();
    final project = PresentationProject(
      id: _newId(now),
      name: name,
      createdAt: now,
      modifiedAt: now,
      slideWidthEmu: slideWidthEmu,
      slideHeightEmu: slideHeightEmu,
      slides: const <String>[],
      source: source,
      status: status,
      filePath: '',
      sourceUri: sourceUri,
    );
    final stored = _withPath(project, directory);
    await _persist(stored);
    notifyListeners();
    return stored;
  }

  @override
  Future<PresentationProject> rename(String id, String newName) async {
    final project = await _require(id);
    final updated = project.copyWith(name: newName, modifiedAt: DateTime.now());
    await _persist(updated);
    notifyListeners();
    return updated;
  }

  @override
  Future<PresentationProject> duplicate(String id) async {
    final source = await _require(id);
    final directory = await _directory;
    final now = DateTime.now();
    final copy = PresentationProject(
      id: _newId(now),
      name: '${source.name} (Copy)',
      createdAt: now,
      modifiedAt: now,
      slideWidthEmu: source.slideWidthEmu,
      slideHeightEmu: source.slideHeightEmu,
      slides: source.slides,
      source: source.source,
      status: source.status,
      filePath: '',
      sourceUri: source.sourceUri,
    );
    final stored = _withPath(copy, directory);
    await _persist(stored);
    notifyListeners();
    return stored;
  }

  @override
  Future<void> delete(String id) async {
    final directory = await _directory;
    try {
      final file = File(_documentPath(directory, id));
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (e) {
      throw ProjectStorageException('Could not delete "$id": $e');
    }
    notifyListeners();
  }

  // ---- internals ----------------------------------------------------------

  Future<PresentationProject> _require(String id) async {
    final project = await findById(id);
    if (project == null) {
      throw ProjectStorageException('No project with id "$id"');
    }
    return project;
  }

  PresentationProject _withPath(
    PresentationProject project,
    Directory directory,
  ) {
    return PresentationProject(
      id: project.id,
      name: project.name,
      createdAt: project.createdAt,
      modifiedAt: project.modifiedAt,
      slideWidthEmu: project.slideWidthEmu,
      slideHeightEmu: project.slideHeightEmu,
      slides: project.slides,
      source: project.source,
      status: project.status,
      filePath: _documentPath(directory, project.id),
      sourceUri: project.sourceUri,
    );
  }

  Future<void> _persist(PresentationProject project) async {
    try {
      final file = File(project.filePath);
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(project.toJson()), flush: true);
    } on FileSystemException catch (e) {
      throw ProjectStorageException('Could not write "${project.name}": $e');
    }
  }

  String _newId(DateTime now) {
    final stamp = now.microsecondsSinceEpoch.toRadixString(36);
    final noise = _random.nextInt(0x7FFFFFFF).toRadixString(36);
    return 'p-$stamp-$noise';
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[LocalProjectRepository] $message');
    }
  }
}
