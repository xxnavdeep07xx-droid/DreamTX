library;

/// Typed access to an object's `content` payload — the Dart mirror of the
/// engine's `ObjectContent` enum. The payload is plain JSON in the deck
/// (so it persists through the engine verbatim); these helpers read it.

import '../widgets/rich_doc.dart';

/// The content kinds an object can carry.
const kContentText = 'text';
const kContentImage = 'image';
const kContentIcon = 'icon';
const kContentMedia = 'media';
const kContentTable = 'table';

class ObjectContent {
  ObjectContent._();

  /// The raw payload map, or null for classic vector shapes.
  static Map<String, dynamic>? of(Map<String, dynamic> obj) {
    final c = obj['content'];
    return c is Map<String, dynamic> ? c : null;
  }

  /// The kind tag ('text' | 'image' | 'icon' | 'media' | 'table' | '').
  static String kindOf(Map<String, dynamic> obj) =>
      (of(obj)?['kind'] ?? '').toString();

  static bool isText(Map<String, dynamic> obj) => kindOf(obj) == kContentText;
  static bool isImage(Map<String, dynamic> obj) =>
      kindOf(obj) == kContentImage;
  static bool isIcon(Map<String, dynamic> obj) => kindOf(obj) == kContentIcon;
  static bool isMedia(Map<String, dynamic> obj) =>
      kindOf(obj) == kContentMedia;
  static bool isTable(Map<String, dynamic> obj) =>
      kindOf(obj) == kContentTable;

  static bool hasContent(Map<String, dynamic> obj) => of(obj) != null;

  // ---- text ----------------------------------------------------------------

  static RichDoc? textDocOf(Map<String, dynamic> obj) {
    final c = of(obj);
    if (c == null || c['kind'] != kContentText) return null;
    return RichDoc.fromJson(
        (c['doc'] as Map?)?.cast<String, dynamic>());
  }

  /// The JSON payload for a text object carrying [doc].
  static Map<String, dynamic> text(RichDoc doc) =>
      {'kind': kContentText, 'doc': doc.toJson()};

  /// Write [doc] back into [obj]'s content (in place on a copy).
  static Map<String, dynamic> withTextDoc(
      Map<String, dynamic> obj, RichDoc doc) {
    final copy = Map<String, dynamic>.from(obj);
    copy['content'] = text(doc);
    return copy;
  }

  // ---- image / media ---------------------------------------------------------

  static Map<String, dynamic> image(String resourceId,
          {required bool brand, String? name}) =>
      {
        'kind': kContentImage,
        'resource_id': resourceId,
        'brand': brand,
        if (name != null) 'name': name,
      };

  static Map<String, dynamic> media(String resourceId,
          {required bool brand, String? name, String? mediaKind}) =>
      {
        'kind': kContentMedia,
        'resource_id': resourceId,
        'brand': brand,
        if (name != null) 'name': name,
        if (mediaKind != null) 'media_kind': mediaKind,
      };

  static Map<String, dynamic> icon(String name) =>
      {'kind': kContentIcon, 'name': name};

  static Map<String, dynamic> table(int rows, int cols,
          {List<String>? cells}) =>
      {
        'kind': kContentTable,
        'rows': rows,
        'cols': cols,
        'cells': cells ?? List.filled(rows * cols, ''),
      };

  /// Table geometry: (rows, cols, cells) — cells padded/truncated to size.
  static (int, int, List<String>) tableOf(Map<String, dynamic> obj) {
    final c = of(obj);
    if (c == null || c['kind'] != kContentTable) return (0, 0, const []);
    final rows = (c['rows'] as num?)?.toInt() ?? 0;
    final cols = (c['cols'] as num?)?.toInt() ?? 0;
    final raw = (c['cells'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final cells = List<String>.generate(
        rows * cols, (i) => i < raw.length ? raw[i] : '',
        growable: false);
    return (rows, cols, cells);
  }

  /// The object's display label for panels and layers.
  static String labelOf(Map<String, dynamic> obj) {
    switch (kindOf(obj)) {
      case kContentText:
        return 'Text box';
      case kContentImage:
        final n = (of(obj)?['name'] ?? '').toString();
        return n.isEmpty ? 'Image' : n;
      case kContentIcon:
        return 'Icon · ${(of(obj)?['name'] ?? '').toString()}';
      case kContentMedia:
        final n = (of(obj)?['name'] ?? '').toString();
        return n.isEmpty ? 'Media' : n;
      case kContentTable:
        return 'Table';
    }
    return (obj['preset'] ?? 'shape').toString().replaceAll('_', ' ');
  }
}
