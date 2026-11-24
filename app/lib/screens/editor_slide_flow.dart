part of 'editor_screen.dart';

/// Slide and section ops: add/move/delete, sections, archetypes. Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorSlideFlow on _EditorScreenState {
  // ---- slide ops ------------------------------------------------------------

  void _updateSlide(Map slide, String archetype, Map content) {
    final r = Bridge.command({
      'op': 'update_slide',
      'deck': _deck,
      'slide_id': slide['id'],
      'archetype': archetype,
      'content': content,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
    } else {
      _toast('Could not save: ${r['error']}');
    }
  }

  /// The **+** button: add a blank slide instantly — no picker, no template.
  /// The user gets an empty canvas (just the deck's background) to draw on
  /// or fill later; the curated layout list lives in the Slides tool row.
  void _addSlide() {
    final r = Bridge.command(
        {'op': 'add_slide', 'deck': _deck, 'archetype': 'blank'});
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _gotoSlide(_slides.length - 1);
    } else {
      _toast('Could not add: ${r['error']}');
    }
  }

  /// The curated template list (Cover, Agenda, …) — a deliberate choice
  /// from the Slides tool row or a long-press on **+** when you DO want a
  /// pre-styled layout.
  Future<void> _addLayoutSlide() async {
    final meta = Bridge.command({'op': 'meta'});
    final r = Bridge.command({'op': 'pacing', 'deck': _deck});
    final suggested = (r['next_suggested'] ?? '').toString();
    final archetypes =
        (meta['archetypes'] as List? ?? []).map((e) => e.toString()).toList();
    final choice = await dreamSheet<String>(
      context,
      builder: (context) =>
          _ArchetypeSheet(suggested: suggested, archetypes: archetypes),
    );
    if (choice == null) return;
    final add = Bridge.command(
        {'op': 'add_slide', 'deck': _deck, 'archetype': _archetypeOf(choice)});
    if (add['ok'] == true && add['deck'] is Map) {
      _mutate(add['deck'] as Map);
      _gotoSlide(_slides.length - 1);
    } else {
      _toast('Could not add: ${add['error']}');
    }
  }

  String _archetypeOf(String label) {
    const map = {
      'Cover': 'cover',
      'Agenda': 'agenda',
      'Section break': 'section',
      'Big statement': 'statement',
      'Stat wall': 'stat_wall',
      'Split text + visual': 'split',
      'Comparison': 'comparison',
      'Chart hero': 'chart_hero',
      'Closing': 'closing',
      'Blank': 'blank',
    };
    return map[label] ?? 'statement';
  }

  Future<void> _editContent() async {
    if (_slides.isEmpty) return;
    final slide = _slides[_index];
    final result = await showContentEditor(
      context,
      slide: slide,
      deckTitle: (_deck['title'] ?? 'Deck').toString(),
    );
    if (result == null) return;
    _updateSlide(slide, result.archetype, result.content);
  }

  void _duplicateAt(int i) {
    if (i < 0 || i >= _slides.length) return;
    final slide = _slides[i];
    final add = Bridge.command({
      'op': 'add_slide',
      'deck': _deck,
      'archetype': slide['archetype'],
      'content': slide['content'],
    });
    if (add['ok'] != true || add['deck'] is! Map) {
      _toast('Could not duplicate: ${add['error']}');
      return;
    }
    var deck = add['deck'] as Map;
    // add_slide appends; move the copy right behind the original.
    if (_slides.length > 1) {
      final newId =
          (((deck['slides'] as List?) ?? []).whereType<Map>().last)['id'];
      final move = Bridge.command({
        'op': 'move_slide',
        'deck': deck,
        'slide_id': newId,
        'to_index': i + 1
      });
      if (move['ok'] == true && move['deck'] is Map) deck = move['deck'] as Map;
    }
    _mutate(deck);
    _gotoSlide((i + 1).clamp(0, _slides.length - 1));
  }

  void _moveAt(int i, int delta) {
    if (_slides.isEmpty) return;
    final slide = _slides[i.clamp(0, _slides.length - 1)];
    final target = i + delta;
    if (target < 0 || target >= _slides.length) return;
    final r = Bridge.command({
      'op': 'move_slide',
      'deck': _deck,
      'slide_id': slide['id'],
      'to_index': target,
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _gotoSlide(target);
    }
  }

  void _deleteAt(int i) {
    if (i < 0 || i >= _slides.length) return;
    final slide = _slides[i];
    final r = Bridge.command(
        {'op': 'delete_slide', 'deck': _deck, 'slide_id': slide['id']});
    if (r['ok'] == true && r['deck'] is Map) {
      final newDeck = r['deck'] as Map;
      _mutate(newDeck);
      _refreshLayout(); // clamps _index
      // The slide's objects are gone for good — their deck-scope resources
      // may now be orphans (the same sweep as object deletion; the undo
      // stack is respected inside).
      unawaited(_pruneOrphanedResources(newDeck));
    } else {
      _toast('Could not delete: ${r['error']}');
    }
  }

  /// Long-press menu for a filmstrip thumbnail.
  Future<void> _slideActions(int i) async {
    if (i < 0 || i >= _slides.length) return;
    final action = await dreamSheet<String>(
      context,
      builder: (context) => _SlideActionsSheet(
          index: i,
          count: _slides.length,
          startsSection: _sectionStartingAt(i) != null),
    );
    switch (action) {
      case 'edit':
        _gotoSlide(i);
        _editContent();
      case 'section':
        _startSectionAt(i);
      case 'dup':
        _duplicateAt(i);
      case 'left':
        _moveAt(i, -1);
      case 'right':
        _moveAt(i, 1);
      case 'del':
        _deleteAt(i);
    }
  }

  // ---- filmstrip sections (app-owned deck metadata) --------------------------
  //
  // A section is a named divider in the filmstrip rail: a marker anchored
  // to the slide it STARTS (`deck['sections']` = [{id, name, slide_id}]);
  // display order derives from the slides themselves, so moving, adding
  // or duplicating slides can never corrupt a marker. The markers are
  // APP-owned metadata: the Rust core's Deck struct has no `sections`
  // field and drops it on every op response (serde ignores unknown fields
  // coming in — exports, the AI and the worker never see them either),
  // so [_setDeck] re-attaches the editor's own after every engine
  // round-trip, [_copy]'s JSON snapshot carries them through undo/redo,
  // and DeckStore writes them into the deck file verbatim. PowerPoint
  // keeps sections the same way: presentation.xml metadata, apart from
  // the slides themselves.

  /// The deck's section markers, as fresh maps (never aliases of the
  /// deck's own lists — every caller mutates freely).
  List<Map<String, dynamic>> _sectionsList(Map deck) => [
        for (final s in ((deck['sections'] as List?) ?? const [])
            .whereType<Map>())
          Map<String, dynamic>.from(s),
      ];

  /// The marker that STARTS at slide [index], if any — the slide actions
  /// sheet's "Start section here" state.
  Map<String, dynamic>? _sectionStartingAt(int index) {
    if (index < 0 || index >= _slides.length) return null;
    final id = _slides[index]['id']?.toString();
    if (id == null) return null;
    for (final s in _sectionsList(_deck)) {
      if (s['slide_id']?.toString() == id) return s;
    }
    return null;
  }

  /// The rail's flattened items in one pass: a section divider before its
  /// opening slide, that section's slides omitted while it is collapsed.
  /// A slide belongs to the latest section started at-or-before it, so a
  /// fold always swallows a contiguous run of cards.
  List<_RailItem> _railItems() {
    final startsAt = <String, Map<String, dynamic>>{};
    for (final s in _sectionsList(_deck)) {
      final sid = s['slide_id']?.toString();
      if (sid != null && sid.isNotEmpty) startsAt[sid] = s;
    }
    final out = <_RailItem>[];
    Map<String, dynamic>? current;
    for (var i = 0; i < _slides.length; i++) {
      final id = _slides[i]['id']?.toString();
      final starts = id == null ? null : startsAt[id];
      if (starts != null) {
        current = starts;
        out.add(_RailItem.section(starts));
      }
      final folded = current != null &&
          _collapsedSections.contains(current['id']?.toString());
      if (!folded) out.add(_RailItem.slide(i));
    }
    return out;
  }

  /// How many slides the section owns: from its start to the next
  /// section's start (or the deck's end).
  int _sectionSlideCount(Map<String, dynamic> section) {
    final start = _slides.indexWhere(
        (s) => s['id']?.toString() == section['slide_id']?.toString());
    if (start < 0) return 0;
    var end = _slides.length;
    for (final s in _sectionsList(_deck)) {
      if (s['id'] == section['id']) continue;
      final j = _slides.indexWhere(
          (sl) => sl['id']?.toString() == s['slide_id']?.toString());
      if (j > start && j < end) end = j;
    }
    return end - start;
  }

  /// Fold/unfold a section in the rail.
  void _toggleSection(Map<String, dynamic> section) {
    final id = section['id']?.toString();
    if (id == null || id.isEmpty) return;
    _setState(() {
      if (!_collapsedSections.remove(id)) _collapsedSections.add(id);
    });
  }

  /// "Start section here" (slide actions): name it, anchor it to this
  /// slide. One mutate = one undo step, like every deck edit.
  Future<void> _startSectionAt(int i) async {
    if (i < 0 || i >= _slides.length) return;
    final name = await dreamInputDialog(
      context,
      title: 'Start section here',
      hint: 'Section name',
      initial: _slideTitle(_slides[i]),
      confirmLabel: 'Start',
    );
    if (name == null || name.trim().isEmpty) return;
    final sid = _slides[i]['id']?.toString();
    if (sid == null) return;
    _mutateSections((sections) => [
          ...sections,
          {
            'id': 'sec_${DateTime.now().millisecondsSinceEpoch}',
            'name': name.trim(),
            'slide_id': sid,
          },
        ]);
  }

  /// Long-press menu for a section chip.
  Future<void> _sectionActions(Map<String, dynamic> section) async {
    final action = await dreamSheet<String>(
      context,
      builder: (context) => _SectionActionsSheet(
          name: section['name']?.toString() ?? ''),
    );
    switch (action) {
      case 'rename':
        _renameSection(section);
      case 'remove':
        _removeSection(section);
    }
  }

  Future<void> _renameSection(Map<String, dynamic> section) async {
    final name = await dreamInputDialog(
      context,
      title: 'Rename section',
      initial: section['name']?.toString() ?? '',
      confirmLabel: 'Rename',
    );
    if (name == null || name.trim().isEmpty) return;
    _mutateSections((sections) => [
          for (final s in sections)
            if (s['id'] == section['id'])
              {...s, 'name': name.trim()}
            else
              s,
        ]);
  }

  /// Remove the divider only — the slides were never part of it. The
  /// fold state dies with the section.
  void _removeSection(Map<String, dynamic> section) {
    _collapsedSections.remove(section['id']?.toString());
    _mutateSections((sections) => [
          for (final s in sections)
            if (s['id'] != section['id']) s,
        ]);
  }

  /// Every section edit is a deck edit: apply [change] to a deep copy's
  /// markers and mutate — one undo step, persisted, sanitized.
  void _mutateSections(
      List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
          change) {
    final updated = _copy();
    final next = change(_sectionsList(updated));
    // The empty list is deliberate — a TOMBSTONE. `_setDeck` carries the
    // previous deck's markers forward whenever a deck arrives WITHOUT the
    // field (every engine round-trip drops it); a removal must not look
    // like a round-trip, or the removed markers resurrect. An empty
    // tombstone never carries, so the field quietly disappears again on
    // the next engine op — there is nothing left to preserve.
    updated['sections'] = next;
    _mutate(updated);
  }

  // ---- deck-level ops ----------------------------------------------------------

  Future<void> _renameDeck() async {
    final title = await dreamInputDialog(
      context,
      title: 'Rename deck',
      initial: (_deck['title'] ?? '').toString(),
      confirmLabel: 'Rename',
    );
    if (title == null || title.trim().isEmpty) return;
    final updated = _copy();
    updated['title'] = title.trim();
    _mutate(updated);
  }

}
