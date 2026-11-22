import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/color_utils.dart';

/// The rich text model for a text-box object — the Dart mirror of the
/// engine's `TextDoc` JSON. One data structure serves three consumers:
///
///  * **the model** — plain `text` (paragraphs separated by `\n`) is the
///    caret/selection coordinate space; `runs` are character-format marks
///    over that string; `paras` are paragraph styles anchored at paragraph
///    starts;
///  * **the edit field** — a [RichEditingController] whose
///    `buildTextSpan` decorates the plain text from the marks, so the
///    native caret, selection and IME stay real;
///  * **the canvas** — the same span builder feeds the box's painter.
///
/// Text edits arrive as `old text -> new text` from the controller; the
/// controller listener maps that onto [_replaceRange], which shifts and
/// trims every mark exactly like a text editor does: typing inside a
/// formatted run extends it, a replaced selection inherits the style of
/// what it replaced, deleted marks die with their text, and a zero-width
/// mark at the caret is the "format what I type next" carrier.
class RichDoc {
  RichDoc({this.text = '', List<RichRun>? runs, List<RichPara>? paras})
      : runs = runs ?? [],
        paras = paras ?? [];

  /// Plain text; `\n` separates paragraphs. Offsets everywhere are UTF-16
  /// code units — the same space as a Flutter [TextSelection].
  String text;

  /// Character-format marks over `text`, sorted, disjoint, non-overlapping.
  final List<RichRun> runs;

  /// Paragraph styles, anchored at paragraph starts (sorted by `start`).
  /// A paragraph without an anchor (or before the first anchor) uses the
  /// defaults.
  final List<RichPara> paras;

  /// 'top' | 'middle' | 'bottom' — vertical alignment of text in the box.
  String valign = 'top';

  /// 'none' | 'shrink' — shrink text on overflow, or let it overflow.
  String autofit = 'none';

  // ---- JSON round-trip (the engine's TextDoc schema) ------------------------

  factory RichDoc.fromJson(Map<String, dynamic>? json) {
    if (json == null) return RichDoc();
    final d = RichDoc(
      text: (json['text'] ?? '').toString(),
      runs: [
        for (final r in (json['runs'] as List? ?? const []))
          if (r is Map) RichRun.fromJson(Map<String, dynamic>.from(r))
      ],
      paras: [
        for (final p in (json['paras'] as List? ?? const []))
          if (p is Map) RichPara.fromJson(Map<String, dynamic>.from(p))
      ],
    );
    d.valign = (json['valign'] ?? 'top').toString();
    d.autofit = (json['autofit'] ?? 'none').toString();
    return d;
  }

  Map<String, dynamic> toJson() {
    final pruned = _prunedRuns();
    return {
      'text': text,
      if (pruned.isNotEmpty)
        'runs': [
          for (final r in pruned)
            {
              'start': r.start,
              'end': r.end,
              ...r.toJsonAttrs(),
            }
        ],
      if (paras.isNotEmpty)
        'paras': [
          for (final p in paras)
            {
              'start': p.start,
              ...p.toJsonAttrs(),
            }
        ],
      if (valign != 'top') 'valign': valign,
      if (autofit != 'none') 'autofit': autofit,
    };
  }

  /// Zero-width marks never survive a save — they are live caret state.
  List<RichRun> _prunedRuns() =>
      [for (final r in runs) if (r.end > r.start) r];

  RichDoc clone() {
    final c = RichDoc(
      text: text,
      runs: [for (final r in runs) r.clone()],
      paras: [for (final p in paras) p.clone()],
    );
    c.valign = valign;
    c.autofit = autofit;
    return c;
  }

  // ---- paragraph indexing ----------------------------------------------------

  /// Paragraph start offsets in order (0 plus every `\n` + 1).
  List<int> get paragraphStarts {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) starts.add(i + 1);
    }
    return starts;
  }

  /// The style anchor of the paragraph CONTAINING [offset]: the anchor at
  /// that paragraph's own start, if any (paragraph styles never bleed
  /// across paragraphs — an unanchored paragraph is default-styled).
  RichPara? effectiveParaAt(int offset) {
    final starts = paragraphStarts;
    for (var i = 0; i < starts.length; i++) {
      final s = starts[i];
      final e = i + 1 < starts.length ? starts[i + 1] : text.length;
      if (offset >= s && offset < e) {
        return _anchorAt(s);
      }
    }
    return null;
  }

  // ---- text edits ----------------------------------------------------------

  /// Apply a whole text change (the controller's new value): diffs old vs
  /// new text around the first divergence, updates [text], and maps the
  /// change onto the marks. The single entry point for typing, deletion,
  /// paste and IME composing alike.
  void edit(String newText) {
    final oldText = text;
    if (oldText == newText) return;
    var p = 0;
    final minLen = math.min(oldText.length, newText.length);
    while (p < minLen && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
      p++;
    }
    var sOld = oldText.length, sNew = newText.length;
    while (sOld > p &&
        sNew > p &&
        oldText.codeUnitAt(sOld - 1) == newText.codeUnitAt(sNew - 1)) {
      sOld--;
      sNew--;
    }
    text = newText;
    replaceRange(p, sOld - p, sNew - p);
  }

  /// Map a text change onto the marks: [start, start + delLen) was replaced
  /// by [start, start + insLen). [text] must already BE the new text (see
  /// [edit]) — the transform reads it for the newline analysis below.
  void replaceRange(int start, int delLen, int insLen) {
    final end = start + delLen;
    final delta = insLen - delLen;

    // The source of the inserted text's formatting:
    //  - pure insertion: a zero-width mark AT the point first (the pending
    //    caret format), else the run ending at the point, else the run
    //    strictly containing it;
    //  - replacement: the run covering the replaced range's start.
    RichRun? src;
    if (insLen == 0) {
      // pure deletion — no source
    } else if (delLen == 0) {
      for (final r in runs) {
        if (r.start == start && r.end == start) {
          src = r;
          break;
        }
      }
      src ??=
          runs.where((r) => r.end == start && r.end > r.start).firstOrNull;
      src ??= runs.where((r) => r.start < start && start < r.end).firstOrNull;
    } else {
      src = runs.where((r) => r.start <= start && start < r.end).firstOrNull;
    }
    final zeroWidthSrc =
        src != null && src.start == start && src.end == start;

    final out = <RichRun>[];
    for (final r in runs) {
      final a = r.start, b = r.end;
      if (r == src && insLen > 0) {
        if (delLen == 0) {
          // The insertion belongs to this run: a zero-width mark becomes
          // the inserted span; a non-empty run ending at (or containing)
          // the point grows over it.
          out.add(r.end > r.start
              ? r.clone(end: b + insLen)
              : r.clone(start: start, end: start + insLen));
        } else {
          // Replacement: cover the inserted text plus whatever tail survives.
          out.add(r.clone(
              start: math.min(a, start),
              end: b >= end ? b + delta : start + insLen));
        }
        continue;
      }
      if (delLen == 0) {
        // Pure insertion at `start`.
        if (b <= start) {
          out.add(r); // entirely before — untouched
        } else if (a >= start) {
          out.add(r.clone(start: a + insLen, end: b + insLen)); // after — shift
        } else if (zeroWidthSrc) {
          // A run strictly containing the point while a pending mark claimed
          // the insertion: split around it — [a, start) + [start+ins, b+ins).
          out.add(r.clone(end: start));
          out.add(r.clone(start: start + insLen, end: b + insLen));
        } else {
          // Strictly containing without a competing pending mark — but then
          // it IS the src above; unreachable.
          out.add(r.clone(end: b + insLen));
        }
      } else {
        // A deletion (possibly with replacement) over [start, end).
        if (b <= start) {
          out.add(r); // entirely before
        } else if (a >= end) {
          out.add(r.clone(start: a + delta, end: b + delta)); // entirely after
        } else if (a < start) {
          // Straddles the left edge: the head survives (an empty head —
          // a run that began exactly at the deletion — dies with its
          // text), and if it also ran past the right edge, the tail
          // survives shifted to just after the insertion.
          out.add(r.clone(end: start));
          if (b > end) out.add(r.clone(start: start + insLen, end: b + delta));
        } else if (b <= end) {
          // entirely inside the replaced span — dies with its text
        } else {
          // starts inside, tail survives: shifted past the insertion
          out.add(r.clone(start: start + insLen, end: b + delta));
        }
      }
    }
    runs
      ..clear()
      ..addAll(out);
    _normalize();

    // Paragraph anchors are points, but paragraph-aware ones:
    //  * an anchor AT the edit's start stays put (its paragraph still
    //    starts there — text inserted at a paragraph's start belongs to it,
    //    text deleted from the start does not move the start);
    //  * a deletion kills the paragraphs that started inside (start, end]
    //    (their preceding newline was inside the span — they merge into the
    //    earlier paragraph, whose style wins);
    //  * anchors past the edit shift by the delta.
    if (delLen > 0) {
      final kept = <RichPara>[
        for (final p in paras)
          if (p.start <= start || p.start > end)
            p.clone(
                start: p.start > end ? p.start + delta : p.start)
      ];
      paras
        ..clear()
        ..addAll(kept);
    } else if (insLen > 0) {
      for (final p in paras) {
        if (p.start > start) p.start += delta;
      }
    }

    // Splitting paragraphs: every newline inside the inserted text starts a
    // new paragraph that inherits the style of the paragraph it split.
    final inserted = insLen == 0
        ? ''
        : text.substring(start, math.min(start + insLen, text.length));
    for (var i = 0; i < inserted.length; i++) {
      if (inserted.codeUnitAt(i) != 0x0A) continue;
      final newStart = start + i + 1;
      // The '\n' at newStart - 1 belongs to the paragraph being split —
      // its style is what the new paragraph inherits.
      final anchor = newStart > 0 ? effectiveParaAt(newStart - 1) : null;
      if (anchor != null) {
        final inherit = RichPara(
          start: newStart,
          align: anchor.align,
          list: anchor.list,
          indent: anchor.indent,
          lineSpacing: anchor.lineSpacing,
        );
        final idx = paras.indexWhere((p) => p.start > newStart);
        if (idx < 0) {
          paras.add(inherit);
        } else if (paras[idx].start != newStart) {
          paras.insert(idx, inherit);
        }
      }
    }
  }

  /// Sort, clamp, drop invalid spans, merge identical neighbours.
  /// Zero-width runs (the pending caret marks) are LIVE STATE and are kept
  /// as-is — they never serialize (see [toJson]) and never paint.
  void _normalize() {
    runs.sort((x, y) => x.start.compareTo(y.start));
    final clamped = <RichRun>[];
    for (final r in runs) {
      final s = r.start.clamp(0, text.length);
      final e = r.end.clamp(0, text.length);
      if (e < s || s == text.length && e != s) {
        // negative span, or a mark pushed past the end — dead.
        // (a zero-width mark AT the end still formats what follows typing.)
        continue;
      }
      if (e == s) {
        clamped.add(r.clone(start: s, end: s)); // pending mark — kept
        continue;
      }
      final clean = r.clone(start: s, end: e);
      final last = clamped.isEmpty ? null : clamped.last;
      if (last != null && last.end >= clean.start && last.sameAttrs(clean)) {
        clamped[clamped.length - 1] =
            last.clone(end: math.max(last.end, clean.end));
      } else if (last != null && last.end > clean.start) {
        // Overlap with different attrs: the later one owns its span.
        clamped[clamped.length - 1] = last.clone(end: clean.start);
        clamped.add(clean);
      } else {
        clamped.add(clean);
      }
    }
    runs
      ..clear()
      ..addAll(clamped);
    paras.sort((x, y) => x.start.compareTo(y.start));
    final keptParas = <RichPara>[];
    for (final p in paras) {
      final s = p.start.clamp(0, text.length);
      if (keptParas.isNotEmpty && keptParas.last.start == s) continue;
      keptParas.add(p.clone(start: s));
    }
    paras
      ..clear()
      ..addAll(keptParas);
  }

  // ---- character formatting ---------------------------------------------------

  /// The formatting source for a collapsed caret at [p]: the pending
  /// zero-width mark first, else the character before the caret.
  RichRun? typingSourceAt(int p) {
    for (final r in runs) {
      if (r.start == p && r.end == p) return r;
    }
    if (p == 0) return null;
    for (final r in runs) {
      if (r.start <= p - 1 && p - 1 < r.end) return r;
    }
    return null;
  }

  /// Whether [flag] is active for a range (all covered) — for a collapsed
  /// caret, whether the typing source carries it.
  bool isFlagActive(int start, int end, String flag) {
    if (start == end) {
      final s = typingSourceAt(start);
      return s?.flagValue(flag) == true;
    }
    var covered = 0;
    for (final r in runs) {
      final overlap =
          (math.min(r.end, end) - math.max(r.start, start)).toInt();
      if (overlap > 0 && r.flagValue(flag) == true) covered += overlap;
    }
    return covered >= (end - start);
  }

  /// Toggle a boolean flag over [start, end); a collapsed caret targets the
  /// zero-width pending mark at the caret.
  void toggleFlag(int start, int end, String flag) {
    if (start == end) {
      final effective = isFlagActive(start, end, flag);
      _setCaretAttrs(start, {flag: !effective});
      return;
    }
    final setTo = !isFlagActive(start, end, flag);
    _applyAttr(start, end, {flag: setTo});
  }

  /// Set (or clear with null) an attribute over the range; collapsed caret
  /// writes the pending mark.
  void setAttr(int start, int end, String key, Object? value) {
    if (start == end) {
      _setCaretAttrs(start, {key: value});
      return;
    }
    _applyAttr(start, end, {key: value});
  }

  /// Clear every character format in [start, end) — "back to the slide
  /// theme". A collapsed caret clears the pending mark.
  void clearRange(int start, int end) {
    if (start == end) {
      runs.removeWhere((r) => r.start == start && r.end == start);
      return;
    }
    final out = <RichRun>[];
    for (final r in runs) {
      if (r.end <= start || r.start >= end) {
        out.add(r);
      } else if (r.start < start && r.end > end) {
        out.add(r.clone(end: start));
        out.add(r.clone(start: end));
      } else if (r.start < start) {
        out.add(r.clone(end: start));
      } else if (r.end > end) {
        out.add(r.clone(start: end));
      }
    }
    runs
      ..clear()
      ..addAll(out);
    _normalize();
  }

  void _setCaretAttrs(int p, Map<String, Object?> attrs) {
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].start == p && runs[i].end == p) {
        final merged = runs[i].clone();
        attrs.forEach(merged.setAttribute);
        runs[i] = merged;
        _normalize();
        return;
      }
    }
    final pending = RichRun(start: p, end: p);
    attrs.forEach(pending.setAttribute);
    runs.add(pending);
    runs.sort((x, y) => x.start.compareTo(y.start));
  }

  /// Apply attrs over [start, end): split boundary runs, write the attr
  /// into every piece (gaps in [start, end) become fresh runs), merge back.
  void _applyAttr(int start, int end, Map<String, Object?> attrs) {
    if (end <= start) return;
    final out = <RichRun>[];
    var pos = start;
    for (final r in runs) {
      if (r.end <= start || r.start >= end) {
        out.add(r); // outside — untouched
        continue;
      }
      // The head before the range keeps its own attrs.
      if (r.start < start) out.add(r.clone(end: start));
      // A gap since the last piece: freshly formatted text.
      final a = math.max(r.start, start);
      if (a > pos) {
        final fresh = RichRun(start: pos, end: a);
        attrs.forEach(fresh.setAttribute);
        out.add(fresh);
      }
      final b = math.min(r.end, end);
      final mid = r.clone(start: math.max(a, pos), end: b);
      attrs.forEach(mid.setAttribute);
      out.add(mid);
      pos = math.max(pos, b);
      // The tail after the range keeps its own attrs.
      if (r.end > end) out.add(r.clone(start: end));
    }
    if (pos < end) {
      final fresh = RichRun(start: pos, end: end);
      attrs.forEach(fresh.setAttribute);
      out.add(fresh);
    }
    runs
      ..clear()
      ..addAll(out);
    _normalize();
  }

  // ---- paragraph formatting ---------------------------------------------------

  /// Paragraph indices covered by a selection; a collapsed caret covers
  /// its own paragraph.
  List<int> _paragraphsForSelection(int start, int end) {
    final starts = paragraphStarts;
    final out = <int>[];
    for (var i = 0; i < starts.length; i++) {
      final s = starts[i];
      final e = i + 1 < starts.length ? starts[i + 1] : text.length;
      if (start == end) {
        // A caret belongs to exactly one paragraph: the one containing it.
        if (start >= s && start < e) out.add(i);
      } else {
        if (start < e && s < end) out.add(i);
      }
    }
    return out;
  }

  /// Set a paragraph attribute over the selection's paragraphs.
  void setParagraphAttr(int start, int end, String key, Object? value) {
    final targets = _paragraphsForSelection(start, end);
    final starts = paragraphStarts;
    for (final i in targets) {
      _setParaAttrAt(starts[i], key, value);
    }
    _normalizeParas();
  }

  /// Toggle a list kind over the selection's paragraphs: all-same → off.
  void toggleList(int start, int end, String kind) {
    final targets = _paragraphsForSelection(start, end);
    if (targets.isEmpty) return;
    final starts = paragraphStarts;
    var allSame = true;
    for (final i in targets) {
      final anchor = _anchorAt(starts[i]);
      if ((anchor?.list ?? 'none') != kind) allSame = false;
    }
    final value = allSame ? 'none' : kind;
    for (final i in targets) {
      _setParaAttrAt(starts[i], 'list', value);
    }
    _normalizeParas();
  }

  /// Indent (dir +1) or outdent (dir -1) the selection's paragraphs.
  void indentBy(int start, int end, int dir) {
    final targets = _paragraphsForSelection(start, end);
    final starts = paragraphStarts;
    for (final i in targets) {
      final anchor = _anchorAt(starts[i]);
      final cur = anchor?.indent ?? 0;
      _setParaAttrAt(starts[i], 'indent', (cur + dir).clamp(0, 6));
    }
    _normalizeParas();
  }

  RichPara? _anchorAt(int paragraphStart) {
    for (final p in paras) {
      if (p.start == paragraphStart) return p;
    }
    return null;
  }

  void _setParaAttrAt(int paragraphStart, String key, Object? value) {
    for (var i = 0; i < paras.length; i++) {
      if (paras[i].start == paragraphStart) {
        final updated = paras[i].clone();
        updated.setAttribute(key, value);
        paras[i] = updated;
        return;
      }
    }
    // Materialize an explicit anchor for a paragraph that had none — it
    // inherits nothing (defaults) and takes the new attribute.
    final fresh = RichPara(start: paragraphStart);
    fresh.setAttribute(key, value);
    final idx = paras.indexWhere((p) => p.start > paragraphStart);
    if (idx < 0) {
      paras.add(fresh);
    } else {
      paras.insert(idx, fresh);
    }
  }

  void _normalizeParas() {
    paras.sort((x, y) => x.start.compareTo(y.start));
    // Anchors that carry no attributes at all are dead weight — drop them.
    paras.removeWhere((p) => p.toJsonAttrs().isEmpty);
    // Keep one anchor per paragraph start.
    final seen = <int>{};
    final kept = <RichPara>[];
    for (final p in paras) {
      if (seen.contains(p.start)) continue;
      seen.add(p.start);
      kept.add(p);
    }
    paras
      ..clear()
      ..addAll(kept);
  }
}

// ---------------------------------------------------------------------------
// Runs and paragraph anchors
// ---------------------------------------------------------------------------

/// One character-format mark over `[start, end)` of the doc's text. Absent
/// attributes inherit the doc's base (slide-theme) style; explicit `false`
/// boolean values matter for the zero-width pending mark at a caret.
class RichRun {
  RichRun({
    required this.start,
    required this.end,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.subscript,
    this.superscript,
    this.color,
    this.highlight,
    this.fontFamily,
    this.fontSize,
  });

  int start, end;
  bool? bold, italic, underline, strike, subscript, superscript;
  String? color, highlight, fontFamily;
  double? fontSize;

  factory RichRun.fromJson(Map<String, dynamic> json) => RichRun(
        start: (json['start'] as num).toInt(),
        end: (json['end'] as num).toInt(),
        bold: json['bold'] == null ? null : json['bold'] == true,
        italic: json['italic'] == null ? null : json['italic'] == true,
        underline: json['underline'] == null ? null : json['underline'] == true,
        strike: json['strike'] == null ? null : json['strike'] == true,
        subscript:
            json['subscript'] == null ? null : json['subscript'] == true,
        superscript:
            json['superscript'] == null ? null : json['superscript'] == true,
        color: json['color']?.toString(),
        highlight: json['highlight']?.toString(),
        fontFamily: json['font_family']?.toString(),
        fontSize: (json['font_size'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJsonAttrs() => {
        if (bold != null) 'bold': bold,
        if (italic != null) 'italic': italic,
        if (underline != null) 'underline': underline,
        if (strike != null) 'strike': strike,
        if (subscript != null) 'subscript': subscript,
        if (superscript != null) 'superscript': superscript,
        if (color != null) 'color': color,
        if (highlight != null) 'highlight': highlight,
        if (fontFamily != null) 'font_family': fontFamily,
        if (fontSize != null) 'font_size': fontSize,
      };

  RichRun clone({int? start, int? end}) => RichRun(
        start: start ?? this.start,
        end: end ?? this.end,
        bold: bold,
        italic: italic,
        underline: underline,
        strike: strike,
        subscript: subscript,
        superscript: superscript,
        color: color,
        highlight: highlight,
        fontFamily: fontFamily,
        fontSize: fontSize,
      );

  bool sameAttrs(RichRun other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      strike == other.strike &&
      subscript == other.subscript &&
      superscript == other.superscript &&
      color == other.color &&
      highlight == other.highlight &&
      fontFamily == other.fontFamily &&
      fontSize == other.fontSize;

  /// The effective value of a named flag at this run (null = inherit).
  bool? flagValue(String flag) {
    switch (flag) {
      case 'bold':
        return bold;
      case 'italic':
        return italic;
      case 'underline':
        return underline;
      case 'strike':
        return strike;
      case 'subscript':
        return subscript;
      case 'superscript':
        return superscript;
    }
    return null;
  }

  void setAttribute(String key, Object? value) {
    switch (key) {
      case 'bold':
        bold = value == null ? null : value == true;
      case 'italic':
        italic = value == null ? null : value == true;
      case 'underline':
        underline = value == null ? null : value == true;
      case 'strike':
        strike = value == null ? null : value == true;
      case 'subscript':
        subscript = value == null ? null : value == true;
      case 'superscript':
        superscript = value == null ? null : value == true;
      case 'color':
        color = value?.toString();
      case 'highlight':
        highlight = value?.toString();
      case 'font_family':
        fontFamily = value?.toString();
      case 'font_size':
        fontSize = value == null ? null : (value as num).toDouble();
    }
  }
}

/// A paragraph-style anchor: applies from [start] until the next anchor.
class RichPara {
  RichPara({
    required this.start,
    this.align,
    this.list,
    this.indent,
    this.lineSpacing,
  });

  int start;
  String? align; // left | center | right | justify
  String? list; // none | bullet | number
  int? indent; // 0-based list indent level
  double? lineSpacing; // 1.0 | 1.15 | 1.5 | 2.0

  factory RichPara.fromJson(Map<String, dynamic> json) => RichPara(
        start: (json['start'] as num).toInt(),
        align: json['align']?.toString(),
        list: json['list']?.toString(),
        indent: (json['indent'] as num?)?.toInt(),
        lineSpacing: (json['line_spacing'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJsonAttrs() => {
        if (align != null) 'align': align,
        if (list != null && list != 'none') 'list': list,
        if (indent != null && indent != 0) 'indent': indent,
        if (lineSpacing != null) 'line_spacing': lineSpacing,
      };

  RichPara clone({int? start}) => RichPara(
        start: start ?? this.start,
        align: align,
        list: list,
        indent: indent,
        lineSpacing: lineSpacing,
      );

  void setAttribute(String key, Object? value) {
    switch (key) {
      case 'align':
        align = value?.toString();
      case 'list':
        list = value?.toString();
      case 'indent':
        indent = value == null ? null : (value as num).toInt();
      case 'line_spacing':
        lineSpacing = value == null ? null : (value as num).toDouble();
    }
  }
}

// ---------------------------------------------------------------------------
// The editing controller
// ---------------------------------------------------------------------------

/// A [TextEditingController] that renders the [RichDoc]'s formatting: the
/// plain text (and so the caret, selection, IME composing, shortcuts) stays
/// the platform's; only the painted spans are decorated from the marks.
///
/// The session keeps [doc] and the controller in lockstep: the controller's
/// text IS `doc.text`; edits flow back through the controller's listener,
/// which hands the whole new text to [RichDoc.edit] — that method diffs it
/// against the old and moves the marks like a text editor does.
class RichEditingController extends TextEditingController {
  RichEditingController({required this.doc}) : super(text: doc.text) {
    _lastText = text;
    addListener(_onOwnChange);
  }

  /// The live document this controller renders.
  RichDoc doc;

  /// Scale applied to the runs' design-space font sizes when rendering
  /// (the on-canvas field is a screen-space widget: base size × canvas
  /// scale × autofit factor; the painter path leaves this at 1).
  double runScale = 1.0;

  String _lastText = '';

  /// Every text change (typing, deletion, paste, IME) flows into the doc's
  /// mark transforms.
  void _onOwnChange() {
    final newText = text;
    if (newText == _lastText) return;
    doc.edit(newText);
    _lastText = newText;
  }

  /// Force a rebuild of the painted spans after a formatting change (the
  /// text itself did not change, so the field would not repaint).
  void refresh() => notifyListeners();

  @override
  void dispose() {
    removeListener(_onOwnChange);
    super.dispose();
  }

  /// The selection clamped to the text (null-safe).
  TextSelection get effectiveSelection {
    final s = selection;
    if (!s.isValid) {
      return const TextSelection.collapsed(offset: 0);
    }
    return s;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool withComposing = false,
  }) {
    final base = style ?? const TextStyle(color: Color(0xFF17181A));
    final children = <InlineSpan>[];
    final text = this.text;
    final composing = value.composing;
    final composingRange =
        (withComposing && composing.isValid && !composing.isCollapsed)
            ? composing
            : null;

    // Walk the doc's runs (plus the composing underline) over the text.
    int cursor = 0;
    List<int> boundaries() {
      final pts = <int>{0, text.length};
      for (final r in doc.runs) {
        pts.add(r.start.clamp(0, text.length));
        pts.add(r.end.clamp(0, text.length));
      }
      if (composingRange != null) {
        pts.add(composingRange.start);
        pts.add(composingRange.end);
      }
      return pts.where((x) => x >= 0 && x <= text.length).toList()..sort();
    }

    RichRun? runAt(int i) {
      for (final r in doc.runs) {
        if (r.start <= i && i < r.end) return r;
        if (r.start == i && r.end == i) return r; // pending caret mark
      }
      return null;
    }

    final pts = boundaries();
    for (var bi = 0; bi < pts.length - 1; bi++) {
      final a = pts[bi], b = pts[bi + 1];
      if (b <= a) continue;
      if (a >= text.length) break;
      final segEnd = math.min(b, text.length);
      final piece = text.substring(a, segEnd);
      if (piece.isEmpty) continue;
      final run = runAt(a);
      final s = richTextStyle(
        run,
        base: base,
        runScale: runScale,
        composing: composingRange != null &&
            a < composingRange.end &&
            composingRange.start < segEnd,
      );
      children.add(TextSpan(text: piece, style: s));
      cursor = segEnd;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: base));
    }
    if (children.isEmpty) {
      return TextSpan(text: '', style: base);
    }
    return TextSpan(style: base, children: children);
  }
}

/// Map a run's attributes onto a [TextStyle] over [base]. [runScale]
/// converts the run's design-space font size to the render space (the
/// on-canvas editing field).
TextStyle richTextStyle(RichRun? run,
    {TextStyle base = const TextStyle(color: Color(0xFF17181A)),
    bool composing = false,
    double runScale = 1.0}) {
  if (run == null) {
    return base.copyWith(
      decoration: composing ? TextDecoration.underline : null,
    );
  }
  final deco = <TextDecoration>[
    if (run.underline == true) TextDecoration.underline,
    if (run.strike == true) TextDecoration.lineThrough,
    if (composing) TextDecoration.underline,
  ];
  // The size the run renders at: an explicit run size lives in design px
  // (scaled by [runScale] into the render space); an inherited size IS
  // the base style's own (already in the render space). Sub/superscript
  // shrinks that size — whichever space it came from — so the painter and
  // the edit field agree (the painter additionally shifts the baseline).
  final runSize =
      run.fontSize != null ? run.fontSize! * runScale : base.fontSize;
  final scaled = runSize == null
      ? null
      : (run.subscript == true || run.superscript == true)
          ? runSize * 0.65
          : runSize;
  return base.copyWith(
    fontWeight: run.bold == true ? FontWeight.w700 : null,
    fontStyle: run.italic == true ? FontStyle.italic : null,
    decoration: deco.isEmpty ? null : TextDecoration.combine(deco),
    color: run.color == null ? null : hexToColor(run.color!),
    background: run.highlight == null
        ? null
        : (Paint()..color = hexToColor(run.highlight!)),
    fontFamily: _familyValue(run.fontFamily),
    fontSize: scaled,
    debugLabel: null,
  );
}

String? _familyValue(String? f) {
  switch (f) {
    case 'serif':
      return 'serif';
    case 'mono':
      return 'monospace';
    case 'sans':
      return null; // the app's default family
  }
  return null;
}

