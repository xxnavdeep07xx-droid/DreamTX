import 'package:dreamtx/features/projects/services/file_import_service.dart';
import 'package:dreamtx/features/projects/services/project_service.dart';
import 'package:dreamtx/shared/services/file_picker_service.dart';
import 'package:dreamtx/shared/services/services.dart';

import 'in_memory_project_repository.dart';

/// Rewires the service-locator globals to microtask-backed fakes so widget
/// tests run inside the fake async zone without real IO.
void installWidgetTestGlobals() {
  projectRepository = InMemoryProjectRepository();
  projectService = ProjectService(projectRepository);
  fileImportService = const FileImportService();
}

/// A [FilePickerService] stand-in that returns a predetermined file —
/// widget tests use it to simulate a completed native picker session.
class FakeFilePicker implements FilePickerService {
  const FakeFilePicker({this.nextFile});

  final PickedFile? nextFile;

  @override
  Future<PickedFile?> pickDocument() async => nextFile;
}
