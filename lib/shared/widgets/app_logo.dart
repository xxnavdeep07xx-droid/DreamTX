import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The DreamTX mark: a neon-gradient chat bubble with a play glyph, text
/// bars and a sparkle burst — presentations that speak.
///
/// Renders the compact variant (bubble + play glyph) below [_compactBelow]
/// so the mark stays legible when used inline at small sizes.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 34});

  final double size;

  /// Below this size the full mark's bars and sparkles smudge; the compact
  /// variant keeps the silhouette readable.
  static const double _compactBelow = 26;

  @override
  Widget build(BuildContext context) {
    final String asset = size < _compactBelow
        ? 'assets/brand/dreamtx_mark_compact.svg'
        : 'assets/brand/dreamtx_mark.svg';
    // The full mark is wider than tall (the sparkle burst reaches right), so
    // it is letterboxed inside the square slot via BoxFit.contain.
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(asset),
    );
  }
}
