import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:material_ui/material_ui.dart';

import '../core/object_content.dart';

/// Interactive vector overlay layer: paints every object (fills, gradients,
/// strokes, arrows, shadows, glow) and — when `interactive` — handles
/// selection, move/resize/rotate with smart-guide snapping, and freeform
/// scribble capture. Coordinates live in the deck's design space (1280×720
/// for 16:9 decks — [designW]/[designH] carry other aspects), exactly like
/// the Rust engine's model.

class ShapesLayer extends StatefulWidget {
  const ShapesLayer({
    super.key,
    required this.objects,
    this.selectedId,
    this.interactive = false,
    this.scribbleMode = false,
    this.designW = 1280,
    this.designH = 720,
    this.onSelect,
    this.onLive,
    this.onCommit,
    this.onGestureStart,
    this.onScribble,
  });

  final List<Map<String, dynamic>> objects;
  final String? selectedId;
  final bool interactive;
  final bool scribbleMode;

  /// The deck's design-space frame — non-16:9 aspects lay objects out in
  /// their true frame instead of stretching the classic one.
  final double designW;
  final double designH;

  /// selection change (null = deselect)
  final void Function(String?)? onSelect;
  /// live geometry change during a gesture (no engine round-trip)
  final void Function(Map<String, dynamic>)? onLive;
  /// gesture finished → commit this object to the engine
  final void Function(Map<String, dynamic>)? onCommit;
  /// gesture started → snapshot deck for undo
  final VoidCallback? onGestureStart;
  /// scribble finished (design-space points) → create a freeform object
  final void Function(List<Offset>)? onScribble;

  @override
  State<ShapesLayer> createState() => _ShapesLayerState();
}

class _ShapesLayerState extends State<ShapesLayer> {
  static const double snapTol = 6.0;

  _Grab? _grab;
  List<Offset> _scribblePts = [];
  List<_GuideLine> _guides = [];

  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _scale = constraints.biggest.width / constraints.biggest.height >
              widget.designW / widget.designH
          ? constraints.biggest.height / widget.designH
          : constraints.biggest.width / widget.designW;
      return GestureDetector(
        behavior: widget.interactive ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onTapUp: widget.interactive ? _onTap : null,
        onPanStart: widget.interactive ? _onPanStart : null,
        onPanUpdate: widget.interactive ? _onPanUpdate : null,
        onPanEnd: widget.interactive ? _onPanEnd : null,
        onPanCancel: widget.interactive ? _onPanCancel : null,
        child: SizedBox(
          width: widget.designW * _scale,
          height: widget.designH * _scale,
          child: FittedBox(
            fit: BoxFit.fill,
            child: CustomPaint(
              size: Size(widget.designW, widget.designH),
              painter: _ShapesPainter(
                objects: widget.objects,
                selectedId: widget.selectedId,
                guides: _guides,
                scribblePts: _scribblePts,
              ),
            ),
          ),
        ),
      );
    });
  }

  Offset _toDesign(Offset local) => local / _scale;
  Map<String, dynamic>? _objectAt(Offset design) {
    for (final obj in widget.objects.reversed) {
      if (obj['locked'] == true) continue;
      if (_hit(obj, design)) return obj;
    }
    return null;
  }

  bool _hit(Map obj, Offset p) {
    final rot = ((obj['rotation'] ?? 0) as num).toDouble();
    final cx = (obj['x'] as num).toDouble() + (obj['w'] as num).toDouble() / 2;
    final cy = (obj['y'] as num).toDouble() + (obj['h'] as num).toDouble() / 2;
    final local = _rotateAround(p, Offset(cx, cy), -rot);
    final w = (obj['w'] as num).toDouble();
    final h = (obj['h'] as num).toDouble();
    return local.dx >= (obj['x'] as num).toDouble() - 2 &&
        local.dx <= (obj['x'] as num).toDouble() + w + 2 &&
        local.dy >= (obj['y'] as num).toDouble() - 2 &&
        local.dy <= (obj['y'] as num).toDouble() + h + 2;
  }

  Offset _rotateAround(Offset p, Offset c, double deg) {
    final r = deg * math.pi / 180.0;
    final cosv = math.cos(r);
    final sinv = math.sin(r);
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    return Offset(c.dx + dx * cosv - dy * sinv, c.dy + dx * sinv + dy * cosv);
  }

  // ---- handle geometry -------------------------------------------------------

  List<Offset> _corners(Map obj) {
    final x = (obj['x'] as num).toDouble();
    final y = (obj['y'] as num).toDouble();
    final w = (obj['w'] as num).toDouble();
    final h = (obj['h'] as num).toDouble();
    return [Offset(x, y), Offset(x + w, y), Offset(x + w, y + h), Offset(x, y + h)];
  }

  Offset _center(Map obj) {
    return Offset(
      (obj['x'] as num).toDouble() + (obj['w'] as num).toDouble() / 2,
      (obj['y'] as num).toDouble() + (obj['h'] as num).toDouble() / 2,
    );
  }

  Offset _rotateHandle(Map obj) {
    final c = _center(obj);
    final rot = ((obj['rotation'] ?? 0) as num).toDouble();
    final top = Offset(c.dx, (obj['y'] as num).toDouble() - 28);
    return _rotateAround(top, c, rot);
  }

  _GrabKind? _handleAt(Offset design, Map obj) {
    final hitR = 26 / _scale.clamp(0.2, 4.0);
    final rot = ((obj['rotation'] ?? 0) as num).toDouble();
    final c = _center(obj);
    for (final corner in _corners(obj)) {
      if ((_rotateAround(corner, c, rot) - design).distance <= hitR) {
        return _GrabKind.resize;
      }
    }
    if ((_rotateHandle(obj) - design).distance <= hitR) {
      return _GrabKind.rotate;
    }
    return null;
  }

  // ---- gestures ---------------------------------------------------------------

  void _onTap(TapUpDetails d) {
    if (!widget.interactive) return;
    if (widget.scribbleMode) return;
    final design = _toDesign(d.localPosition);
    final sel = widget.selectedId == null ? null : _find(widget.selectedId!);
    if (sel != null) {
      final handle = _handleAt(design, sel);
      if (handle != null) return; // handled by pan
    }
    final obj = _objectAt(design);
    widget.onSelect?.call(obj?['id'] as String?);
  }

  void _onPanStart(DragStartDetails d) {
    if (!widget.interactive) return;
    final design = _toDesign(d.localPosition);
    if (widget.scribbleMode) {
      setState(() => _scribblePts = [design]);
      return;
    }
    final sel = widget.selectedId == null ? null : _find(widget.selectedId!);
    if (sel != null) {
      final handle = _handleAt(design, sel);
      if (handle != null) {
        widget.onGestureStart?.call();
        setState(() {
          _grab = _Grab(
            id: sel['id'] as String,
            kind: handle,
            start: design,
            origin: _copyObj(sel),
          );
        });
        return;
      }
    }
    final obj = _objectAt(design);
    if (obj == null) {
      widget.onSelect?.call(null);
      return;
    }
    widget.onSelect?.call(obj['id'] as String);
    widget.onGestureStart?.call();
    setState(() {
      _grab = _Grab(id: obj['id'] as String, kind: _GrabKind.move, start: design, origin: _copyObj(obj));
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.interactive) return;
    final design = _toDesign(d.localPosition);
    if (widget.scribbleMode) {
      if (_scribblePts.isNotEmpty && (_scribblePts.last - design).distance < 4) return;
      setState(() => _scribblePts.add(design));
      return;
    }
    final grab = _grab;
    if (grab == null) return;
    final live = _find(grab.id);
    if (live == null) return;
    switch (grab.kind) {
      case _GrabKind.move:
        final o = grab.origin;
        double nx = (o['x'] as num).toDouble() + design.dx - grab.start.dx;
        double ny = (o['y'] as num).toDouble() + design.dy - grab.start.dy;
        final snapped = _snap(live, nx, ny, o);
        nx = snapped.x;
        ny = snapped.y;
        final updated = _copyObj(live);
        updated['x'] = nx;
        updated['y'] = ny;
        widget.onLive?.call(updated);
        setState(() => _guides = snapped.guides);
      case _GrabKind.resize:
        final o = grab.origin;
        final rot = ((o['rotation'] ?? 0) as num).toDouble();
        final c = Offset(
          (o['x'] as num).toDouble() + (o['w'] as num).toDouble() / 2,
          (o['y'] as num).toDouble() + (o['h'] as num).toDouble() / 2,
        );
        final local = _rotateAround(design, c, -rot);
        final cs = [
          Offset((o['x'] as num).toDouble(), (o['y'] as num).toDouble()),
          Offset((o['x'] as num).toDouble() + (o['w'] as num).toDouble(), (o['y'] as num).toDouble()),
          Offset((o['x'] as num).toDouble() + (o['w'] as num).toDouble(), (o['y'] as num).toDouble() + (o['h'] as num).toDouble()),
          Offset((o['x'] as num).toDouble(), (o['y'] as num).toDouble() + (o['h'] as num).toDouble()),
        ];
        // anchor = the corner farthest from the pointer
        var anchor = cs.first;
        for (final k in cs) {
          if ((k - local).distance > (anchor - local).distance) anchor = k;
        }
        var nw = (local.dx - anchor.dx).abs().clamp(8.0, double.infinity);
        var nh = (local.dy - anchor.dy).abs().clamp(8.0, double.infinity);
        final nc = Offset(
          anchor.dx < local.dx ? anchor.dx + nw / 2 : anchor.dx - nw / 2,
          anchor.dy < local.dy ? anchor.dy + nh / 2 : anchor.dy - nh / 2,
        );
        final updated = _copyObj(live);
        updated['w'] = nw;
        updated['h'] = nh;
        updated['x'] = nc.dx - nw / 2;
        updated['y'] = nc.dy - nh / 2;
        widget.onLive?.call(updated);
      case _GrabKind.rotate:
        final o = grab.origin;
        final c = Offset(
          (o['x'] as num).toDouble() + (o['w'] as num).toDouble() / 2,
          (o['y'] as num).toDouble() + (o['h'] as num).toDouble() / 2,
        );
        var deg = _angleBetween(design - c) - _angleBetween(grab.start - c) + ((o['rotation'] ?? 0) as num).toDouble();
        deg = deg % 360;
        // snap to 15° increments when close
        const step = 15.0;
        final near = (deg / step).round() * step;
        if ((deg - near).abs() < 4.0) deg = near.toDouble();
        final updated = _copyObj(live);
        updated['rotation'] = deg.abs();
        widget.onLive?.call(updated);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (widget.scribbleMode) {
      final pts = List<Offset>.from(_scribblePts);
      setState(() => _scribblePts = []);
      if (pts.length >= 2 && widget.onScribble != null) {
        widget.onScribble!(pts);
      }
      return;
    }
    final grab = _grab;
    if (grab == null) return;
    final live = _find(grab.id);
    setState(() {
      _grab = null;
      _guides = [];
    });
    if (live != null) {
      widget.onCommit?.call(live);
    }
  }

  void _onPanCancel() {
    setState(() {
      _grab = null;
      _guides = [];
      _scribblePts = [];
    });
  }

  double _angleBetween(Offset v) => math.atan2(v.dy, v.dx) * 180 / math.pi;

  Map<String, dynamic>? _find(String id) {
    for (final o in widget.objects) {
      if (o['id'] == id) return o;
    }
    return null;
  }

  Map<String, dynamic> _copyObj(Map o) => Map<String, dynamic>.from(o);

  // ---- smart guides ------------------------------------------------------------

  _SnapResult _snap(Map live, double nx, double ny, Map origin) {
    final w = (origin['w'] as num).toDouble();
    final h = (origin['h'] as num).toDouble();
    final guides = <_GuideLine>[];
    // candidate X positions: slide edges/center + other objects
    final candX = <double>[0, widget.designW / 2, widget.designW];
    final candY = <double>[0, widget.designH / 2, widget.designH];
    for (final other in widget.objects) {
      if (other['id'] == live['id']) continue;
      final ox = (other['x'] as num).toDouble();
      final oy = (other['y'] as num).toDouble();
      final ow = (other['w'] as num).toDouble();
      final oh = (other['h'] as num).toDouble();
      candX.addAll([ox, ox + ow / 2, ox + ow]);
      candY.addAll([oy, oy + oh / 2, oy + oh]);
    }
    double bestX = double.infinity;
    double bestY = double.infinity;
    for (final target in [nx, nx + w / 2, nx + w]) {
      for (final c in candX) {
        final d = (target - c).abs();
        if (d <= snapTol && d < bestX) {
          bestX = d;
          nx = c - (target - nx);
          guides.add(_GuideLine.x(c));
        }
      }
    }
    for (final target in [ny, ny + h / 2, ny + h]) {
      for (final c in candY) {
        final d = (target - c).abs();
        if (d <= snapTol && d < bestY) {
          bestY = d;
          ny = c - (target - ny);
          guides.add(_GuideLine.y(c));
        }
      }
    }
    return _SnapResult(x: nx, y: ny, guides: guides);
  }
}

enum _GrabKind { move, resize, rotate }

class _Grab {
  _Grab({required this.id, required this.kind, required this.start, required this.origin});
  final String id;
  final _GrabKind kind;
  final Offset start;
  final Map origin;
}

class _GuideLine {
  _GuideLine.x(this.pos) : axis = 'x';
  _GuideLine.y(this.pos) : axis = 'y';
  final String axis;
  final double pos;
}

class _SnapResult {
  _SnapResult({required this.x, required this.y, required this.guides});
  final double x;
  final double y;
  final List<_GuideLine> guides;
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _ShapesPainter extends CustomPainter {
  _ShapesPainter({
    required this.objects,
    required this.selectedId,
    required this.guides,
    required this.scribblePts,
  });

  final List<Map<String, dynamic>> objects;
  final String? selectedId;
  final List<_GuideLine> guides;
  final List<Offset> scribblePts;

  @override
  void paint(Canvas canvas, Size size) {
    for (final obj in objects) {
      // Content-carrying objects (text boxes, images, icons, media, tables)
      // render as CONTENT in the sibling content layer — their vector
      // silhouette stays gesture/selection geometry only, never paint.
      if (ObjectContent.hasContent(obj)) continue;
      _paintObject(canvas, obj);
    }
    // scribble-in-progress
    if (scribblePts.length >= 2) {
      final p = Path()..moveTo(scribblePts.first.dx, scribblePts.first.dy);
      for (final pt in scribblePts.skip(1)) {
        p.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0xFFFF3B30)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }
    // selection overlay
    if (selectedId != null) {
      for (final o in objects) {
        if (o['id'] == selectedId) {
          _paintSelection(canvas, o);
          break;
        }
      }
    }
    // smart guides
    for (final g in guides) {
      final paint = Paint()
        ..color = const Color(0xFFFF0099)
        ..strokeWidth = 1.5;
      if (g.axis == 'x') {
        canvas.drawLine(Offset(g.pos, 0), Offset(g.pos, 720), paint);
      } else {
        canvas.drawLine(Offset(0, g.pos), Offset(1280, g.pos), paint);
      }
    }
  }

  void _paintSelection(Canvas canvas, Map obj) {
    final rot = ((obj['rotation'] ?? 0) as num).toDouble();
    final c = _centerOf(obj);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot * math.pi / 180);
    canvas.translate(-c.dx, -c.dy);
    final rect = Rect.fromLTWH(
      (obj['x'] as num).toDouble(),
      (obj['y'] as num).toDouble(),
      (obj['w'] as num).toDouble(),
      (obj['h'] as num).toDouble(),
    );
    final outline = Paint()
      ..color = const Color(0xFFFF3B30)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect.deflate(1), outline);
    final handle = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;
    final handleBorder = Paint()
      ..color = const Color(0xFFFF3B30)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const hs = 7.0;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      canvas.drawCircle(corner, hs, handle);
      canvas.drawCircle(corner, hs, handleBorder);
    }
    // rotate handle above top-center
    final rh = Offset(rect.center.dx, rect.top - 28);
    canvas.drawLine(Offset(rect.center.dx, rect.top), Offset(rect.center.dx, rect.top - 28), outline);
    canvas.drawCircle(rh, hs, handle);
    canvas.drawCircle(rh, hs, handleBorder);
    canvas.restore();
  }

  Offset _centerOf(Map obj) => Offset(
        (obj['x'] as num).toDouble() + (obj['w'] as num).toDouble() / 2,
        (obj['y'] as num).toDouble() + (obj['h'] as num).toDouble() / 2,
      );

  void _paintObject(Canvas canvas, Map obj) {
    final rot = ((obj['rotation'] ?? 0) as num).toDouble();
    final opacity = ((obj['opacity'] ?? 1) as num).toDouble().clamp(0.0, 1.0);
    final path = objectPath(obj);
    if (path == null) return;
    final c = _centerOf(obj);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot * math.pi / 180);
    canvas.translate(-c.dx, -c.dy);
    final open = isOpenPreset(obj);

    // shadow
    final effects = obj['effects'];
    if (effects is Map) {
      final sh = effects['shadow'];
      if (sh is Map) {
        final dx = (sh['dx'] ?? 0) as num;
        final dy = (sh['dy'] ?? 0) as num;
        final blur = ((sh['blur'] ?? 12) as num).toDouble();
        final alpha = (((sh['opacity'] ?? 0.45) as num).toDouble() * opacity).clamp(0.0, 1.0);
        canvas.drawPath(
          path.shift(Offset(dx.toDouble(), dy.toDouble())),
          Paint()
            ..color = _color((sh['color'] ?? '000000').toString(), alpha)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
        );
      }
      final gl = effects['glow'];
      if (gl is Map) {
        final blur = ((gl['blur'] ?? 12) as num).toDouble();
        canvas.drawPath(
          path,
          Paint()
            ..color = _color((gl['color'] ?? 'D03028').toString(), 0.35 * opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = blur
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
        );
      }
    }

    // fill
    if (!open) {
      final fillPaint = _fillPaint(obj, opacity);
      if (fillPaint != null) canvas.drawPath(path, fillPaint);
    }

    // stroke
    final stroke = obj['stroke'];
    if (stroke is Map) {
      var width = (stroke['width'] ?? 0) as num;
      if (open && width.toDouble() <= 0) width = 2;
      if (width.toDouble() > 0) {
        final dash = (stroke['dash'] ?? 'solid').toString();
        Path toDraw = path;
        if (dash != 'solid') {
          toDraw = dashPath(path, _dashPattern(dash, width.toDouble()));
        }
        canvas.drawPath(
          toDraw,
          Paint()
            ..color = _color((stroke['color'] ?? '17181A').toString(), opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = width.toDouble()
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        if (open) {
          _drawArrowheads(canvas, obj, path, opacity);
        }
      }
    }
    canvas.restore();
  }

  void _drawArrowheads(Canvas canvas, Map obj, Path path, double opacity) {
    final stroke = obj['stroke'] as Map;
    final width = ((stroke['width'] ?? 2) as num).toDouble().clamp(2.0, 40.0);
    final size = (width * 3).clamp(10.0, 60.0).toDouble();
    final color = _color((stroke['color'] ?? '17181A').toString(), opacity);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final endTangent = _tangentAt(metrics, true);
    final startTangent = _tangentAt(metrics, false);
    final paint = Paint()..color = color;
    if ((stroke['end_arrow'] ?? 'none') != 'none' && endTangent != null) {
      canvas.drawPath(_arrowHead(endTangent, size), paint);
    }
    if ((stroke['start_arrow'] ?? 'none') != 'none' && startTangent != null) {
      canvas.drawPath(_arrowHead(startTangent, size), paint);
    }
  }

  /// Tangent (position + outward direction) at the start or end of a path.
  _Tangent? _tangentAt(List<PathMetric> metrics, bool atEnd) {
    final m = metrics.first;
    final len = m.length;
    if (len < 1e-6) return null;
    final off = atEnd ? math.max(0.0, len - 0.01) : 0.01;
    final tan = m.getTangentForOffset(off);
    if (tan == null) return null;
    var dir = Offset(math.cos(tan.angle), math.sin(tan.angle));
    if (!atEnd) dir = Offset(-dir.dx, -dir.dy);
    return _Tangent(tan.position, dir);
  }

  Path _arrowHead(_Tangent t, double size) {
    final base = t.pos - t.dir * size;
    final perp = Offset(-t.dir.dy, t.dir.dx);
    return Path()
      ..moveTo(t.pos.dx, t.pos.dy)
      ..lineTo(base.dx + perp.dx * size * 0.4, base.dy + perp.dy * size * 0.4)
      ..lineTo(base.dx - perp.dx * size * 0.4, base.dy - perp.dy * size * 0.4)
      ..close();
  }

  Paint? _fillPaint(Map obj, double opacity) {
    final fill = obj['fill'];
    if (fill is! Map) return null;
    final type = (fill['type'] ?? 'none').toString();
    final rect = Rect.fromLTWH(
      (obj['x'] as num).toDouble(),
      (obj['y'] as num).toDouble(),
      (obj['w'] as num).toDouble(),
      (obj['h'] as num).toDouble(),
    );
    switch (type) {
      case 'solid':
        return Paint()..color = _color((fill['color'] ?? 'D03028').toString(), opacity);
      case 'linear_gradient':
        final angle = ((fill['angle'] ?? 0) as num).toDouble() * math.pi / 180;
        final axis = Offset(math.cos(angle), math.sin(angle));
        return Paint()
 ..shader = LinearGradient(
            colors: [
              _color((fill['from'] ?? 'D03028').toString(), opacity),
              _color((fill['to'] ?? 'F7F6F3').toString(), opacity),
            ],
            begin: Alignment(-axis.dx, -axis.dy),
            end: Alignment(axis.dx, axis.dy),
          ).createShader(rect);
      case 'radial_gradient':
        return Paint()
          ..shader = RadialGradient(
            colors: [
              _color((fill['from'] ?? 'D03028').toString(), opacity),
              _color((fill['to'] ?? 'F7F6F3').toString(), opacity),
            ],
          ).createShader(rect);
      default:
        return null;
    }
  }

  List<double> _dashPattern(String dash, double w) {
    switch (dash) {
      case 'dash':
        return [w * 3, w * 2];
      case 'dot':
        return [w, w * 2];
      case 'dash_dot':
        return [w * 3, w * 2, w, w * 2];
      default:
        return [w * 3, w * 2];
    }
  }

  Color _color(String hex, double alpha) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
    return Color(0xFF000000 | (v & 0xFFFFFF)).withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  @override
  bool shouldRepaint(_ShapesPainter old) =>
      old.objects != objects || old.selectedId != selectedId || old.guides != guides || old.scribblePts != scribblePts;
}

class _Tangent {
  _Tangent(this.pos, this.dir);
  final Offset pos;
  final Offset dir;
}

// ---------------------------------------------------------------------------
// Geometry (mirrors core/src/shapes.rs — one representation everywhere)
// ---------------------------------------------------------------------------

bool isOpenPreset(Map obj) {
  final preset = (obj['preset'] ?? 'rectangle').toString();
  switch (preset) {
    case 'line':
    case 'wave':
    case 'zigzag':
      return true;
    default:
      return obj['closed'] == false;
  }
}

Path? objectPath(Map obj) {
  final preset = (obj['preset'] ?? 'rectangle').toString();
  final x = (obj['x'] as num).toDouble();
  final y = (obj['y'] as num).toDouble();
  final w = (obj['w'] as num).toDouble();
  final h = (obj['h'] as num).toDouble();
  final rect = Rect.fromLTWH(x, y, w, h);
  switch (preset) {
    case 'rectangle':
      return Path()..addRect(rect);
    case 'rounded':
      final r = rect.shortestSide * 0.18;
      return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
    case 'ellipse':
      return Path()..addOval(rect);
    case 'donut':
      final inner = Rect.fromCenter(center: rect.center, width: w * 0.45, height: h * 0.45);
      return Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(rect)
        ..addOval(inner);
    case 'line':
      return Path()
        ..moveTo(x, y)
        ..lineTo(x + w, y + h);
    case 'path':
      final pts = obj['points'];
      if (pts is! List || pts.isEmpty) return null;
      final p = Path();
      var first = true;
      for (final pt in pts.whereType<Map>()) {
        final px = x + ((pt['x'] ?? 0) as num).toDouble() * w;
        final py = y + ((pt['y'] ?? 0) as num).toDouble() * h;
        if (first) {
          p.moveTo(px, py);
          first = false;
        } else {
          p.lineTo(px, py);
        }
      }
      // boolean-subtract holes (even-odd)
      final holes = obj['holes'];
      if (holes is List && holes.isNotEmpty) {
        p.fillType = PathFillType.evenOdd;
        for (final hole in holes.whereType<List>()) {
          var hFirst = true;
          for (final pt in hole.whereType<Map>()) {
            final px = x + ((pt['x'] ?? 0) as num).toDouble() * w;
            final py = y + ((pt['y'] ?? 0) as num).toDouble() * h;
            if (hFirst) {
              p.moveTo(px, py);
              hFirst = false;
            } else {
              p.lineTo(px, py);
            }
          }
          if (hole.length > 2) p.close();
        }
      }
      if (obj['closed'] == true && pts.length > 2) p.close();
      return p;
    default:
      final poly = presetPolygon(preset, w, h);
      if (poly.length < 2) return null;
      final p = Path()..moveTo(x + poly.first.dx, y + poly.first.dy);
      for (final pt in poly.skip(1)) {
        p.lineTo(x + pt.dx, y + pt.dy);
      }
      if (isOpenPreset(obj)) return p;
      p.close();
      return p;
  }
}

List<Offset> presetPolygon(String name, double w, double h) {
  final wv = w < 1 ? 1.0 : w;
  final hv = h < 1 ? 1.0 : h;
  Offset p(double x, double y) => Offset(x, y);
  switch (name) {
    case 'triangle':
      return regularPolygon(3, wv, hv);
    case 'rt_triangle':
      return [p(0, hv), p(wv, hv), p(0, 0)];
    case 'diamond':
      return [p(wv / 2, 0), p(wv, hv / 2), p(wv / 2, hv), p(0, hv / 2)];
    case 'parallelogram':
      return [p(wv * 0.22, 0), p(wv, 0), p(wv * 0.78, hv), p(0, hv)];
    case 'trapezoid':
      return [p(wv * 0.2, 0), p(wv * 0.8, 0), p(wv, hv), p(0, hv)];
    case 'pentagon':
      return regularPolygon(5, wv, hv);
    case 'hexagon':
      return regularPolygon(6, wv, hv);
    case 'heptagon':
      return regularPolygon(7, wv, hv);
    case 'octagon':
      return regularPolygon(8, wv, hv);
    case 'nonagon':
      return regularPolygon(9, wv, hv);
    case 'decagon':
      return regularPolygon(10, wv, hv);
    case 'dodecagon':
      return regularPolygon(12, wv, hv);
    case 'star5':
      return star(5, 0.42, wv, hv);
    case 'star6':
      return star(6, 0.55, wv, hv);
    case 'star8':
      return star(8, 0.62, wv, hv);
    case 'burst8':
      return star(8, 0.78, wv, hv);
    case 'arrow_right':
      return arrow(wv, hv);
    case 'arrow_left':
      return arrow(wv, hv).map((e) => p(wv - e.dx, e.dy)).toList();
    case 'arrow_up':
      return arrowUp(wv, hv);
    case 'arrow_down':
      return arrowUp(wv, hv).map((e) => p(e.dx, hv - e.dy)).toList();
    case 'double_arrow':
      {
        final head = wv * 0.3;
        final bar = hv * 0.28;
        return [
          p(0, hv / 2),
          p(head, hv / 2 - bar),
          p(wv - head, hv / 2 - bar),
          p(wv, hv / 2),
          p(wv - head, hv / 2 + bar),
          p(head, hv / 2 + bar),
        ];
      }
    case 'chevron_right':
      {
        final c = wv * 0.5;
        return [p(0, 0), p(c, 0), p(wv, hv / 2), p(c, hv), p(0, hv), p(c, hv / 2)];
      }
    case 'cross':
      {
        const t = 0.34;
        return [
          p(wv * (1 - t) / 2, 0),
          p(wv * (1 + t) / 2, 0),
          p(wv * (1 + t) / 2, hv * (1 - t) / 2),
          p(wv, hv * (1 - t) / 2),
          p(wv, hv * (1 + t) / 2),
          p(wv * (1 + t) / 2, hv * (1 + t) / 2),
          p(wv * (1 + t) / 2, hv),
          p(wv * (1 - t) / 2, hv),
          p(wv * (1 - t) / 2, hv * (1 + t) / 2),
          p(0, hv * (1 + t) / 2),
          p(0, hv * (1 - t) / 2),
          p(wv * (1 - t) / 2, hv * (1 - t) / 2),
        ];
      }
    case 'heart':
      return heart(wv, hv);
    case 'moon':
      return moon(wv, hv);
    case 'banner':
      {
        final notch = wv * 0.12;
        return [p(0, 0), p(wv, 0), p(wv - notch, hv / 2), p(wv, hv), p(0, hv), p(notch, hv / 2)];
      }
    case 'ribbon':
      return ribbon(wv, hv);
    case 'bubble':
      return bubble(wv, hv);
    case 'wave':
      return wave(wv, hv);
    case 'zigzag':
      return zigzag(wv, hv);
    default:
      return [p(0, 0), p(wv, 0), p(wv, hv), p(0, hv)];
  }
}

List<Offset> regularPolygon(int k, double w, double h) {
  final out = <Offset>[];
  for (var i = 0; i < k; i++) {
    final a = i * 2 * math.pi / k - math.pi / 2;
    out.add(Offset(w / 2 + w / 2 * math.cos(a), h / 2 + h / 2 * math.sin(a)));
  }
  return out;
}

List<Offset> star(int tips, double inner, double w, double h) {
  final out = <Offset>[];
  for (var i = 0; i < tips * 2; i++) {
    final r = i.isEven ? 1.0 : inner;
    final a = i * math.pi / tips - math.pi / 2;
    out.add(Offset(w / 2 + w / 2 * r * math.cos(a), h / 2 + h / 2 * r * math.sin(a)));
  }
  return out;
}

List<Offset> arrow(double w, double h) {
  final head = w * 0.45;
  final bar = h / 4;
  return [
    Offset(0, h / 2 - bar),
    Offset(w - head, h / 2 - bar),
    Offset(w - head, 0),
    Offset(w, h / 2),
    Offset(w - head, h),
    Offset(w - head, h / 2 + bar),
    Offset(0, h / 2 + bar),
  ];
}

List<Offset> arrowUp(double w, double h) {
  final head = h * 0.45;
  final bar = w / 4;
  return [
    Offset(w / 2 - bar, h),
    Offset(w / 2 - bar, head),
    Offset(0, head),
    Offset(w / 2, 0),
    Offset(w, head),
    Offset(w / 2 + bar, head),
    Offset(w / 2 + bar, h),
  ];
}

List<Offset> heart(double w, double h) {
  final out = <Offset>[];
  for (var i = 0; i < 40; i++) {
    final t = i / 40 * 2 * math.pi;
    final x = 16 * math.pow(math.sin(t), 3).toDouble();
    final y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) + math.cos(4 * t));
    out.add(Offset(((x + 17) / 34 * w).clamp(0, w).toDouble(), ((y + 17) / 34 * h).clamp(0, h).toDouble()));
  }
  return out;
}

List<Offset> moon(double w, double h) {
  final out = <Offset>[];
  for (var i = 0; i < 24; i++) {
    final a = i / 24 * 2 * math.pi;
    out.add(Offset(w / 2 + w / 2 * math.cos(a), h / 2 + h / 2 * math.sin(a)));
  }
  final cx = w * 0.72;
  return out.map((pt) {
    if (pt.dx > w * 0.5) {
      final d = (pt.dy - h / 2) / (h / 2);
      return Offset(cx - w * 0.42 * math.sqrt(math.max(0, 1 - d * d)), pt.dy);
    }
    return pt;
  }).toList();
}

List<Offset> ribbon(double w, double h) {
  final t = h * 0.45;
  return [
    const Offset(0, 0),
    Offset(w, 0),
    Offset(w, t),
    Offset(w * 0.75, t),
    Offset(w, h),
    Offset(w * 0.5, t * 1.15),
    Offset(0, h),
    Offset(w * 0.25, t),
    Offset(0, t),
  ];
}

List<Offset> bubble(double w, double h) {
  final hb = h * 0.75;
  return [
    const Offset(0, 0),
    Offset(w, 0),
    Offset(w, hb),
    Offset(w * 0.3, hb),
    Offset(w * 0.42, h),
    Offset(w * 0.12, hb),
    Offset(0, hb),
  ];
}

List<Offset> wave(double w, double h) {
  final out = <Offset>[];
  final amp = h / 2;
  for (var i = 0; i <= 32; i++) {
    final t = i / 32;
    out.add(Offset(t * w, h / 2 + amp * math.sin(t * 2 * math.pi)));
  }
  return out;
}

List<Offset> zigzag(double w, double h) {
  const n = 8;
  final out = <Offset>[];
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    final y = i.isEven ? h / 4 : h * 3 / 4;
    out.add(Offset(t * w, y));
  }
  return out;
}

/// Manually dash a path (design-px pattern).
Path dashPath(Path src, List<double> pattern) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    var d = 0.0;
    var i = 0;
    while (d < m.length) {
      final len = pattern[i % pattern.length];
      final seg = m.extractPath(d, math.min(d + len, m.length));
      if (i.isEven) out.addPath(seg, Offset.zero);
      d += len;
      i++;
    }
  }
  return out;
}
