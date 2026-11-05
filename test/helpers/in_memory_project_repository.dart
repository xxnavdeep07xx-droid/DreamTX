import 'package:dreamtx/features/projects/models/presentation_project.dart';
import 'package:dreamtx/features/projects/repositories/project_repository.dart';

/// Microtask-backed repository for widget tests.
///
/// `testWidgets` runs inside a fake async zone where real file IO never
/// completes, so screens under test are wired to this in-memory
/// implementation. The real persistence is covered by the plain `test()`
/// suite in `repositories/local_project_repository_test.dart`.
class InMemoryProjectRepository extends ProjectRepository {
  final List<PresentationProject> _projects = <PresentationProject>[];
  int _counter = 0;

  @override
  Future<PresentationProject> add({
    required String name,
    required int slideWidthEmu,
    required int slideHeightEmu,
    required ProjectSource source,
    required ProjectStatus status,
    String? sourceUri,
  }) async {
    final now = DateTime.now();
    final id = 'p-test-${_counter++}';
    final project = PresentationProject(
      id: id,
      name: name,
      createdAt: now,
      modifiedAt: now,
      slideWidthEmu: slideWidthEmu,
      slideHeightEmu: slideHeightEmu,
      slides: const <String>[],
      source: source,
      status: status,
      filePath: '/tmp/dreamtx-test/$id.dreamtx',
      sourceUri: sourceUri,
    );
    _projects.insert(0, project);
    notifyListeners();
    return project;
  }

  @override
  Future<List<PresentationProject>> allProjects() async {
    final sorted = [..._projects]
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return sorted;
  }

  @override
  Future<void> delete(String id) async {
    _projects.removeWhere((project) => project.id == id);
    notifyListeners();
  }

  @override
  Future<PresentationProject> duplicate(String id) async {
    final source = await findById(id);
    if (source == null) {
      throw ProjectStorageException('No project with id "$id"');
    }
    final now = DateTime.now();
    final newId = 'p-test-${_counter++}';
    final copy = PresentationProject(
      id: newId,
      name: '${source.name} (Copy)',
      createdAt: now,
      modifiedAt: now,
      slideWidthEmu: source.slideWidthEmu,
      slideHeightEmu: source.slideHeightEmu,
      slides: source.slides,
      source: source.source,
      status: source.status,
      filePath: '/tmp/dreamtx-test/$newId.dreamtx',
      sourceUri: source.sourceUri,
    );
    _projects.insert(0, copy);
    notifyListeners();
    return copy;
  }

  @override
  Future<PresentationProject?> findById(String id) async {
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  @override
  Future<List<PresentationProject>> recentProjects({int limit = 8}) async {
    final projects = await allProjects();
    return projects.length <= limit ? projects : projects.sublist(0, limit);
  }

  @override
  Future<PresentationProject> rename(String id, String newName) async {
    final project = await findById(id);
    if (project == null) {
      throw ProjectStorageException('No project with id "$id"');
    }
    final updated =
        project.copyWith(name: newName, modifiedAt: DateTime.now());
    final index = _projects.indexWhere((p) => p.id == id);
    _projects[index] = updated;
    notifyListeners();
    return updated;
  }
}
