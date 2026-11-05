/// Status of an assistant connection.
///
/// Mock layer only — nothing is reported as connected until a real
/// connection exists.
enum ConnectionStatus { notConnected }

class AssistantConnection {
  const AssistantConnection({
    required this.id,
    required this.name,
    required this.detail,
    required this.status,
  });

  final String id;
  final String name;
  final String detail;
  final ConnectionStatus status;

  bool get isConnected => false; // Mock: no real connections yet.
}

class ConnectionSummary {
  const ConnectionSummary({
    required this.connections,
    required this.mcpServerConfigured,
  });

  final List<AssistantConnection> connections;
  final bool mcpServerConfigured;

  /// Always zero in the mock layer — never claim live connections.
  int get connectedCount => 0;
}
