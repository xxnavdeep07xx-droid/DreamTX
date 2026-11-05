import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/models/project.dart';
import '../../../shared/services/services.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pressable_card.dart';
import '../../../shared/widgets/project_overflow_menu.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/slide_thumbnail.dart';
import '../../projects/screens/editor_placeholder_screen.dart';

/// Recent projects as a horizontal rail, backed by the project repository.
class RecentProjectsSection extends StatefulWidget {
  const RecentProjectsSection({super.key});

  @override
  State<RecentProjectsSection> createState() => _RecentProjectsSectionState();
}

class _RecentProjectsSectionState extends State<RecentProjectsSection> {
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
    final projects = await projectRepository.recentProjects(limit: 6);
    if (!mounted) return;
    setState(() => _projects = projects);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent Projects',
          actionLabel: 'View All',
          onAction: () => AppRoutes.openLibrary(context),
        ),
        const SizedBox(height: 14),
        if (_projects == null)
          const SizedBox(
            height: 198,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_projects!.isEmpty)
          _EmptyProjectsState(
            onCreate: () => AppRoutes.openNewPresentation(context),
          )
        else
          SizedBox(
            height: 198,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _projects!.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  ProjectCard(project: _projects![index]),
            ),
          ),
      ],
    );
  }
}

class _EmptyProjectsState extends StatelessWidget {
  const _EmptyProjectsState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: EmptyState(
        icon: Icons.auto_awesome_motion_outlined,
        title: 'No presentations yet',
        message: 'Your recent work will appear here once you start creating.',
        action: FilledButton.icon(
          onPressed: onCreate,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text('Create Presentation'),
        ),
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: () => _openProject(context),
      child: Container(
        width: 232,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SlideThumbnail(project: project, width: double.infinity),
            ),
            const SizedBox(height: 10),
            Text(
              project.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${project.slideCountLabel} · ${timeAgo(project.modifiedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                ProjectOverflowMenu(project: project),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openProject(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPlaceholderScreen(project: project),
      ),
    );
  }
}
