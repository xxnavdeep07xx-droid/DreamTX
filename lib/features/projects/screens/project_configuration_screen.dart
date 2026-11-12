import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/services/services.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../models/slide_size.dart';
import '../repositories/project_repository.dart';
import '../widgets/project_name_field.dart';
import '../widgets/slide_size_selector.dart';
import 'editor_placeholder_screen.dart';

/// Configuration for a blank presentation: name and slide size.
///
/// On success the project is persisted and the (placeholder) editor opens.
/// If persistence fails the user stays here with a clear error — success
/// is never simulated.
class ProjectConfigurationScreen extends StatefulWidget {
  const ProjectConfigurationScreen({super.key});

  @override
  State<ProjectConfigurationScreen> createState() =>
      _ProjectConfigurationScreenState();
}

class _ProjectConfigurationScreenState extends State<ProjectConfigurationScreen> {
  final TextEditingController _nameController = TextEditingController();
  SlideSize? _slideSize = SlideSize.widescreen;
  bool _creating = false;

  bool get _canCreate => !_creating && _slideSize != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _creating = true);

    try {
      final project = await projectService.createBlankProject(
        name: _nameController.text,
        slideSize: _slideSize!,
      );
      if (!mounted) return;
      // Replace this screen with the editor destination — going back from
      // the editor lands on the creation options, not a stale form.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => EditorPlaceholderScreen(project: project),
        ),
      );
    } on ProjectStorageException catch (error) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't save the project (${error.message}). "
            'Check available storage and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start from Scratch')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  ProjectNameField(
                    controller: _nameController,
                    onSubmitted: () => FocusScope.of(context).unfocus(),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Slide Size',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pick a preset or set exact dimensions.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SlideSizeSelector(
                    onChanged: (size) => setState(() => _slideSize = size),
                  ),
                  const SizedBox(height: 26),
                  const _LocalSaveNote(),
                ],
              ),
            ),
            _CreateBar(
              enabled: _canCreate,
              creating: _creating,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet reassurance about where the project lives.
class _LocalSaveNote extends StatelessWidget {
  const _LocalSaveNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.save_outlined,
            size: 16,
            color: AppColors.textTertiary,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Projects are saved on this device and appear in your '
              'library immediately.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent, always-reachable create action pinned above the keyboard.
class _CreateBar extends StatelessWidget {
  const _CreateBar({
    required this.enabled,
    required this.creating,
    required this.onPressed,
  });

  final bool enabled;
  final bool creating;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: GradientButton(
        key: const Key('create-presentation-button'),
        onPressed: enabled ? onPressed : null,
        child: creating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Create Presentation'),
      ),
    );
  }
}
