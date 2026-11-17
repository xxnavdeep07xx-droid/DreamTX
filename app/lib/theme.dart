import 'dart:async';

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

// ---- shared dark widgets ------------------------------------------------------

/// Input dialog pinned to ONE comfortable place: the middle of the band that
/// stays visible above the keyboard. The card is centered around a third of
/// the screen height (fractional, so it adapts to any device) — below the
/// masthead, well clear of the tallest keyboards — and the subtree is fed
/// zeroed viewInsets, so the opening keyboard never lifts the card, the
/// field is never covered, and nothing re-centers or jumps.
Future<String?> dreamInputDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  String confirmLabel = 'Create',
  bool multiline = false,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    useSafeArea: false,
    builder: (context) => MediaQuery(
      // Belt and braces: even on insets-delivered (non-resizing) keyboards
      // the subtree sees none, so nothing re-centers or jumps.
      data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
      child: Align(
        // y = -0.34 puts the card's vertical center at ~33% of the screen —
        // mid-flight between the masthead and the keyboard, not hugging the
        // top edge.
        alignment: const Alignment(0, -0.34),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: kSurface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: kHairline),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kText)),
                      const SizedBox(height: 14),
                      darkTextField(
                        controller: controller,
                        hint: hint,
                        autofocus: true,
                        maxLines: multiline ? 4 : 1,
                        onSubmitted: multiline ? null : (_) => Navigator.pop(context, controller.text),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(confirmLabel)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Neutral dark dialog. The seeded dialog surface carries a warm tint and its
/// TextFields default to light-theme styling, so dialogs are styled here once.
AlertDialog dreamDialog({required Widget title, Widget? content, List<Widget>? actions}) {
  return AlertDialog(
    title: title,
    content: content,
    actions: actions,
    backgroundColor: kSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    titleTextStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kText),
    contentTextStyle: const TextStyle(fontSize: 13.5, color: kText2),
  );
}

/// Dark TextField for dialogs and sheets: inset black fill, hairline border,
/// purple focus ring.
TextField darkTextField({
  required TextEditingController controller,
  String? hint,
  String? label,
  bool autofocus = false,
  int maxLines = 1,
  void Function(String)? onChanged,
  void Function(String)? onSubmitted,
}) {
  return TextField(
    controller: controller,
    autofocus: autofocus,
    maxLines: maxLines,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    style: const TextStyle(color: kText, fontSize: 14),
    cursorColor: kPurple,
    decoration: darkInput(hint: hint, label: label),
  );
}

/// Dark input decoration — also used by form fields on sheets.
InputDecoration darkInput({String? hint, String? label}) {
  return InputDecoration(
    hintText: hint,
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: kBg,
    hintStyle: const TextStyle(color: kText3, fontSize: 13),
    labelStyle: const TextStyle(color: kText2, fontSize: 13),
    floatingLabelStyle: const TextStyle(color: kPurple, fontSize: 13),
    border: _inputBorder(kHairline),
    enabledBorder: _inputBorder(kHairline),
    focusedBorder: _inputBorder(kPurple, 1.6),
  );
}

OutlineInputBorder _inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );

// ---- keyboard-stable screen wrapper -------------------------------------------

/// Keeps a screen's layout laid out at its steady (keyboard-free) metrics for
/// the whole duration of a keyboard session — the shared fix for layout
/// "lift"/"shake" while the keyboard opens.
///
/// Two ways a keyboard can reach a Flutter layout, and a screen must survive
/// both:
///
///  * Inset-delivery mode (edge-to-edge): the window keeps its size and
///    `MediaQuery.viewInsets.bottom` animates up.
///  * Window-resize mode (classic adjustResize — common on many devices):
///    the OS geometrically shrinks the window, and `viewInsets` stays ZERO
///    because the resize already consumed the inset. A viewInsets-gated
///    freeze never engages; the Scaffold body region shrinks; centered
///    content re-centers in the smaller region and visibly lifts.
///
/// So this wrapper detects the keyboard by EITHER signal — viewInsets > 0 OR
/// the viewport height shrinking at an unchanged width — and then feeds the
/// subtree the steady size, the steady padding and zeroed viewInsets for the
/// whole session (plus a short hold after the keyboard closes, so bar churn
/// on close also lands off-screen). The screen simply keeps drawing at its
/// full steady size; the surplus flows away behind the keyboard. Nothing in
/// the layout can move.
///
/// Wrap the screen's Scaffold. Bottom-sheet routes and dialogs live in the
/// Overlay OUTSIDE the wrapped subtree, so they still see the real viewport
/// and real viewInsets — sheets that pad themselves above the keyboard keep
/// working untouched.
class KeyboardStableMetrics extends StatefulWidget {
  const KeyboardStableMetrics({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardStableMetrics> createState() => _KeyboardStableMetricsState();
}

class _KeyboardStableMetricsState extends State<KeyboardStableMetrics> {
  Size? _steadySize;
  EdgeInsets _stablePadding = EdgeInsets.zero;

  bool _wasKeyboardish = false;
  bool _holding = false;
  Timer? _holdTimer;

  static const _holdAfterClose = Duration(milliseconds: 900);

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final steady = _steadySize;

    // First frame (or metrics not yet seen): just record the steady state.
    if (steady == null) {
      _steadySize = mq.size;
      _stablePadding = mq.padding;
      return MediaQuery(data: mq, child: widget.child);
    }

    // Keyboard signal: delivered insets, OR the viewport shrinking at an
    // unchanged width (window-resize mode delivers no insets). A rotation or
    // split-screen change alters the width too, so it falls through to the
    // steady-refresh path instead of freezing.
    final sizeShrunk =
        (mq.size.width - steady.width).abs() < 0.5 && mq.size.height < steady.height - 0.5;
    final keyboardish = mq.viewInsets.bottom > 0 || sizeShrunk;

    if (keyboardish) {
      _wasKeyboardish = true;
      // A new keyboard session cancels any pending release from the previous
      // one — the freeze simply continues.
      _holdTimer?.cancel();
      _holdTimer = null;
      _holding = false;
      return _frozen(mq);
    }

    if (_wasKeyboardish && !_holding) {
      // Keyboard just closed: hold the frozen metrics a moment longer so the
      // debounced immersive re-entry (400ms) plus the resize/bar animation
      // (~300ms) finish inside the hold, not on screen.
      _holding = true;
      _holdTimer = Timer(_holdAfterClose, () {
        _holdTimer = null;
        if (!mounted) return;
        setState(() {
          _holding = false;
          _wasKeyboardish = false;
        });
      });
      return _frozen(mq);
    }

    if (_holding) return _frozen(mq);

    // No keyboard around: record the steady metrics and pass through.
    _steadySize = mq.size;
    _stablePadding = mq.padding;
    return MediaQuery(data: mq, child: widget.child);
  }

  Widget _frozen(MediaQueryData mq) {
    return MediaQuery(
      data: mq.copyWith(
        size: _steadySize ?? mq.size,
        padding: _stablePadding,
        viewInsets: EdgeInsets.zero,
      ),
      child: widget.child,
    );
  }
}
