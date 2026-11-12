import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A filled button wearing the DreamTX ember gradient (violet → magenta →
/// orange, sampled from the mark's sparkle burst).
///
/// Reserved for the primary brand actions — every other action keeps the
/// restrained solid [FilledButton] from the theme.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    this.onPressed,
    this.child,
    this.height = 52,
  });

  final VoidCallback? onPressed;
  final Widget? child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: AppColors.emberGradient,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: enabled ? null : AppColors.cardActive,
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: enabled ? Colors.white : AppColors.textTertiary,
                ),
                child: IconTheme(
                  data: IconThemeData(
                    color: enabled ? Colors.white : AppColors.textTertiary,
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
