import 'package:flutter/material.dart';

import '../../../shared/widgets/empty_state.dart';

/// Notifications destination — honest empty state for now.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const EmptyState(
        centered: true,
        icon: Icons.notifications_none_rounded,
        title: "You're all caught up",
        message:
            'Activity about your projects and connections will appear here.',
      ),
    );
  }
}
