import 'package:flutter/material.dart';

import '../../features/connections/screens/connections_screen.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/projects/models/presentation_project.dart';
import '../../features/projects/screens/creation_options_screen.dart';
import '../../features/projects/screens/editor_placeholder_screen.dart';
import '../../features/projects/screens/import_preview_screen.dart';
import '../../features/projects/screens/project_configuration_screen.dart';
import '../../features/projects/services/file_import_service.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../shared/models/design_collection.dart';
import 'theme/app_colors.dart';

/// Central navigation helpers — easy to extend with a real router later.
abstract final class AppRoutes {
  static void openCreationOptions(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CreationOptionsScreen()),
    );
  }

  static void openProjectConfiguration(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProjectConfigurationScreen(),
      ),
    );
  }

  static void openImportPreview(
    BuildContext context,
    ImportCandidate import,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportPreviewScreen(import: import),
      ),
    );
  }

  static void openEditor(
    BuildContext context,
    PresentationProject project,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPlaceholderScreen(project: project),
      ),
    );
  }

  static void openConnections(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ConnectionsScreen()),
    );
  }

  static void openDesignStudio(BuildContext context) {
    return _pushComingSoon(
      context,
      title: 'Design Studio',
      message:
          'A creative playground for shaping your own visual language — '
          'palettes, type pairings and layout rules — is on the roadmap.',
      icon: Icons.palette_outlined,
    );
  }

  static void openLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LibraryScreen()),
    );
  }

  static void openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  static void openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  static void openTools(BuildContext context) {
    return _pushComingSoon(
      context,
      title: 'MCP Tools',
      message:
          'Once an assistant is connected, the tools it exposes over MCP will '
          'be listed here.',
      icon: Icons.extension_outlined,
    );
  }

  static void openDesignDirection(
    BuildContext context,
    DesignCollection collection,
  ) {
    return _pushComingSoon(
      context,
      title: collection.name,
      message:
          '${collection.blurb}. "${collection.name}" is a design direction, not '
          'a template — the DreamTX design engine will generate original '
          'compositions in this style.',
      icon: Icons.auto_awesome_outlined,
    );
  }

  static void _pushComingSoon(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComingSoonScreen(
          title: title,
          message: message,
          icon: icon,
        ),
      ),
    );
  }
}

/// Shared placeholder screen for flows that ship later.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: AppColors.violet.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: AppColors.violet.withOpacity(0.25)),
                ),
                child: Icon(icon, size: 31, color: AppColors.violet),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'ON THE ROADMAP',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
