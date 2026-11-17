import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/decks_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fullscreen: keep the Android status bar (top) and navigation bar (bottom)
  // hidden. immersiveSticky = a swipe from the screen edge reveals them
  // briefly, then they tuck themselves away again.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const DreamTxApp());
}

class DreamTxApp extends StatefulWidget {
  const DreamTxApp({super.key});

  @override
  State<DreamTxApp> createState() => _DreamTxAppState();
}

class _DreamTxAppState extends State<DreamTxApp> with WidgetsBindingObserver {
  Timer? _immersiveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _immersiveDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Keyboards, dialogs and app switches can bring the system bars back;
  /// re-enter immersive mode once things settle (debounced — metrics fire
  /// continuously while the keyboard animates).
  @override
  void didChangeMetrics() {
    _immersiveDebounce?.cancel();
    _immersiveDebounce = Timer(const Duration(milliseconds: 400), () {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Dark studio theme (Vibezy-inspired): black chrome, charcoal surfaces,
    // white active icons, red accents, purple→pink→orange gradient for
    // create moments. See theme.dart.
    return MaterialApp(
      title: 'DreamTX',
      debugShowCheckedModeBanner: false,
      theme: buildDreamTheme(),
      // Wrap the whole app (all routes, dialogs and sheets) in a MediaQuery
      // whose padding is frozen for the duration of any keyboard session —
      // see _KeyboardStablePadding below.
      builder: (context, child) => _KeyboardStablePadding(child: child),
      home: const DecksScreen(),
    );
  }
}

/// Keeps the app layout pixel-still around keyboard sessions.
///
/// The first time the IME opens after a cold start, Android transiently
/// reveals the status and navigation bars alongside the keyboard; the app
/// then re-enters immersive mode (debounced, in this file) and hides them
/// again. Every one of those reveals/hides changes `MediaQuery.padding`,
/// which retwitches every SafeArea in the tree — the centered "No decks
/// yet" card visibly shakes once per session.
///
/// This wrapper freezes the last keyboard-free padding for the whole
/// keyboard session and holds it briefly after the keyboard closes (the
/// debounced immersive re-entry and the bar-hide animation land inside that
/// window), so transient bar churn never reaches the layout. Transient
/// bars simply overlay the UI instead of moving it.
///
/// `viewInsets` are passed through untouched at all times, so sheets and
/// editors that track the keyboard keep working, and the input dialog's own
/// viewInsets-zeroing (theme.dart) keeps working too.
class _KeyboardStablePadding extends StatefulWidget {
  const _KeyboardStablePadding({required this.child});

  final Widget? child;

  @override
  State<_KeyboardStablePadding> createState() => _KeyboardStablePaddingState();
}

class _KeyboardStablePaddingState extends State<_KeyboardStablePadding> {
  /// The padding as it was the last time no keyboard was on screen. Captured
  /// before the keyboard can churn it, replayed while it is open.
  EdgeInsets _stablePadding = EdgeInsets.zero;

  bool _wasKeyboardOpen = false;
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
    final keyboardOpen = mq.viewInsets.bottom > 0;

    if (keyboardOpen) {
      _wasKeyboardOpen = true;
      // A new keyboard session cancels any pending release from the previous
      // one — the freeze simply continues.
      _holdTimer?.cancel();
      _holdTimer = null;
      _holding = false;
      return _frozen(mq);
    }

    if (_wasKeyboardOpen && !_holding) {
      // Keyboard just closed: hold the frozen padding a moment longer so the
      // debounced immersive re-entry (400ms) plus the bar-hide animation
      // (~300ms) finish inside the hold, not on screen.
      _holding = true;
      _holdTimer = Timer(_holdAfterClose, () {
        _holdTimer = null;
        if (!mounted) return;
        setState(() {
          _holding = false;
          _wasKeyboardOpen = false;
        });
      });
      return _frozen(mq);
    }

    if (_holding) return _frozen(mq);

    // No keyboard around: record the steady padding and pass it through.
    _stablePadding = mq.padding;
    return MediaQuery(data: mq, child: widget.child);
  }

  Widget _frozen(MediaQueryData mq) {
    return MediaQuery(data: mq.copyWith(padding: _stablePadding), child: widget.child);
  }
}
