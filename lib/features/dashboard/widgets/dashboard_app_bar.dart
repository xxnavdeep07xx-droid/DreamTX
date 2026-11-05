import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/pressable_card.dart';

/// Compact top bar: brand, notifications, profile.
class DashboardAppBar extends StatelessWidget {
  const DashboardAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AppLogo(size: 34),
        const SizedBox(width: 11),
        const Text(
          'DreamTX',
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        PressableCard(
          onTap: () => AppRoutes.openNotifications(context),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 19,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        PressableCard(
          onTap: () => AppRoutes.openSettings(context),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.violet.withOpacity(0.16),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.violet.withOpacity(0.30)),
            ),
            child: const Center(
              child: Text(
                'AR',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: AppColors.violet,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
