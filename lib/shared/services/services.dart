import '../../features/projects/repositories/project_repository.dart';
import '../../features/projects/services/file_import_service.dart';
import '../../features/projects/services/project_service.dart';
import '../repositories/connection_repository.dart';
import '../repositories/design_repository.dart';

/// Minimal manual service locator.
///
/// Swap these instances for real implementations (database, native core)
/// without touching any screen. Tests reassign the globals with
/// temp-directory-backed repositories.
ProjectRepository projectRepository = LocalProjectRepository();
ProjectService projectService = ProjectService(projectRepository);
FileImportService fileImportService = const FileImportService();

DesignRepository designRepository = MockDesignRepository();
ConnectionRepository connectionRepository = MockConnectionRepository();
