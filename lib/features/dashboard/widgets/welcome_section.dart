import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// Compact welcome block that sets the app's personality.
class WelcomeSection extends StatelessWidget {
  const WelcomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'Create something ',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              height: 1.24,
              color: AppColors.textPrimary,
            ),
            children: [
              TextSpan(
                text: 'remarkable.',
                style: TextStyle(color: AppColors.violet),
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Bring your ideas to life through thoughtful design.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
