import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Application theme — a single, carefully tuned dark theme.
abstract final class AppTheme {
  static ThemeData dark() {
    const ColorScheme colorScheme = ColorScheme.dark(
      primary: AppColors.violet,
      onPrimary: Colors.white,
      primaryContainer: AppColors.violetDeep,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.blue,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.card,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: AppColors.danger,
      onError: Colors.white,
    );

    final ButtonStyle filledStyle = FilledButton.styleFrom(
      backgroundColor: AppColors.violet,
      foregroundColor: Colors.white,
      elevation: 0,
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: AppTypography.textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppColors.textPrimary,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          color: AppColors.textPrimary,
        ),
        position: PopupMenuPosition.under,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1B1B23),
        hintStyle: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.violet, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: filledStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          minimumSize: const Size.fromHeight(42),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.violet,
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.violet
              : const Color(0xFF2A2A33),
        ),
        thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.violet,
        linearTrackColor: AppColors.border,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.violet.withOpacity(0.16),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.violet
                : AppColors.textTertiary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (states) => TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.2,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textTertiary,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
    );
  }
}
