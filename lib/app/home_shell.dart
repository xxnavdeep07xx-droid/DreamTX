import 'package:flutter/material.dart';

import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/explore/screens/explore_screen.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../shared/widgets/app_logo.dart';
import 'theme/app_colors.dart';

/// Main shell: IndexedStack of destinations plus a persistent bottom bar.
///
/// The IndexedStack keeps each destination's state (scroll positions, loaded
/// data) alive while switching.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    DashboardScreen(),
    ExploreScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: AppColors.surface,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.violet.withOpacity(0.16),
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(13)),
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Small inline brand mark used by the shell's app bars where needed.
class ShellTitle extends StatelessWidget {
  const ShellTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AppLogo(size: 28),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
