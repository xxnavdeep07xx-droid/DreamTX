/// Slide dimensions for a presentation project.
///
/// Sizes are stored in EMU (English Metric Units — 914400 per inch), the
/// same unit PowerPoint uses internally, so a project document always
/// carries real dimensions instead of a display label.
library;

/// The selectable presets shown in the project configuration screen.
enum SlideSizePreset { widescreen, standard, portrait, custom }

/// An immutable slide size with conversion and validation helpers.
class SlideSize {
  const SlideSize._({
    required this.widthEmu,
    required this.heightEmu,
    required this.preset,
  });

  /// EMU per inch — PowerPoint's native unit system.
  static const int emuPerInch = 914400;

  /// Smallest slide PowerPoint accepts: 1 inch.
  static const double minInches = 1;

  /// Largest slide PowerPoint accepts: 56 inches.
  static const double maxInches = 56;

  static const double cmPerInch = 2.54;

  /// Widescreen 16:9 — 13.33 × 7.5 in.
  static const SlideSize widescreen = SlideSize._(
    widthEmu: 12192000,
    heightEmu: 6858000,
    preset: SlideSizePreset.widescreen,
  );

  /// Standard 4:3 — 10 × 7.5 in.
  static const SlideSize standard = SlideSize._(
    widthEmu: 9144000,
    heightEmu: 6858000,
    preset: SlideSizePreset.standard,
  );

  /// Portrait 9:16 — 7.5 × 13.33 in.
  static const SlideSize portrait = SlideSize._(
    widthEmu: 6858000,
    heightEmu: 12192000,
    preset: SlideSizePreset.portrait,
  );

  final int widthEmu;
  final int heightEmu;
  final SlideSizePreset preset;

  double get widthInches => widthEmu / emuPerInch;
  double get heightInches => heightEmu / emuPerInch;

  double get widthCm => widthInches * cmPerInch;
  double get heightCm => heightInches * cmPerInch;

  bool get isPortrait => heightEmu > widthEmu;

  /// Recognises a stored EMU pair as one of the known presets (falling back
  /// to [SlideSizePreset.custom] for anything else).
  static SlideSize fromEmu(int widthEmu, int heightEmu) {
    if (widthEmu == widescreen.widthEmu && heightEmu == widescreen.heightEmu) {
      return widescreen;
    }
    if (widthEmu == standard.widthEmu && heightEmu == standard.heightEmu) {
      return standard;
    }
    if (widthEmu == portrait.widthEmu && heightEmu == portrait.heightEmu) {
      return portrait;
    }
    return SlideSize._(
      widthEmu: widthEmu,
      heightEmu: heightEmu,
      preset: SlideSizePreset.custom,
    );
  }

  /// Builds a custom size from inch values. Returns `null` when either side
  /// is outside the supported range.
  static SlideSize? tryCustom({
    required double widthInches,
    required double heightInches,
  }) {
    if (widthInches < minInches ||
        widthInches > maxInches ||
        heightInches < minInches ||
        heightInches > maxInches) {
      return null;
    }
    return SlideSize._(
      widthEmu: inchesToEmu(widthInches),
      heightEmu: inchesToEmu(heightInches),
      preset: SlideSizePreset.custom,
    );
  }

  static int inchesToEmu(double inches) => (inches * emuPerInch).round();

  /// Parses a user-typed measurement string. Accepts `,` or `.` as the
  /// decimal separator; returns `null` when the text is not a positive
  /// number.
  static double? tryParseMeasurement(String value) {
    final normalised = value.trim().replaceAll(',', '.');
    if (normalised.isEmpty) return null;
    final parsed = double.tryParse(normalised);
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  /// Human-readable size, e.g. `13.33 × 7.5 in` or `33.9 × 19.1 cm`.
  String label({bool metric = false}) {
    if (metric) {
      return '${_trim(widthCm)} × ${_trim(heightCm)} cm';
    }
    return '${_trim(widthInches)} × ${_trim(heightInches)} in';
  }

  /// Compact caption for the preset cards.
  String get presetCaption => label();

  static String _trim(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    var text = value.toStringAsFixed(2);
    // "7.50" reads better as "7.5" — drop a single trailing zero.
    if (text.endsWith('0')) text = text.substring(0, text.length - 1);
    return text;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SlideSize &&
          other.widthEmu == widthEmu &&
          other.heightEmu == heightEmu;

  @override
  int get hashCode => Object.hash(widthEmu, heightEmu);

  @override
  String toString() => 'SlideSize(${label()}, preset: $preset)';
}
