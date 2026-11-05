import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/services.dart';
import '../widgets/creation_option_card.dart';

/// Entry point of the project creation experience.
///
/// Three paths: blank project, file import (native picker) and the
/// MCP-powered external assistant workflow.
class CreationOptionsScreen extends StatefulWidget {
  const CreationOptionsScreen({super.key});

  @override
  State<CreationOptionsScreen> createState() => _CreationOptionsScreenState();
}

class _CreationOptionsScreenState extends State<CreationOptionsScreen> {
  bool _picking = false;

  Future<void> _importFromFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final candidate = await fileImportService.pickFile();
      if (candidate == null) return; // user cancelled the picker
      if (!mounted) return;
      AppRoutes.openImportPreview(context, candidate);
    } on FilePickerUnsupportedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File import is available in the Android app.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Presentation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          const Text(
            "Let's create something.",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              height: 1.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Choose how you'd like to begin your next presentation.",
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          CreationOptionCard(
            key: const Key('option-start-from-scratch'),
            icon: Icons.note_add_outlined,
            accent: AppColors.violet,
            emphasis: true,
            title: 'Start from Scratch',
            description:
                'A completely blank canvas. Build everything your way.',
            onTap: () => AppRoutes.openProjectConfiguration(context),
          ),
          const SizedBox(height: 12),
          CreationOptionCard(
            key: const Key('option-import-file'),
            icon: Icons.file_upload_outlined,
            title: 'Import a File',
            description:
                'Bring an existing presentation or document into DreamTX.',
            trailing: 'PPTX · PDF · DOCX',
            onTap: _importFromFile,
          ),
          const SizedBox(height: 12),
          CreationOptionCard(
            key: const Key('option-ai-assistant'),
            icon: Icons.hub_outlined,
            title: 'Use an AI Assistant',
            description:
                'Connect an external AI assistant and create through '
                'DreamTX.',
            badge: 'MCP',
            onTap: () => AppRoutes.openConnections(context),
          ),
        ],
      ),
    );
  }
}
