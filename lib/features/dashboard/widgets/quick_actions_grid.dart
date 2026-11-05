import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/services.dart';
import '../../../shared/widgets/pressable_card.dart';
import '../../projects/screens/import_preview_screen.dart';

/// Four quick actions in a two-column grid.
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  Future<void> _pickAndImport(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final candidate = await fileImportService.pickFile();
      if (candidate == null) return; // user cancelled
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ImportPreviewScreen(import: candidate),
        ),
      );
    } on FilePickerUnsupportedException {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('File import is available in the Android app.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 306,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: QuickActionCard(
                    icon: Icons.file_upload_outlined,
                    accent: AppColors.blue,
                    title: 'Import File',
                    subtitle: 'PDF, DOCX or PPTX',
                    onTap: () => _pickAndImport(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionCard(
                    icon: Icons.note_add_outlined,
                    accent: AppColors.violet,
                    title: 'Blank Project',
                    subtitle: 'Start from scratch',
                    onTap: () => AppRoutes.openProjectConfiguration(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: QuickActionCard(
                    icon: Icons.palette_outlined,
                    accent: AppColors.violet,
                    title: 'Design Studio',
                    subtitle: 'Explore your creativity',
                    onTap: () => AppRoutes.openDesignStudio(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionCard(
                    icon: Icons.folder_outlined,
                    accent: AppColors.blue,
                    title: 'Open Project',
                    subtitle: 'Continue working',
                    onTap: () => AppRoutes.openLibrary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: accent),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
