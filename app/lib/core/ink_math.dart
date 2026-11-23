library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Ink capture for the Draw tab. Pure functions, no widget deps —
/// unit-tested directly (`ink_math_test.dart`) and shared by BOTH sides of
/// a stroke: the capture layer runs it on the growing raw list for the
/// live preview, the editor commits its output verbatim — so the last
/// preview frame IS the committed geometry, by construction.
///
/// Why smoothing happens at capture time and NOT at render: the core
/// exporters (PPTX + PDF) draw the stored polyline as straight segments.
/// Rendering a smoothed interpretation of raw points would diverge from
/// every export — broken WYSIWYG. Instead the pipeline produces the one
/// polyline every renderer sees: canvas, exporters, MCP round-trips.

/// The Draw tab's tools. `null` in the layer APIs means "not drawing" —
/// gestures fall through to selection / move / resize / rotate.
enum InkTool { pen, highlighter, eraser }

/// The style a stroke is painted and committed with. Design-px width and
/// RRGGBB hex — the same vocabulary the deck model's `Shape.stroke` and
/// `Shape.opacity` speak, so committing is a field copy, never a
/// translation. Immutable; [==] covers all three fields (painter repaint
/// checks depend on it).
class InkStyle {
  const InkStyle({
    required this.colorHex,
    required this.width,
    this.opacity = 1.0,
  });

  /// RRGGBB (uppercase, no '#') — `hexToColor` accepts it back.
  final String colorHex;

  /// Design px (the 1280x720-ish space), so widths are zoom-proof: the
  /// editor canvas is fit-scaled, there is no free zoom.
  final double width;

  /// 0..1 object opacity — the highlighter's translucency rides the SAME
  /// field every other object uses, which is why it already exports
  /// translucent in PPTX and PDF with zero exporter changes.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is InkStyle &&
      other.colorHex == colorHex &&
      other.width == width &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(colorHex, width, opacity);
}

/// The full capture pipeline over a stroke's raw design-space points:
///
/// ```
/// raw → thin (≥ [minSpacing] apart) → simplify (Douglas-Peucker, [simplifyEps])
///     → smooth (quadratic-midpoint, [resamplePerSegment] pts/segment)
///     → budget (≤ [maxPoints]; over it, re-simplify at ε×1.5 until it fits)
/// ```
///
/// The output is what gets stored, rendered, and exported — the single
/// truth. Deterministic: the same raw input always yields the same
/// polyline. Endpoints are always preserved (the stroke starts and lifts
/// exactly where the finger did).
List<Offset> inkCapture(
  List<Offset> raw, {
  double minSpacing = 6.0,
  double simplifyEps = 2.0,
  int resamplePerSegment = 4,
  int maxPoints = 400,
}) {
  final pts = _thin(raw, minSpacing);
  if (pts.length < 2) return pts;
  var eps = simplifyEps;
  // The budget loop re-runs simplify + smooth over the SAME thinned input
  // with a coarser epsilon, so the result always stays a simplification
  // of the same stroke (never a resimplification of its own output).
  while (true) {
    final simplified = _simplify(pts, eps);
    final smoothed = _smoothResample(simplified, resamplePerSegment);
    if (smoothed.length <= maxPoints || simplified.length <= 4) {
      return smoothed;
    }
    eps *= 1.5;
  }
}

/// Capture-time thinning: keep a point only when it is at least
/// [minSpacing] from the last KEPT point, then always keep the final raw
/// point (the lift position) so the stroke ends on the glass, not a
/// spacing boundary. A stationary gesture (everything within spacing of
/// the first point) yields a single point — dropped by the >=2 rule
/// downstream, no degenerate zero-length strokes.
List<Offset> _thin(List<Offset> pts, double minSpacing) {
  if (pts.length < 2) return List<Offset>.of(pts);
  final out = <Offset>[pts.first];
  for (final p in pts.skip(1)) {
    if ((p - out.last).distance >= minSpacing) out.add(p);
  }
  if ((pts.last - out.last).distance > 0) out.add(pts.last);
  return out;
}

/// Douglas-Peucker over an open polyline; the anchors (first + last) are
/// always kept. Iterative (explicit stack) rather than recursive — a long
/// scribble can carry thousands of thinned points and recursion depth is
/// an unbounded worst case on noisy input.
List<Offset> _simplify(List<Offset> pts, double eps) {
  if (pts.length < 3) return pts;
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <int>[0, pts.length - 1];
  while (stack.length >= 2) {
    final hi = stack.removeLast();
    final lo = stack.removeLast();
    if (hi <= lo + 1) continue;
    var maxD = -1.0;
    var idx = -1;
    for (var i = lo + 1; i < hi; i++) {
      final d = _segmentDistance(pts[i], pts[lo], pts[hi]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > eps) {
      keep[idx] = true;
      stack
        ..add(lo)
        ..add(idx)
        ..add(idx)
        ..add(hi);
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}

/// Perpendicular-ish distance from [p] to the segment [a]-[b]: the
/// clamped projection distance, degenerating to point distance for a
/// zero-length segment.
double _segmentDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return (p - a).distance;
  // The clamped projection parameter — written out because dart:ui's
  // Offset carries no dot product, only the operators.
  final ap = p - a;
  var t = (ap.dx * ab.dx + ap.dy * ab.dy) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  return (p - (a + ab * t)).distance;
}

/// Quadratic-midpoint resampling — the canonical freehand smoothing
/// scheme: each interior point becomes the control point of a quadratic
/// from the running position to the midpoint of the NEXT segment, plus a
/// straight tail from the last midpoint to the lift point. The curve
/// leaves the anchors untouched and rounds the corners a finger actually
/// rounds. [perSegment] samples per quadratic keep the stored polyline
/// dense enough that every renderer's straight-segment drawing of it is
/// visually indistinguishable from the true curve.
List<Offset> _smoothResample(List<Offset> pts, int perSegment) {
  if (pts.length < 3) return List<Offset>.of(pts);
  final out = <Offset>[pts.first];
  var current = pts.first;
  for (var i = 1; i < pts.length - 1; i++) {
    final end = Offset(
      (pts[i].dx + pts[i + 1].dx) / 2,
      (pts[i].dy + pts[i + 1].dy) / 2,
    );
    for (var j = 1; j <= perSegment; j++) {
      out.add(_quadAt(current, pts[i], end, j / perSegment));
    }
    current = end;
  }
  out.add(pts.last);
  return out;
}

/// The quadratic Bezier B(t) with control [c], from [a] to [b].
Offset _quadAt(Offset a, Offset c, Offset b, double t) {
  final u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
    u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy,
  );
}

// ---------------------------------------------------------------------------
// The eraser — sweep sampling + the scribble-signature hit-test
// ---------------------------------------------------------------------------

/// The eraser's base reach in design px (≈7.5dp on screen for a 16:9
/// deck): the corridor radius before the target's own half stroke width
/// is added.
const double kInkEraserRadius = 24.0;

/// Densify one pointer step into corridor samples — the eraser must cover
/// the path BETWEEN pointer updates too, so a fast swipe never jumps over
/// a stroke. Both endpoints are included; the step (12px design) is under
/// half the corridor, so consecutive discs overlap generously.
List<Offset> inkSweepSamples(Offset from, Offset to, {double step = 12.0}) {
  final d = (to - from).distance;
  if (d <= step) return [from, to];
  final n = (d / step).ceil();
  return [
    for (var i = 0; i <= n; i++)
      Offset(
        from.dx + (to.dx - from.dx) * i / n,
        from.dy + (to.dy - from.dy) * i / n,
      ),
  ];
}

/// The objects an eraser sweep touches — ONLY scribble-signature path
/// objects: `preset == 'path'`, no `content` payload, not `locked`.
/// Content objects (text boxes, images, icons, media, tables) and preset
/// shapes keep their explicit delete flows — an accidental eraser sweep
/// must never eat content. Rotation is honored: each probe point is
/// rotated into the object's local frame around its bbox center, the
/// same center+angle the gesture math and selection chrome rotate around.
///
/// The corridor is [radius] (design px, [kInkEraserRadius] by default)
/// plus half the target's own stroke width; the probe is any [sweep]
/// sample within that reach of the object's normalized polyline.
List<String> inkEraseHits(
  List<Map<String, dynamic>> objects,
  List<Offset> sweep, {
  double radius = kInkEraserRadius,
}) {
  final hits = <String>[];
  for (final obj in objects) {
    if (obj['preset'] != 'path') continue;
    if (obj['content'] != null) continue;
    if (obj['locked'] == true) continue;
    final pts = obj['points'];
    if (pts is! List || pts.length < 2) continue;
    final ox = ((obj['x'] ?? 0) as num).toDouble();
    final oy = ((obj['y'] ?? 0) as num).toDouble();
    final ow = ((obj['w'] ?? 1) as num).toDouble();
    final oh = ((obj['h'] ?? 1) as num).toDouble();
    final rot = ((obj['rotation'] ?? 0) as num?)?.toDouble() ?? 0.0;
    final stroke = obj['stroke'];
    final halfStroke = stroke is Map
        ? ((stroke['width'] ?? 0) as num).toDouble() / 2
        : 0.0;
    final reach = radius + halfStroke;
    final cx = ox + ow / 2;
    final cy = oy + oh / 2;
    // The polyline in the object's local (unrotated) frame.
    final poly = <Offset>[
      for (final pt in pts.whereType<Map>())
        Offset(
          ox + ((pt['x'] ?? 0) as num).toDouble() * ow,
          oy + ((pt['y'] ?? 0) as num).toDouble() * oh,
        ),
    ];
    var touched = false;
    for (final s in sweep) {
      if (touched) break;
      // Rotate the probe into the local frame (rotation == 0 fast path).
      Offset p = s;
      if (rot != 0) {
        final r = -rot * math.pi / 180.0;
        final dx = s.dx - cx;
        final dy = s.dy - cy;
        p = Offset(
          cx + dx * math.cos(r) - dy * math.sin(r),
          cy + dx * math.sin(r) + dy * math.cos(r),
        );
      }
      // The bbox prefilter, inflated by the reach.
      if (p.dx < ox - reach || p.dx > ox + ow + reach) continue;
      if (p.dy < oy - reach || p.dy > oy + oh + reach) continue;
      for (var i = 1; i < poly.length; i++) {
        if (_segmentDistance(p, poly[i - 1], poly[i]) <= reach) {
          touched = true;
          break;
        }
      }
    }
    if (touched) hits.add(obj['id'] as String);
  }
  return hits;
}
