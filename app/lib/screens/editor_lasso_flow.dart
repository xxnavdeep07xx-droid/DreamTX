part of 'editor_screen.dart';

// ---------------------------------------------------------------------------
// Draw B — lasso select. The editor owns the selection SET (_lassoIds); the
// canvas draws the loop and the outlines, and reports a closed loop or a
// released drag. Every action on the selection is ONE batch: one _mutate,
// so one undo step — the same contract the eraser's sweep keeps.
// ---------------------------------------------------------------------------
extension _EditorLassoFlow on _EditorScreenState {
  /// The lasso selection, filtered to objects that still exist on the live
  /// slide (a deleted or slide-switched id drops out silently).
  Set<String> get _liveLassoIds {
    if (_lassoIds.isEmpty) return const {};
    final present = {for (final o in _objects) o['id']};
    return {..._lassoIds.where(present.contains)};
  }

  /// A closed loop (or a tap, with an empty polygon): select what the loop
  /// encloses, replacing the old selection.
  void _onLassoDone(List<Offset> loop) {
    if (loop.isEmpty) {
      if (_lassoIds.isNotEmpty) _setState(() => _lassoIds = {});
      return;
    }
    final hits = inkLassoHits(_objects, loop);
    _setState(() {
      _lassoIds = hits.toSet();
      _selectedObjectId = null;
    });
    if (hits.isEmpty) _toast('Nothing inside the loop');
  }

  /// A selection drag released: move every selected object by the same
  /// delta, in one batch.
  void _onLassoMoveEnd(Offset delta) {
    if (delta == Offset.zero) return;
    _updateLassoMembers(
      (o) => inkTranslated(o, delta.dx, delta.dy),
    );
  }

  /// Recolor the selection's outlines (strokes and scribbles; text boxes and
  /// fill-only shapes keep their own colors), in one batch.
  void _restyleLasso(String colorHex) {
    _updateLassoMembers((o) => inkRestyled(o, colorHex));
  }

  /// Delete the selection in one batch (the same chained delete path the
  /// eraser uses — one undo step), then forget the selection.
  void _deleteLasso() {
    final ids = _liveLassoIds.toList();
    if (ids.isEmpty) return;
    _onEraseHits(ids);
    _setState(() => _lassoIds = {});
  }

  void _clearLasso() {
    if (_lassoIds.isNotEmpty) _setState(() => _lassoIds = {});
  }

  /// The shared batch: [edit] runs over each selected object; objects it
  /// returns unchanged (the same instance) are skipped. Every change lands
  /// through one `_mutate`, so the whole batch is a single undo step.
  void _updateLassoMembers(Map<String, dynamic> Function(Map<String, dynamic>) edit) {
    final slideId = _slideId;
    final ids = _liveLassoIds;
    if (slideId == null || ids.isEmpty) return;
    Map deck = _deck;
    var changed = false;
    for (final o in _objects) {
      if (!ids.contains(o['id'])) continue;
      final next = edit(o);
      if (identical(next, o)) continue;
      final r = Bridge.command({
        'op': 'update_object',
        'deck': deck,
        'slide_id': slideId,
        'object_id': o['id'],
        'shape': next,
      });
      if (r['ok'] == true && r['deck'] is Map) {
        deck = r['deck'] as Map;
        changed = true;
      } else {
        _toast('Could not update: ${r['error']}');
        break;
      }
    }
    if (changed) _mutate(deck);
  }
}
