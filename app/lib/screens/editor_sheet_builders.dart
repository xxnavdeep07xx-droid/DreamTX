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
