import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Quiet empty state with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.centered = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 26, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            fontSize: 13,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    );

    if (centered) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(28), child: content),
      );
    }
    return content;
  }
}
