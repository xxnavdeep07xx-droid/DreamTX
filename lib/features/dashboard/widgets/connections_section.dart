import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/models/connection.dart';
import '../../../shared/services/services.dart';
import '../../../shared/widgets/pressable_card.dart';
import '../../../shared/widgets/section_header.dart';

/// AI & MCP connections — an integration feature, clearly marked as demo
/// data. Nothing here claims a live connection.
class ConnectionsSection extends StatefulWidget {
  const ConnectionsSection({super.key});

  @override
  State<ConnectionsSection> createState() => _ConnectionsSectionState();
}

class _ConnectionsSectionState extends State<ConnectionsSection> {
  late final Future<ConnectionSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = connectionRepository.load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'AI & MCP Connections',
          caption: 'Connect your favourite AI assistants to DreamTX.',
        ),
        const SizedBox(height: 14),
        FutureBuilder<ConnectionSummary>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final summary = snapshot.data ??
                const ConnectionSummary(
                  connections: [],
                  mcpServerConfigured: false,
                );
            return _ConnectionsCard(summary: summary);
          },
        ),
      ],
    );
  }
}

class _ConnectionsCard extends StatelessWidget {
  const _ConnectionsCard({required this.summary});

  final ConnectionSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  '${summary.connectedCount} of '
                  '${summary.connections.length} connected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              const _DemoBadge(),
            ],
          ),
          const SizedBox(height: 15),
          for (final connection in summary.connections) ...[
            _ConnectionRow(connection: connection),
            const SizedBox(height: 10),
          ],
          const Divider(),
          const SizedBox(height: 12),
          _McpRow(configured: summary.mcpServerConfigured),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => AppRoutes.openConnections(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  label: const Text('Manage'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => AppRoutes.openTools(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                  icon: const Icon(Icons.extension_rounded, size: 17),
                  label: const Text('Tools'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'DEMO DATA',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.connection});

  final AssistantConnection connection;

  IconData get _icon => connection.id == 'claude'
      ? Icons.smart_toy_outlined
      : Icons.chat_bubble_outline_rounded;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.blue.withOpacity(0.10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(_icon, size: 18, color: AppColors.blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connection.name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${connection.detail} · ${connection.isConnected ? 'Connected' : 'Not connected'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        PressableCard(
          onTap: () => AppRoutes.openConnections(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.violet.withOpacity(0.35)),
            ),
            child: const Text(
              'Connect',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: AppColors.violet,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _McpRow extends StatelessWidget {
  const _McpRow({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.violet.withOpacity(0.08),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(
            Icons.dns_outlined,
            size: 18,
            color: AppColors.violet,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MCP Server',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Local bridge status · Not configured',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: configured ? AppColors.success : AppColors.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
