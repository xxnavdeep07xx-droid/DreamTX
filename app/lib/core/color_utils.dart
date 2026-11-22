library;

import 'package:material_ui/material_ui.dart';

/// The ONE hex <-> Color contract for the whole app. Five separate
/// converters used to live in five files (typing_toolbar's `_hexKey`,
/// rich_doc's `hexToColor`/`colorToHex`, object_content_layer's `_hex`,
/// shape_canvas's `_color`, design_sheets' `_hexColor`) — all computing
/// the same RRGGBB mapping with subtly different spelling. One place now.

/// RRGGBB (or RRGGBBAA) hex to a Flutter color. Unparseable input is
/// black — the engine's payloads are validated upstream.
Color hexToColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
  final r = (v >> 16) & 0xFF, g = (v >> 8) & 0xFF, b = v & 0xFF;
  return Color(0xFF000000 | (r << 16) | (g << 8) | b);
}

/// A Color to the engine's string form (RRGGBB, no '#', uppercase) —
/// the exact shape `fill.color`, `stroke.color`, run colors and the
/// export pipeline speak.
String colorToHex(Color c) => hexKeyOf(c);

/// The comparison key for palette chips: RRGGBB uppercase, the same
/// string `hexToColor` accepts back.
String hexKeyOf(Color c) =>
    ((c.r * 255).round() << 16 |
            (c.g * 255).round() << 8 |
            (c.b * 255).round())
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
