import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/models/project.dart';

/// Honest placeholder shown when a project is opened.
///
/// The real presentation editor is a separate, upcoming milestone.
class EditorPlaceholderScreen extends StatelessWidget {
  const EditorPlaceholderScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(project.title)),
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
                '"${project.title}" (${project.slideCountLabel}) is saved in '
                'your library. The DreamTX presentation editor is in '
                'development and will open right here.',
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
