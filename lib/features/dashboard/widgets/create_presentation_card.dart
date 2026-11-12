import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/pressable_card.dart';

/// The primary action of the dashboard.
class CreatePresentationCard extends StatelessWidget {
  const CreatePresentationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      key: const Key('create-presentation-card'),
      onTap: () => AppRoutes.openCreationOptions(context),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.violet.withOpacity(0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.violet.withOpacity(0.20),
                    AppColors.pink.withOpacity(0.14),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.violet,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New Presentation',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Start a new creative project',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
