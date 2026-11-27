import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

import '../core/chart_math.dart';
import '../core/ink_math.dart';
import '../core/link_math.dart';
import '../core/motion_math.dart';
import '../core/object_content.dart';
import 'object_content_layer.dart';
import 'rich_doc.dart';
import 'shape_canvas.dart';
import 'slide_canvas.dart';
import 'text_edit_field.dart';

/// The one layered slide stage — the editor's canvas and the presenter's
/// fullscreen pass render the EXACT same thing:
///
///  1. [SlideCanvas] — the archetype layout (DNA background, layout text);
///  2. the object layer in the deck's TRUE Z-order: for each object in
///     `slide['objects']` list order, a content object renders its content
///     (text box, image, icon, media, table) and a plain shape renders its
///     vector body — interleaved, so Bring Forward / Send Backward
///     ([`move_object_z`]) reads exactly on screen;
///  3. the [ShapesLayer] overlay — selection chrome, resize/rotate knobs,
///     ink capture (the Draw tab's tools), smart guides — riding ON TOP of
///     everything
///     (non-interactive + invisible when the stage is presented);
///  4. optionally the live [TextEditFieldLayer] while the selected text box
///     is being typed into (the editor only).
///
/// Both callers own the frame: the editor clips it in its canvas card, the
/// presenter fills the screen at the deck's own aspect.
class SlideStage extends StatelessWidget {
  const SlideStage({
    super.key,
    required this.layout,
    required this.objects,
    required this.designW,
    required this.designH,
    required this.baseColor,
    required this.baseFamily,
    required this.baseFontSize,
    required this.resolveResourcePath,
    this.tableMeta,
    this.imageMeta,
    this.selectedId,
    this.interactive = false,
    this.showLinkBadges = false,
    this.chartPalette = kChartPalette,
    this.inkTool,
    this.inkStyle = const InkStyle(colorHex: 'D03028', width: 8.0),
    this.onTextTap,
    this.onSelect,
    this.onLive,
    this.onCommit,
    this.onGestureStart,
    this.onStroke,
    this.onEraseHits,
    this.eraserRadius = kInkEraserRadius,
    this.lassoIds = const {},
    this.onLasso,
    this.onLassoMove,
    this.showRuler = false,
    this.inkReplay,
    this.entranceClock,
    this.entranceKinds,
    this.onObjectLongPress,
    this.onCanvasLongPress,
    this.textController,
    this.textFocusNode,
    this.typing = false,
  });

  /// The engine's layout JSON for the slide (see `get_layout`).
  final Map<String, dynamic> layout;

  /// The slide's object layer, in Z-order (the engine's `slide.objects`).
  final List<Map<String, dynamic>> objects;

  /// The deck's design-space frame (16:9 → 1280×720, 4:3 → 960×720…).
  final double designW;
  final double designH;

  /// The slide-theme base for text boxes (deck DNA fg + body family).
  final Color baseColor;
  final String? baseFamily;
  final double baseFontSize;

  /// Resolves an image/media content payload to a readable file path.
  final String? Function(Map<String, dynamic> content) resolveResourcePath;

  /// The deck-level table metadata (`deck['tables']`): objectId → the
  /// table's entry (merges + style). App-owned deck data the core drops
  /// on round-trips; the editor carries it, read-only stages just forward
  /// the deck's map. Absent → plain tables.
  final Map<String, dynamic>? tableMeta;

  /// The deck-level image metadata (`deck['imageMeta']`) — shape/brightness/
  /// contrast/alt. Passed straight through to the content layer.
  final Map<String, dynamic>? imageMeta;

  /// Selection / gesture wiring (the editor passes its own; the presenter
  /// passes nothing — the stage is read-only there).
  final String? selectedId;

  /// Edit mode only: a small link mark on each object that has a tap link,
  /// so the author can see which objects will act when presented.
  final bool showLinkBadges;

  /// The deck's DNA chart palette, for charts without their own colors.
  final List<String> chartPalette;
  final bool interactive;

  /// The Draw tab's armed tool (null = not drawing) and its style —
  /// passed verbatim to [ShapesLayer], which captures and previews ink.
  final InkTool? inkTool;
  final InkStyle inkStyle;
  final void Function(String key)? onTextTap;
  final void Function(String?)? onSelect;
  final void Function(Map<String, dynamic>)? onLive;
  final void Function(Map<String, dynamic>)? onCommit;
  final VoidCallback? onGestureStart;
  final void Function(List<Offset>)? onStroke;

  /// The eraser's sweep/tap batch — the marked scribble ids. Passed
  /// verbatim to [ShapesLayer]; the editor owns the delete chain.
  final void Function(List<String>)? onEraseHits;

  /// The eraser's reach (design px) — forwarded to the ink layer.
  final double eraserRadius;

  /// Draw B: the lasso selection and its loop / move callbacks (forwarded
  /// to the ink layer).
  final Set<String> lassoIds;
  final void Function(List<Offset>)? onLasso;
  final void Function(Offset)? onLassoMove;

  /// Draw R: the editor's ruler overlay (forwarded to the ink layer).
  final bool showRuler;

  /// Draw E: the ink replay clock (0..1). Scribbles draw in z-order as it
  /// runs; at 1 (the idle value) every scribble is whole. Null = no replay.
  final Animation<double>? inkReplay;

  /// The Animations tab's entrance clock (0..1): each animated object
  /// arrives on its staggered slice of the timeline (motion_math). At 1
  /// (the idle value) every object is whole. Null = no entrance behavior
  /// (the editor passes it only on the Animations tab; the presenter, on
  /// the slide that just landed).
  final Animation<double>? entranceClock;

  /// The deck's entrance map (objectId → kind) — `deck['animations']`
  /// (app-owned deck data the core drops; the editor carries it). Only
  /// objects with an entry here animate.
  final Map<String, String>? entranceKinds;

  /// Long-press wiring (editing only; the presenter passes nothing —
  /// read-only stages never build the recognizers): an object long-press
  /// opens its actions sheet, an empty-canvas long-press pastes the
  /// object clipboard at the pressed point. Passed verbatim to
  /// [ShapesLayer].
  final void Function(Map<String, dynamic> obj)? onObjectLongPress;
  final void Function(Offset designPos)? onCanvasLongPress;

  /// The live text session's controller/focus — present (with [typing])
  /// while the selected text box is being typed into on the canvas.
  final RichEditingController? textController;
  final FocusNode? textFocusNode;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final selectedObj = selectedId == null
        ? null
        : objects
            .where((o) => o['id'] == selectedId)
            .firstOrNull;
    return LayoutBuilder(builder: (context, constraints) {
      final scale = math.min(constraints.biggest.width / designW,
          constraints.biggest.height / designH);
      // Draw E: the replay's draw order — each scribble's index in z-order.
      final replay = inkReplay;
      final replayIndex = <Object?, int>{};
      if (replay != null) {
        final ids = inkScribbleIds(objects);
        for (var i = 0; i < ids.length; i++) {
          replayIndex[ids[i]] = i;
        }
      }
      final replayCount = replayIndex.length;

      // The entrance build's stagger order: animated objects in the deck's
      // own z-order (exactly the ink replay's index math — same stage, same
      // rule), so the preview and the presenter agree by construction.
      final enterClock = entranceClock;
      final enterKinds = entranceKinds;
      final enterIndex = <Object?, int>{};
      if (enterClock != null && enterKinds != null) {
        for (final obj in objects) {
          final id = obj['id'];
          if (id != null && enterKinds[id.toString()] != null) {
            enterIndex[id] = enterIndex.length;
          }
        }
      }
      final enterCount = enterIndex.length;
      Widget scribblePaint(Map<String, dynamic> obj) {
        final i = replayIndex[obj['id']];
        if (replay == null || i == null) {
          return ShapeObjectPaint(obj: obj, scale: scale);
        }
        return AnimatedBuilder(
          animation: replay,
          builder: (context, _) => ShapeObjectPaint(
            obj: obj,
            scale: scale,
            replayProgress: inkReplayProgress(i, replayCount, replay.value),
          ),
        );
      }

      return Stack(
        clipBehavior: Clip.none,
        children: [
          // The archetype layout, painted at the frame.
          SlideCanvas(layout: layout, onTextTap: onTextTap),
          // The object layer in the deck's true Z-order: content widgets
          // and vector bodies interleaved exactly as `slide.objects`
          // lists them.
          for (final obj in objects)
            () {
              final x = ((obj['x'] as num?) ?? 0).toDouble() * scale;
              final y = ((obj['y'] as num?) ?? 0).toDouble() * scale;
              final w = ((obj['w'] as num?) ?? 1).toDouble() * scale;
              final h = ((obj['h'] as num?) ?? 1).toDouble() * scale;
              // Rotation around the object's bbox center — the same
              // center+angle [ShapesLayer]'s gesture math and selection
              // chrome rotate around, and the same Transform
              // [ObjectContentLayer] applies when it lays out the whole
              // list itself. A rotated text box, image, icon, media card or
              // table turns on the canvas (and presents) exactly like its
              // exports do.
              final rot = ((obj['rotation'] ?? 0) as num?)?.toDouble() ?? 0.0;
              final contentChild = ObjectContent.hasContent(obj)
                  ? ObjectContentLayer(
                      chartPalette: chartPalette,
                      objects: [obj],
                      designW: designW,
                      designH: designH,
                      baseColor: baseColor,
                      baseFamily: baseFamily,
                      baseFontSize: baseFontSize,
                      resolveResourcePath: resolveResourcePath,
                      tableMeta: tableMeta,
                      imageMeta: imageMeta,
                      singleObject: true,
                    )
                  : scribblePaint(obj);
              // The badge sits inside the rotated child, so it turns with
              // the object; IgnorePointer keeps every tap on the object.
              final badged = showLinkBadges && linkOf(obj) != null
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        contentChild,
                        const Positioned(
                          top: -7,
                          right: -7,
                          child: IgnorePointer(child: _LinkBadge()),
                        ),
                      ],
                    )
                  : contentChild;
              // The entrance wrap: only objects with a kind, only while a
              // clock drives the stage. The effect lives INSIDE the object's
              // Positioned box (before rotation), so an entrance on a
              // rotated object reads as the object arriving, not the frame.
              final kind = obj['id'] == null
                  ? null
                  : enterKinds?[obj['id'].toString()];
              final slot = obj['id'] == null ? null : enterIndex[obj['id']];
              final entered = (enterClock != null &&
                      kind != null &&
                      slot != null)
                  ? _ObjectEntrance(
                      kind: kind,
                      slot: slot,
                      count: enterCount,
                      clock: enterClock,
                      child: badged,
                    )
                  : badged;
              return Positioned(
                left: x,
                top: y,
                width: w,
                height: h,
                child: rot != 0
                    ? Transform.rotate(
                        angle: rot * math.pi / 180.0,
                        child: entered,
                      )
                    : entered,
              );
            }(),
          // The interaction + selection overlay on TOP of everything: all
          // gestures, the selection chrome, resize/rotate knobs, the
          // ink capture and the smart guides. Paint-only in the
          // presenter (nothing selected, not interactive).
          ShapesLayer(
            objects: objects,
            selectedId: selectedId,
            interactive: interactive,
            inkTool: inkTool,
            inkStyle: inkStyle,
            designW: designW,
            designH: designH,
            onSelect: onSelect,
            onLive: onLive,
            onCommit: onCommit,
            onGestureStart: onGestureStart,
            onStroke: onStroke,
            onEraseHits: onEraseHits,
            eraserRadius: eraserRadius,
            lassoIds: lassoIds,
            onLasso: onLasso,
            onLassoMove: onLassoMove,
            showRuler: showRuler,
            onObjectLongPress: onObjectLongPress,
            onCanvasLongPress: onCanvasLongPress,
            // This layer rides OPAQUE above the archetype canvas, so it
            // forwards taps that hit NO object (with nothing selected) —
            // the stage hit-tests the canvas's own text slots and invokes
            // [onTextTap], keeping built-in template text (Cover title,
            // Split bullets…) directly tappable while the deck is being
            // edited. Read-only stages pass no [onTextTap] and forward
            // nothing.
            onBackgroundTap: onTextTap == null
                ? null
                : (designPos) {
                    final key = SlideCanvas.textKeyAt(layout, designPos);
                    if (key != null) onTextTap!(key);
                  },
            overlayOnly: true,
          ),
          // The WYSIWYG typing field for the selected text box.
          if (typing &&
              textController != null &&
              textFocusNode != null &&
              selectedObj != null)
            TextEditFieldLayer(
              obj: selectedObj,
              controller: textController!,
              focusNode: textFocusNode!,
              designW: designW,
              designH: designH,
              baseColor: baseColor,
              baseFamily: baseFamily,
              baseFontSize: baseFontSize,
            ),
        ],
      );
    });
  }
}

/// The small link mark drawn on a linked object while editing.
class _LinkBadge extends StatelessWidget {
  const _LinkBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('link_badge'),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: kAccent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Icon(Icons.link, size: 11, color: Colors.white),
    );
  }
}

/// One animated object's arrival, driven by its staggered slice of the
/// entrance clock (the ink replay's AnimatedBuilder pattern, applied to the
/// object itself). At progress 1 the child renders untouched — the wrap is
/// a pure no-op in steady state.
class _ObjectEntrance extends StatelessWidget {
  const _ObjectEntrance({
    required this.kind,
    required this.slot,
    required this.count,
    required this.clock,
    required this.child,
  });

  /// The entrance kind (motion_math: fade / rise / pop).
  final String kind;

  /// This object's stagger slot (z-order among the animated) and the count.
  final int slot;
  final int count;

  /// The entrance clock (0..1 over the whole build's timeline).
  final Animation<double> clock;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: clock,
      builder: (context, built) {
        final p = entranceProgress(slot, count, clock.value);
        if (p >= 1.0) return built!;
        final eased = Curves.easeOut.transform(p);
        switch (kind) {
          case kEntranceFade:
            return Opacity(opacity: eased, child: built);
          case kEntranceRise:
            return Opacity(
              opacity: eased,
              child: Transform.translate(
                offset: Offset(0, 24 * (1 - eased)),
                child: built,
              ),
            );
          case kEntrancePop:
            final pop = Curves.easeOutBack.transform(p);
            return Opacity(
              opacity: eased,
              child: Transform.scale(
                scale: 0.55 + 0.45 * pop.clamp(0.0, 1.2),
                child: built,
              ),
            );
          default:
            return built!;
        }
      },
      child: child,
    );
  }
}
