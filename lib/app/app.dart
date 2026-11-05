import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'theme/app_theme.dart';

/// Root application widget.
class DreamTxApp extends StatelessWidget {
  const DreamTxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DreamTX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeShell(),
    );
  }
}
