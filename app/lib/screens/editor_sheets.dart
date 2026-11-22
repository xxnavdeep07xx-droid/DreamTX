part of 'editor_screen.dart';

/// The live text-editing session for the selected text box.
class _TextSession {
  _TextSession({required this.controller, required this.focus});

  final RichEditingController controller;
  final FocusNode focus;

  /// One undo snapshot per session — typing and its formatting are a
  /// single undo group.
  bool undoPushed = false;

  /// Debounced engine commit while typing (keystrokes never round-trip).
  Timer? commitDebounce;
}

/// The typing toolbar's live view over the session — rebuilt on every
/// controller notification, so the active states track the caret.
class _TypingDocState extends TypingToolbarStateLike {
  _TypingDocState(this._session);

  final _TextSession _session;

  (int, int) get _sel {
    final s = _session.controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  RichRun? _runAtSelection(String? Function(RichRun) pick) {
    final (a, b) = _sel;
    if (a == b) {
      // A caret reads its typing source.
      final src = _session.controller.doc.typingSourceAt(a);
      return src == null ? null : (pick(src) != null ? src : null);
    }
    for (final r in _session.controller.doc.runs) {
      if (r.end <= r.start) continue;
      if (r.start < b && a < r.end) return r;
    }
    return null;
  }

  @override
  bool isFlagActive(String flag) {
    final (a, b) = _sel;
    return _session.controller.doc.isFlagActive(a, b, flag);
  }

  @override
  String? get color => _runAtSelection((r) => r.color)?.color;

  @override
  String? get highlight => _runAtSelection((r) => r.highlight)?.highlight;

  @override
  String? get align {
    final (a, b) = _sel;
    final caret = (a == b) ? a : b;
    return _session.controller.doc
        .effectiveParaAt(caret.clamp(0, _session.controller.doc.text.length))
        ?.align;
  }

  @override
  String? get list {
    final (a, b) = _sel;
    final caret = (a == b) ? a : b;
    return _session.controller.doc
        .effectiveParaAt(caret.clamp(0, _session.controller.doc.text.length))
        ?.list;
  }
}
