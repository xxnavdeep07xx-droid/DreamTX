import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/utils/format.dart';
import '../services/file_import_service.dart';

/// File summary card for the import preview screen: type icon, name,
/// extension, size and a human-readable type label.
class ImportFileCard extends StatelessWidget {
  const ImportFileCard({super.key, required this.import});

  final ImportCandidate import;

  IconData get _icon => switch (import.kind) {
        ImportFileKind.powerpoint => Icons.slideshow_outlined,
        ImportFileKind.pdf => Icons.picture_as_pdf_outlined,
        ImportFileKind.word => Icons.article_outlined,
        ImportFileKind.unsupported => Icons.insert_drive_file_outlined,
      };

  Color get _accent => switch (import.kind) {
        ImportFileKind.powerpoint => AppColors.violet,
        ImportFileKind.pdf => AppColors.danger,
        ImportFileKind.word => AppColors.blue,
        ImportFileKind.unsupported => AppColors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_icon, size: 23, color: _accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  import.file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '.${import.extension}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      formatBytes(import.file.sizeBytes),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const Text(
                      '·',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      import.typeLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
