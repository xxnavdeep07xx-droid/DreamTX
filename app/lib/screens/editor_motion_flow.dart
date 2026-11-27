part of 'editor_screen.dart';

/// The Transitions, Animations and Help tabs' surfaces + logic — the three
/// ribbon tabs that used to render nothing. Verbatim members of
/// _EditorScreenState (the one-library part split — see editor_screen.dart
/// for the class, its fields and the part map).
///
/// Storage is app-owned deck-level data (the sections/tables/imageMeta
/// carry contract): `deck['transitions']` (slideId → how the slide arrives)
/// and `deck['animations']` (objectId → how the object arrives). One
/// [_mutate] per change, so every pick is one undo step; the setters in
/// core/motion_math.dart are pure and unit-tested.
extension _EditorMotionFlow on _EditorScreenState {
  // ---- the Transitions tab -----------------------------------------------

  /// The current slide's arrival kind (push when unset).
  String get _slideTransition =>
      transitionOf(_deck, _slides.isEmpty ? null : _slides[_index]['id']);

  /// One chip pick: one undo step, one persist.
  void _setSlideTransition(String kind) {
    final id = _slideId;
    if (id == null) return;
    final updated = _copy();
    setDeckTransition(updated, id, kind);
    _mutate(updated);
  }

  /// The whole deck at once — the row's trailing action.
  void _applyTransitionToAll(String kind) {
    final updated = _copy();
    applyDeckTransitionToAll(updated, kind);
    _mutate(updated);
  }

  // ---- the Animations tab --------------------------------------------------

  /// The deck's entrance map, cast for the stage (null when no object
  /// carries an entrance — the map is only ever written here, never by the
  /// engine).
  Map<String, String>? get _entranceKinds =>
      (_deck['animations'] as Map?)?.cast<String, String>();

  /// The selected object's entrance kind (null = none).
  String? get _selectedEntrance {
    final obj = _selectedObject;
    return obj == null ? null : entranceOf(_deck, obj['id']);
  }

  /// How many objects on this slide carry an entrance.
  int get _slideEntranceCount => entranceCount(_deck, _objects);

  /// One chip pick on the selected object: one undo step, one persist.
  void _setSelectedEntrance(String kind) {
    final obj = _selectedObject;
    if (obj == null) return;
    final id = obj['id']?.toString();
    if (id == null) return;
    final updated = _copy();
    setDeckEntrance(updated, id, kind);
    _mutate(updated);
  }

  /// Preview: replay this slide's entrances on the editor's own canvas —
  /// the same clock, curve and stagger the presenter will run.
  void _previewEntrances() {
    final count = _slideEntranceCount;
    if (count == 0) {
      _toast('No entrances on this slide yet — animate an object first.');
      return;
    }
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) {
      _entranceClock.value = 1.0;
      return;
    }
    _entranceClock.duration =
        Duration(milliseconds: entranceTimelineMs(count).round());
    _entranceClock.forward(from: 0);
  }

  // ---- the Help tab ----------------------------------------------------------

  /// The ribbon's guide: how the app works, where everything lives, and the
  /// gestures that have no button. Read-only, stateless, the studio chrome.
  Future<void> _showHelpSheet() async {
    await dreamSheet<void>(
      context,
      builder: (context) => const _HelpSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// The Transitions row: a horizontally scrolling chip strip off the ribbon's
// band (the Draw row / View row geometry: one 48dp band, one-line scroll).
// ---------------------------------------------------------------------------

class _TransitionsRow extends StatelessWidget {
  const _TransitionsRow({
    required this.kind,
    required this.onPick,
    required this.onApplyAll,
  });

  /// The current slide's arrival kind (drives the selected chip).
  final String kind;

  final ValueChanged<String> onPick;
  final VoidCallback onApplyAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 10),
            const _RowLabel('THIS SLIDE ARRIVES BY'),
            const SizedBox(width: 8),
            for (final k in kTransitionKinds) ...[
              DreamChoiceChip(
                key: ValueKey('transition_chip_$k'),
                label: kTransitionLabels[k]!,
                selected: k == kind,
                onTap: () => onPick(k),
              ),
              const SizedBox(width: 8),
            ],
            // The deck-wide action rides the same strip: the current kind
            // on every slide, one undo step.
            SizedBox(
              height: 34,
              child: FilledButton.tonal(
                onPressed: onApplyAll,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('All slides'),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The Animations row: entrance effects for the SELECTED object, plus the
// whole-slide preview. Nothing selected: one actionable line, never filler.
// ---------------------------------------------------------------------------

class _AnimationsRow extends StatelessWidget {
  const _AnimationsRow({
    required this.selected,
    required this.selectedKind,
    required this.onPick,
    required this.onPreview,
    required this.animatedCount,
  });

  /// Whether an object is selected at all (the hint state is NO
  /// selection — a selected object always gets its chips, entering by
  /// "None" until it is given one).
  final bool selected;

  /// The selected object's entrance kind (null = it enters by nothing).
  final String? selectedKind;
  final ValueChanged<String> onPick;
  final VoidCallback onPreview;

  /// Objects on this slide with an entrance (the preview's audience).
  final int animatedCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 10),
            if (!selected)
              // The no-selection state: one actionable line, never filler —
              // the preview stays reachable (it previews the whole slide).
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: const Text(
                  'Select an object on the slide, then give it an entrance.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: kText2),
                ),
              )
            else ...[
              const _RowLabel('ENTERS BY'),
              const SizedBox(width: 8),
              for (final k in kEntranceKinds) ...[
                DreamChoiceChip(
                  key: ValueKey('entrance_chip_$k'),
                  label: kEntranceLabels[k]!,
                  selected: k == (selectedKind ?? kEntranceNone),
                  onTap: () => onPick(k),
                ),
                const SizedBox(width: 8),
              ],
            ],
            const SizedBox(width: 8),
            SizedBox(
              height: 34,
              child: FilledButton.tonalIcon(
                onPressed: onPreview,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Preview'),
              ),
            ),
            if (animatedCount > 0) ...[
              const SizedBox(width: 10),
              Text(
                '$animatedCount animated',
                style: const TextStyle(fontSize: 11, color: kText3),
              ),
            ],
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

/// The band's tiny lead-in label (the Draw row's hint style).
class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: kText3,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The Help sheet: the app's guide. Read-only, scrollable, the studio chrome.
// ---------------------------------------------------------------------------

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.66,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Help',
              style: TextStyle(
                  color: kText, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('help_list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                const _HelpSectionLabel('BUILD A DECK'),
                _helpRow(Icons.add, 'the + disc',
                    'adds a blank slide — long-press it for the layout list'),
                _helpRow(Icons.layers_outlined, 'the slide',
                    'renders the archetype; Insert adds text boxes, images, shapes, tables, icons, media and charts'),
                _helpRow(Icons.gesture, 'the canvas',
                    'Draw pens and highlights right on the deck; the lasso circles objects to move or recolor together'),
                _helpRow(Icons.slideshow, 'Slide show',
                    'presents the deck fullscreen at its own aspect'),
                _helpRow(Icons.undo, 'Undo / redo',
                    '60 steps each; every chip on this ribbon is one undo step'),
                const _HelpSectionLabel('GESTURES'),
                _helpRow(Icons.touch_app, 'long-press a deck card',
                    'open / rename / delete'),
                _helpRow(Icons.view_carousel_outlined, 'long-press a thumbnail',
                    'add / duplicate / reorder / delete a slide'),
                _helpRow(Icons.select_all, 'long-press an object',
                    'duplicate / delete / copy / copy style'),
                _helpRow(Icons.open_with, 'hold the Draw island\u2019s grip',
                    'lifts it off its dock; it follows the finger and snaps home'),
                _helpRow(Icons.swipe, 'edge-swipe',
                    'reveals the system bars briefly (immersive mode)'),
                const _HelpSectionLabel('THE RIBBON'),
                _helpRow(Icons.auto_awesome, 'AI',
                    'pair your own AI over MCP — goes live with the server deploy'),
                _helpRow(Icons.folder_outlined, 'Files',
                    'new / open decks, the aspect tool'),
                _helpRow(Icons.add_box, 'Insert',
                    'everything that goes on the slide'),
                _helpRow(Icons.gesture, 'Draw',
                    'pen, pencil, highlighter, eraser, lasso, ink replay'),
                _helpRow(Icons.palette_outlined, 'Design',
                    'design families, variants, slide backgrounds'),
                _helpRow(Icons.swap_horiz, 'Transitions',
                    'how each slide arrives when you present'),
                _helpRow(Icons.animation, 'Animations',
                    'entrance effects per object, staggered in draw order'),
                _helpRow(Icons.slideshow, 'Slide show',
                    'present fullscreen — swipe or tap the edges to advance'),
                _helpRow(Icons.rate_review_outlined, 'Review',
                    'comments on the deck'),
                _helpRow(Icons.visibility_outlined, 'View',
                    'reading view, outline, slide furniture'),
                _helpRow(Icons.help_outline, 'Help',
                    'this guide'),
                const _HelpSectionLabel('EXPORT'),
                _helpRow(Icons.ios_share, 'Share',
                    'sends a .pptx straight out; the Export menu adds PDF'),
                _helpRow(Icons.info_outline, 'DreamTX',
                    'decks stay on this device as plain .json files — no account, no network needed to edit'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpRow(IconData icon, String lead, String rest) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: kText3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12.5, color: kText2),
                children: [
                  TextSpan(
                    text: '$lead — ',
                    style: const TextStyle(
                        color: kText, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: rest),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpSectionLabel extends StatelessWidget {
  const _HelpSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: kText3,
        ),
      ),
    );
  }
}
