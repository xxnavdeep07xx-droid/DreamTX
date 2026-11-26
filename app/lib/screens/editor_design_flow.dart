part of 'editor_screen.dart';

/// Design-family application and the toast. Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorDesignFlow on _EditorScreenState {
  /// Design-family change (family id or 'next_variant') — driven by the
  /// Theme contextual row.
  void _applyDesign(String choice) {
    final current = ((_deck['dna'] ?? const {})['family'] ?? '').toString();
    if (choice == current) return;
    final r =
        Bridge.command({'op': 'apply_dna', 'deck': _deck, 'change': choice});
    if (r['ok'] == true && r['deck'] is Map) _mutate(r['deck'] as Map);
  }

  /// Design tab: whether the current slide hides the DNA background graphics.
  bool get _slideHidesGraphics =>
      _slides.isNotEmpty && _slides[_index]['hide_graphics'] == true;

  /// Design tab: show or hide the DNA background graphics on the current
  /// slide only. One undo step; the engine owns the flag, so exports and the
  /// presenter follow it.
  void _toggleSlideGraphics() {
    final id = _slideId;
    if (id == null) return;
    final r = Bridge.command({
      'op': 'set_slide_hide_graphics',
      'deck': _deck,
      'slide_id': id,
      'hide': !_slideHidesGraphics,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
    } else {
      _toast('Could not change the background graphics');
    }
  }

  // ---- the Files drawer's deck-level tools --------------------------------------

  /// The deck's declared frame aspect ("16:9" for every deck that predates
  /// the field — the engine defaults the same way, so app and engine agree
  /// without a round-trip).
  String get _deckAspect => (_deck['aspect'] ?? '16:9').toString();

  /// **New** — a fresh deck in its own file, never over the active one.
  /// Blank starts with zero slides; Template asks for a design family and
  /// the engine composes the deck in that DNA. Either way the result is a
  /// new deck id under its own file, and the editor hands over to it.
  Future<void> _filesNewDeck() async {
    final kind = await dreamSheet<String>(
      context,
      builder: (context) => const _NewDeckSheet(),
    );
    if (kind == null) return;

    final title = await dreamInputDialog(
      context,
      title: kind == 'blank' ? 'New blank deck' : 'New deck from a template',
      hint: 'Deck name',
      confirmLabel: 'Create',
    );
    if (title == null || title.trim().isEmpty) return;

    var family = 'swiss_editorial';
    if (kind == 'template') {
      final fam = await dreamSheet<String>(
        context,
        builder: (context) => const _DesignFamilySheet(),
      );
      if (fam == null) return;
      family = fam;
    }

    final r = Bridge.command({
      'op': 'new_deck',
      'title': title.trim(),
      'family': family,
      'blank': kind == 'blank',
    });
    if (r['ok'] != true || r['deck'] is! Map) {
      _toast('Could not create the deck: ${r['error'] ?? 'engine error'}');
      return;
    }
    final deck = Map<String, dynamic>.from(r['deck'] as Map);
    // The active deck's file is never touched: the new deck saves under its
    // own engine-issued id, and storage trouble here is never silent.
    try {
      final store = await DeckStore.open();
      await store.save(deck);
    } catch (e) {
      print('[deck-store] new deck could not be written: $e');
      _toast('Deck created, but storage is not answering — it will retry '
          'on the next save.');
    }
    if (!mounted) return;
    await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => EditorScreen(deck: deck)));
  }

  /// **Open** — Recents (the decks on this device, newest first) or Browse
  /// Files (the platform document browser). The app opens DreamTX deck
  /// files (.json) — .pptx import is not supported and is not offered.
  Future<void> _filesOpenDeck() async {
    final kind = await dreamSheet<String>(
      context,
      builder: (context) => const _OpenDeckSheet(),
    );
    if (kind == 'recents') {
      await _openRecentDeck();
    } else if (kind == 'browse') {
      await _browseForDeck();
    }
  }

  Future<void> _openRecentDeck() async {
    List<Map<String, dynamic>> decks;
    try {
      final store = await DeckStore.open();
      decks = (await store.scan()).decks;
    } catch (e) {
      print('[deck-store] recents failed: $e');
      _toast('Storage is not answering — try again in a moment.');
      return;
    }
    final currentId = _deck['id'].toString();
    final choice = await dreamSheet<Map<String, dynamic>>(
      context,
      builder: (context) =>
          _RecentsSheet(decks: decks, currentId: currentId),
    );
    if (choice == null || !mounted) return;
    await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => EditorScreen(
                deck: Map<String, dynamic>.from(choice))));
  }

  Future<void> _browseForDeck() async {
    // file_picker 13.x: pickFile() is the single-file entry point — a
    // PlatformFile, or null when the user dismisses the browser.
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = file?.path;
    if (path == null) return; // dismissed — nothing to do
    Map<String, dynamic>? deck;
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is Map<String, dynamic>) deck = decoded;
    } catch (_) {}
    if (deck == null ||
        (deck['slides'] is! List) ||
        (deck['dna'] is! Map && deck['dna'] == null)) {
      _toast('That file is not a DreamTX deck (.json) — nothing was opened.');
      return;
    }
    // Importing never overwrites: a colliding id gets a fresh one under its
    // own file, the original deck on this device stays untouched.
    final imported = Map<String, dynamic>.from(deck);
    final store = await DeckStore.open();
    final ids = (await store.scan()).decks.map((d) => d['id'].toString()).toSet();
    var id = imported['id'].toString();
    if (id.isEmpty || ids.contains(id)) {
      id = 'd${DateTime.now().millisecondsSinceEpoch}';
      imported['id'] = id;
    }
    try {
      await store.save(imported);
    } catch (e) {
      print('[deck-store] import could not be written: $e');
      _toast('Storage is not answering — the deck was not opened.');
      return;
    }
    if (!mounted) return;
    await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EditorScreen(deck: imported)));
  }

  /// **Aspect ratio** — the current ratio plus the supported presets. The
  /// change is applied to the deck (rendering AND export read the same
  /// field; the engine re-frames drawn objects), never just the preview —
  /// and when existing objects would move, that is stated up front and
  /// confirmed before anything happens.
  Future<void> _filesAspect() async {
    final current = _deckAspect;
    final meta = Bridge.command({'op': 'meta'});
    final aspects =
        ((meta['aspects'] as List?) ?? const ['16:9', '16:10', '4:3', '1:1'])
            .map((e) => e.toString())
            .toList();
    final choice = await dreamSheet<String>(
      context,
      builder: (context) =>
          _AspectSheet(current: current, aspects: aspects),
    );
    if (choice == null || choice == current) return;

    // Re-framing moves drawn objects: say so explicitly and get a yes first.
    final hasDrawn = _slides.any(
            (s) => ((s['objects'] as List?) ?? []).isNotEmpty) ||
        ((_deck['components'] as List?) ?? []).isNotEmpty;
    if (hasDrawn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => dreamDialog(
          title: Text('Re-frame to $choice?'),
          content: const Text(
              'Drawn objects keep their height and vertical position; their '
              'horizontal positions and widths scale to the new frame. '
              'Layouts re-flow for the new width. This applies to the deck '
              '— rendering and export both follow.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Keep $current')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Apply $choice')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final r = Bridge.command(
        {'op': 'set_aspect', 'deck': _deck, 'aspect': choice});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map); // persists + re-renders at the new frame
    } else {
      _toast('Could not change the aspect: ${r['error']}');
    }
  }

  // ---- export -------------------------------------------------------------------

  /// The image assets the exporters need, resolved from the
  /// resource store: resource id -> encoded bytes + format (+ decoded RGBA
  /// for the PDF's FlateDecode path, downscaled so a photo never ships
  /// tens of megabytes of raw pixels over the FFI boundary).
  ///
  /// ONLY image objects ship bytes — media objects render a card in every
  /// export format (the system player plays the local file; the exports
  /// never embed video/audio), so they are skipped here entirely.
  Future<Map<String, Map<String, dynamic>>> _exportImageAssets(
      {required bool withRgba}) async {
    final out = <String, Map<String, dynamic>>{};
    // resource id -> the object's OWN declared scope (brand vs deck).
    final wanted = <String, bool>{};
    for (final slide in _slides) {
      for (final obj in ((slide['objects'] as List?) ?? const [])
          .whereType<Map>()) {
        final content = obj['content'];
        if (content is! Map) continue;
        if (content['kind'] != 'image') continue;
        final id = content['resource_id']?.toString();
        if (id != null && id.isNotEmpty) {
          wanted.putIfAbsent(id, () => content['brand'] == true);
        }
      }
    }
    if (wanted.isEmpty) return out;
    final deckId = (_deck['id'] ?? '').toString();
    for (final want in wanted.entries) {
      try {
        // The object declares which scope it lives in — brand assets
        // resolve from the brand tree, deck assets from this deck's.
        final store = await ResourceStore.open();
        final path = await store.resolve(
            brand: want.value, deckId: want.value ? null : deckId, id: want.key);
        if (path == null) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        var bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final ext = path.toLowerCase().split('.').last;
        var format = switch (ext) {
          'jpg' || 'jpeg' => 'jpeg',
          'gif' => 'gif',
          'png' => 'png',
          _ => 'other', // webp/bmp/heic/… — see the re-encode below
        };
        // PPTX embeds `bytes` VERBATIM as ppt/media/imageN.<format>: a
        // webp/bmp/heic file cannot ship under a png label — that writes a
        // broken image part. Decode it and re-encode as REAL PNG bytes.
        // (The PDF path needs no re-encode: it consumes the decoded RGBA
        // pixels, never the raw file.)
        if (format == 'other' && !withRgba) {
          final png = await _encodeAsPng(path);
          if (png == null) continue; // undecodable → placeholder, never broken
          bytes = png;
          format = 'png';
        }
        if (format == 'other') {
          // The PDF path with an exotic source keeps flowing through the
          // RGBA decode below — the pixels, not the raw bytes, are what it
          // consumes; the tag stays 'png' so any bytes-only consumer on
          // that path can never claim a webp is a jpeg.
          format = 'png';
        }
        final entry = <String, dynamic>{
          'format': format,
          'bytes': base64Encode(bytes),
        };
        if (withRgba && format != 'jpeg') {
          final rgba = await _decodedRgba(path);
          if (rgba != null) {
            entry['width'] = rgba.$1;
            entry['height'] = rgba.$2;
            entry['rgba'] = base64Encode(rgba.$3);
          } else {
            // A failed decode exports a placeholder — never a broken
            // image, and never a half entry either.
            continue;
          }
        } else {
          // Even without the pixel payload the exporter needs no size
          // for pptx (the pic box is the object's own geometry).
          entry['width'] = 1;
          entry['height'] = 1;
        }
        out[want.key] = entry;
      } catch (_) {
        // One unreadable asset exports a placeholder — never a failed
        // export. See object_content_layer's missing-asset card.
      }
    }
    return out;
  }

  /// One local image file re-encoded as real PNG bytes — the PPTX exporter
  /// embeds `ppt/media/*` parts verbatim, so a webp/bmp/heic source must be
  /// decoded and PNG-encoded before it can ship (a raw file under a `png`
  /// label is a broken image part in the exported deck). Returns null when
  /// the file cannot be decoded (a placeholder follows).
  Future<Uint8List?> _encodeAsPng(String path) async {
    try {
      final data = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final bd = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bd == null) return null;
        return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Decoded RGBA of an image file, downscaled to a bounded pixel budget
  /// (design-space never shows more than ~1280px across, and the PDF page
  /// is 960pt — 1600px is already beyond what any viewer can distinguish).
  /// Returns (width, height, rgba) or null when the file cannot be decoded
  /// (a placeholder follows).
  Future<(int, int, List<int>)?> _decodedRgba(String path) async {
    try {
      final data = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        data,
        targetWidth: 1600,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final w = image.width;
        final h = image.height;
        final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (bd == null) return null;
        return (w, h, bd.buffer.asUint8List().toList());
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _export(String op, {String verb = 'Export'}) async {
    _setState(() => _busy = true);
    try {
      // The exporters need the resolved image assets; the PDF request also
      // carries decoded pixels. Collecting them touches disk and decodes
      // images, so it (and the engine call itself) run without holding a
      // frame: the engine runs on a background isolate (exports zip whole
      // decks — the UI never freezes), the asset collection is async IO.
      final withRgba = op == 'export_pdf';
      final images = await _exportImageAssets(withRgba: withRgba);
      final r = await Bridge.commandHeavy({
        'op': op,
        'deck': _deck,
        if (images.isNotEmpty) 'images': images,
      });
      if (r['ok'] != true || r['base64'] is! String) {
        if (!mounted) return;
        _toast('$verb failed: ${r['error'] ?? 'engine unavailable'}');
        return;
      }
      final bytes = base64Decode(r['base64'] as String);
      final ext = op == 'export_pptx' ? 'pptx' : 'pdf';
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${(_deck['title'] ?? 'deck').toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$ext');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: _deck['title'].toString()),
      );
    } catch (e) {
      if (mounted) _toast('$verb error: $e');
    } finally {
      if (mounted) _setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return; // async flows can outlive the editor
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
