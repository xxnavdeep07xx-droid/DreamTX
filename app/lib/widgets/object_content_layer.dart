import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/color_utils.dart';
import '../core/object_content.dart';
import '../theme.dart';
import 'icon_registry.dart';
import 'rich_doc.dart';

/// The paint-only canvas layer for objects that carry `content`: text
/// boxes, images, icon stickers, media cards and tables render as CONTENT
/// at their design-space rects, scaled to the canvas. It never claims a
/// pointer — selection, move/resize/rotate and all gestures stay in the
/// sibling [ShapesLayer], which owns the object geometry for every kind
/// (so the same select-and-drag works identically for a text box, an image
/// or a plain rectangle).
///
/// Design-space units: each object renders inside a `Transform.scale` of
/// the canvas scale, at its own design size — text lays out at the doc's
/// real design font sizes, images at design pixels, all vector-crisp at
/// any zoom.
class ObjectContentLayer extends StatelessWidget {
  const ObjectContentLayer({
    super.key,
    required this.objects,
    required this.designW,
    required this.designH,
    required this.baseColor,
    required this.baseFamily,
    required this.baseFontSize,
    required this.resolveResourcePath,
    this.singleObject = false,
  });

  final List<Map<String, dynamic>> objects;

  /// When true the layer renders exactly ONE object (the first of
  /// [objects]) filling whatever box the parent gives it — the
  /// per-object rendering [SlideStage] interleaves in the deck's true
  /// Z-order, where the parent positions/rotates the box. Default false:
  /// the layer lays the whole list out at the design frame itself.
  final bool singleObject;

  /// The deck's design-space dimensions (16:9 → 1280×720, 4:3 → 960×720…).
  final double designW;
  final double designH;

  /// The slide-theme base: the deck DNA's foreground color and body font
  /// family, and the app's default design-space body size.
  final Color baseColor;
  final String? baseFamily;
  final double baseFontSize;

  /// Resolves an image/media content payload to a readable file path (the
  /// app's resource store scopes), or null when the asset is gone.
  final String? Function(Map<String, dynamic> content) resolveResourcePath;

  @override
  Widget build(BuildContext context) {
    final contentObjects = objects.where(ObjectContent.hasContent).toList();
    if (contentObjects.isEmpty) return const SizedBox.shrink();
    if (singleObject) {
      // One object, one box: the parent (SlideStage) positions and
      // rotates; this layer paints the content alone.
      final obj = contentObjects.first;
      return IgnorePointer(child: _contentFor(obj, 1));
    }
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, constraints) {
        final scale = math.min(constraints.biggest.width / designW,
            constraints.biggest.height / designH);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final obj in contentObjects)
              Positioned(
                left: ((obj['x'] as num?) ?? 0).toDouble() * scale,
                top: ((obj['y'] as num?) ?? 0).toDouble() * scale,
                width: ((obj['w'] as num?) ?? 0).toDouble() * scale,
                height: ((obj['h'] as num?) ?? 0).toDouble() * scale,
                child: _rotated(
                  obj,
                  child: _contentFor(obj, scale),
                ),
              ),
          ],
        );
      }),
    );
  }

  /// Rotation around the object's bbox center, matching [ShapesLayer]'s
  /// selection overlay and gesture math exactly.
  Widget _rotated(Map obj, {required Widget child}) {
    final rot = ((obj['rotation'] ?? 0) as num).toDouble();
    if (rot == 0) return child;
    return Transform.rotate(
      angle: rot * math.pi / 180.0,
      child: child,
    );
  }

  Widget _contentFor(Map<String, dynamic> obj, double scale) {
    switch (ObjectContent.kindOf(obj)) {
      case kContentText:
        return _TextBoxView(
          obj: obj,
          baseColor: baseColor,
          baseFamily: baseFamily,
          baseFontSize: baseFontSize,
        );
      case kContentImage:
        return _ImageView(obj: obj, resolve: resolveResourcePath);
      case kContentIcon:
        return _IconView(obj: obj, baseColor: baseColor);
      case kContentMedia:
        return _MediaView(obj: obj, resolve: resolveResourcePath);
      case kContentTable:
        return _TableView(obj: obj, baseColor: baseColor, baseFamily: baseFamily, baseFontSize: baseFontSize);
    }
    return const SizedBox.shrink();
  }
}

Widget _designScaled({required double scale, required double w, required double h, required Widget child}) {
  return OverflowBox(
    alignment: Alignment.topLeft,
    minWidth: 0,
    minHeight: 0,
    maxWidth: double.infinity,
    maxHeight: double.infinity,
    child: Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: SizedBox(width: w, height: h, child: child),
    ),
  );
}

// ---------------------------------------------------------------------------
// Text box
// ---------------------------------------------------------------------------

class _TextBoxView extends StatelessWidget {
  const _TextBoxView({
    required this.obj,
    required this.baseColor,
    required this.baseFamily,
    required this.baseFontSize,
  });

  final Map<String, dynamic> obj;
  final Color baseColor;
  final String? baseFamily;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    final doc = ObjectContent.textDocOf(obj) ?? RichDoc();
    return LayoutBuilder(builder: (context, constraints) {
      final scale =
          constraints.maxWidth / (((obj['w'] as num?) ?? 1).toDouble());
      final w = ((obj['w'] as num?) ?? 1).toDouble();
      final h = ((obj['h'] as num?) ?? 1).toDouble();
      return _designScaled(
        scale: scale,
        w: w,
        h: h,
        child: Opacity(
          // The object's opacity applies to every content kind — text
          // included, matching the vector shapes (and the exports).
          opacity: _opacityOf(obj),
          child: CustomPaint(
            size: Size(w, h),
            painter: TextBoxPainter(
              doc: doc,
              baseColor: baseColor,
              baseFamily: baseFamily,
              baseFontSize: baseFontSize,
            ),
          ),
        ),
      );
    });
  }
}

/// Paints a rich text document inside a (w × h) design-space box:
/// paragraphs with per-paragraph alignment, bullets/numbers, line spacing,
/// vertical alignment and shrink-on-overflow autofit.
class TextBoxPainter extends CustomPainter {
  TextBoxPainter({
    required this.doc,
    required this.baseColor,
    required this.baseFamily,
    required this.baseFontSize,
  });

  final RichDoc doc;
  final Color baseColor;
  final String? baseFamily;
  final double baseFontSize;

  static const double padX = 14;
  static const double padY = 10;
  static const double indentStep = 36;

  TextStyle get _base => TextStyle(
        color: baseColor,
        fontFamily: baseFamily,
        fontSize: baseFontSize,
      );

  /// The shrink-on-overflow factor for [doc] in a (boxW × boxH) design box
  /// (1.0 when it fits or autofit is off) — shared by the painter and the
  /// editing field so type size tracks what the painted box shows.
  static double autofitScale({
    required RichDoc doc,
    required double boxW,
    required double boxH,
    required Color baseColor,
    required String? baseFamily,
    required double baseFontSize,
  }) {
    if (doc.text.isEmpty || doc.autofit != 'shrink') return 1.0;
    final painter = TextBoxPainter(
      doc: doc,
      baseColor: baseColor,
      baseFamily: baseFamily,
      baseFontSize: baseFontSize,
    );
    final w = (boxW - padX * 2).clamp(0.0, double.infinity);
    if (w <= 1) return 1.0;
    final paragraphs = painter._paragraphLayouts(w);
    var total = 0.0;
    for (final p in paragraphs) {
      total += p.painter.height;
    }
    final avail = (boxH - padY * 2).clamp(0.0, double.infinity);
    if (total <= avail || total <= 0) return 1.0;
    return (avail / total).clamp(0.05, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = ((size.width - padX * 2)).clamp(0.0, double.infinity);
    if (w <= 1 || doc.text.isEmpty) return;
    final availH = (size.height - padY * 2).clamp(0.0, double.infinity);

    // Lay every paragraph out once at natural size.
    final paragraphs = _paragraphLayouts(w);
    var total = 0.0;
    for (final p in paragraphs) {
      total += p.painter.height;
    }

    // Autofit: shrink on overflow.
    final shrink = doc.autofit == 'shrink';
    final k = shrink && total > availH && total > 0
        ? (availH / total).clamp(0.05, 1.0).toDouble()
        : 1.0;

    // Vertical alignment inside the box.
    var y = padY;
    if (doc.valign == 'middle') {
      y = padY + (availH - total * k) / 2;
    } else if (doc.valign == 'bottom') {
      y = size.height - padY - total * k;
    }

    canvas.save();
    canvas.translate(0, 0);
    if (k != 1.0) canvas.scale(k);
    var dy = y / k;
    for (final p in paragraphs) {
      // The paragraph's effective text column: the indent applies to
      // EVERY alignment — center and right align inside the INDENTED
      // column, exactly like left/justify do, instead of ignoring the
      // indent and centering on the full box.
      final col = w - p.indent * indentStep;
      var x = padX + p.indent * indentStep;
      final align = p.align;
      if (align == 'center') {
        x = padX + p.indent * indentStep + (col - p.painter.width) / 2;
      } else if (align == 'right') {
        x = padX + p.indent * indentStep + (col - p.painter.width);
      }
      p.paintX = x;
      p.paintY = dy;
      p.painter.paint(canvas, Offset(x, dy));
      dy += p.painter.height;
    }

    // Sub/superscript baseline shift: the run spans render at 0.65 size
    // (the shrink the edit field shows too) and the painter additionally
    // LIFTS/LOWERS them along the baseline — a real raised/lowered
    // typeset, not just small text. The spans were laid out in the
    // paragraph painter with transparent color (see [_appendRunSpans]);
    // here each sub/sup run piece is re-painted at its measured box
    // position, shifted by the typographic offset. The overlay runs
    // INSIDE the same save/scale transform as the paragraphs themselves —
    // the autofit shrink (k) scales its positions and font sizes exactly
    // like it scales the paragraph glyphs (it used to run after the
    // restore, painting unscaled pieces at unshifted positions whenever
    // k < 1).
    for (final p in paragraphs) {
      if (!p.hasSubSuper) continue;
      _paintSubSuperOverlay(canvas, p);
    }
    canvas.restore();
  }

  /// Re-paint the sub/superscript runs of one paragraph with their baseline
  /// shift, positioned from the paragraph painter's own boxes — the
  /// paragraph layout (line breaks, sizes) is authoritative and unchanged.
  ///
  /// The paragraph painter's coordinate space is its OWN: the optional
  /// list prefix ("•  " / "1.  ") followed by the paragraph's slice of
  /// [doc.text]. Doc offsets and painter offsets therefore differ by
  /// `p.start` and `p.prefixLen`: a doc offset `o` inside the paragraph
  /// renders at painter offset `o - p.start + p.prefixLen`, and a painter
  /// offset maps back with `- p.prefixLen + p.start`. Every run is CLIPPED
  /// to the paragraph's rendered range first — a sub/sup run that spans
  /// several paragraphs (or crosses a list prefix) only repaints the
  /// piece THIS painter actually laid out.
  void _paintSubSuperOverlay(Canvas canvas, _ParaLayout p) {
    final tp = p.painter;
    int docOffset(int tpLocal) => tpLocal - p.prefixLen + p.start;
    for (final r in doc.runs) {
      final isSub = r.subscript == true;
      final isSup = r.superscript == true;
      if (!isSub && !isSup) continue;
      if (r.end <= r.start) continue; // pending marks never render
      // Clip the run to this paragraph's RENDERED text ([p.start, p.end)).
      final rs = math.max(r.start, p.start);
      final rend = math.min(r.end, p.end);
      if (rs >= rend) continue;
      // Position every glyph-run box the painter produced for this run's
      // piece and paint the piece at the box's own x, shifted vertically.
      final boxes = tp.getBoxesForSelection(
        TextSelection(
          baseOffset: rs - p.start + p.prefixLen,
          extentOffset: rend - p.start + p.prefixLen,
        ),
      );
      if (boxes.isEmpty) continue;
      // The run's style at its own (already-shrunk) size, but with a real
      // color instead of the layout pass's transparent placeholder.
      final style = richTextStyle(r, base: _base).copyWith(
        color: _colorForRun(r),
      );
      var pieceStart = rs - p.start + p.prefixLen; // painter-local
      var lastTop = boxes.first.top;
      for (final box in boxes) {
        // A new line begins when the box's top moves: re-anchor the slice
        // at the new line's FIRST glyph so a wrapped fragment is never
        // skipped (the piece covers exactly that line's boxes).
        if ((box.top - lastTop).abs() > 1.0) {
          lastTop = box.top;
          pieceStart = _offsetForBoxStart(tp, box);
        }
        final pieceEnd = _offsetForBoxEnd(tp, box);
        if (pieceEnd > pieceStart) {
          // Painter-local offsets → doc offsets for slicing the doc's text.
          final ds = docOffset(pieceStart).clamp(0, doc.text.length);
          final de = docOffset(pieceEnd).clamp(0, doc.text.length);
          final text = doc.text.substring(ds, de);
          final boxH = box.bottom - box.top;
          // Typographic offsets: a subscript's baseline sits BELOW the
          // line's (about a third of the x-height down), a superscript's
          // above it.
          final shift = isSub ? boxH * 0.34 : -boxH * 0.38;
          final piece = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
          )..layout();
          canvas.save();
          canvas.translate(p.paintX + box.left, p.paintY + box.top + shift);
          piece.paint(canvas, Offset.zero);
          canvas.restore();
          pieceStart = pieceEnd;
        }
      }
    }
  }

  /// The text offset at a box's LEFT edge (the first glyph of the box's
  /// line) — used to re-anchor a run piece when the layout wraps.
  int _offsetForBoxStart(TextPainter tp, TextBox box) {
    final pos = tp.getPositionForOffset(
      Offset(box.left + 0.5, (box.top + box.bottom) / 2),
    );
    return pos.offset;
  }

  /// The text offset just past a box's glyphs (used to slice run pieces).
  int _offsetForBoxEnd(TextPainter tp, TextBox box) {
    final pos = tp.getPositionForOffset(
      Offset(box.right + 0.5, (box.top + box.bottom) / 2),
    );
    return pos.offset;
  }

  Color _colorForRun(RichRun r) => r.color == null ? baseColor : hexToColor(r.color!);

  List<_ParaLayout> _paragraphLayouts(double boxW) {
    final starts = doc.paragraphStarts;
    var numberSeq = 0;
    final out = <_ParaLayout>[];
    for (var i = 0; i < starts.length; i++) {
      final s = starts[i];
      final e = i + 1 < starts.length ? starts[i + 1] : doc.text.length;
      final plain = doc.text.substring(s, e);
      // The paragraph's own anchor (defaults when unanchored).
      final para = doc.effectiveParaAt(s);
      final list = para?.list ?? 'none';
      final indent = para?.indent ?? 0;
      final lineSpacing = para?.lineSpacing ?? 1.15;
      final align = para?.align ?? 'left';

      var number = 0;
      if (list == 'number') {
        numberSeq += 1;
        number = numberSeq;
      } else {
        numberSeq = 0;
      }

      final prefix = switch (list) {
        'bullet' => '\u2022  ',
        'number' => '$number.  ',
        _ => '',
      };

      final spans = <InlineSpan>[];
      final heightStyle = _base.copyWith(height: lineSpacing * 1.28);
      if (prefix.isNotEmpty) {
        spans.add(TextSpan(
          text: prefix,
          style: heightStyle.copyWith(color: baseColor.withValues(alpha: 0.55)),
        ));
      }
      final text = plain.endsWith('\n') ? plain.substring(0, plain.length - 1) : plain;
      var hasSubSuper = false;
      _appendRunSpans(spans, s, s + text.length, heightStyle,
          onSubSuper: () => hasSubSuper = true);

      final tp = TextPainter(
        text: TextSpan(children: spans),
        // Justify: TextPainter distributes the extra space between words
        // on every line but the paragraph's last — the paragraph itself
        // must be laid out at the aligned width for that to happen.
        textAlign: align == 'justify' ? TextAlign.justify : TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: boxW - indent * indentStep);
      out.add(_ParaLayout(
        painter: tp,
        align: align,
        indent: indent,
        start: s,
        end: s + text.length,
        prefixLen: prefix.length,
      )..hasSubSuper = hasSubSuper);
    }
    return out;
  }

  /// Split [from, to) of the doc's text into styled spans, following the
  /// run marks (zero-width pending marks never render).
  ///
  /// Sub/superscript runs lay out at their (shrunk) size but with a
  /// TRANSPARENT color — the paint pass re-paints each of their pieces at
  /// the measured box position with the real color and the baseline
  /// shift, so the paragraph's own line breaking stays authoritative
  /// while the glyphs read raised/lowered, typeset properly.
  void _appendRunSpans(List<InlineSpan> out, int from, int to, TextStyle base,
      {void Function()? onSubSuper}) {
    var pos = from;
    for (final r in doc.runs) {
      if (r.end <= from || r.start >= to || r.end <= r.start) continue;
      final a = math.max(r.start, from);
      final b = math.min(r.end, to);
      if (a > pos) out.add(TextSpan(text: doc.text.substring(pos, a), style: base));
      final subSuper = r.subscript == true || r.superscript == true;
      final style = richTextStyle(r, base: base);
      out.add(TextSpan(
        text: doc.text.substring(a, b),
        style: subSuper
            ? style.copyWith(
                color: baseColor.withValues(alpha: 0),
                background: null,
              )
            : style,
      ));
      if (subSuper) onSubSuper?.call();
      pos = b;
    }
    if (pos < to) {
      out.add(TextSpan(text: doc.text.substring(pos, to), style: base));
    }
  }

  @override
  bool shouldRepaint(TextBoxPainter old) =>
      old.doc != doc ||
      old.baseColor != baseColor ||
      old.baseFamily != baseFamily ||
      old.baseFontSize != baseFontSize;
}

class _ParaLayout {
  _ParaLayout({
    required this.painter,
    required this.align,
    required this.indent,
    required this.start,
    required this.end,
    required this.prefixLen,
  });
  final TextPainter painter;
  final String align;
  final int indent;

  /// The paragraph's slice of the doc's text: [start, end) in doc offsets
  /// (end excludes the stripped trailing `\n`). The sub/superscript
  /// overlay maps doc↔painter offsets through these + [prefixLen].
  final int start;
  final int end;

  /// The list prefix's UTF-16 length ("•  " / "1.  ") — the painter's text
  /// is prefix + paragraph slice, so painter offsets run ahead of doc
  /// offsets by this much.
  final int prefixLen;

  /// Where the paragraph was painted (scaled-space px) — the sub/superscript
  /// overlay re-paints run pieces at these anchors.
  double paintX = 0;
  double paintY = 0;

  /// Whether any rendered run carries sub/superscript (the overlay only
  /// runs when it does).
  bool hasSubSuper = false;
}

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

class _ImageView extends StatefulWidget {
  const _ImageView({required this.obj, required this.resolve});

  final Map<String, dynamic> obj;
  final String? Function(Map<String, dynamic> content) resolve;

  @override
  State<_ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<_ImageView> {
  ImageProvider? _provider;
  String? _resolvedPath;

  @override
  void didUpdateWidget(_ImageView old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Rebuild the image provider from the resolver — only when the RESOLVED
  /// PATH actually moved. The resolver map is editor-owned and populated
  /// the moment an asset is imported or picked, so a fresh path appearing
  /// here remounts the image on the very next build (a newly imported
  /// asset shows right away instead of a "missing asset" card).
  ///
  /// No synchronous `existsSync` runs on this path: [FileImage] loads
  /// asynchronously and the [Image.errorBuilder] below renders the clean
  /// fallback when the file turns out to be gone — disk IO never blocks
  /// or runs inside layout.
  void _refresh() {
    final content = ObjectContent.of(widget.obj);
    final path = content == null ? null : widget.resolve(content);
    if (path == _resolvedPath && _provider != null) return;
    _resolvedPath = path;
    _provider = path == null ? null : FileImage(File(path));
  }

  @override
  Widget build(BuildContext context) {
    final obj = widget.obj;
    return LayoutBuilder(builder: (context, constraints) {
      final w = ((obj['w'] as num?) ?? 1).toDouble();
      final h = ((obj['h'] as num?) ?? 1).toDouble();
      final scale = constraints.maxWidth / w;
      final provider = _provider;
      final stroke = obj['stroke'];
      final strokeWidth = stroke is Map ? ((stroke['width'] ?? 0) as num).toDouble() : 0.0;
      final strokeColor = stroke is Map
          ? hexToColor((stroke['color'] ?? '17181A').toString())
          : const Color(0xFF17181A);
      return _designScaled(
        scale: scale,
        w: w,
        h: h,
        child: Opacity(
          opacity: _opacityOf(obj),
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              border: strokeWidth > 0
                  ? Border.all(color: strokeColor, width: strokeWidth)
                  : null,
            ),
            child: provider == null
                ? _missingAssetFallback(obj)
                : Image(
                    image: provider,
                    fit: BoxFit.cover,
                    width: w,
                    height: h,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => _missingAssetFallback(obj),
                  ),
          ),
        ),
      );
    });
  }

  Widget _missingAssetFallback(Map<String, dynamic> obj) {
    final name = (ObjectContent.of(obj)?['name'] ?? 'image').toString();
    return Container(
      color: kElevated,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 30, color: kText3),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: kText3),
            ),
          ],
        ),
      ),
    );
  }
}

/// The object's opacity (0..1), the same value the vector shapes and the
/// exporters apply.
double _opacityOf(Map obj) =>
    (((obj['opacity'] ?? 1) as num?)?.toDouble() ?? 1).clamp(0.0, 1.0);

// ---------------------------------------------------------------------------
// Icon sticker
// ---------------------------------------------------------------------------

class _IconView extends StatelessWidget {
  const _IconView({required this.obj, required this.baseColor});

  final Map<String, dynamic> obj;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final name = (ObjectContent.of(obj)?['name'] ?? 'star').toString();
    final glyph = iconGlyphOf(name) ?? Icons.star_outline;
    final fill = obj['fill'];
    final color = fill is Map && fill['type'] == 'solid'
        ? hexToColor((fill['color'] ?? 'F5F5F7').toString())
        : baseColor;
    final opacity = ((obj['opacity'] ?? 1) as num).toDouble().clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, constraints) {
      final w = ((obj['w'] as num?) ?? 1).toDouble();
      final h = ((obj['h'] as num?) ?? 1).toDouble();
      final scale = constraints.maxWidth / w;
      final size = math.min(w, h);
      return _designScaled(
        scale: scale,
        w: w,
        h: h,
        child: Center(
          child: Opacity(
            opacity: opacity,
            child: Icon(glyph, size: size, color: color),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Media card
// ---------------------------------------------------------------------------

/// The media card. Playback itself lives in the object panel (the
/// Insert drawer's media group): a Play button there hands the resolved
/// local file to the system's own player through a tiny platform intent —
/// no bundled multi-MB video SDK, no new dependencies. The card stays
/// paint-only like every other content view (selection/tap belongs to
/// the gesture layer above it).
class _MediaView extends StatelessWidget {
  const _MediaView({required this.obj, required this.resolve});

  final Map<String, dynamic> obj;

  /// Resolves the media content payload to its local file path (or null
  /// when the asset is gone — the card renders its name chip then).
  final String? Function(Map<String, dynamic> content) resolve;

  @override
  Widget build(BuildContext context) {
    final content = ObjectContent.of(obj) ?? const {};
    final name = (content['name'] ?? 'media').toString();
    final isVideo = (content['media_kind'] ?? 'video') == 'video';
    final stroke = obj['stroke'];
    final strokeWidth = stroke is Map ? ((stroke['width'] ?? 0) as num).toDouble() : 0.0;
    return LayoutBuilder(builder: (context, constraints) {
      final w = ((obj['w'] as num?) ?? 1).toDouble();
      final h = ((obj['h'] as num?) ?? 1).toDouble();
      final scale = constraints.maxWidth / w;
      return _designScaled(
        scale: scale,
        w: w,
        h: h,
        child: Opacity(
          opacity: _opacityOf(obj),
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: const Color(0xFF101014),
              borderRadius: BorderRadius.circular(6),
              border: strokeWidth > 0
                  ? Border.all(
                      color: hexToColor((stroke['color'] ?? '17181A').toString()),
                      width: strokeWidth)
                  : Border.all(color: const Color(0x332A2A31)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isVideo ? Icons.videocam_outlined : Icons.graphic_eq,
                  size: math.min(w, h) * 0.34,
                  color: kText2,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: kText2),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------

class _TableView extends StatelessWidget {
  const _TableView({
    required this.obj,
    required this.baseColor,
    required this.baseFamily,
    required this.baseFontSize,
  });

  final Map<String, dynamic> obj;
  final Color baseColor;
  final String? baseFamily;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    final (rows, cols, cells) = ObjectContent.tableOf(obj);
    if (rows == 0 || cols == 0) return const SizedBox.shrink();
    final stroke = obj['stroke'];
    final gridColor = stroke is Map
        ? hexToColor((stroke['color'] ?? '17181A').toString())
        : const Color(0xFF17181A);
    final strokeWidth = stroke is Map
        ? (((stroke['width'] ?? 1.5) as num).toDouble().clamp(0.75, 4.0))
        : 1.5;
    return LayoutBuilder(builder: (context, constraints) {
      final w = ((obj['w'] as num?) ?? 1).toDouble();
      final h = ((obj['h'] as num?) ?? 1).toDouble();
      final scale = constraints.maxWidth / w;
      final ch = h / rows;
      return _designScaled(
        scale: scale,
        w: w,
        h: h,
        child: Opacity(
          opacity: _opacityOf(obj),
          child: CustomPaint(
          size: Size(w, h),
          painter: _TablePainter(
            rows: rows,
            cols: cols,
            cells: cells,
            gridColor: gridColor,
            strokeWidth: strokeWidth,
            cellStyle: TextStyle(
              color: baseColor,
              fontFamily: baseFamily,
              fontSize: math.min(baseFontSize * 0.62, ch * 0.42),
            ),
          ),
        ),
        ),
      );
    });
  }
}

class _TablePainter extends CustomPainter {
  _TablePainter({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.gridColor,
    required this.strokeWidth,
    required this.cellStyle,
  });

  final int rows, cols;
  final List<String> cells;
  final Color gridColor;
  final double strokeWidth;
  final TextStyle cellStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final cw = w / cols, ch = h / rows;
    // Outer border.
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
    // Inner rules.
    for (var r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * ch), Offset(w, r * ch), paint);
    }
    for (var c = 1; c < cols; c++) {
      canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, h), paint);
    }
    // Cell text.
    const pad = 7.0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final text = cells[r * cols + c];
        if (text.isEmpty) continue;
        final tp = TextPainter(
          text: TextSpan(text: text, style: cellStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: cw - pad * 2);
        tp.paint(canvas, Offset(c * cw + pad, r * ch + (ch - tp.height) / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_TablePainter old) =>
      old.cells != cells ||
      old.gridColor != gridColor ||
      old.cellStyle != cellStyle ||
      old.rows != rows ||
      old.cols != cols;
}
