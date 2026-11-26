part of 'editor_screen.dart';

/// The Insert drawer flows: inserts, live object edits, table actions. Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorInsertFlow on _EditorScreenState {
  void _liveObjectEdit(Map<String, dynamic> updated) {
    if (!_styleUndoPushed) {
      _styleUndoPushed = true;
      _undo.add(_copy());
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    _replaceObjectLocal(updated);
    _objectCommitDebounce?.cancel();
    _objectCommitDebounce = Timer(const Duration(milliseconds: 350), () {
      final obj = _selectedObject;
      if (obj == null) return;
      final r = Bridge.command({
        'op': 'update_object',
        'deck': _deck,
        'slide_id': _slideId,
        'object_id': obj['id'],
        'shape': obj,
      });
      if (r['ok'] == true && r['deck'] is Map) {
        _setDeck(r['deck'] as Map);
      }
    });
    if (mounted) _setState(() {});
  }

  // ---- the Insert drawer's flows -------------------------------------------------

  Map<String, dynamic> _newContentObject({
    required double w,
    required double h,
    Map<String, dynamic>? content,
    Map<String, dynamic>? fill,
    Map<String, dynamic>? stroke,
    Map<String, dynamic>? effects,
    double opacity = 1.0,
  }) {
    final (dw, dh) = deckDimsOf(_deck['aspect']?.toString());
    return {
      'id': _newObjectId(),
      'preset': 'rectangle',
      'x': (dw - w) / 2,
      'y': (dh - h) / 2,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': opacity,
      'locked': false,
      'fill': fill ?? {'type': 'none'},
      'stroke': stroke ?? {'color': '17181A', 'width': 0.0, 'dash': 'solid', 'start_arrow': 'none', 'end_arrow': 'none'},
      'effects': effects ?? {},
      'closed': true,
      if (content != null) 'content': content,
    };
  }

  void _insertObject(Map<String, dynamic> shape, {bool startTyping = false}) {
    final slideId = _slideId;
    if (slideId == null) {
      _toast('Add a slide first.');
      return;
    }
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': slideId,
      'shape': shape,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _prepareSelectionFor(shape['id'] as String?);
      // The Insert tab must be the active sheet when inserting (the grid
      // lives there); a text box goes straight into typing.
      if (_navTab != _NavTab.insert) _setNavTab(_NavTab.insert);
      if (startTyping) _beginTyping();
    } else {
      _toast('Could not insert: ${r['error']}');
    }
  }

  /// Text Box: an editable text box mid-slide, selected, keyboard open.
  void _insertTextBox() {
    _insertObject(
      _newContentObject(w: 560, h: 170, content: ObjectContent.text(RichDoc())),
      startTyping: true,
    );
  }

  // ---- WordArt (styled-text presets over the model's own powers) --------
  //
  // The seventh Insert card. Six looks assembled ENTIRELY from what every
  // text object already carries — per-run character formatting (size,
  // weight, italic, color, highlight) plus the object chrome both
  // exporters already render (the box's solid fill, the soft shadow, the
  // accent glow). A WordArt insert IS a text box with a preset: it lands
  // selected with the keyboard open on placeholder text, and everything
  // stays editable afterwards — the inspector, the format painter, the
  // exporters, all of it. 'accent' entries resolve to the deck's DNA
  // accent at insert time, so one gallery matches every design family.
  // The presets themselves live at library level (next to the gallery
  // sheet that renders them).

  /// The WordArt tile: the gallery sheet, then the insert.
  Future<void> _wordArtGallery() async {
    final id = await dreamSheet<String>(
      context,
      builder: (context) => _WordArtSheet(accentHex: _dnaAccentHex),
    );
    if (id != null) _addWordArt(id);
  }

  /// Insert the preset: a text box in the preset's style, mid-slide,
  /// keyboard open on the placeholder — the first keystrokes make it
  /// yours.
  void _addWordArt(String presetId) {
    final preset = _wordArtPresets.firstWhere(
        (p) => p['id'] == presetId,
        orElse: () => _wordArtPresets.first);
    final accent = _dnaAccentHex;
    final color = switch (preset['color']) {
      'accent' => accent,
      'white' => 'FFFFFF',
      'muted' => '6B6E76',
      _ => '17181A',
    };
    const placeholder = 'Your text here';
    final doc = RichDoc(
      text: placeholder,
      runs: [
        RichRun(
          start: 0,
          end: placeholder.length,
          bold: true,
          italic: preset['italic'] == true ? true : null,
          fontSize: (preset['font_size'] as num).toDouble(),
          color: color,
          highlight: preset['highlight']?.toString(),
        ),
      ],
    );
    final effects = <String, dynamic>{};
    if (preset['shadow'] == true) {
      effects['shadow'] = {
        'dx': 4.0,
        'dy': 6.0,
        'blur': 10.0,
        'color': '000000',
        'opacity': 0.35,
      };
    }
    if (preset['glow'] == true) {
      effects['glow'] = {'color': accent, 'blur': 18.0};
    }
    _insertObject(
      _newContentObject(
        w: (preset['w'] as num).toDouble(),
        h: (preset['h'] as num).toDouble(),
        content: ObjectContent.text(doc),
        fill: preset['fill_accent'] == true
            ? {'type': 'solid', 'color': accent}
            : null,
        effects: effects.isEmpty ? null : effects,
        opacity: preset['opacity'] == null
            ? 1.0
            : (preset['opacity'] as num).toDouble(),
      ),
      startTyping: true,
    );
  }

  /// Table: 3×3 with editable cells.
  void _insertTable() {
    _insertObject(
      _newContentObject(
        w: 620,
        h: 340,
        content: ObjectContent.table(3, 3),
        stroke: const {
          'color': '17181A',
          'width': 1.5,
          'dash': 'solid',
          'start_arrow': 'none',
          'end_arrow': 'none',
        },
      ),
    );
  }

  /// Chart: a column chart with sample data; edit it from the object menu.
  void _insertChart() {
    _insertObject(
      _newContentObject(
        w: 560,
        h: 340,
        content: ObjectContent.chart(defaultChartData()),
      ),
    );
  }

  /// Icon sticker from the searchable registry.
  void _insertIcon(String name) {
    _insertObject(
      _newContentObject(
        w: 140,
        h: 140,
        content: ObjectContent.icon(name),
        fill: {'type': 'solid', 'color': colorToHex(_baseTextColor)},
      ),
    );
  }

  /// Image: Gallery / Camera / Deck Resources / Brand Resources.
  Future<void> _pickImage(String source) async {
    if (source == 'deck' || source == 'brand') {
      await _pickImageResource(source == 'brand');
      return;
    }
    final path =
        await ImagePickers.pickImage(camera: source == 'camera');
    if (path == null || !mounted) return;
    await _insertImageFromPath(path);
  }

  Future<void> _insertImageFromPath(String path) async {
    try {
      final store = await ResourceStore.open();
      final entry = await store.add(
        brand: false,
        deckId: (_deck['id'] ?? '').toString(),
        sourcePath: path,
      );
      // The resolver cache is populated IMMEDIATELY: the object inserts on
      // the very next frame and the content layer reads this map
      // synchronously — a missing entry would render the just-imported
      // image as a "missing asset" card until some later rebuild.
      final resolved = _resourcePathOf(entry, brand: false);
      if (resolved != null) {
        _resourcePaths['deck:${entry['id']}'] = resolved;
      }
      if (!mounted) return;
      _insertObject(
        _newContentObject(
          w: 480,
          h: 300,
          content: ObjectContent.image('${entry['id']}',
              brand: false, name: '${entry['name']}'),
        ),
      );
    } catch (e) {
      _toast('Could not import that image: $e');
    }
  }

  String? _resourcePathOf(Map<String, dynamic> entry, {required bool brand}) {
    try {
      final store = ResourceStore.peek();
      if (store == null) return null;
      final dir = store.scopeDirPath(
          brand: brand,
          deckId: brand ? null : (_deck['id'] ?? '').toString());
      return '$dir/${entry['file']}';
    } catch (_) {
      return null;
    }
  }

  /// Pick an image from the device's resource libraries (deck or brand).
  /// [replace] swaps the ASSET on the currently selected image object
  /// instead of inserting a new one (frame + metadata survive).
  Future<void> _pickImageResource(bool brand, {bool replace = false}) async {
    try {
      final store = await ResourceStore.open();
      final items = await store.list(
          brand: brand, deckId: brand ? null : (_deck['id'] ?? '').toString());
      final images = items
          .where((e) => isImagePath('${e['name']}'))
          .toList(growable: false);
      if (!mounted) return;
      if (images.isEmpty) {
        _toast(brand
            ? 'No images in Brand resources yet — import some from Files.'
            : 'No images in this deck\'s resources yet — import some from Files.');
        return;
      }
      final choice = await dreamSheet<Map<String, dynamic>>(
        context,
        builder: (sheetContext) => _ImageResourceSheet(
          brand: brand,
          images: images,
          pathOf: (e) => _resourcePathOf(e, brand: brand),
        ),
      );
      if (choice == null || !mounted) return;
      // Same immediate-cache contract as a fresh import: the library pick
      // resolves the file NOW so the inserted object renders first frame.
      final resolved = _resourcePathOf(choice, brand: brand);
      if (resolved != null) {
        _resourcePaths['${brand ? 'brand' : 'deck'}:${choice['id']}'] = resolved;
      }
      if (replace) {
        final obj = _selectedObject;
        if (obj == null || !ObjectContent.isImage(obj)) return;
        final updated = Map<String, dynamic>.from(obj);
        updated['content'] = ObjectContent.image('${choice['id']}',
            brand: brand, name: '${choice['name']}');
        _styleChanged(updated);
        return;
      }
      _insertObject(
        _newContentObject(
          w: 480,
          h: 300,
          content: ObjectContent.image('${choice['id']}',
              brand: brand, name: '${choice['name']}'),
        ),
      );
    } catch (e) {
      _toast('Storage is not answering — try again in a moment.');
    }
  }

  /// Media: import an existing video or audio file (no recorder, ever).
  Future<void> _pickMedia(String kind) async {
    final path = await ImagePickers.pickMedia(kind: kind);
    if (path == null || !mounted) return;
    try {
      final store = await ResourceStore.open();
      final entry = await store.add(
        brand: false,
        deckId: (_deck['id'] ?? '').toString(),
        sourcePath: path,
      );
      final resolved = _resourcePathOf(entry, brand: false);
      if (resolved != null) {
        _resourcePaths['deck:${entry['id']}'] = resolved;
      }
      if (!mounted) return;
      _insertObject(
        _newContentObject(
          w: 460,
          h: 240,
          content: ObjectContent.media('${entry['id']}',
              brand: false,
              name: '${entry['name']}',
              mediaKind: kind),
        ),
      );
    } catch (e) {
      _toast('Could not import that file: $e');
    }
  }

  /// Plays the selected media object's resolved local file with the
  /// system player through the tiny `dreamtx/media` intent channel — no
  /// bundled player SDK, no new dependency. Resolution failures surface
  /// honestly (a toast) — the button never silently does nothing.
  Future<void> _playMedia(Map<String, dynamic> obj) async {
    final content = ObjectContent.of(obj);
    if (content == null) return;
    final path = _resolveResourcePath(content);
    if (path == null) {
      _toast('That media file is no longer on this device — nothing to play.');
      return;
    }
    final mime = (content['media_kind'] ?? 'video') == 'video'
        ? 'video/*'
        : 'audio/*';
    final ok = await MediaPlayback.open(path, mime: mime);
    if (!mounted) return;
    if (!ok) {
      _toast('No player on this device can open that file.');
    }
  }

  /// Table cell editing — the route dialog (text entry lives in routes,
  /// outside the keyboard-stable subtree).
  Future<void> _editTableCell(int index) async {
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isTable(obj)) return;
    final (rows, cols, cells) = ObjectContent.tableOf(obj);
    if (index < 0 || index >= cells.length) return;
    final text = await dreamInputDialog(
      context,
      title: 'Cell ${index ~/ cols + 1},${index % cols + 1}',
      initial: cells[index],
      confirmLabel: 'Save',
    );
    if (text == null || !mounted) return;
    final updated = List<String>.from(cells);
    updated[index] = text;
    final copy = Map<String, dynamic>.from(obj);
    final content = Map<String, dynamic>.from(copy['content'] as Map);
    content['cells'] = updated;
    copy['content'] = content;
    // A committed cell edit is its own undo step (discrete, deliberate).
    _styleChanged(copy);
  }

  /// The selected table's deck-level metadata entry (merges + style),
  /// or null — what the Cells / Table style panels read. Entries live on
  /// the deck (`deck['tables'][objectId]`), not inside the object, because
  /// the core's table payload round-trips only rows/cols/cells.
  Map<String, dynamic>? get _selectedTableEntry {
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isTable(obj)) return null;
    final id = obj['id']?.toString();
    if (id == null) return null;
    final t = (_deck['tables'] as Map?)?[id];
    return t is Map ? Map<String, dynamic>.from(t) : null;
  }

  /// One table structure change = one undo step: the object payload goes
  /// through `update_object`, then the updated metadata entry is patched
  /// into the RESPONSE deck before the mutate — so undo snapshots the
  /// true pre state (cells AND entry together).
  void _tableUpdate(Map<String, dynamic> obj, Map<String, dynamic>? entry) {
    final slideId = _slideId;
    if (slideId == null) return;
    final id = obj['id']?.toString();
    if (id == null) return;
    final r = Bridge.command({
      'op': 'update_object',
      'deck': _deck,
      'slide_id': slideId,
      'object_id': id,
      'shape': obj,
    });
    if (r['ok'] != true || r['deck'] is! Map) {
      _toast('Could not change the table: ${r['error']}');
      return;
    }
    final deck = Map<String, dynamic>.from(r['deck'] as Map);
    // Rebuild the metadata map fresh (never mutate shared response data
    // in place — the fake engine in tests echoes the request deck):
    // other tables' entries ride along from the editor's own carry.
    final raw = (deck['tables'] as Map?) ?? (_deck['tables'] as Map?);
    final tables = <String, dynamic>{
      for (final e in (raw ?? const {}).entries)
        e.key.toString(): Map<String, dynamic>.from(
            (e.value as Map?) ?? const {}),
    };
    if (entry == null) {
      tables.remove(id);
    } else {
      tables[id] = entry;
    }
    if (tables.isEmpty) {
      // An EMPTY tombstone, never a removal: the _setDeck carry cannot
      // tell a legitimate removal from an engine round-trip drop, so a
      // removed entry would resurrect on this very same settle (the
      // filmstrip sections hit exactly that in their first CI cycle).
      // The empty map never carries (the carry only forwards non-empty
      // maps) and quietly disappears on the next real round-trip.
      deck['tables'] = const <String, dynamic>{};
    } else {
      deck['tables'] = tables;
    }
    _mutate(deck);
  }

  /// A named table style ('plain' | 'header' | 'banded' |
  /// 'header_banded'): DNA colors resolve HERE, at apply time (the
  /// WordArt rule — one style set matches every design family). Style
  /// fields fold into the table's existing entry (merges survive).
  void _tableStyle(String style) {
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isTable(obj)) return;
    final id = obj['id']?.toString();
    if (id == null) return;
    final fields = ObjectContent.tableStyleFields(style, _dnaHexes);
    final existing = _selectedTableEntry;
    final merges = (existing?['merges'] as List?) ?? const [];
    Map<String, dynamic>? entry;
    if (fields == null) {
      // Plain: style fields drop; only merges keep the entry alive.
      if (merges.isEmpty) {
        entry = null;
      } else {
        entry = {'merges': List.from(merges)};
      }
    } else {
      entry = {
        ...fields,
        if (merges.isNotEmpty) 'merges': List.from(merges),
      };
    }
    _tableUpdate(obj, entry);
  }

  // ---- image depth (roadmap #11 wave 1 step 5) -----------------------------

  /// The selected image's deck-level metadata entry (shape / brightness /
  /// contrast / alt), or null — the same app-owned deck-data contract as
  /// [entry] for tables: the core's Shape struct drops it on every engine
  /// round-trip, so it lives on the deck and rides the [_setDeck] carry.
  /// (Crop ratios are frame geometry — they ride the object itself.)
  Map<String, dynamic>? get _selectedImageEntry {
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isImage(obj)) return null;
    final id = obj['id']?.toString();
    if (id == null) return null;
    final e = (_deck['imageMeta'] as Map?)?[id];
    return e is Map ? Map<String, dynamic>.from(e) : null;
  }

  /// One image-metadata change = one undo step. The object payload never
  /// changes (nothing for the engine to do), so the deck goes straight
  /// through [_mutate] with the entry patched in — the undo snapshot is
  /// the true pre state, entry and all.
  void _imageMetaUpdate(Map<String, dynamic> obj, Map<String, dynamic>? entry) {
    final id = obj['id']?.toString();
    if (id == null) return;
    final existing = (_deck['imageMeta'] as Map?)?[id];
    // Same-value commits (a slider's trailing onChangeEnd, an untouched
    // alt field) must not stack undo steps.
    if (jsonEncode(existing ?? const <String, dynamic>{}) ==
        jsonEncode(entry ?? const <String, dynamic>{})) {
      return;
    }
    final deck = Map<String, dynamic>.from(_deck);
    final raw = (deck['imageMeta'] as Map?) ?? const {};
    final meta = <String, dynamic>{
      for (final e in raw.entries)
        e.key.toString():
            Map<String, dynamic>.from((e.value as Map?) ?? const {}),
    };
    if (entry == null || entry.isEmpty) {
      meta.remove(id);
    } else {
      meta[id] = entry;
    }
    if (meta.isEmpty) {
      // An EMPTY tombstone, never a removal — the _setDeck carry cannot
      // tell a legitimate removal from an engine round-trip drop, so a
      // removed key would resurrect on the very next settle (the exact
      // lesson the tables/sections tombstones document).
      deck['imageMeta'] = const <String, dynamic>{};
    } else {
      deck['imageMeta'] = meta;
    }
    _mutate(deck);
  }

  /// Replace the selected image's asset from the deck's library — frame,
  /// stroke, rotation and the metadata entry all survive; only the bytes
  /// change (one `update_object`, one undo step).
  Future<void> _replaceSelectedImage() => _pickImageResource(false,
      replace: true);
}
