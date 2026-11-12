import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// Compact welcome block that sets the app's personality.
class WelcomeSection extends StatelessWidget {
  const WelcomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          // "Create something " stays soft white; "remarkable." catches the
          // mark's violet → pink run. If the line wraps, the gradient still
          // lands on the closing word.
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              AppColors.textPrimary,
              AppColors.textPrimary,
              AppColors.violet,
              AppColors.pink,
            ],
            stops: [0.0, 0.52, 0.78, 1.0],
          ).createShader(bounds),
          child: const Text.rich(
            TextSpan(
              text: 'Create something ',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                height: 1.24,
                color: Colors.white,
              ),
              children: [
                TextSpan(
                  text: 'remarkable.',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
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
