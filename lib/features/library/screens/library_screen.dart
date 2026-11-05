import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/models/project.dart';
import '../../../shared/services/services.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pressable_card.dart';
import '../../../shared/widgets/project_overflow_menu.dart';
import '../../../shared/widgets/slide_thumbnail.dart';
import '../../projects/screens/editor_placeholder_screen.dart';

/// Library tab — every project, lazily rendered, kept in sync with the
/// repository.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Project>? _projects;

  @override
  void initState() {
    super.initState();
    projectRepository.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    projectRepository.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final projects = await projectRepository.allProjects();
    if (!mounted) return;
    setState(() => _projects = projects);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: _projects == null
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              itemCount: _projects!.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(projectCount: _projects!.length),
                      if (_projects!.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 36),
                          child: EmptyState(
                            icon: Icons.video_library_outlined,
                            title: 'Your library is empty',
                            message:
                                'Create your first presentation and it will '
                                'show up here.',
                            action: FilledButton.icon(
                              onPressed: () =>
                                  AppRoutes.openNewPresentation(context),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 19),
                              label: const Text('New Presentation'),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ProjectTile(project: _projects![index - 1]),
                );
              },
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.projectCount});

  final int projectCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Library',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => AppRoutes.openNewPresentation(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'All your presentations, ready to open. ($projectCount)',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EditorPlaceholderScreen(project: project),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            SlideThumbnail(project: project, width: 92, height: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${project.slideCountLabel} · Edited ${timeAgo(project.modifiedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            ProjectOverflowMenu(project: project),
          ],
        ),
      ),
    );
  }
}
