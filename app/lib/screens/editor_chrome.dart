part of 'editor_screen.dart';

/// Editor chrome: the filmstrip unit, drawer extent, contextual row, modes. Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorChrome on _EditorScreenState {

  // ---- the filmstrip unit (one subtree, two slots) -----------------------------

  /// The strip unit: the boundary divider plus the reveal, as ONE subtree —
  /// identical in both of its slots. While the Files sheet is closed it is a
  /// row in the editor's flow (canvas above, ribbon below); while the sheet
  /// is open it is the bottom-aligned foreground layer over the sheet's
  /// lower part. The reveal's outer [KeyedSubtree] carries the reparent
  /// GlobalKey ([_filmstripRevealHost]), so the unit's moves between the two
  /// slots preserve the rail's scroll offset and the selection — the element
  /// is reparented, never remounted.
  ///
  /// The strip's boundary is the toggle itself: one continuous rule drawn by
  /// [_FilmstripDivider] directly above the band — flat across the editor,
  /// then near the right edge a ramp up into a short ledge that runs flush
  /// to the edge, with the chevron centered in the pocket under the ledge.
  /// Collapsed, the same rule carries an up chevron in the cool light
  /// neutral; open, the stroke wears the signature sweep — the same purple
  /// → magenta → orange stops as the + disc (kInkGradient's own colors),
  /// run left → right along the boundary so the line warms from quiet
  /// purple to orange exactly at the ramp and ledge, and the chevron
  /// repeats the disc's diagonal gradient over its glyph — the user's
  /// verdict after two single-color tries was that only the disc's own
  /// gradient reads on-theme. And the band itself is a real panel: one
  /// continuous kFilmstrip charcoal fill (a dedicated token — a step
  /// lighter than the black workspace, a shade darker than the nav's
  /// kSurface) runs the full width of the expanded strip behind
  /// everything, so the strip reads as its own surface instead of melting
  /// into the black canvas — flat fill only, no border, no shadow, no left
  /// fade, and the divider still draws the boundary above it.
  ///
  /// The reveal: the band itself never unmounts — it stays laid out at the
  /// full 104dp inside a top-anchored Align/ClipRect pair (Align's
  /// heightFactor drives the reveal height; the clip carries the same
  /// boundary to hit-testing) that collapses paint and taps down to nothing
  /// when collapsed (and ExcludeSemantics pulls it out of the a11y tree).
  /// That is what preserves the scroll offset and the selected slide
  /// across every fold/unfold — and, in the overlay slot, across every
  /// Files open/close — and one 200ms eased height transition, instant
  /// under reduced-motion, is the single coordinated move.
  Widget _filmstripUnit(BuildContext context) {
    // The rail's flattened view — section dividers interleaved with the
    // slides of unfolded sections — computed once per build.
    final rail = _railItems();
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilmstripDivider(
            expanded: _filmOpen,
            onToggle: _toggleFilmstrip,
          ),
          KeyedSubtree(
            key: _filmstripRevealHost,
            child: KeyedSubtree(
              key: const ValueKey('filmstrip_reveal'),
              child: ExcludeSemantics(
                key: const ValueKey('filmstrip_strip_semantics'),
                excluding: !_filmOpen,
                child: TweenAnimationBuilder<double>(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeInOutCubic,
                  tween: Tween<double>(begin: 1.0, end: _filmOpen ? 1.0 : 0.0),
                  builder: (context, v, child) => ClipRect(
                    // Top-anchored: the band folds UP under the divider's
                    // baseline — its bottom edge rises to meet the rule —
                    // and drops back down on unfold. Align's heightFactor
                    // drives the reveal height; the clip carries the same
                    // boundary to hit-testing, so the hidden band cannot
                    // be tapped.
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: v,
                      child: child,
                    ),
                  ),
                  child: SizedBox(
                    key: const ValueKey('filmstrip_row'),
                    height: _EditorScreenState._filmstripBandHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // The panel fill: one continuous charcoal surface
                        // behind the whole expanded band — full width,
                        // behind the + disc, behind the thumbnails, in every
                        // gap and edge. It lives INSIDE the reveal's clip, so
                        // it appears and folds with the row itself: nothing
                        // lingers or flashes during the 200ms transition, and
                        // collapsed the clip takes the fill to zero height —
                        // no colored strip left above the navigation. Flat
                        // kFilmstrip only (dedicated token, between the
                        // black workspace and the nav's kSurface): no
                        // border, no shadow, no gradient — the divider above
                        // stays the only boundary. The fill's top edge meets
                        // the divider's 2dp stroke guard under its baseline,
                        // so the gradient rule reads as lying directly on the
                        // panel's top edge; everything ON the fill — white
                        // cards, selection ring, disc — keeps its own colors.
                        const Positioned.fill(
                          child: ColoredBox(color: kFilmstrip),
                        ),
                        // The rail: full width, slides only. The leading
                        // inset puts slide 0 at the exact resting spot it
                        // has always had since 2.15 (first card at 74dp, a
                        // 16dp gap from the disc's right edge), its border
                        // and rounded corners fully visible. The trailing
                        // inset is the plain 4dp again — nothing reserves
                        // the rail's end zone anymore (the old end chevron
                        // is gone; the toggle lives in the divider above).
                        ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(68, 6, 4, 6),
                          // The rail is a FLATTENED view: section dividers
                          // interleave with slide cards, and a folded
                          // section's slides leave the list entirely — a
                          // list position is never assumed to be a slide
                          // index.
                          itemCount: rail.length,
                          itemBuilder: (context, n) {
                            final item = rail[n];
                            if (item.isSection) {
                              final sec = item.section!;
                              return _SectionChip(
                                id: sec['id']?.toString() ?? '',
                                name: sec['name']?.toString() ?? 'Section',
                                collapsed: _collapsedSections
                                    .contains(sec['id']?.toString()),
                                count: _sectionSlideCount(sec),
                                onToggle: () => _toggleSection(sec),
                                onLongPress: () => _sectionActions(sec),
                              );
                            }
                            final i = item.slideIndex;
                            final selected = i == _index;
                            final label = _slideTitle(_slides[i]);
                            return Padding(
                              padding: const EdgeInsets.all(6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _gotoSlide(i),
                                onLongPress: () => _slideActions(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 124,
                                  padding: EdgeInsets.all(selected ? 2.5 : 1),
                                  decoration: BoxDecoration(
                                    gradient: selected ? kInkGradient : null,
                                    color: selected ? null : kHairline,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Text(
                                          '${i + 1}. $label',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF17181A),
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // The floating +: the signature gradient disc, at its
                        // home spot and size — 14dp from the strip's left edge,
                        // vertically centered (top 30 of the 104dp band), 44dp
                        // across, original soft shadow. Painted LAST, over the
                        // rail and the panel fill: the slides it passes over
                        // are seen behind it, and nothing clips it — the +
                        // still reads as a floating button, now riding the
                        // charcoal panel instead of the bare black canvas.
                        // Tap adds a blank slide; long-press opens the
                        // layout list.
                        Positioned(
                          left: 14,
                          top: 30,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: _addSlide,
                              onLongPress: _addLayoutSlide,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: kInkGradient,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.add,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
  }

  // ---- ribbon wiring ---------------------------------------------------------

  /// The strip's live flow footprint: the divider region plus the reveal's
  /// CURRENT height — read off the mounted reveal (works in both of the
  /// unit's slots, the box under the reparent GlobalKey being the same
  /// subtree), so a fold caught mid-flight reports its real on-screen
  /// height, not its target. This is what gets frozen when Files opens and
  /// what the spacer hands back to on close.
  double _liveStripFlowHeight() {
    final revealH = _filmstripRevealHost.currentContext?.size?.height ??
        (_filmOpen ? _EditorScreenState._filmstripBandHeight : 0.0);
    return _FilmstripDivider.regionHeight + revealH;
  }

  /// The one toggle behind the integrated edge handle: the strip band folds
  /// up under the divider (the canvas reclaims the 104dp) and unfolds back.
  /// Selection, scroll offset, and the ribbon's own tab state are all kept —
  /// nothing here touches them.
  void _toggleFilmstrip() {
    _setState(() => _filmOpen = !_filmOpen);
  }

  // ---- the sheet drawers' shared layer (Files + Insert) --------------------

  /// A live drag on the drawer's header: the sheet's top edge follows the
  /// finger — down shrinks, up grows — clamped between the header sliver
  /// (the pinned handle always fits) and the tall detent. While the drag is
  /// live the sheet tracks the finger exactly (the layer's duration is zero
  /// mid-drag), so the settle below is where the detents do their work.
  void _drawerDragUpdate(double dy) {
    // The entrance/exit slide owns the layer's translation — a drag that
    // lands mid-slide is dead until the sheet is in place.
    if (_sheetEntering || _sheetClosing) return;
    final base = _drawerExtent ?? _drawerHalf;
    final floor = math.min(_EditorScreenState._drawerSliver, _drawerTall);
    _setState(() {
      _drawerDragging = true;
      _drawerExtent = (base - dy).clamp(floor, _drawerTall).toDouble();
    });
  }

  /// The drag's settle: a fling moves one detent in its direction; a plain
  /// release snaps to the NEAREST detent — with a dismiss zone below ~70%
  /// of the half detent where the sheet closes outright instead of snapping
  /// back up.
  void _drawerDragSettle(double velocityDy) {
    // No drag can be in flight while a slide owns the layer.
    if (_sheetEntering || _sheetClosing) return;
    final extent = _drawerExtent ?? _drawerHalf;
    if (velocityDy > 700) {
      // Fling down: tall → half, half-or-lower → dismissed.
      if (extent > _drawerTall - 24) {
        _snapDrawer(_drawerHalf);
      } else {
        _setNavTab(null);
      }
      return;
    }
    if (velocityDy < -700) {
      // Fling up: below half → half, half-or-above → tall.
      _snapDrawer(extent < _drawerHalf - 24 ? _drawerHalf : _drawerTall);
      return;
    }
    if (extent < _drawerHalf * 0.7) {
      _setNavTab(null); // the dismiss zone: gone, cleanly, at its slot
      return;
    }
    _snapDrawer((extent - _drawerHalf).abs() <= (extent - _drawerTall).abs()
        ? _drawerHalf
        : _drawerTall);
  }

  /// Snap to a detent: the settle animates over the 200ms family (the drag
  /// itself was tracking the finger directly, no rubber-banding — the
  /// detents stay honest).
  void _snapDrawer(double target) {
    _setState(() {
      _drawerDragging = false;
      _drawerExtent = target;
    });
  }

  /// Draw C: the island settled (or changed mode) — remember it per device.
  void _setIsland(IslandPlacement placement) {
    _setState(() => _island = placement);
    saveIslandPlacement(placement);
  }

  void _onNavSelect(_NavTab tab) {
    _setNavTab(
        _navTab == tab ? null : tab); // tap the active tab again to collapse
  }

  /// The contextual action row for the active ribbon tab — the selected
  /// tool swaps in a compact toolbar right under the canvas, above the
  /// filmstrip "timeline". Tabs without tools yet render nothing (their
  /// band is skipped in build); the filler hint texts are gone by request.
  Widget _contextualRow() {
    switch (_navTab) {
      case null:
        return const SizedBox.shrink();
      case _NavTab.ai:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.tonalIcon(
                onPressed: _showPairSheet,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Pair AI'),
              ),
            ),
          ],
        );
      case _NavTab.files:
        // The Files tab's tools live in the docked drawer that replaces this
        // band (see build) — the row itself never renders for Files.
        return const SizedBox.shrink();
      case _NavTab.insert:
        // Insert is where things get ADDED to the slide — its compact drawer
        // (the same sheet layer as Files) replaces this band.
        return const SizedBox.shrink();
      case _NavTab.draw:
        // The toolbox: pen / highlighter with per-tool colors, the pen's
        // widths, the expandable palette band (the row lives in the
        // editor_draw_tools part file; the editor owns the ONE state).
        // Draw C-2: the compact island shows the narrow column instead.
        if (_island.compact) {
          return _DrawToolboxCompact(
            state: _drawToolbox,
            defaultPenHex: _dnaAccentHex,
            palette: _deckPalette,
            onChanged: _setDrawToolbox,
            onExpand: () => _setIsland(_island.copyWith(compact: false)),
          );
        }
        return _DrawToolboxRow(
          state: _drawToolbox,
          defaultPenHex: _dnaAccentHex,
          palette: _deckPalette,
          onChanged: _setDrawToolbox,
          onClearAll: _clearAllInk,
          onReplayInk: _replayInk,
          onCompact: () => _setIsland(_island.copyWith(compact: true)),
          onNotice: _toast,
          lassoCount: _liveLassoIds.length,
          onLassoColor: _restyleLasso,
          onLassoDelete: _deleteLasso,
          onLassoClear: _clearLasso,
        );
      case _NavTab.design:
        final current = ((_deck['dna'] ?? const {})['family'] ?? '').toString();
        return Row(
          children: [
            const SizedBox(width: 8),
            for (final (id, label) in _designFamilies)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: DreamChoiceChip(
                    magenta: true,
                    label: label,
                    selected: id == current,
                    onTap: () => _applyDesign(id)),
              ),
            IconButton(
              tooltip: 'New variant of this design',
              icon: const Icon(Icons.shuffle),
              onPressed: () => _applyDesign('next_variant'),
            ),
          ],
        );
      case _NavTab.transitions:
        return const SizedBox.shrink();
      case _NavTab.animations:
        return const SizedBox.shrink();
      case _NavTab.slideshow:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.icon(
                onPressed: _startPresenting,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Present'),
              ),
            ),
          ],
        );
      case _NavTab.review:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.tonalIcon(
                onPressed: _showComments,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Comments'),
              ),
            ),
          ],
        );
      case _NavTab.view:
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FilledButton.tonalIcon(
                onPressed: () => _setMode(_Mode.viewing),
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('Reading view'),
              ),
            ),
          ],
        );
      case _NavTab.help:
        return const SizedBox.shrink();
    }
  }

  String _slideTitle(Map slide) {
    final archetype = (slide['archetype'] ?? 'slide').toString();
    if (archetype == 'blank') return 'Blank';
    final content = slide['content'];
    if (content is Map) {
      for (final k in ['title', 'text', 'kicker']) {
        final v = content[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return archetype;
  }

  void _showPairSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PairSheet(deck: _deck, onDeckUpdate: _applyRemoteDeck),
    );
  }

  /// A deck payload pushed by the AI over the paired WebSocket (update /
  /// snapshot / reset): apply it as one atomic step — it lands on the
  /// canvas live, persists like any edit, and takes its place in undo
  /// history (undo reverts an AI edit like any other).
  void _applyRemoteDeck(Map<String, dynamic> deck) {
    if (!mounted) return;
    _mutate(deck);
    _styleUndoPushed = false;
    _resyncTextSession();
  }

  // ---- editor modes (More menu) ---------------------------------------------

  void _setMode(_Mode m) {
    _setState(() {
      _mode = m;
      if (m == _Mode.viewing) {
        _navTab = null;
        _designMode = false;
        _drawToolbox = _drawToolbox.disarmed();
        _selectedObjectId = null;
        _sheetHiddenForTyping = false;
      }
    });
  }

  Future<void> _onModeMenu(String choice) async {
    switch (choice) {
      case 'editing':
        _setMode(_Mode.editing);
      case 'viewing':
        _setMode(_Mode.viewing);
      case 'presenting':
        await _startPresenting();
      case 'export':
        await _showExportSheet();
    }
  }

  /// Slide-step helper for the viewing chevrons.
  void _step(int delta) {
    if (_slides.isEmpty) return;
    var target = _index + delta;
    if (target < 0) target = 0;
    if (target >= _slides.length) target = _slides.length - 1;
    if (target == _index) return;
    _setState(() => _index = target);
    _refreshLayout();
  }

  /// Presenting mode — a fullscreen, chrome-free pass over the deck.
  Future<void> _startPresenting() async {
    if (_slides.isEmpty) {
      _toast('Add a slide first.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PresenterScreen(deck: _deck, first: _index),
      ),
    );
  }

  // ---- comments & share -------------------------------------------------------

  Future<void> _showComments() async {
    await dreamSheet<void>(
      context,
      builder: (context) => _CommentsSheet(
        comments: _comments,
        field: _commentField,
        onPost: (text) {
          _setState(() => _comments.add({'text': text}));
          _commentField.clear();
        },
      ),
    );
  }

  /// The top-bar Share button — "send a copy": no format dialog, just export
  /// the deck as .pptx and hand it straight to the system share sheet.
  /// Picking a format (pptx/pdf) is the Export menu's job; Share is the
  /// fast lane out of the app.
  Future<void> _showShareSheet() => _export('export_pptx', verb: 'Share');

  Future<void> _showExportSheet() async {
    await dreamSheet<void>(
      context,
      builder: (context) => _ExportSheet(
        busy: _busy,
        onExport: (op) => _export(op),
      ),
    );
  }
}
