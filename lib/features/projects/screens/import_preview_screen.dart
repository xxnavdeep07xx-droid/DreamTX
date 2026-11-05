import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/services.dart';
import '../repositories/project_repository.dart';
import '../services/file_import_service.dart';
import '../widgets/import_file_card.dart';
import 'editor_placeholder_screen.dart';

/// Import preview: file facts, validation status and the staged actions.
///
/// Honest about the current state of the product — a staged import creates
/// a project marked "Import pending"; the conversion engine ships
/// separately and nothing pretends otherwise.
class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({super.key, required this.import});

  final ImportCandidate import;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  bool _continuing = false;

  bool get _canContinue => widget.import.isSupported && !_continuing;

  Future<void> _pickDifferentFile() async {
    try {
      final candidate = await fileImportService.pickFile();
      if (candidate == null) return; // user cancelled the picker
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ImportPreviewScreen(import: candidate),
        ),
      );
    } on FilePickerUnsupportedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File import is available in the Android app.'),
        ),
      );
    }
  }

  Future<void> _continue() async {
    if (!_canContinue) return;
    setState(() => _continuing = true);

    try {
      final project = await projectService.importProject(
        import: widget.import,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => EditorPlaceholderScreen(project: project),
        ),
      );
    } on ProjectStorageException catch (error) {
      if (!mounted) return;
      setState(() => _continuing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't stage the import (${error.message}). "
            'Check available storage and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import File')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                children: [
                  ImportFileCard(import: widget.import),
                  const SizedBox(height: 26),
                  const Text(
                    'Import status',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ImportStatusCard(
                    import: widget.import,
                    onPickDifferent: _pickDifferentFile,
                  ),
                ],
              ),
            ),
            _ImportActionsBar(
              canContinue: _canContinue,
              continuing: _continuing,
              onCancel: () => Navigator.of(context).pop(),
              onContinue: _continue,
            ),
          ],
        ),
      ),
    );
  }
}

/// Validation outcome with a clear, honest explanation of what happens
/// next — including a dedicated message for unsupported formats.
class _ImportStatusCard extends StatelessWidget {
  const _ImportStatusCard({
    required this.import,
    required this.onPickDifferent,
  });

  final ImportCandidate import;
  final VoidCallback onPickDifferent;

  @override
  Widget build(BuildContext context) {
    final supported = import.isSupported;
    final accent = supported ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: supported ? AppColors.border : accent.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                supported
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 19,
                color: accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  supported
                      ? 'Validated · ready to import'
                      : "'.${import.extension}' files aren't supported yet",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            supported
                ? 'The file will be added to your library as a new project '
                    'marked "Import pending". The document conversion engine '
                    'is still in development — your slides will appear once '
                    'it ships.'
                : '${import.unsupportedHint} Tap "Choose Another File" to '
                    'pick a different document.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          if (!supported) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onPickDifferent,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Choose Another File'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cancel / Continue actions pinned above the keyboard area.
class _ImportActionsBar extends StatelessWidget {
  const _ImportActionsBar({
    required this.canContinue,
    required this.continuing,
    required this.onCancel,
    required this.onContinue,
  });

  final bool canContinue;
  final bool continuing;
  final VoidCallback onCancel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: continuing ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('import-continue-button'),
                onPressed: canContinue ? onContinue : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: continuing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
