import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/link_math.dart';

/// Presenter link taps: a tap is mapped into design space through the
/// letterboxed slide frame, and hits the topmost linked object there.
void main() {
  group('designPointOf', () {
    const design = Size(1280, 720);

    test('maps a tap inside a letterboxed 16:9 frame on a 4:3 screen', () {
      // 400x300 screen: the 16:9 frame is 400x225, centred (top offset 37.5).
      expect(designPointOf(const Offset(200, 150), const Size(400, 300), design),
          const Offset(640, 360));
    });

    test('returns null for a tap in the letterbox bars', () {
      expect(designPointOf(const Offset(10, 10), const Size(400, 300), design), isNull);
    });

    test('an exact-aspect screen maps edge to edge', () {
      expect(designPointOf(const Offset(400, 225), const Size(400, 225), design),
          const Offset(1280, 720));
    });
  });

  group('linkObjectAt', () {
    final objects = <Map<String, dynamic>>[
      {'id': 'a', 'x': 0, 'y': 0, 'w': 100, 'h': 100, 'rotation': 0,
        'link': {'kind': 'url', 'target': 'https://a.example'}},
      {'id': 'b', 'x': 50, 'y': 50, 'w': 100, 'h': 100, 'rotation': 0,
        'link': {'kind': 'slide', 'target': 's2'}},
      {'id': 'plain', 'x': 300, 'y': 300, 'w': 50, 'h': 50, 'rotation': 0},
    ];

    test('the topmost linked object under the point wins', () {
      expect(linkObjectAt(objects, const Offset(60, 60))!['id'], 'b');
      expect(linkObjectAt(objects, const Offset(10, 10))!['id'], 'a');
    });

    test('unlinked objects and empty space do not hit', () {
      expect(linkObjectAt(objects, const Offset(320, 320)), isNull);
      expect(linkObjectAt(objects, const Offset(900, 900)), isNull);
    });

    test('a rotated link is hit where it is drawn', () {
      final rotated = <Map<String, dynamic>>[
        {'id': 'bar', 'x': 0, 'y': 0, 'w': 100, 'h': 10, 'rotation': 90,
          'link': {'kind': 'url', 'target': 'https://r.example'}},
      ];
      // Centre (50, 5); turned 90 degrees it stands vertically.
      expect(linkObjectAt(rotated, const Offset(50, -20))!['id'], 'bar');
      expect(linkObjectAt(rotated, const Offset(80, 5)), isNull);
    });
  });
}
