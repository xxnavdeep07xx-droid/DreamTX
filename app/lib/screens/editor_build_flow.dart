part of 'editor_screen.dart';

/// build()'s own body (the class keeps a one-line delegate). Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorBuildFlow on _EditorScreenState {
  Widget _buildBody(BuildContext context) {
    // Deck colors + the text boxes' slide-theme base track the deck version.
    _refreshPalette();
    final title = (_deck['title'] ?? 'Deck').toString();
    final family = ((_deck['dna'] ?? const {})['family'] ?? '')
        .toString()
        .replaceAll('_', ' ');
    final n = _slides.length;
    // KeyboardStableMetrics: all text entry on this screen happens in
    // bottom-sheet routes (content editor, inspector, pair sheet) that sit
    // OUTSIDE this Scaffold and track the keyboard themselves — so the
    // canvas, tool row and filmstrip below keep their steady layout while the
    // keyboard is open, in both inset-delivery and window-resize mode.
    // (The ribbon bar and its contextual tool row sit inside this
    // subtree too, so they stay put as well.)
    return KeyboardStableMetrics(
      child: Scaffold(
        appBar: AppBar(
          title: Tooltip(
            message: '$family — tap to rename deck',
            child: InkWell(
              onTap: _renameDeck,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(title, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: ColoredBox(color: kHairline),
          ),
          // The toolkit lives in the bottom ribbon — the top bar keeps
          // deck-level controls: rename (tap the title), undo/redo, comments,
          // share (a .pptx copy straight to the system share sheet), and the
          // More menu (modes + export with a format choice).
          actions: [
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: _undo.isEmpty ? null : _undoStep,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: _redo.isEmpty ? null : _redoStep,
            ),
            IconButton(
              tooltip: 'Comments',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: _showComments,
            ),
            IconButton(
              tooltip: 'Share',
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2))
                  : const Icon(Icons.share),
              onPressed: _busy ? null : _showShareSheet,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: !_busy,
              icon: const Icon(Icons.more_vert),
              onSelected: _onModeMenu,
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'editing', child: Text('Editing Mode')),
                PopupMenuItem(value: 'viewing', child: Text('Viewing Mode')),
                PopupMenuItem(
                    value: 'presenting', child: Text('Presenting Mode')),
                // The modes are chrome states; Export is an action from a
                // different family — a real divider line keeps them apart.
                PopupMenuDivider(height: 12),
                PopupMenuItem(value: 'export', child: Text('Export')),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        // ---- THE LAYER CAKE --------------------------------------------------
        // The body is not one stacked flow but layers that cannot disturb
        // each other, in one stable stacking order: main slide → Files
        // sheet → filmstrip tray → bottom navbar. The base layer is the
        // editor's whole flow — canvas, contextual row, filmstrip chrome,
        // ribbon — and while the Files sheet is CLOSED the strip is simply
        // one more row in that flow. While the sheet is OPEN the cake
        // inverts: the sheet floats as its own layer pinned DIRECTLY to the
        // ribbon's top edge (a constant anchor — see [sheetAnchor]) and
        // SLIDES as a rigid body — in at full intended height from fully
        // below the navbar's top edge, out the same way — and the filmstrip
        // becomes a bottom-aligned FOREGROUND layer riding the sheet's
        // lower part, painted above it, stationary through the sheet's
        // whole lifecycle. The strip takes no layout space while the sheet
        // is open (the flow keeps a frozen spacer of its exact footprint),
        // so the sheet's height is the user's choice alone AND the slide
        // preview's constraints are frozen: opening or closing the sheet,
        // its animation progress, or toggling the strip can never push,
        // shrink, move, or recenter the sheet, the preview, or the ribbon.
        // The tray may cover the sheet's lower part, but it is
        // clip-constrained to the sheet's own live extent, so it can never
        // reach past the sheet's top edge into the slide preview; and the
        // whole moving sheet is clip-constrained to the navbar boundary, so
        // it can never paint over the navbar — the ribbon stays fixed in
        // front while the sheet rises behind it.
        body: LayoutBuilder(
          builder: (context, constraints) {
            // The sheet's layer is alive while a sheet tab is active (and
            // the typing state is not standing it down) OR its exit slide
            // is still running — the unmount lands when that slide
            // completes (the AnimatedPositioned's onEnd below). While the
            // user is TYPING into a text box the sheet stands down (the
            // keyboard owns the bottom of the screen and the typing
            // toolbar rides it in the root overlay) for EITHER drawer —
            // Files just as Insert — and the flow's spacer system keeps
            // the canvas's constraints frozen through that too.
            final filesOpen = _mode == _Mode.editing &&
                _navTab == _NavTab.files &&
                !_typing;
            final insertOpen = _mode == _Mode.editing &&
                _navTab == _NavTab.insert &&
                !_typing;
            final sheetOpen = filesOpen || insertOpen;
            final sheetLive = sheetOpen || _sheetClosing;
            // The strip's flow footprint at its CURRENT state — what the
            // spacer hands back to on close, and the fallback for a missing
            // freeze.
            final stripFlowHeight = _FilmstripDivider.regionHeight +
                (_filmOpen ? _EditorScreenState._filmstripBandHeight : 0.0);
            // The sheet's anchor: the ribbon's top edge, full stop. While
            // the sheet is open the ribbon's own top hairline always shows
            // (both the open tray and the collapsed divider sit directly on
            // it, and the tray keeps the same boundary it has in the flow),
            // so the band is a constant 77dp — which makes the anchor a
            // constant: toggling the filmstrip never moves the sheet, the
            // canvas, or the ribbon by a single pixel.
            const sheetAnchor = _EditorScreenState._navBarHeight + 1.0;
            // The space the sheet may occupy: everything above the ribbon
            // inside this body. From it, the two detents EITHER drawer's
            // header drag settles between — the resting HALF (floor 296 so
            // the whole 3×2 grid always fits — Files' tool tiles and
            // Insert's cards alike, ceiling 430) and the TALL sheet (~78%,
            // leaving the slide's top sliver in view). The drag handlers run
            // between builds, so both are cached per build.
            final available =
                math.max(64.0, constraints.maxHeight - sheetAnchor);
            final half = math.min(
                math.min(430.0, math.max(296.0, available * 0.45)),
                available - 12.0);
            final tall =
                math.min(math.max(available * 0.78, half + 60.0), available - 12.0);
            _drawerHalf = half;
            _drawerTall = tall;
            // The strip overlay's own box: the strip's live height target —
            // the divider region plus the revealed band while open, just
            // the divider region while collapsed — capped at the sheet's
            // live extent. The cap is the whole "constrain the tray to the
            // available space" contract: mid-drag (both layers track the
            // finger at zero duration) and mid-grow-in/settle (both layers
            // run the same 200ms curve retargeted on the same rebuild) the
            // overlay's animated height stays at or under the sheet's
            // animated height, so the tray can never poke above the
            // sheet's top edge into the preview at any instant.
            final stripH = _filmOpen
                ? _FilmstripDivider.regionHeight + _EditorScreenState._filmstripBandHeight
                : _FilmstripDivider.regionHeight;
            final sheetHeight = _sheetLiveHeightFor();
            final overlayH = math.min(stripH, sheetHeight);
            return Stack(
              children: [
                // The base layer: the editor's whole flow. While a sheet
                // (Files or Insert) is open the filmstrip is NOT in this flow (it is the
                // foreground overlay above the sheet — see the layer cake
                // below), which is what keeps the canvas's geometry and the
                // sheet's anchor completely independent of the strip's
                // state. (The children below keep their historical
                // indentation on purpose — only the strip's placement
                // became conditional.)
                Column(
          children: [
            // ---- canvas ----------------------------------------------------------
            Expanded(
              child: _layout == null
                  ? const Center(
                      child: Text('No slide here yet — add one below.'))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Stack(
                        children: [
                          Center(
                            child: AspectRatio(
                              // The deck's true frame ratio — 16:9 for every
                              // existing deck, and whatever the Files drawer's
                              // Aspect tool has since applied.
                              aspectRatio: aspectRatioOf(_deck['aspect']?.toString()),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  // THE slide stage — the one layered
                                  // stage the presenter renders too:
                                  // archetype layout, then the object
                                  // layer in the deck's TRUE Z-order
                                  // (content objects and vector shapes
                                  // interleaved exactly as
                                  // `slide['objects']` lists them, so
                                  // Bring Forward / Send Backward reads
                                  // on screen), with the gesture/selection
                                  // overlay on top and the live typing
                                  // field above everything.
                                  //
                                  // Objects are SELECTABLE in every editing
                                  // mode (any tab — not only Insert/Draw):
                                  // a tap selects and opens the object's
                                  // panel, a tap on the already-selected
                                  // text box enters typing, and drag/
                                  // resize/rotate work wherever the deck
                                  // is being edited. Viewing stays
                                  // read-only.
                                  child: SlideStage(
                                    layout: _layout!,
                                    objects: _objects,
                                    designW: _designDims.$1,
                                    designH: _designDims.$2,
                                    baseColor: _baseTextColor,
                                    baseFamily: _baseTextFamily,
                                    baseFontSize: kTextBoxBaseSize,
                                    resolveResourcePath:
                                        _resolveResourcePath,
                                    // The table metadata (merges + style)
                                    // rides the deck: the same map the
                                    // painter reads — carried through every
                                    // engine round-trip by [_setDeck].
                                    tableMeta: (_deck['tables'] as Map?)
                                        ?.cast<String, dynamic>(),
                                    // Image metadata (shape/brightness/
                                    // contrast/alt) rides the deck — the
                                    // same map the content layer reads,
                                    // carried by [_setDeck].
                                    imageMeta: (_deck['imageMeta'] as Map?)
                                        ?.cast<String, dynamic>(),
                                    selectedId: _selectedObjectId,
                                    interactive: _mode == _Mode.editing,
                                    // The Draw toolbox: the armed tool
                                    // and its style (the row under the
                                    // canvas owns the state; the preview
                                    // and the committed object agree by
                                    // construction — same InkStyle).
                                    inkTool: _drawToolbox.armed
                                        ? _drawToolbox.tool
                                        : null,
                                    inkStyle: _drawToolbox.inkStyleFor(
                                        defaultPenHex: _dnaAccentHex),
                                    onTextTap: _mode == _Mode.viewing
                                        ? null
                                        : _editText,
                                    onSelect: _onObjectSelected,
                                    onLive: _liveObject,
                                    onCommit: _commitObject,
                                    onGestureStart: _objectGestureStart,
                                    onStroke: _onStrokeDone,
                                    onEraseHits: _onEraseHits,
                                    eraserRadius: _drawToolbox.eraserRadius,
                                    // Draw B: the lasso selection shows only
                                    // while the lasso is armed.
                                    lassoIds: _drawToolbox.armed &&
                                            _drawToolbox.tool == InkTool.lasso
                                        ? _liveLassoIds
                                        : const {},
                                    onLasso: _onLassoDone,
                                    // Draw R: the ruler shows on the Draw tab.
                                    showRuler: _navTab == _NavTab.draw &&
                                        _drawToolbox.ruler,
                                    // Draw E: the ink replay clock.
                                    inkReplay: _inkReplay,
                                    onLassoMove: _onLassoMoveEnd,
                                    onObjectLongPress: _objectActions,
                                    onCanvasLongPress: _pasteObjectAt,
                                    textController: _selectedObject != null &&
                                            ObjectContent.isText(
                                                _selectedObject!)
                                        ? _textSession?.controller
                                        : null,
                                    textFocusNode: _selectedObject != null &&
                                            ObjectContent.isText(
                                                _selectedObject!)
                                        ? _textSession?.focus
                                        : null,
                                    typing: _typing,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // CapCut-style floating position chip (like the
                          // timeline counter) — always-visible slide index.
                          Positioned(
                            right: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: kHairline),
                              ),
                              child: Text(
                                n == 0
                                    ? 'no slides'
                                    : _mode == _Mode.viewing
                                        ? 'viewing · ${_index + 1} / $n'
                                        : 'Slide ${_index + 1} / $n',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: kText2),
                              ),
                            ),
                          ),
                          if (_warnings.isNotEmpty)
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: Chip(
                                avatar: const Icon(Icons.warning_amber_outlined,
                                    size: 18),
                                label: Text(_warnings.first,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          // Viewing mode: edge chevrons replace the editing chrome.
                          if (_mode == _Mode.viewing) ...[
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: IconButton(
                                  tooltip: 'Previous slide',
                                  icon: const Icon(Icons.chevron_left,
                                      size: 30, color: kText2),
                                  onPressed:
                                      _index > 0 ? () => _step(-1) : null,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: IconButton(
                                  tooltip: 'Next slide',
                                  icon: const Icon(Icons.chevron_right,
                                      size: 30, color: kText2),
                                  onPressed:
                                      _index < n - 1 ? () => _step(1) : null,
                                ),
                              ),
                            ),
                          ],
                          // Draw C: the Draw toolbox is a floating island over
                          // the canvas — docked to the top or bottom edge, lifted
                          // by a 500 ms hold on its grip.
                          if (_mode == _Mode.editing &&
                              _navTab == _NavTab.draw)
                            Positioned(
                              // Full: the canvas width. Compact: the side.
                              left: !_island.compact ||
                                      _island.side == IslandSide.left
                                  ? 0
                                  : null,
                              right: !_island.compact ||
                                      _island.side == IslandSide.right
                                  ? 0
                                  : null,
                              top: _island.dock == IslandDock.top ? 0 : null,
                              bottom:
                                  _island.dock == IslandDock.bottom ? 0 : null,
                              child: FloatingIsland(
                                placement: _island,
                                onPlace: _setIsland,
                                child: _contextualRow(),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            // ---- editing chrome: tool row + filmstrip + ribbon nav ---------------
            if (_mode == _Mode.editing) ...[
              // Tabs with no tools yet (transitions / animations / help)
              // skip the band entirely; Files and Insert live in their docked
              // drawers instead of a contextual row — the canvas keeps the
              // space until their toolboxes get spec'd.
              // Draw is an island over the canvas now (see above).
              if (_navTab != null &&
                  _navTab != _NavTab.draw &&
                  _navTab != _NavTab.files &&
                  _navTab != _NavTab.insert &&
                  _navTab != _NavTab.transitions &&
                  _navTab != _NavTab.animations &&
                  _navTab != _NavTab.help)
                // Draw is the one tab whose row changes height: the
                // toolbox's palette band cross-fades the band 48 <-> 94,
                // the same reveal the typing toolbar's palette row does —
                // every other tab stays a constant 48.
                Container(
                  decoration: const BoxDecoration(
                    color: kSurface,
                    border: Border(
                      top: BorderSide(color: kHairline),
                      bottom: BorderSide(color: kHairline),
                    ),
                  ),
                  height: _navTab == _NavTab.draw ? null : 48,
                  child: _contextualRow(),
                ),
              // ---- filmstrip (stories-style, gradient ring on the live slide) --
              // The strip unit — the boundary divider plus the reveal, built
              // once by [_filmstripUnit] — lives in the flow ONLY while the
              // Files sheet is closed: canvas above, ribbon below, and the
              // canvas reclaims the 104dp when the band folds. While the
              // sheet (or its exit slide) is live the SAME subtree is the
              // bottom-aligned foreground layer over the sheet's lower part
              // (see the layer cake below), so it takes no layout space
              // here — the frozen spacer below holds its exact footprint —
              // which is what keeps the sheet, the slide preview, and the
              // ribbon immune to the strip's state. The move between the
              // two slots happens under the reveal's reparent GlobalKey,
              // so the rail's scroll offset and selection survive every
              // Files open/close.
              if (!sheetLive)
                _filmstripUnit(context)
              else
                // The frozen footprint: an EMPTY spacer of exactly the
                // height the strip occupied in the flow when Files opened
                // (frozen — never tracking the tray's toggles, so the slide
                // preview's constraints cannot move while the sheet is
                // open). On close it animates to the strip's current
                // footprint over the same 200ms family, handing the space
                // back as the strip returns to the flow — a continuous
                // handoff, never a jump. Instant under reduced motion.
                AnimatedContainer(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeInOutCubic,
                  height: sheetOpen
                      ? (_frozenStripFootprint ?? stripFlowHeight)
                      : stripFlowHeight,
                ),

              // ---- PowerPoint-style ribbon ----------------------------------------
              _EditorNavBar(
                  active: _navTab,
                  controller: _navScroll,
                  onSelect: _onNavSelect,
                  // The ribbon's top hairline separates whatever sits directly
                  // on it from the band. In the flow that is the strip's
                  // business: the divider's own rule is the boundary while
                  // collapsed (showing this too would double the line), and
                  // the open band rides the hairline. While the Files sheet
                  // is open the hairline ALWAYS shows — the overlay's tray
                  // and collapsed divider both sit directly on it, and a
                  // constant band keeps the sheet's anchor, the canvas, and
                  // the ribbon itself frozen through every tray toggle.
                  showTopRule: sheetOpen || _filmOpen),
            ],
          ],
                ),
                // The sheet + overlay layers, grouped behind ONE semantics
                // boundary ([Semantics] with container: true): the filmstrip
                // overlay's BlockSemantics drops the semantics of everything
                // painted before it BELOW that boundary — the covered part of
                // the sheet — while the base layer (ribbon included, painted
                // before the boundary but OUTSIDE it) keeps its accessibility
                // contract: the Files tab stays reachable, the top bar stays
                // reachable, and the tray's own semantics stay live.
                if (sheetLive)
                  Semantics(
                    container: true,
                    // The slide's hard boundary: the sheet may translate
                    // below the navbar's top edge while entering or leaving,
                    // but it may never PAINT there — the clip keeps the
                    // navbar fixed in front of the moving layer, and
                    // hit-testing follows the same rect, so the hidden part
                    // of the sheet is untappable at every instant of the
                    // slide. (The tray's own box ends exactly at this edge,
                    // so it is untouched by the clip.)
                    child: ClipRect(
                      clipper: _SheetPortalClipper(boundary: sheetAnchor),
                      child: Stack(
                      children: [
                        // ---- the drawer layer -------------------------------------
                        // The drawer (Files' surface or Insert's — the SAME
                        // layer) floats ABOVE the canvas and rides the
                        // RIBBON's top edge (bottom offset = the constant
                        // sheetAnchor), so the filmstrip's state can never
                        // move it: the strip is not in the flow beneath it —
                        // the sheet's own kSurface fills the whole region down
                        // to the ribbon, and the tray overlays it in front
                        // (the layer above) with no spacer of any kind in
                        // between. THE ENTRANCE/EXIT: the sheet is laid out at
                        // its full intended height and translated as a rigid
                        // body — arriving, its top edge starts exactly at the
                        // navbar's top edge (fully below it) and slides up
                        // into view; leaving, the same motion runs in reverse.
                        // The origin is the navbar's edge alone, never the
                        // filmstrip's. While the header's drag is live the
                        // duration is zero (the edge tracks the finger
                        // exactly); every slide runs the same 200ms eased
                        // family as the filmstrip's own reveal — instant under
                        // reduced motion. The slide's ClipRect (above) keeps
                        // the navbar fixed in front of the moving layer.
                        AnimatedPositioned(
                          duration: _drawerDragging
                              ? Duration.zero
                              : (MediaQuery.of(context).disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200)),
                          curve: Curves.easeInOutCubic,
                          left: 0,
                          right: 0,
                          // In place (open, dragging, settled) the sheet's
                          // bottom sits on the anchor; entering or closing, it
                          // is translated fully below the navbar's top edge —
                          // bottom = anchor minus the sheet's own height, so
                          // its top edge lands exactly on the boundary.
                          // AnimatedPositioned retargets from its live value,
                          // so interrupted or reversed slides continue from
                          // the current visible position, never resetting.
                          bottom: (_sheetEntering || _sheetClosing)
                              ? sheetAnchor - sheetHeight
                              : sheetAnchor,
                          height: sheetHeight,
                          // The exit slide's bookend: when the translation
                          // completes the layer unmounts at its slot (a
                          // tab's chrome appears and disappears there).
                          onEnd: () {
                            // Unmount when nothing wants the layer painted:
                            // the tab left the sheet family, OR the typing
                            // state is standing it down (the keyboard owns
                            // the screen — the sheet will rise again when
                            // typing ends, [_sheetHiddenForTyping]).
                            if (!mounted ||
                                !_sheetClosing ||
                                (_isSheetTab(_navTab) &&
                                    _mode == _Mode.editing &&
                                    !_sheetHiddenForTyping)) {
                              return;
                            }
                            _setState(() {
                              _sheetClosing = false;
                              _sheetEntering = false;
                              _drawerExtent = null;
                            });
                          },
                          // The sheet's CONTENT: the Files drawer or the
                          // Insert drawer — same layer, same lifecycle, same
                          // clip, same anchor, same detents, same drag
                          // (both headers forward their vertical drags to
                          // the one shared extent machinery); switching
                          // between the two sheet tabs swaps the surface
                          // without unmounting the layer, and the exit slide
                          // keeps the surface it is animating out.
                          child: _lastSheetTab == _NavTab.insert
                              ? InsertSheet(
                                  bottomInset: _FilmstripDivider.regionHeight +
                                      _EditorScreenState._filmstripBandHeight,
                                  selectedObject: _selectedObject,
                                  textController: _selectedObject != null &&
                                          ObjectContent.isText(_selectedObject!)
                                      ? _textSession?.controller
                                      : null,
                                  textActions: _textActions,
                                  deckPalette: _deckPalette,
                                  onInsertTextBox: _insertTextBox,
                                  onInsertWordArt: _wordArtGallery,
                                  onPickImage: _pickImage,
                                  onPickShape: _addObject,
                                  onInsertTable: _insertTable,
                                  onInsertChart: _insertChart,
                                  onInsertIcon: _insertIcon,
                                  onPickMedia: _pickMedia,
                                  onPlayMedia: _playMedia,
                                  onObjectStyle: _liveObjectEdit,
                                  onTableCell: _editTableCell,
                                  tableEntry: _selectedTableEntry,
                                  onTableUpdate: _tableUpdate,
                                  onTableStyle: _tableStyle,
                                  imageEntry: _selectedImageEntry,
                                  onImageUpdate: _imageMetaUpdate,
                                  onReplaceImage: _replaceSelectedImage,
                                  onShowLayers: _showLayers,
                                  onEditStyleSheet: _editSelectedObjectStyle,
                                  onStartTyping: _beginTyping,
                                  // The panel's back arrow — "stop editing":
                                  // the SAME clear-selection path as
                                  // tapping empty canvas (flush + dispose
                                  // the text session, drop the id); the
                                  // object itself stays on the slide.
                                  onPanelBack: () => _onObjectSelected(null),
                                  // The SAME drag forwarding the Files
                                  // drawer's header carries: the Insert
                                  // drawer's header resizes the shared sheet
                                  // between the same detents and dismisses on
                                  // the same fling/deep-drag rules.
                                  onDragUpdate: _drawerDragUpdate,
                                  onDragSettle: _drawerDragSettle,
                                )
                              : FilesDrawer(
                                  aspect: _deckAspect,
                                  deckId: (_deck['id'] ?? '').toString(),
                                  onNew: _filesNewDeck,
                                  onOpen: _filesOpenDeck,
                                  onRename: _renameDeck,
                                  onAspect: _filesAspect,
                                  onDismiss: () => _setNavTab(null),
                                  // The overlay clearance: the tray (divider
                                  // region + band) rides the sheet's lower part,
                                  // so the grid's scrollable carries this as
                                  // bottom padding — the last row can always be
                                  // scrolled fully above the tray, including its
                                  // raised handle. Scroll content, never chrome:
                                  // the sheet's outer height is the detents' alone.
                                  bottomInset: _FilmstripDivider.regionHeight +
                                      _EditorScreenState._filmstripBandHeight,
                                  onDragUpdate: _drawerDragUpdate,
                                  onDragSettle: _drawerDragSettle,
                                ),
                        ),
                        // ---- the filmstrip overlay layer --------------------------
                        // The tray is a FOREGROUND layer over the sheet's lower
                        // part: the SAME strip unit that lives in the flow
                        // while the sheet is closed (reparented here under
                        // its GlobalKey — scroll and selection survive), now
                        // painted above the sheet. The tray is STATIONARY
                        // through the sheet's whole lifecycle — mounted,
                        // expanded, and already in place from the sheet's
                        // first frame, so the sheet's entrance rises behind
                        // it without flashing, jumping, or briefly covering
                        // the thumbnails (and the exit slide leaves the same
                        // way). The box tracks the sheet's
                        // own live extent (min(stripH, extent), the same
                        // duration/curve as the sheet's layer, retargeted on
                        // the same rebuild — while dragging both are
                        // zero-duration), and the ClipRect clips BOTH paint
                        // and hit-testing to it, so the tray may cover the
                        // sheet but can never reach past the sheet's top edge
                        // into the slide preview, and nothing above the box's
                        // top ever falls through to the sheet underneath.
                        // Inside the clip the OverflowBox lets the strip lay
                        // out at its NATURAL height (divider + the revealed
                        // band, bottom-anchored so the tray always rides the
                        // ribbon), so the reveal's own 200ms fold works
                        // verbatim with no reflow: the box and the strip
                        // retarget on the same frame and share one curve, so
                        // they stay in lockstep through every toggle. The hit
                        // wall behind the strip makes the covered tools inert:
                        // taps on the tray's background or the collapsed
                        // divider's empty zone land on the wall (opaque, no
                        // action) instead of the tools underneath, and the
                        // BlockSemantics around the whole overlay keeps those
                        // covered tools out of the accessibility tree while
                        // the tray is open. (The block rides INSIDE the
                        // positioned box — a Positioned cannot be wrapped by a
                        // render-owning widget on its way to the Stack.)
                        if (_mode == _Mode.editing)
                          AnimatedPositioned(
                          duration: _drawerDragging
                              ? Duration.zero
                              : (MediaQuery.of(context).disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200)),
                          curve: Curves.easeInOutCubic,
                          left: 0,
                          right: 0,
                          bottom: sheetAnchor,
                          height: overlayH,
                          child: BlockSemantics(
                            blocking: _filmOpen,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.bottomCenter,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: Stack(
                                  children: [
                                    // The hit wall: exactly the strip's own
                                    // live footprint (the Stack sizes to the
                                    // strip unit; the wall fills it) — a
                                    // deliberately inert opaque region. Taps
                                    // that miss every real control (the
                                    // chevron pocket, the rail, the disc)
                                    // stop here instead of triggering the
                                    // sheet's tools underneath.
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {},
                                      ),
                                    ),
                                    _filmstripUnit(context),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
