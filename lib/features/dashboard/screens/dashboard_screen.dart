import 'package:flutter/material.dart';

import '../../../shared/widgets/app_logo.dart';
import '../widgets/connections_section.dart';
import '../widgets/create_presentation_card.dart';
import '../widgets/dashboard_app_bar.dart';
import '../widgets/design_discovery_section.dart';
import '../widgets/quick_actions_grid.dart';
import '../widgets/recent_projects_section.dart';
import '../widgets/welcome_section.dart';

/// The DreamTX dashboard — a single, calm vertical scroll.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: const [
          DashboardAppBar(),
          SizedBox(height: 20),
          WelcomeSection(),
          SizedBox(height: 24),
          CreatePresentationCard(),
          SizedBox(height: 14),
          QuickActionsGrid(),
          SizedBox(height: 34),
          RecentProjectsSection(),
          SizedBox(height: 34),
          DesignDiscoverySection(),
          SizedBox(height: 34),
          ConnectionsSection(),
          SizedBox(height: 4),
          _DashboardFooter(),
        ],
      ),
    );
  }
}

class _DashboardFooter extends StatelessWidget {
  const _DashboardFooter();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppLogo(size: 18),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            'Crafted for storytellers',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.3,
              color: Color(0xFF55555F),
            ),
          ),
        ),
      ],
    );
  }
}
