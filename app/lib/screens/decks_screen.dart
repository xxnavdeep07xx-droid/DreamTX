import 'package:material_ui/material_ui.dart';

import '../core/bridge.dart';
import '../core/resources.dart';
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

  /// Set when the deck store could not be read even after the bounded
  /// attempts in [_reload] — the body swaps the eternal spinner for an
  /// actionable error card with a Retry button. Never set while loading.
  String? _loadError;

  /// Monotonic generation counter: a reload that starts while an older one
  /// is still awaiting storage can never have its own results overwritten
  /// by the older run's late answer.
  int _reloadGeneration = 0;

  /// True while an input dialog (New deck / Rename) is on screen. The
  /// empty-state card recedes (fades) while a dialog is open — see
  /// _EmptyState. Measured reality on window-resize-free devices: the card
  /// never moves when the keyboard opens, but the keyboard covers its whole
  /// lower half and the dialog covers its top edge, leaving a middle sliver
  /// that the eye misreads as a "lifted card". Fading the background card
  /// removes that misread: it recedes politely instead of sitting there
  /// half-consumed. No position ever changes.
  bool _dialogOpen = false;

  /// Runs [show] with the dialog-dim active, always restoring it after.
  Future<T?> _dimDuring<T>(Future<T?> Function() show) async {
    setState(() => _dialogOpen = true);
    try {
      return await show();
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _reload(initial: true);
  }

  /// Reads the deck store. Every await is bounded ([DeckStore.open] bounds
  /// the platform-channel call, [DeckStore.scan] bounds the whole read) and
  /// every call inside is nonblocking — a stalled channel or a wedged file
  /// surfaces as a visible error card with a Retry button within seconds,
  /// never as an infinite spinner and never as a crash. One immediate retry
  /// absorbs a transient stall right after an in-place app update; after
  /// that the user decides. No process is ever killed, and no startup path
  /// demands an uninstall, a data wipe, or network.
  Future<void> _reload({bool initial = false}) async {
    final gen = ++_reloadGeneration;
    // Coming from the error card (Retry): back to the spinner. Coming back
    // from the editor (normal silent refresh): no spinner flash — the list
    // stays on screen until the fresh scan lands.
    if (!initial && mounted && _loadError != null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    const attempts = 2;
    const retryGap = Duration(milliseconds: 400);
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        final store = await DeckStore.open();
        // Returning from the editor: let its queued writes land first, so
        // the scan below can never see a stale library.
        await store.flushPendingWrites();
        final scan = await store.scan();
        if (gen != _reloadGeneration || !mounted) return;
        if (scan.skipped.isNotEmpty) {
          // Diagnostics: unreadable files are named, never conflated with
          // an empty library.
          print('[deck-store] scan skipped ${scan.skipped.length} '
              'unreadable deck file(s): ${scan.skipped.join(', ')}');
        }
        setState(() {
          _decks = scan.decks;
          _loading = false;
          _loadError = null;
        });
        return;
      } catch (e, st) {
        lastError = e;
        // Full trace to the logs only — the card carries a concise message.
        print('[deck-store] load attempt ${i + 1}/$attempts failed: $e\n$st');
        if (i + 1 < attempts) await Future<void>.delayed(retryGap);
      }
    }
    if (gen != _reloadGeneration || !mounted) return;
    setState(() {
      _loading = false;
      _loadError = 'Deck store did not respond — ${_briefError(lastError)}';
    });
  }

  /// One line, at most ~200 chars: the actual error text for the card, with
  /// the stack trace kept strictly in the logs.
  static String _briefError(Object? e) {
    var msg = e.toString();
    final nl = msg.indexOf('\n');
    if (nl >= 0) msg = msg.substring(0, nl);
    if (msg.length > 200) msg = msg.substring(0, 200);
    return msg;
  }

  Future<void> _newDeck() async {
    final title = await _dimDuring(_askTitle);
    if (title == null || title.trim().isEmpty) return;
    final r = Bridge.command(
        {'op': 'new_deck', 'title': title.trim(), 'family': 'swiss_editorial'});
    if (r['ok'] != true) {
      _toast('Engine error: ${r['error']}');
      return;
    }
    final deck = (r['deck'] as Map).cast<String, dynamic>();
    try {
      final store = await DeckStore.open();
      await store.save(deck);
    } catch (e) {
      // Storage trouble is never silent: say it, then still open the editor
      // — the deck lives in memory and every later save retries.
      print('[deck-store] new deck could not be written: $e');
      _toast('Deck created, but storage is not answering — it will retry '
          'every time you edit.');
    }
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
    final title = await _dimDuring(() => dreamInputDialog(
          context,
          title: 'Rename deck',
          initial: (deck['title'] ?? '').toString(),
          confirmLabel: 'Rename',
        ));
    if (title == null || title.trim().isEmpty) return;
    final updated = Map<String, dynamic>.from(deck);
    updated['title'] = title.trim();
    try {
      final store = await DeckStore.open();
      await store.save(updated);
    } catch (e) {
      print('[deck-store] rename could not be written: $e');
      _toast('Storage did not accept the rename — try again from the card.');
      return;
    }
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
              child: Text((deck['title'] ?? 'Deck').toString(),
                  style: Theme.of(context).textTheme.titleMedium),
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
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: kAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = (deck['id']).toString();
    try {
      final store = await DeckStore.open();
      await store.delete(id);
    } catch (e) {
      print('[deck-store] delete failed on disk: $e');
      _toast('Could not delete the deck file — it stays in your library.');
      return; // the list below would be a lie
    }
    // The deck's OWN resource scope is orphaned by definition — only that
    // deck ever saw those files — so they go with it. Brand resources stay:
    // every deck shares them.
    try {
      final resources = await ResourceStore.open();
      await resources.wipeScope(deckId: id);
    } catch (e) {
      // The deck file is gone; a resource we could not sweep is noise on
      // disk, never a lie in the list.
      print('[resources] deck scope sweep failed for $id: $e');
    }
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
                            _loading
                                ? 'DECKS · LOADING'
                                : _loadError != null
                                    ? 'DECKS · STORAGE OFFLINE'
                                    : (count == 0
                                        ? 'DECKS · NONE YET'
                                        : 'DECKS · $count ON THIS DEVICE'),
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
                    _GradientButton(
                        icon: Icons.add,
                        label: 'New deck',
                        onPressed: _newDeck),
                  ],
                ),
              ),
              // The rule: hard separation between masthead and body, in the
              // signature purple→pink→orange gradient.
              Container(
                  height: 2,
                  decoration: const BoxDecoration(gradient: kInkGradient)),
              // ---- Body: ruled deck index ------------------------------------
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                        ? _LoadErrorCard(
                            message: _loadError!, onRetry: () => _reload())
                        : count == 0
                            ? _EmptyState(
                                onCreate: _newDeck, dimmed: _dialogOpen)
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 18, 20, 28),
                                itemCount: count,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
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
    final family = ((deck['dna'] ?? const {})['family'] ?? '')
        .toString()
        .replaceAll('_', ' ');
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
                  // Optically centered in its slot between the card edge and
                  // the divider — left-aligned text (with letterSpacing's
                  // trailing space) sat visibly off-center in the 38px zone.
                  textAlign: TextAlign.center,
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
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kText),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$slides slides · $family',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: kText2),
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
///
/// While an input dialog is open ([dimmed] = true) the card recedes: it fades
/// to 30% opacity over 250ms and comes back when the dialog closes. This is
/// purely visual — the position NEVER changes. Rationale: with the keyboard
/// open, the OS keyboard covers the card's lower half and the dialog covers
/// its top edge, leaving a middle sliver that the eye misreads as a "lifted
/// card". A faded, receded background gives the eye nothing to misread.
class _EmptyState extends StatefulWidget {
  const _EmptyState({required this.onCreate, this.dimmed = false});

  final VoidCallback onCreate;
  final bool dimmed;

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
            child: Center(
              // Recede while a dialog owns the screen: fade, never move.
              child: AnimatedOpacity(
                opacity: widget.dimmed ? 0.3 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: _card(),
              ),
            ),
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
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: kText),
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

/// Failure state for the deck store: when the store cannot be read even
/// after the bounded attempts in _reload, this replaces the spinner — an
/// actionable card in the same visual language as the empty state, carrying
/// a concise rendition of the actual error (full stack traces stay in the
/// logs) and a Retry button that runs the bounded load again.
class _LoadErrorCard extends StatelessWidget {
  const _LoadErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
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
              const Icon(Icons.warning_amber_outlined, size: 44, color: kAccent),
              const SizedBox(height: 14),
              const Text(
                'Could not read your decks',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: kText),
              ),
              const SizedBox(height: 4),
              const Text(
                'Device storage did not answer. This can happen right after an '
                'app update — a retry usually fixes it. Your decks stay safe on '
                'disk either way.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: kText2),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: kText2),
              ),
              const SizedBox(height: 20),
              _GradientButton(
                icon: Icons.refresh,
                label: 'Retry',
                onPressed: onRetry,
                height: 46,
              ),
            ],
          ),
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
                // Never overflow the pill on narrow cards or under large
                // accessibility text scales — ellipsize instead.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
