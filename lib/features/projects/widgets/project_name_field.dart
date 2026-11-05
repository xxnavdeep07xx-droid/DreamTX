import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';

/// Labelled name input for the project configuration screen.
///
/// Shows the "Untitled Presentation" fallback as quiet helper text so the
/// default is never a surprise.
class ProjectNameField extends StatelessWidget {
  const ProjectNameField({
    super.key,
    required this.controller,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Presentation Name',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('project-name-field'),
          controller: controller,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted?.call(),
          inputFormatters: [
            LengthLimitingTextInputFormatter(80),
            FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
          ],
          decoration: const InputDecoration(
            hintText: 'Give your presentation a name',
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Leave this empty to use 'Untitled Presentation'.",
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
