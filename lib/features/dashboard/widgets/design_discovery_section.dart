import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/models/design_collection.dart';
import '../../../shared/services/services.dart';
import '../../../shared/widgets/direction_preview.dart';
import '../../../shared/widgets/pressable_card.dart';
import '../../../shared/widgets/section_header.dart';

/// Horizontally scrollable design directions.
///
/// These are visual directions — the future design engine will generate
/// compositions dynamically. They are not templates.
class DesignDiscoverySection extends StatefulWidget {
  const DesignDiscoverySection({super.key});

  @override
  State<DesignDiscoverySection> createState() => _DesignDiscoverySectionState();
}

class _DesignDiscoverySectionState extends State<DesignDiscoverySection> {
  late final Future<List<DesignCollection>> _future;

  @override
  void initState() {
    super.initState();
    _future = designRepository.collections();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Explore Design',
          caption: 'Discover different visual directions.',
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 184,
          child: FutureBuilder<List<DesignCollection>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final collections = snapshot.data ?? const [];
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: collections.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => DesignDirectionCard(
                  collection: collections[index],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DesignDirectionCard extends StatelessWidget {
  const DesignDirectionCard({super.key, required this.collection});

  final DesignCollection collection;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: () => AppRoutes.openDesignDirection(context, collection),
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 92,
                width: double.infinity,
                child: CustomPaint(
                  painter: DirectionPreviewPainter(collection.direction),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              collection.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              collection.blurb,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
