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
      // Wrap the whole app (all routes, dialogs and sheets) in the shared
      // keyboard-stable wrapper, in its padding-only scope: the padding is
      // frozen for the duration of any keyboard session (see theme.dart —
      // the same widget that freezes screen layouts, one implementation).
      builder: (context, child) => KeyboardStableMetrics(
        scope: KeyboardStableScope.paddingOnly,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const DecksScreen(),
    );
  }
}

