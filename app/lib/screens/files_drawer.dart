import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/resources.dart';
import '../theme.dart';

/// The Files drawer — the Files tab's replacement for the old contextual
/// tool row. A full-width charcoal panel docked directly above the ribbon
/// (the ribbon stays visible with Files lit), taking roughly the lower half
/// of the editor while the slide keeps the space above at its true aspect.
///
/// No right-side rail, no duplicate folder icon, no reserved blank column:
/// the drawer spans the editor's full width and its content uses that width
/// with even horizontal padding. One muted charcoal surface (kSurface),
/// rounded top corners, a subtle top hairline, a centered "Files" heading,
/// and a functional grab handle — drag it down (or fling) to dismiss.
///
/// The six tools sit in a 3x2 grid of equal tiles:
///
/// | New | Open | Rename |
/// | Aspect ratio | Deck resources | Brand resources |
///
/// each a simple icon over a label (labels wrap, never shrink), a subtle
/// tile border, and restrained purple accents. The quiet footer states the
/// storage truth: resources live on this device only.
///
/// The four deck-stateful tools call back into the editor (they change deck
/// state or navigation); the two resource libraries are self-contained
/// sheets driven right off this widget.
class FilesDrawer extends StatelessWidget {
  const FilesDrawer({
    super.key,
    required this.aspect,
    required this.deckId,
    required this.onNew,
    required this.onOpen,
    required this.onRename,
    required this.onAspect,
    required this.onDismiss,
  });

  /// The deck's current frame aspect — the Aspect tile shows it live.
  final String aspect;

  /// The active deck's id — scopes the Deck-resources library.
  final String deckId;

  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onAspect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      // One muted charcoal surface: rounded top corners, subtle top edge,
      // no shadow, no gradient — the filmstrip's divider above and the
      // ribbon below stay the only other boundaries.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: kHairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The functional grab handle: the whole header answers a downward
          // drag or fling by dismissing the drawer.
          _DrawerHandle(onDismiss: onDismiss),
          // Short screens scroll the drawer's content instead of clipping;
          // the grid itself fits comfortably in half a portrait editor.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _FilesTile(
                          icon: Icons.note_add,
                          label: 'New',
                          sub: 'Blank · Template',
                          onTap: onNew,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilesTile(
                          icon: Icons.folder_open,
                          label: 'Open',
                          sub: 'Recents · Browse',
                          onTap: onOpen,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilesTile(
                          icon: Icons.edit,
                          label: 'Rename',
                          onTap: onRename,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _FilesTile(
                          icon: Icons.aspect_ratio,
                          label: 'Aspect ratio',
                          sub: aspect,
                          onTap: onAspect,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilesTile(
                          icon: Icons.inventory_2,
                          label: 'Deck resources',
                          sub: 'This deck only',
                          onTap: () => showResourceLibrary(context,
                              brand: false, deckId: deckId),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilesTile(
                          icon: Icons.public,
                          label: 'Brand resources',
                          sub: 'All decks',
                          onTap: () =>
                              showResourceLibrary(context, brand: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // The quiet footer: the storage truth, stated once.
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 2),
            child: Text(
              'Resources stored on this device',
              style: const TextStyle(fontSize: 11, color: kText3),
            ),
          ),
        ],
      ),
    );
  }
}

/// The drawer's header: the grab handle pill under the centered "Files"
/// heading, with the whole header as the functional drag surface — a drag
/// of 60dp downward or a downward fling dismisses.
class _DrawerHandle extends StatefulWidget {
  const _DrawerHandle({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<_DrawerHandle> createState() => _DrawerHandleState();
}

class _DrawerHandleState extends State<_DrawerHandle> {
  double _dragDy = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragDy = 0.0,
      onVerticalDragUpdate: (d) => _dragDy += d.delta.dy,
      onVerticalDragEnd: (d) {
        final flung = d.velocity.pixelsPerSecond.dy > 250;
        if (flung || _dragDy > 60) widget.onDismiss();
      },
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: kHairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Files',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tool tile: icon above label above optional supporting label, a
/// subtle border, restrained purple accent, equal footprint with its
/// siblings. Labels wrap to a second line rather than shrinking.
class _FilesTile extends StatelessWidget {
  const _FilesTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        // Fixed height keeps both rows' tiles equal; the Expanded parents
        // keep the three columns equal in width at every screen size.
        height: 112,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kHairline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: kPurple),
              const SizedBox(height: 8),
              // Wraps without shrinking: two lines fit the longest label
              // ("Aspect ratio", "Deck resources") at the tile width.
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kText,
                  height: 1.15,
                ),
              ),
              if (sub != null) ...[
                const SizedBox(height: 3),
                Text(
                  sub!,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: kText3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The resource library sheet for one scope. Assets are picked with the
/// platform document browser, copied into the app's documents folder, and
/// listed with size and recency; each can be removed. The sheet states the
/// scope (this deck only vs every deck) and the storage truth (on-device,
/// never synced). Inserting resources into slides is not supported by the
/// deck model yet — the sheet says so instead of pretending.
Future<void> showResourceLibrary(
  BuildContext context, {
  required bool brand,
  String? deckId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: StatefulBuilder(
        builder: (context, reload) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ResourceStore.open()
                .then((s) => s.list(brand: brand, deckId: deckId)),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const [];
              return ListView(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          brand ? 'Brand resources' : 'Deck resources',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: kText),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          brand
                              ? 'Available from every deck on this device'
                              : 'Only this deck sees these',
                          style:
                              const TextStyle(fontSize: 12.5, color: kText2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final e in items)
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined,
                          color: kText2),
                      title: Text(e['name'].toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${_kb(e['size'])} · added ${_when(e['added'])}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove from library',
                        icon: const Icon(Icons.delete_outline, color: kText2),
                        onPressed: () =>
                            _confirmRemove(context, brand, deckId, e, reload),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FilledButton.tonalIcon(
                      onPressed: () => _pickResource(context,
                              brand: brand, deckId: deckId)
                          .then((ok) {
                        if (ok) reload(() {});
                      }),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add a file'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      brand
                          ? 'Stored on this device only — never synced or '
                              'uploaded. Usable from any deck here; inserting '
                              'into slides is not supported yet.'
                          : 'Stored on this device only — never synced or '
                              'uploaded. Only this deck lists them; other '
                              'decks never see them. Inserting into slides '
                              'is not supported yet.',
                      style: const TextStyle(fontSize: 11, color: kText3),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<bool> _pickResource(
  BuildContext context, {
  required bool brand,
  String? deckId,
}) async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: false);
  final file = result.files.isEmpty ? null : result.files.first;
  final path = file?.path;
  if (path == null) return false; // the picker was dismissed — nothing to do
  try {
    final store = await ResourceStore.open();
    await store.add(brand: brand, deckId: deckId, sourcePath: path);
    return true;
  } catch (e) {
    print('[resources] copy failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not add the file — it was not stored.')));
    }
    return false;
  }
}

Future<void> _confirmRemove(
  BuildContext context,
  bool brand,
  String? deckId,
  Map<String, dynamic> entry,
  void Function(void Function()) reload,
) async {
  final name = entry['name'].toString();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => dreamDialog(
      title: Text("Remove '$name'?"),
      content: const Text(
          'The file is deleted from this device\u2019s resource library.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: kAccent, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ResourceStore.open().then(
      (s) => s.remove(brand: brand, deckId: deckId, id: entry['id'].toString()));
  reload(() {});
}

String _kb(dynamic size) {
  final bytes = (size is num ? size : 0).toDouble();
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${bytes.round()} B';
}

String _when(dynamic added) {
  final ms = (added is num ? added : 0).toInt();
  if (ms <= 0) return 'unknown';
  final age = DateTime.now().millisecondsSinceEpoch - ms;
  if (age < 60000) return 'just now';
  if (age < 3600000) return '${(age / 60000).round()} min ago';
  if (age < 86400000) return '${(age / 3600000).round()} h ago';
  return '${(age / 86400000).round()} d ago';
}
