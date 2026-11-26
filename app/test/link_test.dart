import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/link_math.dart';

/// Object links: the URL rule (mirrors the core), the stored shape, and the
/// one-line description the object sheet shows.
void main() {
  group('isSafeLinkUrl', () {
    test('accepts http, https, and mailto with a target', () {
      expect(isSafeLinkUrl('https://example.com/a?x=1'), isTrue);
      expect(isSafeLinkUrl('HTTP://example.com'), isTrue);
      expect(isSafeLinkUrl('mailto:hi@example.com'), isTrue);
    });

    test('rejects other schemes, empty targets, and whitespace', () {
      expect(isSafeLinkUrl('javascript:alert(1)'), isFalse);
      expect(isSafeLinkUrl('file:///etc/passwd'), isFalse);
      expect(isSafeLinkUrl('https://'), isFalse);
      expect(isSafeLinkUrl(''), isFalse);
      expect(isSafeLinkUrl('https://exa mple.com'), isFalse);
    });

    test('trims the ends before checking', () {
      expect(isSafeLinkUrl('  https://example.com  '), isTrue);
    });
  });

  group('urlLink', () {
    test('stores the trimmed target', () {
      expect(urlLink('  https://example.com '), {'kind': 'url', 'target': 'https://example.com'});
    });

    test('returns null for an unsafe address', () {
      expect(urlLink('javascript:alert(1)'), isNull);
    });
  });

  group('linkOf', () {
    test('reads a well-formed link and ignores malformed ones', () {
      expect(linkOf({'id': 'o'}), isNull);
      expect(linkOf({'link': 'https://x'}), isNull);
      expect(linkOf({'link': {'kind': 'email', 'target': 'a'}}), isNull);
      expect(linkOf({'link': {'kind': 'slide', 'target': ''}}), isNull);
      expect(linkOf({'link': {'kind': 'slide', 'target': 's2'}}),
          {'kind': 'slide', 'target': 's2'});
    });

    test('slideLink builds the slide form', () {
      expect(slideLink('s3'), {'kind': 'slide', 'target': 's3'});
    });
  });

  group('linkDescription', () {
    final List<Map<String, dynamic>> slides = [
      {'id': 's1', 'title': 'Intro'},
      {'id': 's2', 'title': 'Pricing'},
    ];
    String titleOf(Map<String, dynamic> s) => s['title'] as String;

    test('describes none, URL, slide, and a missing target', () {
      expect(linkDescription(null, slides, titleOf), 'No link');
      expect(linkDescription({'kind': 'url', 'target': 'https://a.co'}, slides, titleOf),
          'https://a.co');
      expect(linkDescription({'kind': 'slide', 'target': 's2'}, slides, titleOf),
          'Slide 2: Pricing');
      expect(linkDescription({'kind': 'slide', 'target': 'gone'}, slides, titleOf),
          'Target slide is missing');
    });
  });
}
