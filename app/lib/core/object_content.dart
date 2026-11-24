library;

/// Typed access to an object's `content` payload — the Dart mirror of the
/// engine's `ObjectContent` enum. The payload is plain JSON in the deck
/// (so it persists through the engine verbatim); these helpers read it.

import 'dart:math' as math;

import 'color_utils.dart';
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

  // ---- table metadata (deck-level, app-owned) -------------------------------
  //
  // The Rust core's `ObjectContent::Table` carries only rows/cols/cells,
  // so cell MERGES and STYLE live outside the object as app-owned deck
  // metadata (`deck['tables'][objectId]`), exactly where filmstrip sections
  // live (`deck['sections']`) — carried through engine round-trips by the
  // editor, invisible to the core's exporters, and persisted by the store.

  /// The table's merge regions, validated against [rows] x [cols]:
  /// `{'r': anchorRow, 'c': anchorCol, 'rs': rowSpan, 'cs': colSpan}`.
  /// Out-of-bounds or degenerate regions fold away (a stale marker can
  /// never crash the painter or the panel).
  static List<Map<String, dynamic>> tableMergesOf(
      Map<String, dynamic>? entry,
      {required int rows,
      required int cols}) {
    if (rows < 1 || cols < 1) return const [];
    final out = <Map<String, dynamic>>[];
    for (final m in ((entry?['merges'] as List?) ?? const []).whereType<Map>()) {
      final r = (m['r'] as num?)?.toInt();
      final c = (m['c'] as num?)?.toInt();
      final rs = (m['rs'] as num?)?.toInt();
      final cs = (m['cs'] as num?)?.toInt();
      if (r == null || c == null || rs == null || cs == null) continue;
      if (r < 0 || c < 0 || rs < 1 || cs < 1 || rs * cs < 2) continue;
      if (r + rs > rows || c + cs > cols) continue;
      out.add({'r': r, 'c': c, 'rs': rs, 'cs': cs});
    }
    return out;
  }

  /// The table's named style: 'plain' (default) | 'header' | 'banded' |
  /// 'header_banded'.
  static String tableStyleOf(Map<String, dynamic>? entry) =>
      (entry?['style'] ?? 'plain').toString();

  /// The style fields for a table metadata entry — DNA colors resolve HERE,
  /// at apply time (the WordArt rule: one style set matches every design
  /// family, without the renderer needing to know the DNA). [dna] is the
  /// resolved DNA palette in RRGGBB hex ('accent', 'surface', …). Returns
  /// null for 'plain' — a plain table keeps no style fields.
  static Map<String, dynamic>? tableStyleFields(
      String style, Map<String, String> dna) {
    final accent = (dna['accent'] ?? '17181A').toUpperCase();
    final band = (dna['surface'] ?? 'F7F6F3').toUpperCase();
    final onAccent = _textOn(accent);
    switch (style) {
      case 'header':
        return {
          'style': 'header',
          'accent': accent,
          'on_accent': onAccent,
        };
      case 'banded':
        return {'style': 'banded', 'band': band};
      case 'header_banded':
        return {
          'style': 'header_banded',
          'accent': accent,
          'on_accent': onAccent,
          'band': band,
        };
      default:
        return null; // 'plain'
    }
  }

  /// Ink or white text on a filled accent: the WCAG relative luminance
  /// with the 0.55 threshold — dark accents carry white text, light ones
  /// carry the deck ink.
  static String _textOn(String accentHex) {
    final c = hexToColor(accentHex);
    double channel(int v) {
      final s = v / 255.0;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }
    final lum = 0.2126 * channel(c.red) +
        0.7152 * channel(c.green) +
        0.0722 * channel(c.blue);
    return lum > 0.55 ? '17181A' : 'FFFFFF';
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
