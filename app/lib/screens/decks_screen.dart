import 'dart:io' show exit;

import 'package:material_ui/material_ui.dart';

import '../core/bridge.dart';
import '../core/restart.dart';
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

  /// Set when the deck store could not be read even after the automatic
  /// retries in [_reload] — the body swaps the eternal spinner for an
  /// actionable error card with a Retry button. Never set while loading.
  String? _loadError;

  /// True when the failure carries the classic in-place-update signature:
  /// a Java ClassNotFoundException mentioning DexPathList. That means the
  /// APK was installed over this still-alive process — the Flutter UI keeps
  /// running (the engine and AOT Dart load from native code, not dex), but
  /// the first Java class the storage bridge lazily loads is gone from the
  /// stale dex path. No in-process code can repair a broken classloader, so
  /// the error card swaps its Retry for a Restart-app button (exit(0)); the
  /// next cold launch is healthy and the decks reappear untouched on disk.
  bool _needsRestart = false;

  /// True while the first stale-classloader detection of this process is
  /// self-healing: instead of asking for a tap, the card becomes a calm
  /// "Finishing the update" notice and the process restarts itself after
  /// a short beat (see [StaleProcessRestart]). Only reachable once per
  /// process; a second detection falls back to the manual card.
  bool _selfHeal = false;

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

  /// Reads the deck store. Bulletproof by design: opening the store goes
  /// over a platform channel (path_provider), and right after an in-place
  /// app update that channel can transiently stall or throw — with the old
  /// code any such hiccup died silently (uncaught async error or a never-
  /// completing await) and the dashboard spun FOREVER. Now every attempt is
  /// guarded: a timeout bounds the channel call, the catch eats any throw,
  /// a stall clears on an automatic retry, and a real failure lands as a
  /// visible error card instead of an infinite spinner.
  Future<void> _reload({bool initial = false}) async {
    // Coming from the error card (Retry): back to the spinner. Coming back
    // from the editor (normal silent refresh): no spinner flash — same
    // behavior as before this guard existed.
    if (!initial && mounted && _loadError != null) {
      setState(() {
        _loading = true;
        _loadError = null;
        _needsRestart = false;
      });
    }
    const attempts = 3;
    const perAttempt = Duration(seconds: 6);
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        final store = await DeckStore.open().timeout(perAttempt);
        final decks = await store.list();
        if (!mounted) return;
        setState(() {
          _decks = decks;
          _loading = false;
          _loadError = null;
          _needsRestart = false;
        });
        return;
      } catch (e) {
        lastError = e;
        // The stale-classloader signature is deterministic — the dex behind
        // this live process was replaced by an in-place app update, and no
        // retry can load a Java class from a dex file that no longer exists.
        // Stop immediately instead of burning the retry delays.
        if (e.toString().contains('ClassNotFound') ||
            e.toString().contains('DexPath')) {
          break;
        }
        if (i + 1 < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    if (!mounted) return;
    final msg = lastError.toString();
    final stale = msg.contains('ClassNotFound') || msg.contains('DexPath');
    // First stale detection in this process: self-heal. Show the calm
    // notice, give the frame a beat to paint, then kill the zombie process
    // outright — the user's very next launch is the healthy new build.
    final heal = stale && !StaleProcessRestart.armed;
    setState(() {
      _loading = false;
      _needsRestart = stale;
      _selfHeal = heal;
      _loadError = 'Deck store did not respond — $msg';
    });
    if (heal) {
      StaleProcessRestart.armed = true;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      StaleProcessRestart.kill();
    }
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
    final title = await _dimDuring(() => dreamInputDialog(
          context,
          title: 'Rename deck',
          initial: (deck['title'] ?? '').toString(),
          confirmLabel: 'Rename',
        ));
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
                            _selfHeal
                                ? 'DECKS · FINISHING UPDATE'
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
                            message: _loadError!,
                            onRetry: () => _reload(),
                            restart: _needsRestart,
                            auto: _selfHeal)
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
/// after the automatic retries in _reload, this replaces the spinner — an
/// actionable card in the same visual language as the empty state, carrying
/// the actual error text so a recurring cause is visible on screen, and a
/// Retry button that runs the guarded load again.
///
/// The [restart] variant is the stale-classloader case (APK installed over a
/// live process — see _needsRestart): a Retry would only fail again in this
/// broken process, so the button becomes Restart app, which kills the
/// process outright; the user reopens DreamTX and gets a healthy cold start.
///
/// The [auto] flavor is the FIRST detection in this process: the card swaps
/// its scary copy for a calm "Finishing the update" notice with no button —
/// the app restarts itself after a short beat ([StaleProcessRestart]), so
/// the user does nothing at all and the next launch is the healthy new build.
class _LoadErrorCard extends StatelessWidget {
  const _LoadErrorCard(
      {required this.message,
      required this.onRetry,
      this.restart = false,
      this.auto = false});

  final String message;
  final VoidCallback onRetry;

  /// True when the failure is the in-place-update classloader casualty —
  /// show the restart copy and the Restart-app button instead of Retry.
  final bool restart;

  /// True while this process is self-healing: the calm notice, not the
  /// manual card. Implies [restart].
  final bool auto;

  /// Deliberate self-kill for the [restart] case: the dex classloader of
  /// THIS process is stale and cannot be repaired in place, so a fresh
  /// cold launch is the only cure. exit(0) is normally avoided in Flutter
  /// apps; this is the exceptional case that justifies it.
  void _exitApp() => exit(0);

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
              Icon(
                restart
                    ? (auto ? Icons.sync : Icons.restart_alt_outlined)
                    : Icons.warning_amber_outlined,
                size: 44,
                color: restart ? kPurple : kAccent,
              ),
              const SizedBox(height: 14),
              Text(
                restart
                    ? (auto
                        ? 'Finishing the update'
                        : 'DreamTX needs a quick restart')
                    : 'Could not read your decks',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: kText),
              ),
              const SizedBox(height: 4),
              Text(
                restart
                    ? (auto
                        ? 'DreamTX was updated while it was still running, so it is closing for a second to finish switching to the new version. Your decks are safe on disk — nothing is lost. Just reopen it.'
                        : 'The app was updated while it was still running, so its storage bridge went stale. Your decks are safe on disk — nothing is lost. Tap Restart, then reopen DreamTX.')
                    : 'Device storage did not answer. This can happen right after an app update — a retry usually fixes it.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: kText2),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: kText3),
              ),
              const SizedBox(height: 20),
              if (auto)
                const SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                )
              else
                _GradientButton(
                  icon: restart ? Icons.restart_alt : Icons.refresh,
                  label: restart ? 'Restart app' : 'Retry',
                  onPressed: restart ? _exitApp : onRetry,
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
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
