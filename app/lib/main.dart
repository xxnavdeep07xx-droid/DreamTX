import 'package:material_ui/material_ui.dart';

import 'screens/decks_screen.dart';

void main() {
  runApp(const DreamTxApp());
}

class DreamTxApp extends StatelessWidget {
  const DreamTxApp({super.key});

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
