// Slide furniture (View tab): the slide number, the date and a footer,
// built as real text objects on every slide, so PPTX and PDF export them
// with no exporter changes. Pure, so the rules are unit-tested.
//
// The deck keeps the SETTINGS (`deck['furniture']`, carried through every
// engine round-trip like the other app-owned deck fields). Each slide's
// furniture OBJECTS are rebuilt from those settings on every deck change,
// so the slide numbers stay right after an insert, delete or move.

import 'aspects.dart';
import 'object_content.dart';
import '../widgets/rich_doc.dart';

/// Furniture objects carry this id prefix. The Rust core keeps `id`
/// verbatim, so the prefix survives every round-trip (a custom field
/// would not: the core's Shape struct drops unknown keys).
const String kFurniturePrefix = 'furn_';

/// The three pieces, as the deck stores them.
class Furniture {
  const Furniture({this.slideNumber = false, this.date = false, this.footer = ''});

  final bool slideNumber;
  final bool date;
  final String footer;

  /// True when any piece is on, so the slides carry furniture objects.
  bool get any => slideNumber || date || footer.trim().isNotEmpty;

  Map<String, dynamic> toJson() =>
      {'slideNumber': slideNumber, 'date': date, 'footer': footer};

  /// Missing or malformed settings read as all off.
  static Furniture fromJson(Object? j) {
    if (j is! Map) return const Furniture();
    return Furniture(
      slideNumber: j['slideNumber'] == true,
      date: j['date'] == true,
      footer: (j['footer'] ?? '').toString(),
    );
  }
}

bool isFurnitureId(Object? id) => id is String && id.startsWith(kFurniturePrefix);

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The date piece's text, e.g. "25 Nov 2026".
String furnitureDateText(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// The furniture objects for one slide, in z-order (footer, date, number —
/// each placed in the bottom band of the frame). Locked, so they can't be
/// moved or edited on the slide; the Furniture sheet is their editor.
List<Map<String, dynamic>> furnitureObjects({
  required String slideId,
  required int number,
  required Furniture f,
  required double designW,
  required double designH,
  required String dateText,
}) {
  const band = 28.0; // box height
  const margin = 40.0;
  final y = designH - band - 16;
  final out = <Map<String, dynamic>>[];

  Map<String, dynamic> box(String kind, String text, double x, double w) => {
        'id': '$kFurniturePrefix${slideId}_$kind',
        'preset': 'rectangle',
        'x': x,
        'y': y,
        'w': w,
        'h': band,
        'rotation': 0.0,
        'opacity': 1.0,
        'locked': true,
        'fill': {'type': 'none'},
        'stroke': {
          'color': '17181A',
          'width': 0.0,
          'dash': 'solid',
          'start_arrow': 'none',
          'end_arrow': 'none',
        },
        'effects': <String, dynamic>{},
        'closed': true,
        'content': ObjectContent.text(RichDoc(text: text)),
      };

  if (f.footer.trim().isNotEmpty) {
    const w = 360.0;
    out.add(box('footer', f.footer.trim(), (designW - w) / 2, w));
  }
  if (f.date) {
    out.add(box('date', dateText, margin, 180));
  }
  if (f.slideNumber) {
    const w = 60.0;
    out.add(box('number', '$number', designW - w - margin, w));
  }
  return out;
}

/// The deck with every slide's furniture rebuilt from its settings: the
/// old furniture objects are dropped and the current ones appended (on
/// top). Slides with no furniture keep their objects untouched. Idempotent.
Map<String, dynamic> syncFurnitureInDeck(
  Map<String, dynamic> deck, {
  required String dateText,
}) {
  final f = Furniture.fromJson(deck['furniture']);
  final (dw, dh) = deckDimsOf(deck['aspect']?.toString());
  final slides = (deck['slides'] as List?) ?? const [];
  final outSlides = <dynamic>[];
  for (var i = 0; i < slides.length; i++) {
    final raw = slides[i];
    if (raw is! Map) {
      outSlides.add(raw); // never expected; carried through untouched
      continue;
    }
    final slide = Map<String, dynamic>.from(raw);
    final objects = <Map<String, dynamic>>[
      for (final o in (slide['objects'] as List?) ?? const [])
        if (o is Map && !isFurnitureId(o['id']))
          Map<String, dynamic>.from(o),
    ];
    if (f.any) {
      objects.addAll(furnitureObjects(
        slideId: (slide['id'] ?? 'slide$i').toString(),
        number: i + 1,
        f: f,
        designW: dw,
        designH: dh,
        dateText: dateText,
      ));
    }
    slide['objects'] = objects;
    outSlides.add(slide);
  }
  return {...deck, 'slides': outSlides};
}
