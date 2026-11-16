import 'package:material_ui/material_ui.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import 'editor_screen.dart';

/// Screen 1 — Decks. List, create, open, delete. Nothing else.
class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  List<Map<String, dynamic>> _decks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final store = await DeckStore.open();
    final decks = await store.list();
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _loading = false;
    });
  }

  Future<void> _newDeck() async {
    final title = await _askTitle();
    if (title == null || title.trim().isEmpty) return;
    final r = Bridge.command({'op': 'new_deck', 'title': title.trim(), 'family': 'swiss_editorial'});
    if (r['ok'] != true) {
      _toast('Engine error: ${r['error']}');
      return;
    }
    final deck = (r['deck'] as Map).cast<String, dynamic>();
    final store = await DeckStore.open();
    await store.save(deck);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(deck: deck),
    )).then((_) => _reload());
  }

  Future<String?> _askTitle() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New deck'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Q3 launch review'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Create')),
        ],
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> deck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete '${deck['title']}'?"),
        content: const Text('The deck file is removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final store = await DeckStore.open();
    await store.delete((deck['id']).toString());
    _reload();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final decks = _decks;
    return Scaffold(
      appBar: AppBar(title: const Text('DreamTX'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New deck'),
        onPressed: _newDeck,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : decks.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  itemCount: decks.length,
                  itemBuilder: (context, i) {
                    final deck = decks[i];
                    final slides = (deck['slides'] as List? ?? []).length;
                    final family = ((deck['dna'] ?? const {})['family'] ?? '').toString();
                    return ListTile(
                      leading: const Icon(Icons.layers_outlined),
                      title: Text((deck['title'] ?? 'Untitled').toString()),
                      subtitle: Text('$slides slides · ${family.replaceAll('_', ' ')}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(deck),
                      ),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                            builder: (_) => EditorScreen(deck: Map<String, dynamic>.from(deck)),
                          ))
                          .then((_) => _reload()),
                    );
                  },
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_motion_outlined, size: 64, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          const Text('No decks yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Create one — then pair it with your AI.'),
        ],
      ),
    );
  }
}
