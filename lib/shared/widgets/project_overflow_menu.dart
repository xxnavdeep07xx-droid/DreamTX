import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../features/projects/models/presentation_project.dart';
import '../../features/projects/repositories/project_repository.dart';
import '../services/services.dart';
import '../utils/format.dart';

/// Overflow menu shared by dashboard cards and library rows:
/// Open, Rename, Duplicate, Delete (with confirmation).
class ProjectOverflowMenu extends StatelessWidget {
  const ProjectOverflowMenu({super.key, required this.project, this.color});

  final PresentationProject project;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 18,
        color: color ?? AppColors.textTertiary,
      ),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 178),
      onSelected: (value) => _handleSelected(context, value),
      itemBuilder: (context) => [
        _item('open', Icons.open_in_new_rounded, 'Open'),
        _item('rename', Icons.edit_outlined, 'Rename'),
        _item('duplicate', Icons.copy_rounded, 'Duplicate'),
        const PopupMenuItem<String>(
          value: 'delete',
          height: 42,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.danger),
              SizedBox(width: 12),
              Text(
                'Delete',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 13.5)),
        ],
      ),
    );
  }

  Future<void> _handleSelected(BuildContext context, String value) async {
    switch (value) {
      case 'open':
        if (context.mounted) AppRoutes.openEditor(context, project);
        break;
      case 'rename':
        if (context.mounted) await _showRenameDialog(context);
        break;
      case 'duplicate':
        await _guardStorage(
          context,
          () => projectRepository.duplicate(project.id),
          successMessage: '"${project.name}" duplicated',
        );
        break;
      case 'delete':
        if (context.mounted) await _confirmDelete(context);
        break;
    }
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: project.name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
          decoration: const InputDecoration(hintText: 'Project name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final name = controller.text.trim();
    controller.dispose();

    if (confirmed == true && name.isNotEmpty && name != project.name) {
      if (!context.mounted) return;
      await _guardStorage(context, () => projectRepository.rename(project.id, name));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Project renamed')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          '"${project.name}" (${project.slideCountLabel.toLowerCase()}, '
          'edited ${timeAgo(project.modifiedAt)}) will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerSurface,
              foregroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      await _guardStorage(
        context,
        () => projectRepository.delete(project.id),
        successMessage: '"${project.name}" deleted',
      );
    }
  }

  /// Runs a storage mutation and reports failure honestly instead of
  /// pretending it worked.
  Future<void> _guardStorage(
    BuildContext context,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (successMessage != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on ProjectStorageException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't save the change (${error.message})."),
          ),
        );
      }
    }
  }
}


