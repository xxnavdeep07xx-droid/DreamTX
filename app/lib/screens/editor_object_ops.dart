part of 'editor_screen.dart';

/// Object ops: gestures, z-order, grouping, clipboard, layers. Verbatim members of _EditorScreenState (the
/// one-library part split — see editor_screen.dart for the
/// class, its fields and the part map).

extension _EditorObjectOps on _EditorScreenState {
  void _objectGestureStart() {
    _undo.add(_copy());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void _liveObject(Map obj) {
    _setState(() => _replaceObjectLocal(obj));
  }

  void _replaceObjectLocal(Map obj) {
    final slideId = _slideId;
    if (slideId == null) return;
    for (final s in (_deck['slides'] as List? ?? const []).whereType<Map>()) {
      if (s['id'] != slideId) continue;
      final objs = s['objects'] as List?;
      if (objs == null) return;
      for (var i = 0; i < objs.length; i++) {
        if (objs[i] is Map && objs[i]['id'] == obj['id']) {
          objs[i] = obj;
          return;
        }
      }
    }
  }

  /// Gesture commit: undo was already pushed at gesture start.
  void _commitObject(Map obj) {
    final slideId = _slideId;
    if (slideId == null) return;
    final r = Bridge.command({
      'op': 'update_object',
      'deck': _deck,
      'slide_id': slideId,
      'object_id': obj['id'],
      'shape': obj
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _setDeck(r['deck'] as Map);
    } else {
      _toast('Could not save: ${r['error']}');
    }
  }

  /// Style change from the inspector: full mutate (own undo step).
  void _styleChanged(Map obj) {
    final slideId = _slideId;
    if (slideId == null) return;
    final r = Bridge.command({
      'op': 'update_object',
      'deck': _deck,
      'slide_id': slideId,
      'object_id': obj['id'],
      'shape': obj
    });
    if (r['ok'] == true && r['deck'] is Map) {
      _mutate(r['deck'] as Map);
    } else {
      _toast('Could not apply style: ${r['error']}');
    }
  }

  void _objOp(Map<String, dynamic> req,
      {void Function(Map newDeck)? after}) {
    final r = Bridge.command(req);
    if (r['ok'] == true && r['deck'] is Map) {
      final newDeck = r['deck'] as Map;
      _mutate(newDeck);
      after?.call(newDeck);
    } else {
      _toast('${r['error'] ?? 'operation failed'}');
    }
  }

  void _groupObjects(List<String> ids) => _objOp(
      {'op': 'group_objects', 'deck': _deck, 'slide_id': _slideId, 'ids': ids});

  void _ungroupObjects(List<String> ids) => _objOp({
        'op': 'ungroup_objects',
        'deck': _deck,
        'slide_id': _slideId,
        'ids': ids
      });

  void _alignObjects(String mode, List<String> ids) => _objOp({
        'op': 'align_objects',
        'deck': _deck,
        'slide_id': _slideId,
        'ids': ids,
        'mode': mode
      });

  void _booleanObjects(String mode, List<String> ids) {
    if (ids.length != 2) return;
    _objOp({
      'op': 'boolean_op',
      'deck': _deck,
      'slide_id': _slideId,
      'a': ids[0],
      'b': ids[1],
      'mode': mode
    });
  }

  void _saveComponent(List<String> ids, String name) => _objOp({
        'op': 'save_component',
        'deck': _deck,
        'slide_id': _slideId,
        'ids': ids,
        'name': name
      });

  void _placeComponent(String componentId) => _objOp({
        'op': 'place_component',
        'deck': _deck,
        'slide_id': _slideId,
        'component_id': componentId
      });

  void _syncComponent(String objectId) {
    if (objectId.isEmpty) return;
    _objOp({
      'op': 'update_component',
      'deck': _deck,
      'slide_id': _slideId,
      'object_id': objectId
    });
  }

  void _reorderObject(String id, int dir) {
    final objs = _objects;
    final idx = objs.indexWhere((o) => o['id'] == id);
    if (idx < 0) return;
    final to = (idx + dir).clamp(0, objs.length - 1);
    _objOp({
      'op': 'move_object_z',
      'deck': _deck,
      'slide_id': _slideId,
      'object_id': id,
      'to_index': to
    });
  }

  void _toggleObjectLock(String id) {
    for (final o in _objects) {
      if (o['id'] == id) {
        final updated = Map<String, dynamic>.from(o);
        updated['locked'] = !(updated['locked'] == true);
        _styleChanged(updated);
        return;
      }
    }
  }

  void _deleteObject(String id) => _objOp({
        'op': 'delete_object',
        'deck': _deck,
        'slide_id': _slideId,
        'object_id': id
      }, after: (newDeck) => _pruneOrphanedResources(newDeck));

  /// Deletes leave resource files orphaned on disk when nothing references
  /// them anymore (an image/media object deleted, or a whole slide). The
  /// deck's file is the reference graph — after a real deletion (never
  /// after undo/redo: undo resurrects objects and would need the files
  /// back), sweep the deck scope's assets that no object references.
  /// Brand resources are shared by every deck — never swept here.
  Future<void> _pruneOrphanedResources(Map newDeck) async {
    try {
      final referenced = <String>{};
      for (final slide in ((newDeck['slides'] as List?) ?? const [])
          .whereType<Map>()) {
        for (final obj in ((slide['objects'] as List?) ?? const [])
            .whereType<Map>()) {
          final content = obj['content'];
          if (content is! Map) continue;
          final kind = content['kind'];
          if (kind != 'image' && kind != 'media') continue;
          if (content['brand'] == true) continue; // brand scope: shared
          final rid = content['resource_id']?.toString();
          if (rid != null && rid.isNotEmpty) referenced.add(rid);
        }
      }
      final deckId = (newDeck['id'] ?? _deck['id'] ?? '').toString();
      final store = await ResourceStore.open();
      final items = await store.list(brand: false, deckId: deckId);
      for (final e in items) {
        final id = e['id']?.toString();
        if (id == null || referenced.contains(id)) continue;
        // Not referenced anywhere in the deck anymore: sweep it (the
        // object that owned it is gone — undo restores its own copy only
        // if the deck map comes back, and the resource store keeps the
        // file until the moment it is truly unreferenced).
        //
        // UNLESS the undo stack still knows it: a pending undo WILL
        // resurrect the object, and it should resurrect its asset too.
        final inUndoOrRedo = _undo.any((d) => _deckReferences(d, id)) ||
            _redo.any((d) => _deckReferences(d, id));
        if (inUndoOrRedo) continue;
        await store.remove(brand: false, deckId: deckId, id: id);
      }
    } catch (_) {
      // A failed sweep is noise on disk, never a failed delete.
    }
  }

  /// Whether a deck snapshot still references resource [id].
  bool _deckReferences(Map deck, String id) {
    for (final slide in ((deck['slides'] as List?) ?? const [])
        .whereType<Map>()) {
      for (final obj in ((slide['objects'] as List?) ?? const [])
          .whereType<Map>()) {
        final content = obj['content'];
        if (content is! Map) continue;
        if (content['brand'] == true) continue;
        if (content['resource_id']?.toString() == id) return true;
      }
    }
    return false;
  }

  void _editStyleOf(String id) {
    for (final o in _objects) {
      if (o['id'] == id) {
        showInspector(context, object: o, onChange: _styleChanged);
        return;
      }
    }
  }

  void _duplicateObject(String id) {
    final objs = _objects;
    final idx = objs.indexWhere((o) => o['id'] == id);
    if (idx < 0) return;
    final copy = Map<String, dynamic>.from(objs[idx]);
    final newId = _newObjectId();
    copy['id'] = newId;
    copy['x'] = ((objs[idx]['x'] as num?)?.toDouble() ?? 0) + 24;
    copy['y'] = ((objs[idx]['y'] as num?)?.toDouble() ?? 0) + 24;
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': _slideId,
      'shape': copy
    });
    if (r['ok'] != true || r['deck'] is! Map) {
      _toast('Could not duplicate: ${r['error']}');
      return;
    }
    final r2 = Bridge.command({
      'op': 'move_object_z',
      'deck': r['deck'],
      'slide_id': _slideId,
      'object_id': newId,
      'to_index': (idx + 1).clamp(0, objs.length),
    });
    if (r2['ok'] == true && r2['deck'] is Map) {
      _mutate(r2['deck'] as Map);
    } else {
      _mutate(r['deck'] as Map);
    }
    _setState(() => _selectedObjectId = newId);
  }

  // ---- long-press object actions + the clipboards (Home, redistributed) ---
  //
  // The long-press is the mobile context menu: an object opens its action
  // sheet (copy / duplicate / the format painter / delete — the layers
  // sheet keeps the deep ops), an empty-canvas long-press pastes the
  // object clipboard at the pressed point. The clipboards live on the
  // editor state, not the OS clipboard: deck objects are JSON documents,
  // not text, and they must survive every deck edit short of a deck
  // switch.

  /// Long-press on an object: make it the selection (the panel shows the
  /// target), then pop the actions sheet. Selection happens through the
  /// prepare path, NOT `_onObjectSelected` — a long-press must never read
  /// as the tap's second tap, so holding the already-selected text box
  /// opens this menu and the keyboard stays down.
  Future<void> _objectActions(Map<String, dynamic> obj) async {
    final id = obj['id'] as String;
    if (_selectedObjectId != id) {
      _prepareSelectionFor(id);
      if (_mode == _Mode.editing && _navTab != _NavTab.insert) {
        _setNavTab(_NavTab.insert);
      }
    }
    final action = await dreamSheet<String>(
      context,
      builder: (context) => _ObjectActionsSheet(
        canApplyStyle: _styleClipboard != null,
        linkText: linkDescription(linkOf(obj), _slides, _slideTitle),
        isChart: ObjectContent.isChart(obj),
      ),
    );
    switch (action) {
      case 'copy':
        _copyObject(obj);
      case 'dup':
        _duplicateObject(id);
      case 'copyStyle':
        _copyStyle(obj);
      case 'applyStyle':
        _applyStyle(obj);
      case 'link':
        _editLinkOf(id);
      case 'chart':
        _editChartOf(id);
      case 'del':
        _deleteObject(id);
    }
  }

  /// Object actions → Edit chart: change the chart's data and style, then
  /// write the new content through the style path (one undo step).
  void _editChartOf(String id) {
    Map<String, dynamic>? obj;
    for (final o in _objects) {
      if (o['id'] == id) obj = o;
    }
    if (obj == null) return;
    final current = obj;
    final data = chartDataOf(ObjectContent.of(current));
    if (data == null) return;
    dreamSheet<ChartData>(
      context,
      builder: (context) => ChartSheet(data: data),
    ).then((picked) {
      if (picked == null) return;
      final updated = Map<String, dynamic>.from(current);
      updated['content'] = ObjectContent.chart(picked);
      _styleChanged(updated);
    });
  }

  /// Object actions → Link: pick none, a web address, or a slide, then
  /// write it through the style path (one undo step).
  void _editLinkOf(String id) {
    Map<String, dynamic>? obj;
    for (final o in _objects) {
      if (o['id'] == id) obj = o;
    }
    if (obj == null) return;
    final current = obj;
    dreamSheet<LinkEdit>(
      context,
      builder: (context) => LinkSheet(
        current: linkOf(current),
        slides: _slides,
        titleOf: _slideTitle,
      ),
    ).then((picked) {
      if (picked == null) return;
      final updated = Map<String, dynamic>.from(current);
      if (picked.link == null) {
        updated.remove('link');
      } else {
        updated['link'] = picked.link;
      }
      _styleChanged(updated);
    });
  }

  /// Long-press on empty canvas: paste the clipboard with its top-left at
  /// the press, clamped inside the slide. No clipboard, no-op — a stray
  /// hold on the canvas must never punish the user with a toast.
  void _pasteObjectAt(Offset design) {
    final clip = _objectClipboard;
    final slideId = _slideId;
    if (clip == null || slideId == null) return;
    final copy = Map<String, dynamic>.from(clip);
    final newId = _newObjectId();
    copy['id'] = newId;
    final w = (clip['w'] as num?)?.toDouble() ?? 0.0;
    final h = (clip['h'] as num?)?.toDouble() ?? 0.0;
    copy['x'] = design.dx.clamp(0.0, math.max(0.0, _designDims.$1 - w));
    copy['y'] = design.dy.clamp(0.0, math.max(0.0, _designDims.$2 - h));
    final r = Bridge.command({
      'op': 'add_object',
      'deck': _deck,
      'slide_id': slideId,
      'shape': copy
    });
    if (r['ok'] != true || r['deck'] is! Map) {
      _toast('Could not paste: ${r['error']}');
      return;
    }
    _mutate(r['deck'] as Map);
    _setState(() => _selectedObjectId = newId);
  }

  /// Copy for the object clipboard. The JSON round-trip is the point, not
  /// an implementation detail: it guarantees the clipboard is exactly what
  /// the engine would serialize, and a non-round-trippable object cannot
  /// be pasted back anyway — the copy would be a lie, so it stays null.
  void _copyObject(Map<String, dynamic> obj) {
    try {
      _objectClipboard =
          jsonDecode(jsonEncode(obj)) as Map<String, dynamic>;
      _toast('Copied — long-press the canvas to paste');
    } catch (_) {
      _objectClipboard = null;
    }
  }

  /// Format painter, pickup half: grab the universal chrome fields.
  void _copyStyle(Map<String, dynamic> obj) {
    _styleClipboard = {
      for (final k in const ['fill', 'stroke', 'opacity', 'effects'])
        if (obj.containsKey(k)) k: obj[k],
    };
    _toast('Style copied');
  }

  /// Format painter, apply half: the picked chrome onto the pressed
  /// object. One `update_object` through [_styleChanged] = one undo step.
  void _applyStyle(Map<String, dynamic> obj) {
    final style = _styleClipboard;
    if (style == null || style.isEmpty) return;
    final updated = Map<String, dynamic>.from(obj);
    updated.addAll(style);
    _styleChanged(updated);
  }

  void _reflectObject(String id) {
    for (final o in _objects) {
      if (o['id'] != id) continue;
      final copy = Map<String, dynamic>.from(o);
      final y = (o['y'] as num?)?.toDouble() ?? 0;
      final h = (o['h'] as num?)?.toDouble() ?? 0;
      final op = (o['opacity'] as num?)?.toDouble() ?? 1;
      final newId = _newObjectId();
      copy['id'] = newId;
      copy['y'] = y + h + 10 + h;
      copy['opacity'] = (op * 0.35).clamp(0.05, 0.6);
      copy['effects'] = {};
      final r = Bridge.command({
        'op': 'add_object',
        'deck': _deck,
        'slide_id': _slideId,
        'shape': copy
      });
      if (r['ok'] != true || r['deck'] is! Map) {
        _toast('Could not add reflection: ${r['error']}');
        return;
      }
      final r2 = Bridge.command({
        'op': 'group_objects',
        'deck': r['deck'],
        'slide_id': _slideId,
        'ids': [id, newId]
      });
      if (r2['ok'] == true && r2['deck'] is Map) {
        _mutate(r2['deck'] as Map);
      } else {
        _mutate(r['deck'] as Map);
      }
      return;
    }
  }

  void _showLayers() {
    if (_slides.isEmpty) return;
    showLayersSheet(
      context,
      objects: _objects,
      presets: _objectPresets,
      deck: _deck,
      onGroup: _groupObjects,
      onUngroup: _ungroupObjects,
      onAlign: _alignObjects,
      onBoolean: _booleanObjects,
      onSaveComponent: _saveComponent,
      onPlaceComponent: _placeComponent,
      onSyncComponent: _syncComponent,
      onReorder: _reorderObject,
      onToggleLock: _toggleObjectLock,
      onEditStyle: _editStyleOf,
      onDelete: _deleteObject,
      onDuplicate: _duplicateObject,
      onReflect: _reflectObject,
    );
  }

  // ---- quick single-field edit (tap text on the canvas) ----------------------

  Future<void> _editText(String key) async {
    final slide = _slides[_index];
    final content =
        Map<String, dynamic>.from(slide['content'] ?? <String, dynamic>{});
    final current = _resolveKey(content, key)?.toString() ?? '';
    final text = await dreamInputDialog(
      context,
      title: 'Edit — ${key.replaceAll('.', ' ')}',
      initial: current,
      confirmLabel: 'Save',
      multiline: true,
    );
    if (text == null) return;
    final updated = _applyKey(content, key, text);
    _updateSlide(slide, slide['archetype'].toString(), updated);
  }

  /// Resolve a dotted path like `stats.0.value` inside the content map.
  dynamic _resolveKey(Map<String, dynamic> map, String path) {
    dynamic cur = map;
    for (final part in path.split('.')) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else if (cur is List) {
        final i = int.tryParse(part);
        if (i != null && i >= 0 && i < cur.length) {
          cur = cur[i];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return cur;
  }

  /// Set a dotted path inside a copy of the content map, returning the copy.
  Map<String, dynamic> _applyKey(
      Map<String, dynamic> content, String key, String value) {
    final updated = Map<String, dynamic>.from(content);
    final parts = key.split('.');
    dynamic cur = updated;
    for (var i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (cur is Map) {
        final next = cur[part];
        if (next is! Map && next is! List) {
          final nextIsList = int.tryParse(parts[i + 1]) != null;
          cur[part] = nextIsList ? <dynamic>[] : <String, dynamic>{};
        }
        cur = cur[part];
      } else if (cur is List) {
        final idx = int.tryParse(part);
        if (idx != null && idx >= 0 && idx < cur.length) {
          cur = cur[idx];
        }
      }
    }
    if (cur is Map) {
      cur[parts.last] = value;
    } else if (cur is List) {
      final idx = int.tryParse(parts.last);
      if (idx != null && idx >= 0 && idx < cur.length) cur[idx] = value;
    }
    return updated;
  }

}
