import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/resources.dart';
import '../core/saf_bridge.dart';
import '../theme.dart';
import '../widgets/dream_drawer.dart';

/// The Files drawer — the Files tab's sheet, floating over the workspace
/// as its own layer. The editor owns the layering; this widget owns the
/// surface and its contents: the sheet rides the RIBBON's top edge (a
/// constant anchor, so its height is the user's choice alone), and the
/// filmstrip is the editor's foreground layer over the sheet's LOWER part
/// — the sheet's own kSurface fills the whole region down to the ribbon
/// behind the tray, with no spacer of any kind between them. The grid's
/// scrollable carries [bottomInset] as bottom padding so its last row can
/// always be scrolled fully above that overlay — scroll content, never
/// chrome.
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
    this.bottomInset = 0,
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

  /// The overlay clearance at the sheet's bottom: the editor's filmstrip
  /// tray rides the sheet's lower part (the divider region plus the band,
  /// raised handle included), and the grid's scrollable carries this as
  /// bottom padding so the last row can always be scrolled fully above
  /// it. It is scroll content, never chrome — the sheet's outer height is
  /// the detents' alone, and the clearance is constant so the tray's
  /// toggles never jump the scroll position.
  final double bottomInset;

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
        children: [
          // The functional grab handle: the whole header is the drag
          // surface — up grows the sheet, down shrinks it toward closing.
          // It stays PINNED: never inside the scrollable, so dragging it
          // resizes the sheet (no arena contest with the list) and it is
          // still on screen at every height the sheet can ever be at —
          // the sheet's extent is floored above the header's own height.
          DreamDrawerHeader(
            title: 'Files',
            dragKey: const ValueKey('files_drawer_handle'),
            onDragUpdate: onDragUpdate,
            onDragSettle: onDragSettle,
          ),
          // The grid scrolls only when the sheet is too short for it
          // (short screens); at the resting detents the content fits
          // whole, and the drag surface never scrolls away. The bottom
          // inset is the overlay clearance — the filmstrip tray covers
          // the sheet's lower part, and the last row must be able to
          // scroll fully above it (constant, so the tray's toggles never
          // jump the scroll position).
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 10 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DreamTileRow(tiles: [
                    DreamToolTile(
                      icon: Icons.note_add,
                      label: 'New',
                      sub: 'Blank · Template',
                      onTap: onNew,
                    ),
                    DreamToolTile(
                      icon: Icons.folder_open,
                      label: 'Open',
                      sub: 'Recents · Browse',
                      onTap: onOpen,
                    ),
                    DreamToolTile(
                      icon: Icons.edit,
                      label: 'Rename',
                      onTap: onRename,
                    ),
                  ]),
                  const SizedBox(height: 10),
                  DreamTileRow(tiles: [
                    DreamToolTile(
                      icon: Icons.aspect_ratio,
                      label: 'Aspect ratio',
                      sub: aspect,
                      onTap: onAspect,
                    ),
                    DreamToolTile(
                      icon: Icons.inventory_2,
                      label: 'Deck resources',
                      sub: 'This deck only',
                      onTap: () => showResourceLibrary(context,
                          brand: false, deckId: deckId),
                    ),
                    DreamToolTile(
                      icon: Icons.public,
                      label: 'Brand resources',
                      sub: 'All decks',
                      onTap: () => showResourceLibrary(context, brand: true),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
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
              // The store's answer is one of four visible states — waiting,
              // failed, empty or the shelves — never a bare list that reads
              // "empty" while the scan is still in flight (or after it
              // threw): a load in progress and a load that failed are
              // different facts than "nothing here".
              final waiting = snapshot.connectionState != ConnectionState.done;
              final failed = snapshot.hasError;
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
                  if (waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 56),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (failed)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_outlined,
                              size: 32, color: kAccent),
                          const SizedBox(height: 10),
                          const Text(
                            'Could not read this library',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kText),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            snapshot.error.toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 11.5, color: kText2),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            onPressed: () => reload(() {}),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          'Nothing here yet — add files or a folder.',
                          style: TextStyle(fontSize: 12.5, color: kText2),
                        ),
                      ),
                    )
                  else
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
                      // kText2, not kText3: this is a privacy/storage
                      // disclosure the user is expected to actually read.
                      style: const TextStyle(fontSize: 11, color: kText2),
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
          try {
            await store.add(
                brand: brand, deckId: deckId, sourcePath: cached, folder: name);
            ok++;
          } finally {
            // The SAF staging copy in the cache has served its purpose — the
            // store copied it into its own documents tree. Leaving the
            // saf-* files behind only ever grew the cache dir (one file
            // per imported document, never reclaimed).
            try {
              final staged = File(cached);
              if (await staged.exists()) await staged.delete();
            } catch (_) {
              // A cache file we cannot remove is noise, not a failure.
            }
          }
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
