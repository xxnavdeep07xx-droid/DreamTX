import 'package:material_ui/material_ui.dart';

/// Renders a deck-core layout JSON (1280x720 space) via CustomPainter.
/// Tapping a text element reports its content `key` for the editor.
class SlideCanvas extends StatelessWidget {
  const SlideCanvas({
    super.key,
    required this.layout,
    this.onTextTap,
    this.warning,
  });

  final Map<String, dynamic> layout;
  final void Function(String key)? onTextTap;
  final String? warning;

  static const double designW = 1280;
  static const double designH = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scale =
          constraints.biggest.width / constraints.biggest.height > designW / designH
              ? constraints.biggest.height / designH
              : constraints.biggest.width / designW;
      return GestureDetector(
        onTapUp: (details) => _handleTap(details.localPosition * (1 / scale)),
        child: SizedBox(
          width: designW * scale,
          height: designH * scale,
          child: FittedBox(
            fit: BoxFit.fill,
            child: CustomPaint(
              size: const Size(designW, designH),
              painter: _SlidePainter(layout),
            ),
          ),
        ),
      );
    });
  }

  void _handleTap(Offset designPos) {
    final elements = (layout['elements'] as List? ?? []);
    for (final e in elements) {
      if (e is! Map || e['type'] != 'text') continue;
      final key = e['key'];
      if (key == null || key is! String) continue;
      final x = (e['x'] as num).toDouble();
      final y = (e['y'] as num).toDouble();
      final w = (e['w'] as num).toDouble();
      final h = (e['h'] as num).toDouble();
      if (designPos.dx >= x && designPos.dx <= x + w && designPos.dy >= y && designPos.dy <= y + h) {
        onTextTap?.call(key);
        return;
      }
    }
  }
}

class _SlidePainter extends CustomPainter {
  _SlidePainter(this.layout);

  final Map<String, dynamic> layout;

  @override
  void paint(Canvas canvas, Size size) {
    final elements = (layout['elements'] as List? ?? []);
    for (final el in elements) {
      if (el is! Map) continue;
      final type = el['type'];
      if (type == 'rect') {
        _paintRect(canvas, el);
      } else if (type == 'text') {
        _paintText(canvas, el);
      }
    }
  }

  void _paintRect(Canvas canvas, Map el) {
    final rect = Rect.fromLTWH(
      (el['x'] as num).toDouble(),
      (el['y'] as num).toDouble(),
      (el['w'] as num).toDouble(),
      (el['h'] as num).toDouble(),
    );
    final paint = Paint()..color = _color(el['color'] as String? ?? '000000');
    final radius = (el['radius'] as num?)?.toDouble() ?? 0.0;
    if (radius > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  void _paintText(Canvas canvas, Map el) {
    final lines = (el['lines'] as List? ?? const [])
        .map((l) => l.toString())
        .toList(growable: false);
    if (lines.isEmpty) return;
    final fontSize = (el['size'] as num).toDouble();
    final color = _color(el['color'] as String? ?? '000000');
    final serif = el['font'] == 'serif';
    final bold = (el['bold'] as bool? ?? false);
    final align = (el['align'] as String? ?? 'left');
    final lineHeight = fontSize * 1.28;
    var y = (el['y'] as num).toDouble();
    final boxW = (el['w'] as num).toDouble();
    final xLeft = (el['x'] as num).toDouble();

    for (final line in lines) {
      final tp = TextPainter(
        text: TextSpan(
          text: line,
          style: TextStyle(
            fontSize: fontSize,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            fontFamily: serif ? 'serif' : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: boxW);
      var x = xLeft;
      if (align == 'center') x = xLeft + (boxW - tp.width) / 2;
      if (align == 'right') x = xLeft + (boxW - tp.width);
      tp.paint(canvas, Offset(x, y));
      y += lineHeight;
    }
  }

  Color _color(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
    return Color(0xFF000000 | (v & 0xFFFFFF));
  }

  @override
  bool shouldRepaint(_SlidePainter oldDelegate) => oldDelegate.layout != layout;
}
