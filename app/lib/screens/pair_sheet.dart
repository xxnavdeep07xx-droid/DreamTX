import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

/// Pair sheet — "use your own AI" UX: ask the server for a 15-minute pairing
/// code + URL, paste it into ChatGPT/Claude/any MCP client, then watch the
/// deck update live over the deck DO WebSocket (with version catch-up).
///
/// Hardened contract: every network wait is bounded (a dead server surfaces
/// as a visible error within seconds, never as a stuck "pairing…" state),
/// the HttpClient and WebSocket are always released, every setState after an
/// await is dispose-guarded, and a mid-flight dispose closes whatever was
/// in flight instead of leaking it. Pairing is fully independent of the
/// offline startup path: it only ever touches this sheet's own state.
class PairSheet extends StatefulWidget {
  const PairSheet({super.key, required this.deck, this.onDeckUpdate});

  final Map<String, dynamic> deck;

  /// Receives deck payloads pushed by the AI over the WebSocket (update /
  /// snapshot / reset) so the edits appear LIVE on the canvas behind this
  /// sheet instead of only moving the status label.
  final void Function(Map<String, dynamic> deck)? onDeckUpdate;

  @override
  State<PairSheet> createState() => _PairSheetState();
}

class _PairSheetState extends State<PairSheet> {
  static const _httpTimeout = Duration(seconds: 10);
  static const _wsTimeout = Duration(seconds: 15);

  String? _serverUrl;
  Map<String, dynamic>? _pairing;
  String? _error;
  String _status = 'idle';
  WebSocket? _ws;
  int? _lastVersion;
  bool _disposed = false;

  /// Owned by this state and disposed with it — the URL field used to build
  /// a fresh controller per frame, leaking one per keystroke.
  late final TextEditingController _urlField;

  @override
  void initState() {
    super.initState();
    _urlField = TextEditingController();
    _loadServerUrl();
  }

  @override
  void dispose() {
    _disposed = true;
    _ws?.close();
    _urlField.dispose();
    super.dispose();
  }

  Future<void> _loadServerUrl() async {
    try {
      final path = await _serverFile().timeout(_httpTimeout);
      final file = File(path);
      if (await file.exists()) {
        final url = (await file.readAsString()).trim();
        if (url.isEmpty) return;
        if (_disposed) return;
        setState(() {
          _serverUrl = url;
          _urlField.text = url;
        });
      }
    } catch (e) {
      // A settings file that cannot be read is not worth a red screen: the
      // user just retypes the URL. Logged, not shown.
      print('[pair-sheet] could not read the saved server URL: $e');
    }
  }

  Future<String> _serverFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/dreamtx_server.txt';
  }

  Future<void> _saveServerUrl(String url) async {
    try {
      final path = await _serverFile().timeout(_httpTimeout);
      await File(path).writeAsString(url.trim());
    } catch (e) {
      print('[pair-sheet] could not save the server URL: $e');
      if (!_disposed) {
        setState(() => _error = 'Could not save the server URL: $e');
      }
    }
  }

  /// Safe setState after any await — a disposed sheet never updates itself.
  void _update(VoidCallback fn) {
    if (_disposed) return;
    setState(fn);
  }

  Future<void> _pair() async {
    final url = _serverUrl;
    if (url == null || url.trim().isEmpty) {
      _update(() => _error =
          'Set your DreamTX server URL first (deployed in M2).');
      return;
    }
    _update(() {
      _error = null;
      _status = 'pairing…';
    });
    final http = HttpClient()..connectionTimeout = _httpTimeout;
    try {
      final req = await http.postUrl(Uri.parse('$url/pair')).timeout(_httpTimeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'deckId': widget.deck['id']}));
      final resp = await req.close().timeout(_httpTimeout);
      final bodyText =
          await resp.transform(utf8.decoder).join().timeout(_httpTimeout);
      final decoded = jsonDecode(bodyText); // malformed JSON → the catch below
      if (decoded is! Map<String, dynamic>) {
        _update(() {
          _error = 'pairing failed — the server sent an unexpected response';
          _status = 'idle';
        });
        return;
      }
      final body = decoded;
      if (body['ok'] == true) {
        _update(() {
          _pairing = body;
          _status = 'paired — waiting for your AI';
        });
        // The Durable Object holds the REAL deck state from the first
        // moment of pairing — the AI's first command has a deck to mutate
        // instead of an empty object, and every editor tab catches up from
        // the same source of truth. Bounded, logged, never fatal: a failed
        // init surfaces in the status line, pairing still completes.
        await _pushInitialState(url);
        _connect(url);
      } else {
        _update(() {
          _error = body['error']?.toString() ?? 'pairing failed';
          _status = 'idle';
        });
      }
    } catch (e) {
      // Bounded and visible: a dead server is an error in seconds, not a
      // permanent "pairing…" badge.
      _update(() {
        _error = 'server unreachable: $e';
        _status = 'idle';
      });
    } finally {
      // The client is always released, success or failure.
      http.close();
    }
  }

  /// POST /decks/<id>/init with the current deck — the Durable Object's
  /// baseline. Bounded and always released; a failure is visible (status)
  /// but never blocks the WebSocket leg that follows.
  Future<void> _pushInitialState(String serverUrl) async {
    final http = HttpClient()..connectionTimeout = _httpTimeout;
    try {
      final deckId = widget.deck['id'].toString();
      final req = await http
          .postUrl(Uri.parse('$serverUrl/decks/$deckId/init'))
          .timeout(_httpTimeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'deck': widget.deck}));
      final resp = await req.close().timeout(_httpTimeout);
      await resp.transform(utf8.decoder).join().timeout(_httpTimeout);
      if (resp.statusCode >= 400) {
        _update(() => _status = 'paired — deck sync failed (${resp.statusCode})');
      }
    } catch (e) {
      print('[pair-sheet] deck init push failed: $e');
      _update(() => _status = 'paired — deck sync failed');
    } finally {
      http.close();
    }
  }

  void _connect(String serverUrl) {
    final deckId = widget.deck['id'].toString();
    final wsUri = Uri.parse(serverUrl).replace(
      scheme: Uri.parse(serverUrl).scheme == 'https' ? 'wss' : 'ws',
      path: '/decks/$deckId/ws',
    );
    WebSocket.connect(wsUri.toString()).timeout(_wsTimeout).then((ws) {
      if (_disposed) {
        // The sheet died mid-connect: own the socket just long enough to
        // close it — never leak it.
        ws.close();
        return;
      }
      _ws = ws;
      ws.add(jsonEncode({'type': 'subscribe', 'since_version': _lastVersion}));
      ws.listen(
        (msg) {
          try {
            final data = jsonDecode(msg.toString()) as Map<String, dynamic>;
            final version = data['version'];
            if (version is num) _lastVersion = version.toInt();
            final deck = data['deck'];
            if ((data['type'] == 'update' ||
                    data['type'] == 'snapshot' ||
                    data['type'] == 'reset') &&
                deck is Map<String, dynamic>) {
              // The AI's edit arrives as the whole deck: hand it to the
              // editor so the canvas reflects it live (the editor applies,
              // persists and records undo), then report the version.
              widget.onDeckUpdate?.call(deck);
              _update(() => _status = 'live — version ${data['version']}');
            } else if (data['type'] == 'hello') {
              _update(() => _status = 'connected');
            } else if (data['type'] == 'update' ||
                data['type'] == 'snapshot' ||
                data['type'] == 'reset') {
              _update(() => _status = 'live — version ${data['version']}');
            }
          } catch (e) {
            print('[pair-sheet] unparseable ws message: $e');
          }
        },
        onDone: () => _update(() => _status = 'disconnected — tap reconnect'),
        onError: (e) {
          print('[pair-sheet] websocket error: $e');
          _update(() => _status = 'disconnected — tap reconnect');
        },
      );
    }).catchError((e) {
      print('[pair-sheet] websocket connect failed: $e');
      _update(() => _status = 'websocket failed: $e');
    });
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
            style: const TextStyle(color: kText, fontSize: 14),
            cursorColor: kPurple,
            decoration: darkInput(
              label: 'DreamTX server URL',
              hint: 'https://dreamtx.your-name.workers.dev',
            ),
            controller: _urlField,
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
