import 'package:flutter/material.dart';

/// DreamTX color tokens.
///
/// A restrained, premium dark identity: deep charcoal surfaces, hairline
/// borders, one muted violet accent and one cool blue secondary accent.
abstract final class AppColors {
  // Surfaces
  static const Color background = Color(0xFF0E0E12); // deep charcoal, almost black
  static const Color surface = Color(0xFF15151B); // slightly lighter graphite
  static const Color card = Color(0xFF1A1A21); // subtle dark grey cards
  static const Color cardActive = Color(0xFF20202A);
  static const Color border = Color(0xFF26262E); // very subtle grey border

  // Accents
  static const Color violet = Color(0xFF8B7CF6); // muted violet
  static const Color blue = Color(0xFF6BA6F5); // cool blue
  static const Color violetDeep = Color(0xFF5D5478);

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
