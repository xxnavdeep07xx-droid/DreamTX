import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/outline_math.dart';

/// Outline view: the body preview under each slide's title.
void main() {
  test('the preview is the body text, without the title', () {
    expect(
      outlineBodyPreview({'title': 'Plan', 'body': 'Ship it', 'n': 3}),
      'Ship it',
    );
  });

  test('several strings join with a middle dot; whitespace collapses', () {
    expect(
      outlineBodyPreview({'title': 'T', 'a': '  one\n  two ', 'b': 'three'}),
      'one two · three',
    );
  });

  test('empty and non-text values are skipped', () {
    expect(outlineBodyPreview({'title': 'T', 'a': '   ', 'list': [1, 2]}), '');
    expect(outlineBodyPreview({}), '');
  });

  test('a long preview is cut to the limit with an ellipsis', () {
    final long = 'x' * 300;
    final p = outlineBodyPreview({'body': long}, max: 20);
    expect(p.length, 20);
    expect(p.endsWith('…'), isTrue);
  });
}
