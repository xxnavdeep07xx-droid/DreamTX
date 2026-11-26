/// Outline view (View tab): the text a slide shows under its title. Pure,
/// so the rules are unit-tested.

/// The slide's body text, one line: every non-empty string in [content]
/// except the title, whitespace collapsed, joined with a middle dot, and
/// cut to [max] characters with an ellipsis. Non-text values (lists,
/// maps, numbers) are skipped.
String outlineBodyPreview(Map content, {int max = 120}) {
  final parts = <String>[];
  content.forEach((key, value) {
    if (key == 'title' || value is! String) return;
    final t = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) parts.add(t);
  });
  final joined = parts.join(' · ');
  if (joined.length <= max) return joined;
  return '${joined.substring(0, max - 1).trimRight()}…';
}
