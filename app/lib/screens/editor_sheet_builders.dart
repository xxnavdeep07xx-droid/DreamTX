part of 'editor_screen.dart';

// ---- bottom-sheet content widgets ------------------------------------------------
//
// The pure-UI bodies of the editor's `dreamSheet` pickers and menus, lifted
// out of `_EditorScreenState` one-by-one. Each one is the exact tree the old
// inline `builder:` closures produced: the widget's build context IS the
// sheet's context, so `Navigator.pop(context, value)` resolves the sheet the
// same way, and results flow back to the orchestrating method unchanged.
//
// Data and actions stay owned by the editor state — these widgets take the
// list to render or the callback to run, nothing more.

/// **New deck** — Blank, or a design family composes it. Pops `'blank'` /
/// `'template'`.
class _NewDeckSheet extends StatelessWidget {
  const _NewDeckSheet();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('New deck',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        ListTile(
          leading: const Icon(Icons.note_add, color: kPurple),
          title: const Text('Blank'),
          subtitle: const Text('Starts empty — no template content'),
          onTap: () => Navigator.pop(context, 'blank'),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome, color: kPurple),
          title: const Text('Template'),
          subtitle: const Text('A design family composes the deck'),
          onTap: () => Navigator.pop(context, 'template'),
        ),
      ],
    );
  }
}

/// **Design family** — which family composes a new template deck. Pops the
/// family id.
class _DesignFamilySheet extends StatelessWidget {
  const _DesignFamilySheet();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Design family',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        for (final (id, label) in _designFamilies)
          ListTile(
            leading: const Icon(Icons.palette, color: kPurple),
            title: Text(label),
            onTap: () => Navigator.pop(context, id),
          ),
      ],
    );
  }
}

/// **Open a deck** — Recents (this device) or Browse Files. Pops `'recents'`
/// / `'browse'`.
class _OpenDeckSheet extends StatelessWidget {
  const _OpenDeckSheet();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Open a deck',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        ListTile(
          leading: const Icon(Icons.history, color: kPurple),
          title: const Text('Recents'),
          subtitle: const Text('Decks saved on this device'),
          onTap: () => Navigator.pop(context, 'recents'),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file, color: kPurple),
          title: const Text('Browse files'),
          subtitle: const Text('DreamTX deck (.json) — .pptx import isn\u2019t supported'),
          onTap: () => Navigator.pop(context, 'browse'),
        ),
      ],
    );
  }
}

/// **Recents** — the decks on this device, newest first. Pops the chosen deck
/// map; the current deck is flagged inline.
class _RecentsSheet extends StatelessWidget {
  const _RecentsSheet({required this.decks, required this.currentId});

  final List<Map<String, dynamic>> decks;
  final String currentId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Recents',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          for (final d in decks)
            ListTile(
              leading: const Icon(Icons.layers_outlined, color: kPurple),
              title: Text((d['title'] ?? 'Untitled').toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${((d['slides'] as List?) ?? []).length} slides · '
                '${((d['dna'] ?? const {})['family'] ?? '').toString().replaceAll('_', ' ')}'
                '${d['id'].toString() == currentId ? ' · this deck' : ''}',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () => Navigator.pop(context, d),
            ),
        ],
      ),
    );
  }
}

/// **Aspect ratio** — the current ratio plus the supported presets. Pops the
/// chosen aspect string.
class _AspectSheet extends StatelessWidget {
  const _AspectSheet({required this.current, required this.aspects});

  final String current;
  final List<String> aspects;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aspect ratio',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Current: $current · ${dimsLabel(current)}',
                  style: const TextStyle(fontSize: 12.5, color: kText2)),
            ],
          ),
        ),
        for (final a in aspects)
          ListTile(
            leading: Icon(
              a == current ? Icons.check_circle : Icons.crop_free,
              color: a == current ? kPurple : kText2,
            ),
            title: Text(a),
            subtitle: Text(dimsLabel(a),
                style: const TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.pop(context, a),
          ),
      ],
    );
  }
}

/// **Add slide** — the curated archetype list, with the pacing engine's
/// suggestion in the header. Pops the archetype label.
class _ArchetypeSheet extends StatelessWidget {
  const _ArchetypeSheet({required this.suggested, required this.archetypes});

  final String suggested;
  final List<String> archetypes;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Add slide${suggested.isEmpty ? '' : ' — suggested next: $suggested'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...archetypes.map((a) => ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: Text(a),
              onTap: () => Navigator.pop(context, a),
            )),
      ],
    );
  }
}

/// **Slide actions** — the filmstrip's per-slide menu. Pops the action code
/// (`'edit'` / `'section'` / `'dup'` / `'left'` / `'right'` / `'del'`); the
/// orchestrating method maps it onto the deck. "Start section here" is
/// disabled when the slide already opens a section.
class _SlideActionsSheet extends StatelessWidget {
  const _SlideActionsSheet({
    required this.index,
    required this.count,
    required this.startsSection,
  });

  final int index;
  final int count;

  /// Whether slide [index] is already the start of a section.
  final bool startsSection;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Slide ${index + 1} of $count',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Edit content'),
          onTap: () => Navigator.pop(context, 'edit'),
        ),
        ListTile(
          leading: const Icon(Icons.label_outline),
          title: const Text('Start section here'),
          enabled: !startsSection,
          subtitle: Text(
              startsSection
                  ? 'This slide already starts a section'
                  : 'A named divider in the filmstrip',
              style: const TextStyle(fontSize: 11.5)),
          onTap: () => Navigator.pop(context, 'section'),
        ),
        ListTile(
          leading: const Icon(Icons.content_copy),
          title: const Text('Duplicate'),
          onTap: () => Navigator.pop(context, 'dup'),
        ),
        ListTile(
          leading: const Icon(Icons.arrow_upward),
          title: const Text('Move left'),
          enabled: index > 0,
          onTap: () => Navigator.pop(context, 'left'),
        ),
        ListTile(
          leading: const Icon(Icons.arrow_downward),
          title: const Text('Move right'),
          enabled: index < count - 1,
          onTap: () => Navigator.pop(context, 'right'),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline,
              color: Theme.of(context).colorScheme.error),
          title: const Text('Delete'),
          onTap: () => Navigator.pop(context, 'del'),
        ),
      ],
    );
  }
}

/// **Object actions** — the long-press context menu for a canvas object
/// (the mobile answer to PowerPoint's right-click). Pops the action code
/// (`'copy'` / `'dup'` / `'copyStyle'` / `'applyStyle'` / `'del'`); the
/// orchestrating method maps it onto the deck. Apply style stays disabled
/// until a style has been picked up — the subtitle says what's missing.
class _ObjectActionsSheet extends StatelessWidget {
  const _ObjectActionsSheet({required this.canApplyStyle});

  /// Whether the style clipboard holds a pickup (Copy style ran first).
  final bool canApplyStyle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Object actions',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.copy_all_outlined),
          title: const Text('Copy'),
          subtitle: const Text('Then long-press the canvas to paste',
              style: TextStyle(fontSize: 11.5)),
          onTap: () => Navigator.pop(context, 'copy'),
        ),
        ListTile(
          leading: const Icon(Icons.content_copy),
          title: const Text('Duplicate'),
          onTap: () => Navigator.pop(context, 'dup'),
        ),
        ListTile(
          leading: const Icon(Icons.format_paint_outlined),
          title: const Text('Copy style'),
          subtitle: const Text('Pick up fill, stroke, opacity, effects',
              style: TextStyle(fontSize: 11.5)),
          onTap: () => Navigator.pop(context, 'copyStyle'),
        ),
        ListTile(
          leading: const Icon(Icons.format_paint),
          title: const Text('Apply style'),
          enabled: canApplyStyle,
          subtitle: Text(
              canApplyStyle
                  ? 'The picked-up style, on this object'
                  : 'Copy a style first',
              style: const TextStyle(fontSize: 11.5)),
          onTap: () => Navigator.pop(context, 'applyStyle'),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline,
              color: Theme.of(context).colorScheme.error),
          title: const Text('Delete'),
          onTap: () => Navigator.pop(context, 'del'),
        ),
      ],
    );
  }
}

/// **Section actions** — the filmstrip's per-section menu (long-press a
/// section chip). Pops `'rename'` / `'remove'`; removal deletes the
/// divider only — the slides were never part of it.
class _SectionActionsSheet extends StatelessWidget {
  const _SectionActionsSheet({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(name.isEmpty ? 'Section' : name,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Rename section'),
          onTap: () => Navigator.pop(context, 'rename'),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline,
              color: Theme.of(context).colorScheme.error),
          title: const Text('Remove section'),
          subtitle: const Text('The slides stay — only the divider goes',
              style: TextStyle(fontSize: 11.5)),
          onTap: () => Navigator.pop(context, 'remove'),
        ),
      ],
    );
  }
}

/// The WordArt gallery's presets — library-level like `_designFamilies`
/// (the sheet that renders them and the editor that inserts them both
/// read this one list). Colors are semantic — 'ink' | 'white' | 'muted' |
/// 'accent' — resolved on insert; the accent reaches the run, the glow,
/// or the badge's fill.
const List<Map<String, dynamic>> _wordArtPresets = [
  {
    'id': 'headline',
    'label': 'Headline',
    'w': 560.0,
    'h': 150.0,
    'font_size': 58.0,
    'color': 'ink',
    'shadow': true,
  },
  {
    'id': 'accent',
    'label': 'Accent',
    'w': 560.0,
    'h': 150.0,
    'font_size': 58.0,
    'color': 'accent',
  },
  {
    'id': 'glow',
    'label': 'Glow',
    'w': 560.0,
    'h': 160.0,
    'font_size': 58.0,
    'color': 'accent',
    'glow': true,
  },
  {
    'id': 'marker',
    'label': 'Highlight',
    'w': 560.0,
    'h': 110.0,
    'font_size': 38.0,
    'color': 'ink',
    'highlight': 'FFD400',
  },
  {
    'id': 'badge',
    'label': 'Badge',
    'w': 380.0,
    'h': 110.0,
    'font_size': 34.0,
    'color': 'white',
    'fill_accent': true,
  },
  {
    'id': 'watermark',
    'label': 'Watermark',
    'w': 720.0,
    'h': 190.0,
    'font_size': 84.0,
    'color': 'muted',
    'italic': true,
    'opacity': 0.35,
  },
];

/// **WordArt** — the styled-text gallery (the seventh Insert card). Each
/// tile previews its look at card scale; picking pops the preset id and
/// the editor resolves the semantic colors ('accent' → the deck's DNA
/// accent) and inserts a live text box in that style, keyboard open.
class _WordArtSheet extends StatelessWidget {
  const _WordArtSheet({required this.accentHex});

  /// The deck's resolved DNA accent (RRGGBB) — the accent previews.
  final String accentHex;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('WordArt',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            children: [
              for (var r = 0; r * 2 < _wordArtPresets.length; r++)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: r * 2 + 2 < _wordArtPresets.length ? 8 : 0),
                  child: Row(
                    children: [
                      for (var c = 0; c < 2; c++)
                        if (r * 2 + c < _wordArtPresets.length)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                  left: c == 0 ? 0 : 4,
                                  right: c == 1 ? 0 : 4),
                              child: _WordArtPreview(
                                preset: _wordArtPresets[r * 2 + c],
                                accentHex: accentHex,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One gallery tile: the preset's look rendered at preview scale plus its
/// name. The preview approximates (boxShadow for shadow/glow, a filled
/// chip for the badge) — it communicates the look, the insert carries the
/// exact model payload.
class _WordArtPreview extends StatelessWidget {
  const _WordArtPreview({required this.preset, required this.accentHex});

  final Map<String, dynamic> preset;
  final String accentHex;

  @override
  Widget build(BuildContext context) {
    final accent = hexToColor(accentHex);
    final color = switch (preset['color']) {
      'accent' => accent,
      'white' => Colors.white,
      'muted' => kText2,
      _ => kText,
    };
    final Widget sample;
    if (preset['highlight'] != null) {
      // The marker pen: ink on a highlighter chip.
      sample = Container(
        color: hexToColor(preset['highlight'].toString()),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: Text('Your text',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      );
    } else if (preset['fill_accent'] == true) {
      // The badge: white on the accent chip.
      sample = Container(
        decoration: BoxDecoration(
            color: accent, borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: const Text('Your text',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );
    } else {
      // The type-only looks; translucent presets stay visible enough
      // to read (the floor is for the watermark's 0.35).
      final o = preset['opacity'] == null
          ? 1.0
          : ((preset['opacity'] as num).toDouble())
              .clamp(0.55, 1.0)
              .toDouble();
      sample = Opacity(
        opacity: o,
        child: Text('Your text',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontStyle:
                    preset['italic'] == true ? FontStyle.italic : null,
                color: color)),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(context, preset['id'].toString()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: kElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kHairline),
          boxShadow: preset['shadow'] == true
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(2, 3)),
                ]
              : preset['glow'] == true
                  ? [
                      BoxShadow(
                          color: accent.withValues(alpha: 0.6), blurRadius: 12),
                    ]
                  : null,
        ),
        child: Column(
          children: [
            sample,
            const SizedBox(height: 6),
            Text(preset['label'].toString(),
                style: const TextStyle(fontSize: 11, color: kText2)),
          ],
        ),
      ),
    );
  }
}

/// **Resource images** — the importable images of the deck's or the brand's
/// SAF resource store. Pops the chosen entry; thumbnails resolve through
/// [pathOf] (the editor's cached `_resourcePathOf`) so they render on the
/// first frame.
class _ImageResourceSheet extends StatelessWidget {
  const _ImageResourceSheet({
    required this.brand,
    required this.images,
    required this.pathOf,
  });

  final bool brand;
  final List<Map<String, dynamic>> images;

  /// Resolves a resource entry to its cached file path.
  final String? Function(Map<String, dynamic> entry) pathOf;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              brand ? 'Brand resources — images' : 'Deck resources — images',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          for (final e in images)
            ListTile(
              leading: Image(
                image: FileImage(File(pathOf(e) ?? '')),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.image_outlined, size: 22),
              ),
              title: Text('${e['name']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${((e['size'] ?? 0) as num).toInt() ~/ 1024} KB',
                  style: const TextStyle(fontSize: 11.5)),
              onTap: () => Navigator.pop(context, e),
            ),
        ],
      ),
    );
  }
}

/// **Comments** — the slide's comment list with the input row. Posting runs
/// [onPost] (the editor's own state update, which owns the list and clears
/// the shared field) and then rebuilds the sheet.
class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.comments,
    required this.field,
    required this.onPost,
  });

  final List<Map<String, String>> comments;

  /// The editor-owned input controller — posting reads and clears it.
  final TextEditingController field;

  /// Adds the comment where `_comments` lives (the editor's `setState`).
  final void Function(String text) onPost;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  void _post() {
    final text = widget.field.text.trim();
    if (text.isEmpty) return;
    widget.onPost(text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Comments',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (widget.comments.isEmpty)
          const SizedBox(
            height: 120,
            child: Center(
                child: Text('No comments yet — leave the first one.',
                    style: _rowHint)),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final c in widget.comments)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline,
                        size: 20, color: kText2),
                    title: Text(c['text'] ?? ''),
                    subtitle: const Text('You · just now'),
                  ),
              ],
            ),
          ),
        const Divider(height: 1, color: kHairline),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.field,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Add a comment',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Post comment',
                icon: const Icon(Icons.send, size: 20),
                onPressed: _post,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// **Export deck** — the two format actions. Each pops the sheet first, then
/// hands the operation to [onExport] (the editor's `_export` pipeline).
class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.busy, required this.onExport});

  final bool busy;

  /// Runs the export pipeline with the sheet already closed.
  final Future<void> Function(String op) onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Export deck',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      onExport('export_pptx');
                    },
              icon: const Icon(Icons.description, size: 18),
              label: const Text('PowerPoint (.pptx)'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      onExport('export_pdf');
                    },
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('PDF (.pdf)'),
            ),
          ),
        ),
      ],
    );
  }
}
