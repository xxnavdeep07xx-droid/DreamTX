import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../features/projects/screens/editor_placeholder_screen.dart';
import '../models/project.dart';
import '../services/services.dart';
import '../utils/format.dart';

/// Overflow menu shared by dashboard cards and library rows:
/// Open, Rename, Duplicate, Delete (with confirmation).
class ProjectOverflowMenu extends StatelessWidget {
  const ProjectOverflowMenu({super.key, required this.project, this.color});

  final Project project;
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
        if (context.mounted) _openEditor(context);
        break;
      case 'rename':
        if (context.mounted) await _showRenameDialog(context);
        break;
      case 'duplicate':
        final messenger = ScaffoldMessenger.of(context);
        await projectRepository.duplicate(project.id);
        messenger.showSnackBar(
          SnackBar(content: Text('"${project.title}" duplicated')),
        );
        break;
      case 'delete':
        if (context.mounted) await _confirmDelete(context);
        break;
    }
  }

  void _openEditor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPlaceholderScreen(project: project),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: project.title);
    final messenger = ScaffoldMessenger.of(context);

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

    if (confirmed == true && name.isNotEmpty && name != project.title) {
      await projectRepository.rename(project.id, name);
      messenger.showSnackBar(const SnackBar(content: Text('Project renamed')));
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          '"${project.title}" (${project.slideCountLabel.toLowerCase()}, '
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
      await projectRepository.delete(project.id);
      messenger.showSnackBar(
        SnackBar(content: Text('"${project.title}" deleted')),
      );
    }
  }
}


