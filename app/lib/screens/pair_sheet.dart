import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Pair sheet — "use your own AI" UX: ask the server for a 15-minute pairing
/// code + URL, paste it into ChatGPT/Claude/any MCP client, then watch the
/// deck update live over the deck DO WebSocket (with version catch-up).
class PairSheet extends StatefulWidget {
  const PairSheet({super.key, required this.deck});

  final Map<String, dynamic> deck;

  @override
  State<PairSheet> createState() => _PairSheetState();
}

class _PairSheetState extends State<PairSheet> {
  String? _serverUrl;
  Map<String, dynamic>? _pairing;
  String? _error;
  String _status = 'idle';
  WebSocket? _ws;
  int? _lastVersion;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final file = File(await _serverFile());
    if (file.existsSync()) {
      final url = file.readAsStringSync().trim();
      if (url.isNotEmpty) setState(() => _serverUrl = url);
    }
  }

  Future<String> _serverFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/dreamtx_server.txt';
  }

  Future<void> _saveServerUrl(String url) async {
    final file = File(await _serverFile());
    await file.writeAsString(url.trim());
  }

  Future<void> _pair() async {
    final url = _serverUrl;
    if (url == null || url.trim().isEmpty) {
      setState(() => _error = 'Set your DreamTX server URL first (deployed in M2).');
      return;
    }
    setState(() {
      _error = null;
      _status = 'pairing…';
    });
    try {
      final http = HttpClient();
      final req = await http.postUrl(Uri.parse('$url/pair'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'deckId': widget.deck['id']}));
      final resp = await req.close();
      final body = jsonDecode(await resp.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      if (body['ok'] == true) {
        setState(() {
          _pairing = body;
          _status = 'paired — waiting for your AI';
        });
        _connect(url);
      } else {
        setState(() {
          _error = body['error']?.toString() ?? 'pairing failed';
          _status = 'idle';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'server unreachable: $e';
        _status = 'idle';
      });
    }
  }

  void _connect(String serverUrl) {
    final deckId = widget.deck['id'].toString();
    final wsUri = Uri.parse(serverUrl).replace(
      scheme: Uri.parse(serverUrl).scheme == 'https' ? 'wss' : 'ws',
      path: '/decks/$deckId/ws',
    );
    WebSocket.connect(wsUri.toString()).then((ws) {
      _ws = ws;
      ws.add(jsonEncode({'type': 'subscribe', 'since_version': _lastVersion}));
      ws.stream.listen(
        (msg) {
          final data = jsonDecode(msg.toString()) as Map<String, dynamic>;
          if (data['type'] == 'update' || data['type'] == 'snapshot') {
            setState(() => _status = 'live — version ${data['version']}');
          } else if (data['type'] == 'hello') {
            setState(() => _status = 'connected');
          }
        },
        onDone: () => setState(() => _status = 'disconnected — tap reconnect'),
        onError: (_) => setState(() => _status = 'disconnected — tap reconnect'),
      );
    }).catchError((e) {
      setState(() => _status = 'websocket failed: $e');
    });
  }

  @override
  void dispose() {
    _ws?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final mcpUrl = pairing == null
        ? null
        : '$_serverUrl/p/${pairing['token']}/mcp';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pair with your AI', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Paste the URL into ChatGPT / Claude / any MCP client. '
            'It controls this deck only — for 15 minutes.',
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'DreamTX server URL',
              hintText: 'https://dreamtx.your-name.workers.dev',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _serverUrl ?? ''),
            onChanged: (v) => _serverUrl = v,
            onSubmitted: _saveServerUrl,
          ),
          const SizedBox(height: 12),
          if (mcpUrl != null) ...[
            _CopyRow(label: 'Pairing code', value: pairing!['code'].toString()),
            _CopyRow(label: 'MCP URL', value: mcpUrl),
            const SizedBox(height: 8),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text('Generate pairing code'),
                  onPressed: _pair,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _status.contains('live') || _status.contains('connected')
                    ? Icons.circle
                    : Icons.circle_outlined,
                size: 12,
                color: _status.contains('live') || _status.contains('connected')
                    ? Colors.green
                    : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text('Deck status: $_status')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ],
      ),
    );
  }
}
