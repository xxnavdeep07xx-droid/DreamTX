import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/models/connection.dart';
import '../../../shared/services/services.dart';

/// AI & MCP Connections — introduces the MCP-powered creation workflow and
/// shows the current (honest, clearly marked) connection state.
///
/// DreamTX deliberately has no built-in chatbot: you connect the assistant
/// you already use, and it drives DreamTX over MCP.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late final Future<ConnectionSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = connectionRepository.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI & MCP Connections')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          const Text(
            'Create with an AI assistant',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'DreamTX exposes its presentation tools over MCP — the Model '
            'Context Protocol. Connect the assistant you already use and '
            'create presentations through it; no built-in chatbot, no '
            'extra subscription.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          const _HowItWorksCard(),
          const SizedBox(height: 22),
          const Text(
            'CURRENT STATUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
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
              return _StatusCard(summary: summary);
            },
          ),
        ],
      ),
    );
  }
}

/// Three-step explanation of the MCP-powered workflow.
class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    Widget step(int index, IconData icon, String title, String detail) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.violet.withOpacity(0.09),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 17, color: AppColors.violet),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$index. $title',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          step(
            1,
            Icons.link_rounded,
            'Connect an assistant',
            'Link Claude, ChatGPT or any MCP client from this screen.',
          ),
          const Divider(height: 1),
          step(
            2,
            Icons.forum_outlined,
            'Start creating',
            'Ask your assistant for a presentation — it calls DreamTX '
            'tools over MCP.',
          ),
          const Divider(height: 1),
          step(
            3,
            Icons.slideshow_outlined,
            'Review in DreamTX',
            'Finished projects land in your library, ready to refine.',
          ),
        ],
      ),
    );
  }
}

/// Live (mock, clearly marked) connection state.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.summary});

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
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Connections',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _DemoBadge(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${summary.connectedCount} of ${summary.connections.length} '
            'connected',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          for (final connection in summary.connections) ...[
            _ConnectionRow(connection: connection),
            const SizedBox(height: 10),
          ],
          const Divider(),
          const SizedBox(height: 12),
          Row(
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
                  color: summary.mcpServerConfigured
                      ? AppColors.success
                      : AppColors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: AppColors.textTertiary,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nothing is connected yet. The DreamTX MCP server ships '
                    'in an upcoming release — when it does, you\'ll connect '
                    'and manage assistants right here.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
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
                '${connection.detail} · '
                '${connection.isConnected ? 'Connected' : 'Not connected'}',
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
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.textTertiary,
        ),
      ],
    );
  }
}
