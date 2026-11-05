import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/utils/format.dart';
import '../models/presentation_project.dart';

/// Honest placeholder shown when a project is opened.
///
/// The real presentation editor is a separate, upcoming milestone — this
/// screen surfaces the persisted project facts (size, source, status)
/// until it ships.
class EditorPlaceholderScreen extends StatelessWidget {
  const EditorPlaceholderScreen({super.key, required this.project});

  final PresentationProject project;

  @override
  Widget build(BuildContext context) {
    final pending = project.status == ProjectStatus.importPending;
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
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
                child: const Icon(
                  Icons.slideshow_rounded,
                  size: 31,
                  color: AppColors.violet,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'The editor is next',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"${project.name}" is saved on this device. The DreamTX '
                'presentation editor is in development and will open right '
                'here.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 26),
              _ProjectDetailsCard(project: project),
              if (pending) ...[
                const SizedBox(height: 14),
                _ImportPendingCard(project: project),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The facts actually persisted with the project document.
class _ProjectDetailsCard extends StatelessWidget {
  const _ProjectDetailsCard({required this.project});

  final PresentationProject project;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 11),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          row(Icons.crop_din_rounded, 'Slides',
              project.slideCount == 0 ? 'None yet' : project.slideCountLabel),
          const Divider(height: 1),
          row(
            Icons.aspect_ratio_rounded,
            'Slide size',
            '${project.slideSize.label()} · '
                '${project.slideSize.isPortrait ? 'Portrait' : 'Landscape'}',
          ),
          const Divider(height: 1),
          row(Icons.source_outlined, 'Source', project.sourceLabel),
          const Divider(height: 1),
          row(
            Icons.event_outlined,
            'Created',
            formatDate(project.createdAt),
          ),
        ],
      ),
    );
  }
}

/// Honest status for projects staged from a picked file.
class _ImportPendingCard extends StatelessWidget {
  const _ImportPendingCard({required this.project});

  final PresentationProject project;

  @override
  Widget build(BuildContext context) {
    final fileName = Uri.tryParse(project.sourceUri ?? '')
            ?.pathSegments
            .isNotEmpty ==
        true
        ? Uri.parse(project.sourceUri!).pathSegments.last
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                size: 17,
                color: AppColors.warning,
              ),
              SizedBox(width: 9),
              Text(
                'Import pending',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fileName == null || fileName.isEmpty
                ? 'The source document is staged for conversion. Slides and '
                    'layout will appear here as soon as the import engine '
                    'ships.'
                : '"$fileName" is staged for conversion. Slides and layout '
                    'will appear here as soon as the import engine ships.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
