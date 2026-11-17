import 'package:material_ui/material_ui.dart';

/// Dark studio theme (from the user's Vibezy reference): pure-black app
/// chrome, charcoal surfaces with hairline borders, white active icons with
/// gray inactive ones, a red LIVE-style accent, and one signature
/// purple → pink → orange gradient reserved for "create" moments
/// (new-deck button, add-slide button, selected filmstrip ring).

// ---- palette -----------------------------------------------------------------
const Color kBg = Color(0xFF000000); // app background (reference is pure black)
const Color kSurface = Color(0xFF141417); // cards, sheets, bottom bands
const Color kElevated = Color(0xFF1C1C22); // floating dock, chips, tiles
const Color kHairline = Color(0xFF2A2A31); // subtle borders / dividers
const Color kText = Color(0xFFF5F5F7); // primary text — near-white
const Color kText2 = Color(0xFF9E9EA6); // muted secondary text
const Color kText3 = Color(0xFF6C6C74); // tertiary / hints
const Color kAccent = Color(0xFFFF3B30); // red accent (LIVE red in reference)
const Color kPurple = Color(0xFFA855F7); // gradient start
const Color kMagenta = Color(0xFFE1306C); // gradient middle
const Color kOrange = Color(0xFFFF6B4A); // gradient end

/// The signature gradient: story rings, create buttons, selected thumbnail.
const LinearGradient kInkGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kPurple, kMagenta, kOrange],
);

ThemeData buildDreamTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kMagenta,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kText, // active toggles/icons render white (reference style)
    onPrimary: kBg,
    secondary: kPurple,
    error: kAccent,
    surface: kBg,
    onSurface: kText,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: kText,
      iconTheme: IconThemeData(color: kText),
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kElevated,
      contentTextStyle: TextStyle(color: kText, fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: kElevated,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(fontSize: 14, color: kText),
    ),
    dividerTheme: const DividerThemeData(color: kHairline, thickness: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: kText2,
      textColor: kText,
    ),
    iconTheme: const IconThemeData(color: kText),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kElevated,
      foregroundColor: kText,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kPurple),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}
