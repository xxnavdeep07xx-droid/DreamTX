import 'package:flutter/material.dart';

import 'app_colors.dart';

/// DreamTX type scale.
///
/// Built on the default Roboto with a refined rhythm: tight display
/// letter-spacing, generous line heights, quiet labels.
abstract final class AppTypography {
  static const TextTheme textTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.24,
      color: AppColors.textPrimary,
    ),
    headlineMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      height: 1.3,
      color: AppColors.textPrimary,
    ),
    titleLarge: TextStyle(
      fontSize: 16.5,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.35,
      color: AppColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.35,
      color: AppColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.5,
      color: AppColors.textSecondary,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.45,
      color: AppColors.textSecondary,
    ),
    labelLarge: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.2,
      color: AppColors.textPrimary,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      height: 1.3,
      color: AppColors.textTertiary,
    ),
  );
}
