import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/resources.dart';
import '../core/saf_bridge.dart';
import '../theme.dart';

/// The Files drawer — the Files tab's sheet, floating over the workspace
/// as its own layer. The editor owns the layering; this widget owns the
/// surface and its contents: pinned to the filmstrip's top boundary, the
/// sheet covers only the slide, never the strip or the ribbon — both stay
/// fully visible and fully tappable while the drawer is open, so jumping
/// to another slide never means closing anything first.
///
/// Drag the header up or down to resize the sheet between its detents; a
/// downward fling (or dragging it far down) dismisses it, as does tapping
/// the Files tab again in the ribbon.
///
/// The surface is the app's own sheet language — one kSurface panel,
/// rounded top corners, a hairline edge, the grab handle under the centered
/// "Files" heading. The six tools sit in a 3x2 grid of equal tiles
///
/// | New | Open | Rename |
/// | Aspect ratio | Deck resources | Brand resources |
///
/// each an ELEVATED card — one deliberate step above the drawer's own
/// surface, hairline edge, the icon in a washed-purple chip — so the tiles
/// read as raised controls, not more of the panel behind them. No footer:
/// the drawer says what it does; the resource sheets carry their own scope
/// notes.
///
/// The four deck-stateful tools call back into the editor (they change
/// deck state or navigation); the two resource libraries are self-contained
/// sheets driven right off this widget — where files AND whole folders
/// import in one gesture each.
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
    this.onDragUpdate,
    this.onDragSettle,
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

  /// Live drag forwarding from the header: the vertical deltas (positive =
  /// the finger moved down) and the settle velocity, both mapped by the
  /// editor onto the sheet's extent and detents.
  final void Function(double dy)? onDragUpdate;
  final void Function(double velocityDy)? onDragSettle;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('files_drawer'),
      // One muted charcoal surface: rounded top corners, subtle top edge,
      // no shadow, no gradient — the boundary rule of the filmstrip below
      // and the workspace above stay the only other edges.
      color: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: kHairline),
      ),
      child: Column(
        // hardEdge: the sheet must survive ANY height — the grow-in mounts
        // at zero, and a deep downward drag / the dismissal collapse pass
        // through sliver heights where the content no longer fits. The
        // Column stays top-anchored, so a shrinking sheet reads as sliding
        // DOWN behind the chrome (rounded top and handle last to go),
        // clipped instead of overflowing.
        clipBehavior: Clip.hardEdge,
        children: [
          // The functional grab handle: the whole header is the drag
          // surface — up grows the sheet, down shrinks it toward closing.
          _DrawerHandle(
            onDragUpdate: onDragUpdate,
            onDragSettle: onDragSettle,
          ),
          // Short screens scroll the drawer's content instead of clipping;
          // at the resting detent the whole grid fits with room to spare.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
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
        ],
      ),
    );
  }
}

/// The drawer's header: the grab handle pill under the centered "Files"
/// heading, with the whole header as the sheet's drag surface. A drag up
/// or down streams its deltas to the editor (which resizes the sheet
/// between detents); how it settles — snap to a detent, or dismiss on a
/// downward fling / deep drag — is the editor's call, from the settle
/// velocity it receives here.
class _DrawerHandle extends StatelessWidget {
  const _DrawerHandle({this.onDragUpdate, this.onDragSettle});

  final void Function(double dy)? onDragUpdate;
  final void Function(double velocityDy)? onDragSettle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('files_drawer_handle'),
      // Opaque: the pill AND the heading are the drag surface, and the
      // header eats its own taps — a touch there is a gesture, not a
      // button press into whatever the sheet is floating over.
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDragUpdate?.call(d.delta.dy),
      onVerticalDragEnd: (d) =>
          onDragSettle?.call(d.velocity.pixelsPerSecond.dy),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 5),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  // The affordance: one shade clearer than a hairline so
                  // the pill reads as a handle, never as decoration.
                  color: kText3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
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

/// One tool tile: an elevated card — a deliberate step above the drawer's
/// own surface, hairline edge — with the icon in a washed-purple chip,
/// the label under it (wrapping, never shrinking), and the optional
/// supporting label under that. Equal footprint with its siblings; the
/// Expanded parents keep the three columns equal at every screen size.
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
    return Material(
      // The card: kElevated over the drawer's kSurface, so the grid reads
      // as raised controls rather than more of the panel behind it. The
      // Material (not a decorated Container) carries the ink — the press
      // ripple lands ON the elevated fill instead of hiding under it.
      color: kElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          // Fixed height keeps both rows' tiles equal; two label lines
          // ("Aspect ratio", "Deck resources") fit with the chip on board.
          height: 112,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  // The signature color, quiet: the glyph sits in its own
                  // washed-purple field — highlighted without borrowing the
                  // gradient the app reserves for create-moments.
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kPurpleWash,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 19, color: kPurple),
                ),
                const SizedBox(height: 6),
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
      ),
    );
  }
}

/// The resource library sheet for one scope. Assets import one file at a
/// time, many files at once, or a whole folder in one gesture — every
/// entry from a folder carries its name, so the list groups into shelves
/// (one per brand folder) instead of one undifferentiated pile. The sheet
/// states the scope (this deck only vs every deck) and the storage truth
/// (on-device, never synced). Inserting resources into slides is not
/// supported by the deck model yet — the sheet says so instead of
/// pretending.
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
                  // Loose files first (newest last, as always), then one
                  // section per imported folder — a shelf of brand folders
                  // reads as shelves, not noise.
                  ..._libraryRows(context,
                      items: items,
                      brand: brand,
                      deckId: deckId,
                      reload: reload),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _addPickedFiles(context,
                                    brand: brand, deckId: deckId)
                                .then((ok) {
                              if (ok) reload(() {});
                            }),
                            icon: const Icon(Icons.library_add, size: 18),
                            label: const Text('Add files'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _addPickedFolder(context,
                                    brand: brand, deckId: deckId)
                                .then((ok) {
                              if (ok) reload(() {});
                            }),
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: const Text('Add folder'),
                          ),
                        ),
                      ],
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

/// The library list as rows: loose files in listing order, then one
/// section per imported folder — a header with the folder's name and
/// count, its files beneath.
List<Widget> _libraryRows(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
  required bool brand,
  String? deckId,
  required void Function(void Function()) reload,
}) {
  final loose = <Map<String, dynamic>>[];
  final folders = <String, List<Map<String, dynamic>>>{};
  for (final e in items) {
    final f = e['folder']?.toString();
    if (f == null || f.isEmpty) {
      loose.add(e);
    } else {
      folders.putIfAbsent(f, () => []).add(e);
    }
  }
  return [
    for (final e in loose)
      _resourceTile(context,
          brand: brand, deckId: deckId, reload: reload, entry: e),
    for (final shelf in folders.entries) ...[
      _folderHeader(shelf.key, shelf.value.length),
      for (final e in shelf.value)
        _resourceTile(context,
            brand: brand, deckId: deckId, reload: reload, entry: e),
    ],
  ];
}

Widget _folderHeader(String name, int count) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          const Icon(Icons.folder, size: 16, color: kPurple),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: kText),
            ),
          ),
          Text('$count', style: const TextStyle(fontSize: 11.5, color: kText3)),
        ],
      ),
    );

Widget _resourceTile(
  BuildContext context, {
  required bool brand,
  String? deckId,
  required void Function(void Function()) reload,
  required Map<String, dynamic> entry,
}) =>
    ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined, color: kText2),
      title: Text(entry['name'].toString(),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_kb(entry['size'])} · added ${_when(entry['added'])}',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: IconButton(
        tooltip: 'Remove from library',
        icon: const Icon(Icons.delete_outline, color: kText2),
        onPressed: () =>
            _confirmRemove(context, brand: brand, deckId: deckId, entry: entry)
                .then((_) => reload(() {})),
      ),
    );

/// Multi-file import: the system picker's own multi-select — long-press,
/// then tap away — every selection copied into the library in ONE gesture.
/// (file_picker 13.x: pickFiles() is multi-select by itself and returns an
/// empty list when the browser is dismissed.)
Future<bool> _addPickedFiles(
  BuildContext context, {
  required bool brand,
  String? deckId,
}) async {
  final files = await FilePicker.pickFiles();
  final sources = [for (final f in files) if (f.path != null) f.path!];
  if (sources.isEmpty) return false; // dismissed — nothing to do
  return _importSources(context, brand: brand, deckId: deckId, sources: sources);
}

/// Folder import: ONE gesture brings a whole folder in — a brand's logos,
/// palettes and fonts, or any resource folder — instead of file after
/// file. Android's picker returns a `content://` tree URI the host's SAF
/// channel walks and streams; on every other platform the picked directory
/// is a real path the store walks itself.
Future<bool> _addPickedFolder(
  BuildContext context, {
  required bool brand,
  String? deckId,
}) async {
  final uri = await FilePicker.pickDirectory();
  if (uri == null) return false; // dismissed — nothing to do
  try {
    if (uri.isScheme('content')) {
      final listing = await SafBridge.list(uri.toString());
      final name = listing.rootName;
      if (listing.files.isEmpty) {
        _toast(context, 'No files found in that folder.');
        return false;
      }
      final store = await ResourceStore.open();
      var ok = 0;
      for (final f in listing.files.take(ResourceStore.importCap)) {
        try {
          final cached = await SafBridge.copyToCache(f.uri);
          await store.add(
              brand: brand, deckId: deckId, sourcePath: cached, folder: name);
          ok++;
        } catch (e) {
          print('[resources] folder import skipped one file: $e');
        }
      }
      if (ok == 0) {
        _toast(context, 'Could not read that folder — nothing was stored.');
        return false;
      }
      _toast(context,
          'Added $ok file${ok == 1 ? '' : 's'}${name.isEmpty ? '' : ' from $name'}.');
      return true;
    }
    final dir = Directory(uri.toFilePath());
    if (!dir.existsSync()) {
      _toast(context, 'That folder could not be opened.');
      return false;
    }
    final store = await ResourceStore.open();
    final added = await store.addFilesFromDirectory(
        brand: brand, deckId: deckId, dir: dir);
    if (added.isEmpty) {
      _toast(context, 'No files found in that folder.');
      return false;
    }
    final folder = added.first['folder']?.toString() ?? '';
    _toast(
        context,
        'Added ${added.length} file${added.length == 1 ? '' : 's'}'
        '${folder.isEmpty ? '' : ' from $folder'}.');
    return true;
  } on MissingPluginException {
    _toast(context,
        'Folder import is not available here — use Add files and select several at once.');
    return false;
  } catch (e) {
    print('[resources] folder import failed: $e');
    _toast(context, 'Could not add that folder — nothing was stored.');
    return false;
  }
}

/// The shared import tail: copies each picked path into the store, then
/// tells the truth about how many landed.
Future<bool> _importSources(
  BuildContext context, {
  required bool brand,
  String? deckId,
  required List<String> sources,
}) async {
  try {
    final store = await ResourceStore.open();
    var ok = 0;
    for (final path in sources) {
      try {
        await store.add(brand: brand, deckId: deckId, sourcePath: path);
        ok++;
      } catch (e) {
        print('[resources] copy failed: $e');
      }
    }
    if (ok == 0) {
      _toast(context, 'Could not add the files — they were not stored.');
      return false;
    }
    if (ok < sources.length) {
      _toast(context, 'Added $ok of ${sources.length} files — the rest could not be read.');
    } else {
      _toast(context, 'Added $ok file${ok == 1 ? '' : 's'}.');
    }
    return true;
  } catch (e) {
    print('[resources] import failed: $e');
    _toast(context, 'Could not add the files — they were not stored.');
    return false;
  }
}

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _confirmRemove(
  BuildContext context, {
  required bool brand,
  String? deckId,
  required Map<String, dynamic> entry,
}) async {
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
}
