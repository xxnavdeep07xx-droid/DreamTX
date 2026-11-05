import '../models/connection.dart';

/// Contract for the AI & MCP connection layer.
abstract class ConnectionRepository {
  Future<ConnectionSummary> load();
}

/// Mock connection state.
///
/// Everything reports as not connected / not configured — no provider is
/// claimed to be live until a real connection exists.
class MockConnectionRepository implements ConnectionRepository {
  @override
  Future<ConnectionSummary> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 240));
    return const ConnectionSummary(
      mcpServerConfigured: false,
      connections: [
        AssistantConnection(
          id: 'claude',
          name: 'Claude',
          detail: 'MCP client',
          status: ConnectionStatus.notConnected,
        ),
        AssistantConnection(
          id: 'chatgpt',
          name: 'ChatGPT',
          detail: 'OpenAI · API key',
          status: ConnectionStatus.notConnected,
        ),
      ],
    );
  }
}
