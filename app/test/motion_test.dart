import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/motion_math.dart';

/// Presentation-time motion: the deck maps, the sanitize rules and the
/// entrance timeline's stagger math.
void main() {
  Map<String, dynamic> deck(List<String> slideIds) => <String, dynamic>{
        'id': 'd',
        'slides': [
          for (final id in slideIds)
            <String, dynamic>{'id': id, 'objects': const []},
        ],
      };

  group('transitions — the deck map', () {
    test('absent, malformed and unknown kinds read as the default push', () {
      final d = deck(['a', 'b']);
      expect(transitionOf(d, 'a'), kTransitionPush);
      expect(transitionOf(d, null), kTransitionPush);
      d['transitions'] = {'a': 'spin', 'b': 42};
      expect(transitionOf(d, 'a'), kTransitionPush);
      expect(transitionOf(d, 'b'), kTransitionPush);
    });

    test('setting the default removes the entry — untouched decks carry no data', () {
      final d = deck(['a']);
      setDeckTransition(d, 'a', kTransitionFade);
      expect(d['transitions'], {'a': kTransitionFade});
      setDeckTransition(d, 'a', kTransitionPush);
      expect(d.containsKey('transitions'), isFalse);
    });

    test('apply to all covers every slide; push clears the whole map', () {
      final d = deck(['a', 'b', 'c']);
      applyDeckTransitionToAll(d, kTransitionZoom);
      expect(transitionOf(d, 'a'), kTransitionZoom);
      expect(transitionOf(d, 'c'), kTransitionZoom);
      applyDeckTransitionToAll(d, kTransitionPush);
      expect(d.containsKey('transitions'), isFalse);
    });
  });

  group('entrances — the deck map', () {
    Map<String, dynamic> deckWithObject(String slideId, String objectId) =>
        <String, dynamic>{
          'id': 'd',
          'slides': [
            {
              'id': slideId,
              'objects': [
                {'id': objectId},
              ],
            },
          ],
        };

    test('a valid kind reads back; none and unknown read as no entrance', () {
      final d = deckWithObject('s', 'o');
      expect(entranceOf(d, 'o'), isNull);
      setDeckEntrance(d, 'o', kEntrancePop);
      expect(entranceOf(d, 'o'), kEntrancePop);
      setDeckEntrance(d, 'o', kEntranceNone);
      expect(d.containsKey('animations'), isFalse);
      expect(entranceOf(d, 'o'), isNull);
      d['animations'] = {'o': 'flashbulb'};
      expect(entranceOf(d, 'o'), isNull);
    });

    test('the stagger walks the deck z-order, skipping plain objects', () {
      final d = <String, dynamic>{
        'id': 'd',
        'animations': {'o2': kEntranceFade, 'o4': kEntranceRise},
        'slides': [
          {
            'id': 's',
            'objects': [
              {'id': 'o1'},
              {'id': 'o2'},
              {'id': 'o3'},
              {'id': 'o4'},
            ],
          },
        ],
      };
      expect(animatedObjectIds(d, [
        {'id': 'o1'},
        {'id': 'o2'},
        {'id': 'o3'},
        {'id': 'o4'},
      ]), ['o2', 'o4']);
      expect(entranceCount(d, [
        {'id': 'o1'},
        {'id': 'o2'},
        {'id': 'o3'},
        {'id': 'o4'},
      ]), 2);
    });
  });

  group('sanitize — dead ids fold away', () {
    test('a deleted slide takes its transition with it', () {
      final d = deck(['a']);
      setDeckTransition(d, 'a', kTransitionFade);
      d['slides'] = [
        {'id': 'z', 'objects': const []},
      ];
      expect(sanitizeDeckTransitions(d), isNull);
      expect(d.containsKey('transitions'), isFalse,
          reason: 'the tombstone rule — an empty map means genuinely empty');
    });

    test('a deleted object takes its entrance with it', () {
      final d = <String, dynamic>{
        'id': 'd',
        'animations': {'gone': kEntrancePop, 'kept': kEntranceFade},
        'slides': [
          {
            'id': 's',
            'objects': [
              {'id': 'kept'},
            ],
          },
        ],
      };
      final settled = sanitizeDeckAnimations(d);
      expect(settled, {'kept': kEntranceFade});
      // 'none' entries never settle either — none IS absence.
      d['animations'] = {'kept': kEntranceNone};
      expect(sanitizeDeckAnimations(d), isNull);
      expect(d.containsKey('animations'), isFalse);
    });
  });

  group('the entrance timeline', () {
    test('one object is one effect; more objects stagger and cap', () {
      expect(entranceTimelineMs(0), 0);
      expect(entranceTimelineMs(1), kEntranceEffectMs);
      expect(entranceTimelineMs(2), kEntranceStaggerMs + kEntranceEffectMs);
      // The cap: a very long build compresses the stagger, never the
      // ceiling itself.
      final big = entranceTimelineMs(200);
      expect(big <= kEntranceMaxTotalMs, isTrue);
      expect(big, greaterThanOrEqualTo(kEntranceEffectMs));
    });

    test('the slices overlap: object 2 starts before object 1 finishes', () {
      // At t where object 1 is mid-effect, object 2 has already begun.
      final total2 = entranceTimelineMs(2); // 300 + 110
      final t = (kEntranceEffectMs * 0.9) / total2;
      final p1 = entranceProgress(0, 2, t);
      final p2 = entranceProgress(1, 2, t);
      expect(p1, greaterThan(0));
      expect(p1, lessThan(1));
      expect(p2, greaterThan(0), reason: 'the stagger overlaps the effects');
    });

    test('clamps are honest', () {
      expect(entranceProgress(0, 0, 0), 1.0);
      expect(entranceProgress(-1, 2, 1), 0.0);
      expect(entranceProgress(5, 2, 0), 1.0);
      expect(entranceProgress(0, 2, -1), 0.0);
      expect(entranceProgress(1, 2, 5), 1.0);
    });
  });
}
