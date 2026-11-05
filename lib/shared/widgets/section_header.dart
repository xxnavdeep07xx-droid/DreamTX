import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Section title with an optional supporting caption and trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? caption;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 3),
          Text(
            caption!,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
