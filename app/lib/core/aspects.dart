/// Deck-frame aspects — the one Dart mirror of the Rust core's `ASPECTS`
/// contract (deck-core model.rs). The design HEIGHT is 720 in every aspect;
/// only the width follows the ratio. The editor's canvas frame, the Files
/// drawer's Aspect tile, and object placement all read from here so the app
/// and the engine agree on the frame without a round-trip.

/// Supported aspects → design-space (width, height) in px.
const Map<String, (double, double)> kDeckAspects = {
  '16:9': (1280.0, 720.0),
  '16:10': (1152.0, 720.0),
  '4:3': (960.0, 720.0),
  '1:1': (720.0, 720.0),
};

/// The deck's design-space dimensions — the recognized aspect, else the
/// classic 1280×720 (old decks predate the field; the engine defaults the
/// same way).
(double, double) deckDimsOf(String? aspect) =>
    kDeckAspects[aspect ?? '16:9'] ?? const (1280.0, 720.0);

/// The deck's width÷height ratio for [AspectRatio].
double aspectRatioOf(String? aspect) {
  final (w, h) = deckDimsOf(aspect);
  return w / h;
}

/// The aspect's frame size as a display string ("1280 × 720").
String dimsLabel(String aspect) {
  final (w, h) = deckDimsOf(aspect);
  final whole = (v) => v.round() == v ? v.toInt().toString() : v.toString();
  return '${whole(w)} × ${whole(h)}';
}
