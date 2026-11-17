import 'package:material_ui/material_ui.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import '../theme.dart';
import 'editor_screen.dart';

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

  Future<void> _rename(Map<String, dynamic> deck) async {
    final title = await dreamInputDialog(
      context,
      title: 'Rename deck',
      initial: (deck['title'] ?? '').toString(),
      confirmLabel: 'Rename',
    );
    if (title == null || title.trim().isEmpty) return;
    final updated = Map<String, dynamic>.from(deck);
    updated['title'] = title.trim();
    final store = await DeckStore.open();
    await store.save(updated);
    _reload();
  }

  /// Long-press a deck card: open / rename / delete.
  Future<void> _cardActions(Map<String, dynamic> deck) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text((deck['title'] ?? 'Deck').toString(), style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'open':
        _open(deck);
      case 'rename':
        _rename(deck);
      case 'delete':
        _delete(deck);
    }
  }

  Future<String?> _askTitle() {
    return dreamInputDialog(
      context,
      title: 'New deck',
      hint: 'e.g. Q3 launch review',
      confirmLabel: 'Create',
    );
  }

  Future<void> _delete(Map<String, dynamic> deck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => dreamDialog(
        title: Text("Delete '${deck['title']}'?"),
        content: const Text('The deck file is removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
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
    return KeyboardStableMetrics(
      child: Scaffold(
        backgroundColor: kBg,
        // The only input on this screen lives inside the dialog's overlay
        // route, which handles the keyboard itself — so the page body must
        // NOT resize: the centered "No decks yet" card (and masthead) stay
        // perfectly still while the keyboard opens and closes.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Masthead: unambiguous "top" --------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
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
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          count == 0 ? 'DECKS · NONE YET' : 'DECKS · $count ON THIS DEVICE',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.8,
                            color: kText2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _GradientButton(icon: Icons.add, label: 'New deck', onPressed: _newDeck),
                ],
              ),
            ),
            // The rule: hard separation between masthead and body, in the
            // signature purple→pink→orange gradient.
            Container(height: 2, decoration: const BoxDecoration(gradient: kInkGradient)),
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
                            onLongPress: () => _cardActions(_decks[i]),
                          ),
                        ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// One deck = one charcoal tile with a hairline border and an indexed number.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.index,
    required this.deck,
    required this.onOpen,
    required this.onDelete,
    required this.onLongPress,
  });

  final int index;
  final Map<String, dynamic> deck;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final slides = (deck['slides'] as List? ?? []).length;
    final family = ((deck['dna'] ?? const {})['family'] ?? '').toString().replaceAll('_', ' ');
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kHairline, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
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
                    color: kAccent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 38, color: kHairline),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (deck['title'] ?? 'Untitled').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$slides slides · $family',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: kText2),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: kText2),
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

/// The empty-state card anchors to the steady (keyboard-free) height of the
/// body region rather than to whatever the region measures right now. If the
/// region momentarily shrinks — cold-start keyboard quirks, transient
/// system-bar churn — the surplus just flows away behind the keyboard and
/// the card keeps its exact screen position instead of shaking.
class _EmptyState extends StatefulWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_EmptyState> createState() => _EmptyScreenState();
}

class _EmptyScreenState extends State<_EmptyState> {
  double? _steadyHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Refresh the anchor only while the region is at its full size —
        // never mid-keyboard, when the region may be transiently shrunken.
        final keyboardClosed = MediaQuery.viewInsetsOf(context).bottom == 0;
        if (keyboardClosed && constraints.maxHeight > 0) {
          _steadyHeight = constraints.maxHeight;
        }
        final h = _steadyHeight;
        if (h == null) return Center(child: _card());
        // Top-anchored box of the steady height: the card centers at h/2 from
        // the region's top edge, so a shrink of the region only moves the
        // empty space that already sits behind the keyboard.
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: h,
            child: Center(child: _card()),
          ),
        );
      },
    );
  }

  Widget _card() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kHairline, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 44, color: kText2),
            const SizedBox(height: 14),
            const Text(
              'No decks yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kText),
            ),
            const SizedBox(height: 4),
            const Text(
              'Create one — then pair it with your AI.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: kText2),
            ),
            const SizedBox(height: 20),
            _GradientButton(
              icon: Icons.add,
              label: 'Create your first deck',
              onPressed: widget.onCreate,
              height: 46,
            ),
          ],
        ),
      ),
    );
  }
}

/// Signature gradient pill button (purple→pink→orange) for create actions —
/// the reference app's "create" button style.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.height = 42,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: kInkGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
