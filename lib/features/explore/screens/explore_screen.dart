import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/models/design_collection.dart';
import '../../../shared/services/services.dart';
import '../../../shared/widgets/direction_preview.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pressable_card.dart';

/// Explore tab — searchable design directions in a two-column grid.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final List<DesignCollection> _collections = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final collections = await designRepository.collections();
    if (!mounted) return;
    setState(() {
      _collections.addAll(collections);
      _loading = false;
    });
  }

  List<DesignCollection> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _collections;
    return _collections
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) ||
              c.blurb.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          const Text(
            'Explore',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Visual directions for your next presentation.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search directions',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (filtered.isEmpty)
            const EmptyState(
              centered: true,
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message: 'Try a different search term.',
            )
          else
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
              children: [
                for (final collection in filtered)
                  _DirectionGridCard(collection: collection),
              ],
            ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'New directions arrive with the design engine.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionGridCard extends StatelessWidget {
  const _DirectionGridCard({required this.collection});

  final DesignCollection collection;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: () => AppRoutes.openDesignDirection(context, collection),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  child: CustomPaint(
                    painter: DirectionPreviewPainter(collection.direction),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              collection.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              collection.blurb,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
