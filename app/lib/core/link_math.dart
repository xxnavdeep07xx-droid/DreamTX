// Tap-action (link) rules for canvas objects. Pure, so the rules are
// unit-tested. The URL rule mirrors the core's `Link::safe_url`, so the
// sheet never offers a link the exporters would drop.

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
