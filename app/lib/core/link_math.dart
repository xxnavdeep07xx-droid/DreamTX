// Tap-action (link) rules for canvas objects. Pure, so the rules are
// unit-tested. The URL rule mirrors the core's `Link::safe_url`, so the
// sheet never offers a link the exporters would drop.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Whether [raw] is a link the exporters accept: http, https, or mailto,
/// with a target after the scheme and no whitespace or control characters.
bool isSafeLinkUrl(String raw) {
  final t = raw.trim();
  final lower = t.toLowerCase();
  const schemes = ['https://', 'http://', 'mailto:'];
  final okScheme = schemes.any((p) => lower.length > p.length && lower.startsWith(p));
  final clean = !RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(t);
  return okScheme && clean;
}

/// The link stored on an object, or null. Malformed link maps count as none.
Map<String, dynamic>? linkOf(Map obj) {
  final l = obj['link'];
  if (l is! Map) return null;
  final kind = l['kind'];
  final target = l['target'];
  if (target is! String || target.isEmpty) return null;
  if (kind != 'url' && kind != 'slide') return null;
  return {'kind': kind, 'target': target};
}

/// The stored link for a typed web address, or null when it is not safe.
Map<String, dynamic>? urlLink(String raw) {
  if (!isSafeLinkUrl(raw)) return null;
  return {'kind': 'url', 'target': raw.trim()};
}

/// The stored link that jumps to the slide with [slideId].
Map<String, dynamic> slideLink(String slideId) => {'kind': 'slide', 'target': slideId};

/// One line for the object sheet: the URL, the target slide with its
/// number and title, or a note when the target slide no longer exists.
String linkDescription(
  Map<String, dynamic>? link,
  List<Map<String, dynamic>> slides,
  String Function(Map<String, dynamic> slide) titleOf,
) {
  if (link == null) return 'No link';
  if (link['kind'] == 'url') return link['target'] as String;
  final i = slides.indexWhere((s) => s['id'] == link['target']);
  if (i < 0) return 'Target slide is missing';
  return 'Slide ${i + 1}: ${titleOf(slides[i])}';
}

/// Where a screen tap lands in slide design coordinates. The slide frame is
/// the largest rectangle with the design's aspect, centred on the screen
/// (how the presenter lays out a page). Null when the tap is outside it.
Offset? designPointOf(Offset tap, Size screen, Size design) {
  if (screen.width <= 0 || screen.height <= 0 || design.width <= 0 || design.height <= 0) {
    return null;
  }
  final aspect = design.width / design.height;
  final double bw;
  final double bh;
  if (screen.width / screen.height > aspect) {
    bh = screen.height;
    bw = bh * aspect;
  } else {
    bw = screen.width;
    bh = bw / aspect;
  }
  final x = tap.dx - (screen.width - bw) / 2;
  final y = tap.dy - (screen.height - bh) / 2;
  if (x < 0 || y < 0 || x > bw || y > bh) return null;
  return Offset(x / bw * design.width, y / bh * design.height);
}

/// The topmost linked object under a design-space point, or null. Objects
/// are in z-order (last is on top), and rotation is undone around the
/// object's centre, so a rotated link is hit where it is drawn.
Map<String, dynamic>? linkObjectAt(List<Map<String, dynamic>> objects, Offset p) {
  for (final obj in objects.reversed) {
    if (linkOf(obj) == null) continue;
    final x = ((obj['x'] as num?) ?? 0).toDouble();
    final y = ((obj['y'] as num?) ?? 0).toDouble();
    final w = ((obj['w'] as num?) ?? 1).toDouble();
    final h = ((obj['h'] as num?) ?? 1).toDouble();
    final rot = ((obj['rotation'] as num?) ?? 0).toDouble();
    final dx = p.dx - (x + w / 2);
    final dy = p.dy - (y + h / 2);
    final a = -rot * math.pi / 180;
    final rx = dx * math.cos(a) - dy * math.sin(a);
    final ry = dx * math.sin(a) + dy * math.cos(a);
    if (rx.abs() <= w / 2 && ry.abs() <= h / 2) return obj;
  }
  return null;
}
