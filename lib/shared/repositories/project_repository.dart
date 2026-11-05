import 'package:flutter/foundation.dart';

import '../models/project.dart';

/// Contract for project storage.
///
/// The UI only ever talks to this interface, so the in-memory mock can be
/// swapped for a database or the future native core without touching screens.
/// Implementations notify listeners when the data set changes.
abstract class ProjectRepository extends ChangeNotifier {
  Future<List<Project>> recentProjects({int limit});
  Future<List<Project>> allProjects();
  Future<Project> create({required String title});
  Future<void> rename(String id, String newTitle);
  Future<void> duplicate(String id);
  Future<void> delete(String id);
}

/// In-memory mock with realistic seed data and a small simulated latency.
///
/// Mutations notify listeners so open screens refresh themselves.
class MockProjectRepository extends ProjectRepository {
  MockProjectRepository() {
    _projects.addAll(_seedProjects());
  }

  static List<Project> _seedProjects() {
    final now = DateTime.now();
    return [
      Project(
        id: 'p-quantum',
        title: 'Quantum Computing',
        slideCount: 14,
        modifiedAt: now.subtract(const Duration(hours: 2)),
      ),
      Project(
        id: 'p-strategy',
        title: 'Business Strategy',
        slideCount: 22,
        modifiedAt: now.subtract(const Duration(hours: 26)),
      ),
      Project(
        id: 'p-climate',
        title: 'Climate Change',
        slideCount: 9,
        modifiedAt: now.subtract(const Duration(days: 3)),
      ),
      Project(
        id: 'p-architecture',
        title: 'Modern Architecture',
        slideCount: 17,
        modifiedAt: now.subtract(const Duration(days: 6)),
      ),
    ];
  }

  final List<Project> _projects = <Project>[];
  int _nextId = 1;

  Future<void> _simulateLatency() =>
      Future<void>.delayed(const Duration(milliseconds: 260));

  List<Project> _sorted() {
    final sorted = [..._projects]
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return sorted;
  }

  @override
  Future<List<Project>> recentProjects({int limit = 8}) async {
    await _simulateLatency();
    return _sorted().take(limit).toList();
  }

  @override
  Future<List<Project>> allProjects() async {
    await _simulateLatency();
    return _sorted();
  }

  @override
  Future<Project> create({required String title}) async {
    await _simulateLatency();
    final project = Project(
      id: 'p-created-${_nextId++}',
      title: title,
      slideCount: 1,
      modifiedAt: DateTime.now(),
    );
    _projects.insert(0, project);
    notifyListeners();
    return project;
  }

  @override
  Future<void> rename(String id, String newTitle) async {
    await _simulateLatency();
    final index = _projects.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _projects[index] =
          _projects[index].copyWith(title: newTitle, modifiedAt: DateTime.now());
      notifyListeners();
    }
  }

  @override
  Future<void> duplicate(String id) async {
    await _simulateLatency();
    final index = _projects.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final source = _projects[index];
    final copy = Project(
      id: 'p-created-${_nextId++}',
      title: '${source.title} (Copy)',
      slideCount: source.slideCount,
      modifiedAt: DateTime.now(),
    );
    _projects.insert(index + 1, copy);
    notifyListeners();
  }

  @override
  Future<void> delete(String id) async {
    await _simulateLatency();
    _projects.removeWhere((p) => p.id == id);
    notifyListeners();
  }
}
