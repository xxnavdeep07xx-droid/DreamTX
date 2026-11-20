import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'object_content_layer.dart';
import 'rich_doc.dart';

/// The on-canvas WYSIWYG editing field for a selected text box — mounted
/// ONLY while the box's editing session has focus (the typing state). It
/// sits at the object's design rect scaled to the canvas, renders the
/// [RichDoc]'s formatting through the controller's `buildTextSpan`, and
/// owns the live caret/selection. Everything below (the painter) stays
/// exactly where it was: same box, same metrics — the field is simply its
/// editable face.
///
/// The expand button (in the typing toolbar) unfocuses this field; the
/// controller keeps the text, caret and selection, so re-entering typing
/// restores them.
class TextEditFieldLayer extends StatelessWidget {
  const TextEditFieldLayer({
    super.key,
    required this.obj,
    required this.controller,
    required this.focusNode,
    required this.designW,
    required this.designH,
    required this.baseColor,
    required this.baseFamily,
    required this.baseFontSize,
  });

  final Map<String, dynamic> obj;
  final RichEditingController controller;
  final FocusNode focusNode;

  final double designW;
  final double designH;

  final Color baseColor;
  final String? baseFamily;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scale = math.min(constraints.biggest.width / designW,
          constraints.biggest.height / designH);
      final x = ((obj['x'] as num?) ?? 0).toDouble();
      final y = ((obj['y'] as num?) ?? 0).toDouble();
      final w = ((obj['w'] as num?) ?? 1).toDouble();
      final h = ((obj['h'] as num?) ?? 1).toDouble();
      final rot = ((obj['rotation'] ?? 0) as num).toDouble();
      final doc = controller.doc;

      // Autofit: same shrink math as the painter, so the field's type size
      // tracks what the painted box will show.
      var k = 1.0;
      if (doc.autofit == 'shrink') {
        k = TextBoxPainter.autofitScale(
          doc: doc,
          boxW: w,
          boxH: h,
          baseColor: baseColor,
          baseFamily: baseFamily,
          baseFontSize: baseFontSize,
        );
      }
      final fontSize = baseFontSize * scale * k;
      final runScale = scale * k;

      // The caret's paragraph drives the field's overall alignment (the
      // closest WYSIWYG a single field can offer while typing).
      final sel = controller.effectiveSelection;
      final caretOffset = sel.extentOffset.clamp(0, doc.text.length);
      final align = switch (doc.effectiveParaAt(caretOffset)?.align) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        'left' => TextAlign.left,
        _ => TextAlign.left,
      };

      controller.runScale = runScale;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: x * scale,
            top: y * scale,
            width: w * scale,
            height: h * scale,
            child: Transform.rotate(
              angle: rot * math.pi / 180.0,
              child: _Field(
                controller: controller,
                focusNode: focusNode,
                fontSize: fontSize,
                baseColor: baseColor,
                baseFamily: baseFamily,
                align: align,
                boxHeight: h * scale,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.fontSize,
    required this.baseColor,
    required this.baseFamily,
    required this.align,
    required this.boxHeight,
  });

  final RichEditingController controller;
  final FocusNode focusNode;
  final double fontSize;
  final Color baseColor;
  final String? baseFamily;
  final TextAlign align;
  final double boxHeight;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('text_box_field'),
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      maxLines: null,
      expands: false,
      textAlign: align,
      cursorColor: baseColor.withValues(alpha: 0.9),
      cursorWidth: 1.6,
      style: TextStyle(
        color: baseColor,
        fontFamily: baseFamily,
        fontSize: fontSize,
      ),
      decoration: const InputDecoration(
        isDense: true,
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
      ),
    );
  }
}
