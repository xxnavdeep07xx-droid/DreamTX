import '../repositories/connection_repository.dart';
import '../repositories/design_repository.dart';
import '../repositories/project_repository.dart';

/// Minimal manual service locator.
///
/// Swap these instances for real implementations (database, native core)
/// without touching any screen.
ProjectRepository projectRepository = MockProjectRepository();
DesignRepository designRepository = MockDesignRepository();
ConnectionRepository connectionRepository = MockConnectionRepository();
