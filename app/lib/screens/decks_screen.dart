import 'package:material_ui/material_ui.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import 'editor_screen.dart';

const Color _ink = Color(0xFF17181A);
const Color _paper = Color(0xFFF7F6F3);
const Color _accent = Color(0xFFD03028);
const Color _muted = Color(0xFF6B6B70);

/// Screen 1 — Decks. Editorial masthead on top, ruled index of deck cards
/// below. Nothing else.
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
    _open(deck);
  }

  void _open(Map<String, dynamic> deck) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => EditorScreen(deck: Map<String, dynamic>.from(deck)),
        ))
        .then((_) => _reload());
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
    final count = _decks.length;
    return Scaffold(
      backgroundColor: _paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Masthead: unambiguous "top" --------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DreamTX',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            height: 1.1,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          count == 0 ? 'DECKS · NONE YET' : 'DECKS · $count ON THIS DEVICE',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.8,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _newDeck,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New deck'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: _ink, width: 1.2),
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // The rule: hard separation between masthead and body.
            Container(height: 2, color: _ink),
            // ---- Body: ruled deck index ------------------------------------
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : count == 0
                      ? _EmptyState(onCreate: _newDeck)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                          itemCount: count,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => _DeckCard(
                            index: i + 1,
                            deck: _decks[i],
                            onOpen: () => _open(_decks[i]),
                            onDelete: () => _delete(_decks[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One deck = one hairline-bordered white tile with an indexed number.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.index,
    required this.deck,
    required this.onOpen,
    required this.onDelete,
  });

  final int index;
  final Map<String, dynamic> deck;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final slides = (deck['slides'] as List? ?? []).length;
    final family = ((deck['dna'] ?? const {})['family'] ?? '').toString().replaceAll('_', ' ');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _ink, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(2),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: _accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 38, color: const Color(0x3D17181A)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (deck['title'] ?? 'Untitled').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$slides slides · $family',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete deck',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _ink, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_outlined, size: 44, color: _ink),
                const SizedBox(height: 14),
                const Text(
                  'No decks yet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Create one — then pair it with your AI.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: _muted),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create your first deck'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
