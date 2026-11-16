import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/decks_screen.dart';

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
    // Swiss-editorial lean UI: near-white, ink text, one accent, quiet chrome.
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFD03028),
      surface: const Color(0xFFF7F6F3),
    );
    return MaterialApp(
      title: 'DreamTX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F6F3),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F6F3),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF17181A),
          foregroundColor: Color(0xFFF7F6F3),
        ),
      ),
      home: const DecksScreen(),
    );
  }
}
