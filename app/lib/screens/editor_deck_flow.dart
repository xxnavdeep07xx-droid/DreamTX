part of 'editor_screen.dart';

/// Deck plumbing: palette refresh, setDeck carry, undo/redo, layout, navigation. Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorDeckFlow on _EditorScreenState {
  /// The panel's "full style inspector" affordance — the existing sheet,
  /// driven on the CURRENT selection.
  void _editSelectedObjectStyle() {
    final obj = _selectedObject;
    if (obj == null) return;
    showInspector(context, object: obj, onChange: _styleChanged);
  }

  /// The deck's palette + the text boxes' slide-theme base — recomputed when
  /// the deck version moves (new deck, DNA change, undo/redo).
  void _refreshPalette() {
    final version = (_deck['version'] as num?)?.toInt() ?? 0;
    if (version == _paletteForVersion) return;
    _paletteForVersion = version;
    final r = Bridge.command({'op': 'resolve_dna', 'deck': _deck});
    if (r['ok'] != true || r['dna'] is! Map) return;
    final palette = (r['dna']['palette'] as Map?) ?? const {};
    final colors = <Color>[];
    for (final key in ['bg', 'surface', 'fg', 'muted', 'accent']) {
      final hex = palette[key]?.toString();
      if (hex != null && hex.length == 6) {
        colors.add(hexToColor(hex));
      }
    }
    // The deck colors first, then the studio's standard swatches.
    _deckPalette = [...colors, ...kSwatchPalette];
    final accentHex = palette['accent']?.toString();
    if (accentHex != null && accentHex.length == 6) {
      _dnaAccentHex = accentHex.toUpperCase();
    }
    _dnaChartPalette = chartPaletteFrom(r['dna']['chart_palette']);
    _dnaHexes = {
      for (final key in ['bg', 'surface', 'fg', 'muted', 'accent'])
        if (palette[key] is String &&
            (palette[key] as String).length == 6)
          key: (palette[key] as String).toUpperCase(),
    };
    final fg = palette['fg']?.toString();
    _baseTextColor = fg != null && fg.length == 6
        ? hexToColor(fg)
        : const Color(0xFF17181A);
    _baseTextFamily = (r['dna']['body_font'] ?? '').toString() == 'serif'
        ? 'serif'
        : null;
  }

  List<Map<String, dynamic>> get _slides => (_deck['slides'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();

  // ---- deck state + undo/redo ------------------------------------------------

  Map<String, dynamic> _copy() =>
      jsonDecode(jsonEncode(_deck)) as Map<String, dynamic>;

  /// Fire-and-forget by design — the editor never blocks on the disk — but
  /// never *unhandled*: the store snapshots the deck at enqueue time and
  /// serializes writes per deck, so rapid edits/undo/redo land in order with
  /// the latest state always winning, and a failed write leaves the prior
  /// valid file untouched and surfaces here (throttled toast). Later saves
  /// recover automatically; the deck list shown on return is coordinated by
  /// the dashboard's flush-then-scan reload.
  Future<void> _persist() async {
    try {
      final store = await DeckStore.open();
      await store.save(_deck);
    } catch (e, st) {
      print('[deck-store] editor save failed: $e\n$st');
      _warnSaveFailed();
    }
  }

  /// At most one save-failure toast per 10s — a broken disk must be visible,
  /// not deafening. The message is actionable without being a stack trace.
  void _warnSaveFailed() {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastSaveToastAt;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastSaveToastAt = now;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Could not save this deck — your edits stay in memory and saving '
            'retries automatically.')));
  }

  /// Apply a new deck produced by the engine (or a local edit): push undo,
  /// wipe redo, persist, refresh.
  void _mutate(Map? newDeck) {
    if (newDeck == null) return;
    _undo.add(_copy());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    _setDeck(newDeck);
  }

  void _setDeck(Map newDeck) {
    final deck = Map<String, dynamic>.from(newDeck);
    // Sections are app-owned deck metadata (see the filmstrip sections
    // block below): the Rust core's Deck struct has no `sections` field,
    // so every engine round-trip drops it. Carry the editor's own forward
    // — then sanitize against the NEW deck's slides, so a marker whose
    // start slide is gone folds away instead of haunting the rail.
    if (!deck.containsKey('sections')) {
      final carried = _deck['sections'];
      if (carried is List && carried.isNotEmpty) deck['sections'] = carried;
    }
    if (deck['sections'] is List && (deck['sections'] as List).isNotEmpty) {
      final ids = <String>{
        for (final s in ((deck['slides'] as List?) ?? const [])
            .whereType<Map>())
          if (s['id'] != null) s['id'].toString(),
      };
      final live = <Map<String, dynamic>>[
        for (final s in ((deck['sections'] as List?) ?? const [])
            .whereType<Map>())
          if (ids.contains(s['slide_id']?.toString()))
            Map<String, dynamic>.from(s),
      ];
      if (live.isEmpty) {
        deck.remove('sections');
      } else {
        deck['sections'] = live;
      }
    }
    // Table metadata rides the SAME deck-level carry: `deck['tables']`
    // (objectId → {style, merges, colors}) is app-owned deck data the
    // Rust core's `Deck` struct drops on every round-trip. Carried
    // forward, then sanitized against the NEW deck's table objects —
    // deleting a table (or pasting into a deck without it) folds its
    // entry away instead of haunting the deck.
    if (!deck.containsKey('tables')) {
      final carried = _deck['tables'];
      if (carried is Map && carried.isNotEmpty) {
        deck['tables'] = Map<String, dynamic>.from(carried);
      }
    }
    if (deck['tables'] is Map && (deck['tables'] as Map).isNotEmpty) {
      final liveTableIds = <String>{
        for (final s in ((deck['slides'] as List?) ?? const [])
            .whereType<Map>())
          for (final o in ((s['objects'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>())
            if (ObjectContent.isTable(o) && o['id'] != null)
              o['id'].toString(),
      };
      final liveTables = <String, dynamic>{
        for (final e in (deck['tables'] as Map).entries)
          if (liveTableIds.contains(e.key.toString()) &&
              e.value is Map &&
              (e.value as Map).isNotEmpty)
            e.key.toString(): e.value,
      };
      if (liveTables.isEmpty) {
        deck.remove('tables');
      } else {
        deck['tables'] = liveTables;
      }
    }
    // Image metadata rides the SAME deck-level carry: `deck['imageMeta']`
    // (objectId → {shape, brightness, contrast, alt}) is app-owned deck
    // data the Rust core's Shape struct drops on every round-trip.
    // Carried forward, then sanitized against the NEW deck's image
    // objects — deleting an image (or its whole slide) folds its entry
    // away instead of haunting the deck. The empty-map tombstone is the
    // tables lesson: a missing key reads as "engine dropped it" and
    // would resurrect the old value on this very settle.
    if (!deck.containsKey('imageMeta')) {
      final carried = _deck['imageMeta'];
      if (carried is Map && carried.isNotEmpty) {
        deck['imageMeta'] = Map<String, dynamic>.from(carried);
      }
    }
    if (deck['imageMeta'] is Map && (deck['imageMeta'] as Map).isNotEmpty) {
      final liveImageIds = <String>{
        for (final s in ((deck['slides'] as List?) ?? const [])
            .whereType<Map>())
          for (final o in ((s['objects'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>())
            if (ObjectContent.isImage(o) && o['id'] != null)
              o['id'].toString(),
      };
      final liveMeta = <String, dynamic>{
        for (final e in (deck['imageMeta'] as Map).entries)
          if (liveImageIds.contains(e.key.toString()) &&
              e.value is Map &&
              (e.value as Map).isNotEmpty)
            e.key.toString(): e.value,
      };
      if (liveMeta.isEmpty) {
        deck.remove('imageMeta');
      } else {
        deck['imageMeta'] = liveMeta;
      }
    }
    // Slide furniture: carry the settings forward (the core drops the key),
    // then rebuild every slide's furniture objects from them, so the slide
    // numbers follow the order on every change.
    if (!deck.containsKey('furniture')) {
      final carried = _deck['furniture'];
      if (carried is Map) {
        deck['furniture'] = Map<String, dynamic>.from(carried);
      }
    }
    _deck = syncFurnitureInDeck(
      deck,
      dateText: furnitureDateText(DateTime.now()),
    );
    unawaited(_persist());
    _refreshLayout();
    _refreshPalette();
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    _setState(() {
      _redo.add(_copy());
      _deck = _undo.removeLast();
    });
    unawaited(_persist());
    _refreshLayout();
    _refreshPalette();
    _styleUndoPushed = false;
    _resyncTextSession();
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    _setState(() {
      _undo.add(_copy());
      _deck = _redo.removeLast();
    });
    unawaited(_persist());
    _refreshLayout();
    _refreshPalette();
    _styleUndoPushed = false;
    _resyncTextSession();
  }

  void _refreshLayout() {
    if (!mounted) return;
    if (_slides.isEmpty) {
      _setState(() {
        _layout = null;
        _warnings = [];
      });
      return;
    }
    _index = _index.clamp(0, _slides.length - 1);
    final r = Bridge.command(
        {'op': 'get_layout', 'deck': _deck, 'slide_index': _index});
    _setState(() {
      if (r['ok'] == true && r['layout'] is Map) {
        _layout = (r['layout'] as Map).cast<String, dynamic>();
        _warnings = ((r['layout']['warnings'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
      } else {
        _layout = null;
        _warnings = ['layout error: ${r['error']}'];
      }
    });
  }

  // ---- vector overlay layer (studio tools) -------------------------------------

  String? get _slideId =>
      _slides.isEmpty ? null : _slides[_index]['id'] as String?;

  List<Map<String, dynamic>> get _objects {
    if (_slides.isEmpty) return const [];
    return ((_slides[_index]['objects'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Map<String, dynamic>? get _selectedObject {
    final id = _selectedObjectId;
    if (id == null) return null;
    for (final o in _objects) {
      if (o['id'] == id) return o;
    }
    return null;
  }

  String _newObjectId() {
    _oidSeq += 1;
    return 'o${DateTime.now().millisecondsSinceEpoch}_$_oidSeq';
  }

  /// Switch the active slide. A different slide means the old slide's
  /// selection is CLEARED — the object panel, the text session and the
  /// editing state all belong to the slide they were opened on, and no
  /// one keeps accidentally editing the previous slide's object.
  void _gotoSlide(int i) {
    if (i < 0 || i >= _slides.length || i == _index) {
      if (i == _index) _refreshLayout();
      return;
    }
    _flushTextSession();
    _disposeTextSession();
    _removeTypingToolbar();
    _setState(() {
      _index = i;
      _selectedObjectId = null;
      _typing = false;
      _sheetHiddenForTyping = false;
    });
    _refreshLayout();
  }

  /// Ribbon state machine: one contextual row at a time, tapped again to
  /// collapse. Tabs that work on the canvas overlay (Insert, Draw) double
  /// as design mode, so leaving them disarms the toolbox and clears the
  /// selection — but the selection SURVIVES a Files ⇄ Insert switch (both
  /// are sheet tabs over the same design mode canvas). Entering Draw arms
  /// the toolbox (the last-used tool); Draw ⇄ Insert keeps the selection
  /// and only disarms.
  void _setNavTab(_NavTab? tab) {
    final wasSheet = _isSheetTab(_navTab);
    final willBeSheet = _isSheetTab(tab);
    final wasDraw = _navTab == _NavTab.draw;
    // The sheet's height where it stands RIGHT NOW (before the tab flips) —
    // what the exit slide holds when it reverses. ONE machinery for both
    // drawers: a held extent if one exists, the shared resting half detent
    // otherwise.
    final leavingHeight = _drawerExtent ?? _drawerHalf;
    // The strip's live height where it stands right now — read BEFORE the
    // setState rebuild, so a fold caught mid-flight freezes at its real
    // on-screen height, not its target.
    final arrivingFootprint = _liveStripFlowHeight();
    _setState(() {
      _navTab = tab;
      if (willBeSheet) _lastSheetTab = tab!;
      _designMode = tab == _NavTab.insert || tab == _NavTab.draw;
      if (!_designMode) {
        _drawToolbox = _drawToolbox.disarmed();
        _selectedObjectId = null;
        _disposeTextSession();
      } else if (tab == _NavTab.draw) {
        // Entering Draw: arm the last-used tool (the pen by default) and
        // clear the selection — draw focus. The armed tool consumes
        // canvas taps, so the selection chrome would be untouchable;
        // re-tapping the active tool inside the row disarms it (select
        // mode without leaving Draw).
        _drawToolbox = _drawToolbox.rearmed();
        _selectedObjectId = null;
      } else if (wasDraw) {
        // Draw -> Insert: the same design-mode canvas. Only disarm — the
        // selection survives, exactly like Files <-> Insert.
        _drawToolbox = _drawToolbox.disarmed();
      }
      if (tab != _NavTab.insert) {
        // Leaving the typing state: any tab switch closes the keyboard and
        // ends the typing session's field focus (the sheet returns).
        _endTyping();
      }
      // The drawer layer's lifecycle. ARRIVING at a sheet tab (Files or
      // Insert): the sheet mounts at its full intended height translated
      // fully below the navbar's top edge — the first frame paints nothing —
      // and the post-frame callback below slides it up into view; the flow
      // freezes the strip's footprint so the slide preview cannot move.
      // SWITCHING Files ⇄ Insert: the layer simply swaps its content —
      // same layer, same spacer, no entrance.
      // LEAVING a sheet tab: the sheet reverses the entrance — it
      // translates back down behind the navbar, and the layer unmounts
      // when the slide completes (onEnd below). Only if it never rose past
      // its mount frame is there nothing on screen to animate out — then
      // the layer unmounts at once.
      if (!willBeSheet) {
        _drawerDragging = false;
        if (wasSheet) {
          if (_sheetEntering) {
            // Never rose: no pixels were ever shown — nothing to animate.
            _sheetEntering = false;
            _sheetClosing = false;
            _drawerExtent = null;
          } else {
            _sheetClosing = true;
            // hold the height it stands at
            _drawerExtent ??= leavingHeight;
          }
        }
        // (Leaving a sheet tab for another non-sheet tab while the exit
        // slide already runs changes nothing — the slide continues to the
        // same unmount.)
      } else if (!wasSheet) {
        final resumingExit = _sheetClosing;
        _sheetClosing = false;
        _sheetEntering = !resumingExit;
        _drawerExtent = null;
        _frozenStripFootprint = arrivingFootprint;
      }
    });
    if (willBeSheet && !wasSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_isSheetTab(_navTab) ||
            _drawerDragging ||
            !_sheetEntering) {
          return;
        }
        // Flip the entrance: the sheet's bottom retargets from
        // (anchor - height) to the anchor, and AnimatedPositioned slides
        // it up over the 200ms family.
        _setState(() => _sheetEntering = false);
      });
    }
    if (tab != null) {
      // Keep the freshly-lit tab centered in the scrollable bar.
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerNavTab(tab));
    }
  }

  bool _isSheetTab(_NavTab? tab) =>
      tab == _NavTab.files || tab == _NavTab.insert || tab == _NavTab.design;

  /// The sheet layer's live height for the CURRENT state, for BOTH drawer
  /// surfaces (Files and Insert ride the SAME machinery verbatim — same
  /// anchor, same detents, same drag, same dismiss): a held drag/settle
  /// extent when one exists, the shared resting half detent otherwise.
  /// The Insert drawer's cards scroll inside whatever the detent gives
  /// them, exactly like the Files drawer's grid on short screens.
  double _sheetLiveHeightFor() => _drawerExtent ?? _drawerHalf;

  /// Centers the active ribbon tab in the bar's viewport — but only when
  /// the tab is actually off-screen. A tab that is already fully visible
  /// never nudges the bar: the centering glide is a nicety for reaching
  /// far-edge tabs, and an unnecessary one would leave the scroll animating
  /// (and its content ignoring pointers) for a quarter second after every
  /// switch — exactly when the user's next tap lands.
  void _centerNavTab(_NavTab tab) {
    if (!_navScroll.hasClients) return;
    final i = _NavTab.values.indexOf(tab);
    final view = _navScroll.position.viewportDimension;
    final maxExtent = _navScroll.position.maxScrollExtent;
    final itemLeft = i * _navItemWidth;
    if (itemLeft >= -4 && itemLeft + _navItemWidth <= view + 4) {
      return; // fully visible — the bar stays put
    }
    final target = (i * _navItemWidth + _navItemWidth / 2 - view / 2)
        .clamp(0.0, maxExtent)
        .toDouble();
    _navScroll.animateTo(target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic);
  }

}
