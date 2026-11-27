part of 'editor_screen.dart';

/// Selection, the live text session, and the typing toolbar. Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorSessionFlow on _EditorScreenState {
  void _addObject(String preset) {
    final slideId = _slideId;
    if (slideId == null) return;
    final open = preset == 'line' || preset == 'wave' || preset == 'zigzag';
    var w = 240.0;
    var h = 140.0;
    if (open) {
      w = 320.0;
      h = preset == 'line' ? 0.0 : (preset == 'wave' ? 80.0 : 60.0);
    }
    final n = _objects.length;
    // New shapes center on the deck's actual frame — 4:3 and 1:1 decks drop
    // them on-frame, not at the classic 1280-wide midpoint.
    final (dw, dh) = deckDimsOf(_deck['aspect']?.toString());
    final shape = <String, dynamic>{
      'id': _newObjectId(),
      'preset': preset,
      'x': (dw - w) / 2 + (n % 5) * 24.0,
      'y': (dh - h) / 2 + (n % 5) * 16.0,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': 1.0,
      'locked': false,
      'fill': open ? {'type': 'none'} : {'type': 'solid', 'color': 'FFFFFF'},
      'stroke': open
          ? {
              'color': 'D03028',
              'width': 3.0,
              'dash': 'solid',
              'start_arrow': 'none',
              'end_arrow': 'none'
            }
          : {
              'color': '17181A',
              'width': 1.5,
              'dash': 'solid',
              'start_arrow': 'none',
              'end_arrow': 'none'
            },
      'effects': {},
      'closed': true,
    };
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': slideId,
      'shape': shape
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
      _prepareSelectionFor(shape['id'] as String?);
    } else {
      _toast('Could not add shape: ${r['error']}');
    }
  }

  /// The eraser's sweep (or tap) finished: delete every marked
  /// scribble in ONE chained pass — deck -> deck -> deck — so the whole
  /// sweep is a single undo step (the deck snapshot lands in the stack
  /// once, after the last delete; undo restores every stroke at once).
  /// The ids came from the layer's hit-test, which only ever marks
  /// scribble-signature path objects — content is immune by construction.
  void _onEraseHits(List<String> ids) {
    if (ids.isEmpty) return;
    final slideId = _slideId;
    if (slideId == null) return;
    Map? deck = _deck;
    var changed = false;
    for (final id in ids) {
      final r = Bridge.command({
        'op': 'delete_object',
        'deck': deck,
        'slide_id': slideId,
        'object_id': id,
      });
      if (r['ok'] == true && r['deck'] is Map) {
        deck = r['deck'] as Map;
        changed = true;
      } else {
        _toast('Could not erase: ${r['error']}');
        break;
      }
    }
    if (changed) _mutate(deck);
  }

  /// "Erase all ink on this slide": every scribble on the current slide
  /// goes in ONE batch through [_onEraseHits] — one undo step, content
  /// (text, images, shapes, tables) and locked strokes untouched.
  void _clearAllInk() {
    final ids = inkScribbleIds(_objects);
    if (ids.isEmpty) {
      _toast('No ink on this slide');
      return;
    }
    _onEraseHits(ids);
    _toast('Cleared ${ids.length} stroke${ids.length == 1 ? '' : 's'}');
  }

  /// Draw E: replay the slide's ink in draw order. Display only — nothing
  /// in the deck changes and nothing is exported.
  void _replayInk() {
    final count = inkScribbleIds(_objects).length;
    if (count == 0) {
      _toast('No ink on this slide');
      return;
    }
    _inkReplay.duration = inkReplayDuration(count);
    _inkReplay.forward(from: 0);
  }

  /// The Draw toolbox's one mutation point (the row's onChanged): state
  /// in, state out. Arming through a tool tap clears the selection (draw
  /// focus — the armed tool consumes canvas taps); style edits and band
  /// toggles never touch anything but the toolbox.
  void _setDrawToolbox(_DrawToolboxState next) {
    _setState(() {
      final nowArmed = next.armed && !_drawToolbox.armed;
      _drawToolbox = next;
      if (nowArmed) _selectedObjectId = null;
      // Leaving the lasso (or Draw) ends its selection.
      if (!next.armed || next.tool != InkTool.lasso) _lassoIds = {};
    });
  }

  /// Ink → shape (Draw D): the recognized shape as an object, styled exactly
  /// like the stroke it replaces. Null = keep the freehand path. A line
  /// becomes a two-point path (the editor's own path model), so it exports
  /// and erases like any scribble.
  Map<String, dynamic>? _recognizedShapeFor(
    InkShapeKind kind,
    List<Offset> pts,
    InkStyle style,
  ) {
    if (kind == InkShapeKind.none || pts.length < 2) return null;
    var minx = pts.first.dx;
    var miny = pts.first.dy;
    var maxx = minx;
    var maxy = miny;
    for (final p in pts) {
      minx = math.min(minx, p.dx);
      miny = math.min(miny, p.dy);
      maxx = math.max(maxx, p.dx);
      maxy = math.max(maxy, p.dy);
    }
    final w = math.max(maxx - minx, 1.0);
    final h = math.max(maxy - miny, 1.0);
    final stroke = <String, dynamic>{
      'color': style.colorHex,
      'width': style.width,
      'dash': 'solid',
      'start_arrow': 'none',
      'end_arrow': 'none',
    };
    if (kind == InkShapeKind.line) {
      final ends = [pts.first, pts.last];
      return <String, dynamic>{
        'id': _newObjectId(),
        'preset': 'path',
        'x': minx,
        'y': miny,
        'w': w,
        'h': h,
        'rotation': 0.0,
        'opacity': style.opacity,
        'locked': false,
        'fill': {'type': 'none'},
        'stroke': stroke,
        'effects': {},
        'points': [
          for (final p in ends)
            {
              'x': ((p.dx - minx) / w).clamp(0.0, 1.0).toDouble(),
              'y': ((p.dy - miny) / h).clamp(0.0, 1.0).toDouble(),
            },
        ],
        'closed': false,
      };
    }
    final preset = switch (kind) {
      InkShapeKind.rect => 'rect',
      InkShapeKind.ellipse => 'ellipse',
      _ => 'triangle',
    };
    return <String, dynamic>{
      'id': _newObjectId(),
      'preset': preset,
      'x': minx,
      'y': miny,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': style.opacity,
      'locked': false,
      'fill': {'type': 'none'},
      'stroke': stroke,
      'effects': {},
      'closed': true,
    };
  }

  /// A stroke finished: the capture pipeline's smoothed design-space
  /// polyline ([inkCapture] — the same list the live preview painted its
  /// last frame with) lands as a plain `path` object in the deck's model,
  /// styled exactly as the preview showed it. NOT auto-selected: drawing
  /// focus — the selection chrome stays away while the tool is armed, and
  /// the stroke is selectable the moment drawing ends.
  void _onStrokeDone(List<Offset> pts) {
    final slideId = _slideId;
    if (slideId == null || pts.length < 2) return;
    final style =
        _drawToolbox.inkStyleFor(defaultPenHex: _dnaAccentHex);
    var minx = pts.first.dx;
    var miny = pts.first.dy;
    var maxx = minx;
    var maxy = miny;
    for (final p in pts) {
      minx = math.min(minx, p.dx);
      miny = math.min(miny, p.dy);
      maxx = math.max(maxx, p.dx);
      maxy = math.max(maxy, p.dy);
    }
    final w = math.max(maxx - minx, 1.0);
    final h = math.max(maxy - miny, 1.0);
    final norm = [
      for (final p in pts)
        {
          'x': ((p.dx - minx) / w).clamp(0.0, 1.0).toDouble(),
          'y': ((p.dy - miny) / h).clamp(0.0, 1.0).toDouble()
        },
    ];
    // Ink → shape: when the toggle is on and the stroke reads as a shape,
    // that shape replaces the freehand path — one add, one undo step.
    final shape = _recognizedShapeFor(
          _drawToolbox.inkToShape && _drawToolbox.tool == InkTool.pen
              ? inkRecognizeShape(pts)
              : InkShapeKind.none,
          pts,
          style,
        ) ??
        <String, dynamic>{
      'id': _newObjectId(),
      'preset': 'path',
      'x': minx,
      'y': miny,
      'w': w,
      'h': h,
      'rotation': 0.0,
      'opacity': style.opacity,
      'locked': false,
      'fill': {'type': 'none'},
      'stroke': {
        'color': style.colorHex,
        'width': style.width,
        'dash': 'solid',
        'start_arrow': 'none',
        'end_arrow': 'none'
      },
      'effects': {},
      'points': norm,
      'closed': false,
    };
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': slideId,
      'shape': shape
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
    }
  }

  // ---- object selection + the text editing session ---------------------------

  /// Selection from the canvas layer (tap): first tap selects and SHOWS
  /// the object's panel (the Insert sheet rises with it); tapping the SAME
  /// text box again re-enters typing.
  void _onObjectSelected(String? id) {
    if (id == null) {
      _flushTextSession();
      _disposeTextSession();
      _setState(() => _selectedObjectId = null);
      return;
    }
    if (id == _selectedObjectId) {
      final obj = _selectedObject;
      if (obj != null && ObjectContent.isText(obj)) {
        _beginTyping();
        return;
      }
    }
    _prepareSelectionFor(id);
    // The panel IS the selection's face: selecting a canvas object opens
    // the Insert sheet (rising from behind the navbar) whichever editing
    // tab was active — Draw just as Insert — while a read-only deck never
    // gets here (the stage is non-interactive in viewing).
    // The Animations tab is the exception: IT is the selection's face
    // there (the entrance chips read the selection), so a pick on that
    // tab keeps the tab and its row instead of swapping to Insert.
    if (_mode == _Mode.editing &&
        _navTab != _NavTab.insert &&
        _navTab != _NavTab.animations) {
      _setNavTab(_NavTab.insert);
    }
  }

  /// Point the editor's selection at [id]: swap the text session (a text box
  /// gets a live doc + controller; anything else ends it), reset the
  /// per-selection style undo bookkeeping.
  void _prepareSelectionFor(String? id) {
    _flushTextSession();
    _disposeTextSession();
    _endTyping();
    _styleUndoPushed = false;
    _objectCommitDebounce?.cancel();
    _objectCommitDebounce = null;
    _setState(() {
      _selectedObjectId = id;
      if (id == null) return;
      final obj = _selectedObject;
      if (obj != null && ObjectContent.isText(obj)) {
        _textSession = _TextSession(
          controller: RichEditingController(
            doc: ObjectContent.textDocOf(obj) ?? RichDoc(),
          ),
          focus: FocusNode(),
        );
        _wireTextSession();
      }
    });
  }

  void _wireTextSession() {
    final s = _textSession;
    if (s == null) return;
    // Text changes: local deck update + debounced engine commit; one undo
    // snapshot per session (typing is one undo group, like the pros).
    s.controller.addListener(_onSessionTextChanged);
    // The typing state IS the field's focus.
    s.focus.addListener(_onSessionFocusChanged);
  }

  void _onSessionTextChanged() {
    final s = _textSession;
    if (s == null) return;
    // A programmatic resync (undo/redo) is not a user edit: no undo
    // snapshot, no redo wipe, no commit — just the new state landing.
    if (_suppressSessionChange) return;
    if (!s.undoPushed) {
      s.undoPushed = true;
      _undo.add(_copy());
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    _syncSessionDocIntoDeck();
    _scheduleTextCommit();
    if (mounted) _setState(() {});
  }

  /// The session's doc, written back into the LOCAL deck map (the debounced
  /// commit takes it across the engine + storage).
  void _syncSessionDocIntoDeck() {
    final s = _textSession;
    if (s == null) return;
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isText(obj)) return;
    _replaceObjectLocal(ObjectContent.withTextDoc(obj, s.controller.doc));
  }

  void _scheduleTextCommit() {
    final s = _textSession;
    if (s == null) return;
    s.commitDebounce?.cancel();
    s.commitDebounce = Timer(const Duration(milliseconds: 450), () {
      _flushTextSession();
    });
  }

  /// Commit the live text session to the engine now (persist + layout).
  void _flushTextSession() {
    final s = _textSession;
    if (s == null) return;
    s.commitDebounce?.cancel();
    s.commitDebounce = null;
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isText(obj)) return;
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
  }

  void _disposeTextSession() {
    final s = _textSession;
    _textSession = null;
    if (s == null) return;
    s.commitDebounce?.cancel();
    s.controller.removeListener(_onSessionTextChanged);
    s.focus.removeListener(_onSessionFocusChanged);
    s.controller.dispose();
    s.focus.dispose();
  }

  /// After an undo/redo swap of the whole deck, the live session must
  /// re-read its object (the box may be gone or carry older text). The
  /// resync runs under [_suppressSessionChange]: writing `controller.text`
  /// notifies the change listener synchronously, and an unsuppressed
  /// notification would push the PRE-swap deck as an "edit" (a fake undo
  /// step) and clear `_redo` — corrupting the very history being walked.
  void _resyncTextSession() {
    final s = _textSession;
    if (s == null) return;
    final obj = _selectedObject;
    if (obj == null || !ObjectContent.isText(obj)) {
      _disposeTextSession();
      return;
    }
    final fresh = ObjectContent.textDocOf(obj) ?? RichDoc();
    _suppressSessionChange = true;
    try {
      s.controller.doc = fresh;
      s.controller.text = fresh.text;
      s.controller.refresh();
    } finally {
      _suppressSessionChange = false;
      s.undoPushed = false;
    }
  }

  void _beginTyping() {
    final s = _textSession;
    if (s == null) return;
    // The field mounts focused (autofocus) — the focus listener below
    // flips the typing state, hides the sheet, shows the toolbar.
    _setState(() {
      _typing = true;
      // The sheet (Files OR Insert — whichever is the active tab) stands
      // down while the keyboard owns the bottom of the screen: it slides
      // out behind the navbar over the same 200ms family a tab switch
      // uses, never a snap. The flag remembers WHO closed it so ending
      // the typing state can rise it back.
      _sheetHiddenForTyping = _mode == _Mode.editing && _isSheetTab(_navTab);
      if (_sheetHiddenForTyping) {
        if (_sheetEntering) {
          // Never rose: no pixels were ever shown — nothing to animate.
          _sheetEntering = false;
          _sheetClosing = false;
          _drawerExtent = null;
        } else if (!_sheetClosing) {
          _sheetClosing = true;
          _drawerExtent ??= _sheetLiveHeightFor(); // hold the height it stands at
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_typing) return;
      s.focus.requestFocus();
    });
  }

  void _endTyping() {
    final s = _textSession;
    if (_typing || _typingToolbarEntry != null) {
      s?.focus.unfocus();
    }
    _setState(() {
      _typing = false;
      // If the typing state was what stood the sheet down (the keyboard
      // covered it), ending it rises the sheet back through the same
      // entrance a tab arrival uses — slide up from behind the navbar,
      // frozen strip footprint, post-frame flip into place. Only when the
      // sheet's tab is still the active one (a tab switch's own exit
      // machinery owns the layer otherwise).
      if (_sheetHiddenForTyping) {
        _sheetHiddenForTyping = false;
        if (_mode == _Mode.editing && _isSheetTab(_navTab)) {
          final resumingExit = _sheetClosing;
          _sheetClosing = false;
          _sheetEntering = !resumingExit;
          _drawerExtent = null;
          _frozenStripFootprint = _liveStripFlowHeight();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _typing ||
                !_sheetEntering ||
                !_isSheetTab(_navTab) ||
                _mode != _Mode.editing ||
                _drawerDragging) {
              return;
            }
            _setState(() => _sheetEntering = false);
          });
        }
      }
    });
    _removeTypingToolbar();
  }

  void _onSessionFocusChanged() {
    final s = _textSession;
    if (s == null || !mounted) return;
    if (s.focus.hasFocus) {
      _setState(() => _typing = true);
      _showTypingToolbar();
    } else {
      // Keyboard closed with the text box still selected: the sheet (and
      // its full panel) returns — capture the strip's footprint first, in
      // flow-order, so the spacer is honest through the reparent.
      _removeTypingToolbar();
      final footprint = _liveStripFlowHeight();
      _setState(() {
        _typing = false;
        _frozenStripFootprint = footprint;
        // An EXTERNAL focus loss (this listener firing without
        // [_endTyping] — the system took the focus, another field claimed
        // it) must clear the typing state's sheet-down flag HERE too:
        // otherwise the sheet that stood down for the keyboard stays down
        // and later SNAPS into place instead of animating through the
        // entrance now. Same machinery [_endTyping] runs — only once ever,
        // because both paths clear the flag before the other checks it.
        if (_sheetHiddenForTyping) {
          _sheetHiddenForTyping = false;
          if (_mode == _Mode.editing && _isSheetTab(_navTab)) {
            final resumingExit = _sheetClosing;
            _sheetClosing = false;
            _sheetEntering = !resumingExit;
            _drawerExtent = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted ||
                  _typing ||
                  !_sheetEntering ||
                  !_isSheetTab(_navTab) ||
                  _mode != _Mode.editing ||
                  _drawerDragging) {
                return;
              }
              _setState(() => _sheetEntering = false);
            });
          }
        }
      });
      _flushTextSession();
    }
  }

  void _showTypingToolbar() {
    if (_typingToolbarEntry != null) return;
    final s = _textSession;
    if (s == null) return;
    _typingToolbarEntry = OverlayEntry(
      builder: (overlayContext) {
        // The root overlay sees the REAL viewport: the toolbar rides the
        // keyboard in both inset-delivery and window-resize mode.
        final bottom = MediaQuery.viewInsetsOf(overlayContext).bottom;
        return Positioned(
          left: 0,
          right: 0,
          // Anchored to the SCREEN's bottom, not to the inset's top: the
          // toolbar sits exactly where it always did (its bottom edge at
          // the inset), and everything below it — the IME's whole reserved
          // region — is filled with the toolbar's own surface. Themed
          // keyboards reserve more window than they paint (their top band
          // is transparent), which used to show the slide peeking through
          // that band between the toolbar and the first key row; the
          // backdrop makes the toolbar read flush against the keys
          // wherever the keyboard actually starts painting (under the
          // opaque keys the backdrop is simply covered).
          //
          // NO SafeArea here, deliberately: the overlay already owns the
          // whole bottom — the backdrop carries the keyboard region and
          // the toolbar rides flush on its top — so a system-bar inset
          // applied by SafeArea would double-pad BELOW the keyboard on
          // devices that report one while the IME is up. The one inset
          // that matters (the keyboard's own) is the backdrop's height.
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: s.controller,
                builder: (context, _) => TypingToolbar(
                  docState: _TypingDocState(s),
                  palette: _deckPalette,
                  onToggle: (flag) => _docMutate(
                      (doc, a, b) => doc.toggleFlag(a, b, flag)),
                  onColor: (hex) =>
                      _docMutate((doc, a, b) => doc.setAttr(a, b, 'color', hex)),
                  onHighlight: (hex) => _docMutate(
                      (doc, a, b) => doc.setAttr(a, b, 'highlight', hex)),
                  onAlign: (v) => _docMutate(
                      (doc, a, b) => doc.setParagraphAttr(a, b, 'align', v)),
                  onList: (k) => _docMutate((doc, a, b) => doc.toggleList(a, b, k)),
                  onExpand: _endTyping,
                ),
              ),
              if (bottom > 0)
                SizedBox(
                  key: const ValueKey('typing_toolbar_backdrop'),
                  width: double.infinity,
                  height: bottom,
                  child: const ColoredBox(color: kElevated),
                ),
            ],
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_typingToolbarEntry!);
  }

  void _removeTypingToolbar() {
    _typingToolbarEntry?.remove();
    _typingToolbarEntry = null;
  }

  /// One mutator for every toolbar/panel text action: target the current
  /// selection (or caret), apply, refresh the field, commit live.
  void _docMutate(void Function(RichDoc doc, int a, int b) fn) {
    final s = _textSession;
    if (s == null) return;
    final sel = s.controller.effectiveSelection;
    fn(s.controller.doc, sel.baseOffset, sel.extentOffset);
    _onSessionTextChanged();
    s.controller.refresh();
  }

  // ---- live object style edits (the panel) -------------------------------------

}
