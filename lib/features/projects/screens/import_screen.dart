import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/utils/format.dart';

/// Import preview for a picked document.
///
/// The native Android picker already ran; the document conversion engine is
/// a separate milestone, so this screen is honest about what happens next.
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key, required this.file});

  final PickedFile file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import file')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    size: 21,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 2,
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
                        formatBytes(file.sizeBytes),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Ready to import',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'DreamTX will convert this document into an editable presentation. '
            'The conversion engine is in early development — this file is '
            'staged and will land in your library as soon as import ships.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: () {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop();
              messenger.showSnackBar(
                SnackBar(
                  content:
                      Text('"${file.name}" queued — the document engine will '
                          'handle it soon.'),
                ),
              );
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
