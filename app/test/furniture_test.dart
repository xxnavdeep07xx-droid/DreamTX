import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/core/furniture_math.dart';

/// Slide furniture: the settings, the per-slide objects, and the deck sync.
Map<String, dynamic> _deck(List<String> slideIds, {Map<String, dynamic>? furniture}) => {
      'id': 'd',
      'title': 't',
      'version': 1,
      'aspect': '16:9',
      if (furniture != null) 'furniture': furniture,
      'slides': [
        for (final id in slideIds)
          {
            'id': id,
            'archetype': 'blank',
            'objects': [
              {'id': 'o_user_$id', 'preset': 'rectangle', 'x': 0.0, 'y': 0.0, 'w': 10.0, 'h': 10.0},
            ],
          },
      ],
    };

List<String> _ids(Map<String, dynamic> slide) =>
    [for (final o in slide['objects'] as List) (o as Map)['id'] as String];

String _text(Map<String, dynamic> o) =>
    ((o['content'] as Map)['doc'] as Map)['text'] as String;

void main() {
  test('settings default to all off; malformed reads as off', () {
    final f = Furniture.fromJson(null);
    expect(f.any, isFalse);
    expect(Furniture.fromJson({'slideNumber': 'yes', 'footer': 42}).slideNumber, isFalse);
    expect(Furniture.fromJson({'footer': 42}).footer, '42');
  });

  test('a footer of only spaces does not count as furniture', () {
    expect(const Furniture(footer: '   ').any, isFalse);
    expect(const Furniture(date: true).any, isTrue);
  });

  test('the date text reads day, short month, year', () {
    expect(furnitureDateText(DateTime(2026, 11, 25)), '25 Nov 2026');
    expect(furnitureDateText(DateTime(2027, 1, 3)), '3 Jan 2027');
  });

  test('each piece becomes a locked text object with its own id', () {
    final objs = furnitureObjects(
      slideId: 's1',
      number: 4,
      f: const Furniture(slideNumber: true, date: true, footer: 'ACME'),
      designW: 1280,
      designH: 720,
      dateText: '25 Nov 2026',
    );
    expect(objs.map((o) => o['id']),
        ['furn_s1_footer', 'furn_s1_date', 'furn_s1_number']);
    expect(objs.every((o) => o['locked'] == true), isTrue);
    expect(objs.every((o) => isFurnitureId(o['id'])), isTrue);
    expect(_text(objs[0]), 'ACME');
    expect(_text(objs[1]), '25 Nov 2026');
    expect(_text(objs[2]), '4');
  });

  test('the number sits at the right margin, inside the frame', () {
    final num = furnitureObjects(
      slideId: 's',
      number: 1,
      f: const Furniture(slideNumber: true),
      designW: 1280,
      designH: 720,
      dateText: '',
    ).single;
    expect((num['x'] as double) + (num['w'] as double), 1280 - 40);
    expect((num['y'] as double) + (num['h'] as double) <= 720, isTrue);
  });

  test('the sync numbers each slide by its position', () {
    final synced = syncFurnitureInDeck(
      _deck(['a', 'b', 'c'], furniture: const {'slideNumber': true, 'date': false, 'footer': ''}),
      dateText: '',
    );
    final slides = synced['slides'] as List;
    for (var i = 0; i < 3; i++) {
      final number = (slides[i] as Map)['objects'] as List;
      final f = number.last as Map<String, dynamic>;
      expect(_text(f), '${i + 1}');
    }
  });

  test('user objects survive; furniture is never doubled', () {
    final deck = _deck(['a'], furniture: const {'slideNumber': true, 'date': true, 'footer': ''});
    final once = syncFurnitureInDeck(deck, dateText: 'x');
    final twice = syncFurnitureInDeck(once, dateText: 'x');
    final ids = _ids((twice['slides'] as List).first as Map<String, dynamic>);
    expect(ids, ['o_user_a', 'furn_a_date', 'furn_a_number']);
  });

  test('turning every piece off removes the furniture and keeps the rest', () {
    final on = syncFurnitureInDeck(
      _deck(['a'], furniture: const {'slideNumber': true, 'date': true, 'footer': 'F'}),
      dateText: 'x',
    );
    final off = syncFurnitureInDeck(
      {...on, 'furniture': const {'slideNumber': false, 'date': false, 'footer': ''}},
      dateText: 'x',
    );
    expect(_ids((off['slides'] as List).first as Map<String, dynamic>), ['o_user_a']);
  });

  test('a duplicated slide with copied furniture gets its own, not the copy', () {
    final on = syncFurnitureInDeck(
      _deck(['a'], furniture: const {'slideNumber': true, 'date': false, 'footer': ''}),
      dateText: 'x',
    );
    // Copy slide 'a' as 'b' with its furniture ids still pointing at 'a'.
    final slides = (on['slides'] as List).cast<Map<String, dynamic>>();
    final copy = {...slides.first, 'id': 'b'};
    final withCopy = {...on, 'slides': [...slides, copy]};
    final synced = syncFurnitureInDeck(withCopy, dateText: 'x');
    final bIds = _ids((synced['slides'] as List)[1] as Map<String, dynamic>);
    expect(bIds, ['o_user_a', 'furn_b_number']);
    expect(_text(((synced['slides'] as List)[1] as Map)['objects'].last as Map<String, dynamic>), '2');
  });
}
