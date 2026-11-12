import 'package:flutter/material.dart';

/// DreamTX color tokens.
///
/// A dark identity built around the DreamTX mark: near-black surfaces with
/// hairline borders, an electric violet primary, a periwinkle blue secondary,
/// and the mark's neon gradient family reserved for brand moments.
abstract final class AppColors {
  // Surfaces
  static const Color background = Color(0xFF0E0E12); // deep charcoal, almost black
  static const Color surface = Color(0xFF15151B); // slightly lighter graphite
  static const Color card = Color(0xFF1A1A21); // subtle dark grey cards
  static const Color cardActive = Color(0xFF20202A);
  static const Color border = Color(0xFF26262E); // very subtle grey border

  // Accents — sampled from the DreamTX mark's bubble ring.
  static const Color violet = Color(0xFF8B5CF6); // mark violet, primary
  static const Color blue = Color(0xFF6E9BF0); // mark periwinkle, secondary
  static const Color violetDeep = Color(0xFF4E3FA8); // pressed / container violet

  // Mark gradient family — for brand moments only, keep the UI restrained.
  static const Color sky = Color(0xFF6FD2FA); // ring, top-right
  static const Color pink = Color(0xFFFF4FD8); // sparkles
  static const Color orange = Color(0xFFFF9A3D); // ring, bottom-right
  static const Color gold = Color(0xFFFFC43C); // ring, gold accent

  /// The signature sweep around the mark's bubble ring.
  static const List<Color> markGradient = [
    Color(0xFF9B1BFB), // electric violet
    Color(0xFF6E8CF5), // periwinkle
    Color(0xFF6FD2FA), // sky
    Color(0xFFCE52F2), // orchid
    Color(0xFFFF9A3D), // orange
    Color(0xFFFFC43C), // gold
  ];

  /// Warm accent run used on the primary create action.
  static const List<Color> emberGradient = [
    Color(0xFF8B5CF6), // violet
    Color(0xFFE935C1), // magenta
    Color(0xFFFF9A3D), // orange
  ];

  // Text
  static const Color textPrimary = Color(0xFFEDEDF2); // soft white
  static const Color textSecondary = Color(0xFF9A9AA6); // muted grey
  static const Color textTertiary = Color(0xFF6C6C78);

  // Status
  static const Color success = Color(0xFF6FBF8E);
  static const Color warning = Color(0xFFE0B36A);
  static const Color danger = Color(0xFFE07A7A);
  static const Color dangerSurface = Color(0xFF322026);
}
