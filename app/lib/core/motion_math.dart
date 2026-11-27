/// Presentation-time motion: slide transitions and object entrance effects.
///
/// Deck-level app-owned maps, the sections/tables/imageMeta carry contract —
/// the Rust core's `Deck` struct drops unknown keys on every round-trip, so
/// the editor carries these forward in `_setDeck` (and sanitizes them against
/// live slide/object ids, so a deleted slide or object folds its entry away
/// instead of haunting the deck):
///
///  * `deck['transitions']` — slideId → transition kind. How the slide
///    ARRIVES when the presenter moves to it by tap / link jump. Swipes
///    always follow the finger (the classic push), exactly as before.
///  * `deck['animations']`  — objectId → entrance kind. How the object
///    ARRIVES when its slide is shown: staggered, z-order, automatic.
///
/// Presentation-time only: the exporters render slides statically today, so
/// transitions and entrances are the app's playback layer (README "Known
/// v0.2 limits" says so) — the deck files carry the intent for the day the
/// exporters grow the corresponding PPTX/PDF fields.
///
/// Pure functions throughout — the rules are unit-testable, mirroring
/// furniture_math / ink_math.
library;

// ---------------------------------------------------------------------------
// Kinds
// ---------------------------------------------------------------------------

/// The default arrival: the standard slide-along push. Absent from the
/// deck map entirely — an old deck (or an untouched slide) behaves exactly
/// as it always has.
const String kTransitionPush = 'push';

/// The incoming slide fades in through black.
const String kTransitionFade = 'fade';

/// The incoming slide scales up into place.
const String kTransitionZoom = 'zoom';

/// The incoming slide glides up into place.
const String kTransitionRise = 'rise';

/// A hard cut — no arrival motion at all.
const String kTransitionCut = 'none';

/// Every transition kind the picker offers, in display order.
const List<String> kTransitionKinds = [
  kTransitionPush,
  kTransitionFade,
  kTransitionZoom,
  kTransitionRise,
  kTransitionCut,
];

/// The picker labels, one per [kTransitionKinds] entry.
const Map<String, String> kTransitionLabels = {
  kTransitionPush: 'Push',
  kTransitionFade: 'Fade',
  kTransitionZoom: 'Zoom',
  kTransitionRise: 'Rise',
  kTransitionCut: 'Cut',
};

/// No entrance effect — the object is simply there. Absent from the deck
/// map; picking it removes the entry.
const String kEntranceNone = 'none';

/// The object fades in.
const String kEntranceFade = 'fade';

/// The object rises into place.
const String kEntranceRise = 'rise';

/// The object pops in from small.
const String kEntrancePop = 'pop';

/// Every entrance kind the picker offers, in display order.
const List<String> kEntranceKinds = [
  kEntranceNone,
  kEntranceFade,
  kEntranceRise,
  kEntrancePop,
];

/// The picker labels, one per [kEntranceKinds] entry.
const Map<String, String> kEntranceLabels = {
  kEntranceNone: 'None',
  kEntranceFade: 'Fade',
  kEntranceRise: 'Rise',
  kEntrancePop: 'Pop',
};

// ---------------------------------------------------------------------------
// Transitions — read / write / sanitize
// ---------------------------------------------------------------------------

/// The slide's transition kind. Absent, malformed or unknown reads as the
/// default push — a hand-edited or future deck file never breaks playback.
String transitionOf(Map<String, dynamic> deck, Object? slideId) {
  if (slideId == null) return kTransitionPush;
  final t = (deck['transitions'] as Map?)?[slideId.toString()];
  return t is String && kTransitionKinds.contains(t) ? t : kTransitionPush;
}

/// Set or clear a slide's transition on [deck] (mutates it — callers pass
/// their `_copy()`). `push` or null removes the entry: the default carries no
/// data, so untouched decks stay byte-identical to old files.
void setDeckTransition(
    Map<String, dynamic> deck, String slideId, String? kind) {
  final map = _transitionsOf(deck);
  if (kind == null ||
      kind == kTransitionPush ||
      !kTransitionKinds.contains(kind)) {
    map.remove(slideId);
  } else {
    map[slideId] = kind;
  }
  if (map.isEmpty) {
    deck.remove('transitions');
  } else {
    deck['transitions'] = map;
  }
}

/// One kind on every slide — the picker's "Apply to all". `push` clears the
/// whole map (the default everywhere is no data at all).
void applyDeckTransitionToAll(Map<String, dynamic> deck, String kind) {
  if (!kTransitionKinds.contains(kind) || kind == kTransitionPush) {
    deck.remove('transitions');
    return;
  }
  final ids = [
    for (final s in ((deck['slides'] as List?) ?? const []).whereType<Map>())
      if (s['id'] != null) s['id'].toString(),
  ];
  deck['transitions'] = {for (final id in ids) id: kind};
}

/// Drop transition entries whose slide no longer exists. Empty result
/// removes the key entirely (the imageMeta tombstone lesson: an absent key
/// is "engine dropped it — carry forward"; an empty map is "genuinely
/// empty"). Mutates [deck]; returns the settled map (or null when empty).
Map<String, String>? sanitizeDeckTransitions(Map<String, dynamic> deck) {
  final map = deck['transitions'];
  if (map is! Map || map.isEmpty) {
    deck.remove('transitions');
    return null;
  }
  final live = <String>{
    for (final s in ((deck['slides'] as List?) ?? const []).whereType<Map>())
      if (s['id'] != null) s['id'].toString(),
  };
  final clean = <String, String>{
    for (final e in map.entries)
      if (live.contains(e.key.toString()) &&
          e.value is String &&
          kTransitionKinds.contains(e.value))
        e.key.toString(): e.value as String,
  };
  if (clean.isEmpty) {
    deck.remove('transitions');
    return null;
  }
  deck['transitions'] = clean;
  return clean;
}

Map<String, String> _transitionsOf(Map<String, dynamic> deck) {
  final t = deck['transitions'];
  if (t is Map) {
    return <String, String>{
      for (final e in t.entries)
        if (e.value is String) e.key.toString(): e.value as String,
    };
  }
  return {};
}

// ---------------------------------------------------------------------------
// Entrances — read / write / stagger
// ---------------------------------------------------------------------------

/// The object's entrance kind (null / unknown = none — simply present).
String? entranceOf(Map<String, dynamic> deck, Object? objectId) {
  if (objectId == null) return null;
  final a = (deck['animations'] as Map?)?[objectId.toString()];
  return a is String && kEntranceKinds.contains(a) && a != kEntranceNone
      ? a
      : null;
}

/// Set or clear an object's entrance on [deck] (mutates it — callers pass
/// their `_copy()`). `none` or null removes the entry.
void setDeckEntrance(Map<String, dynamic> deck, String objectId, String? kind) {
  final map = _animationsOf(deck);
  if (kind == null || kind == kEntranceNone || !kEntranceKinds.contains(kind)) {
    map.remove(objectId);
  } else {
    map[objectId] = kind;
  }
  if (map.isEmpty) {
    deck.remove('animations');
  } else {
    deck['animations'] = map;
  }
}

/// The slide's animated object ids in z-order — the stagger walks the deck's
/// own stacking, exactly what the canvas shows and the exporters honor.
List<String> animatedObjectIds(Map<String, dynamic> deck,
    List<Map<String, dynamic>> objects) {
  return [
    for (final o in objects)
      if (o['id'] != null && entranceOf(deck, o['id']) != null)
        o['id'].toString(),
  ];
}

/// How many objects on the slide carry an entrance.
int entranceCount(Map<String, dynamic> deck, List<Map<String, dynamic>> objects) =>
    animatedObjectIds(deck, objects).length;

/// Drop animation entries whose object no longer exists (any slide). Empty
/// result removes the key entirely (the tombstone rule above). Mutates
/// [deck]; returns the settled map (or null when empty).
Map<String, dynamic>? sanitizeDeckAnimations(Map<String, dynamic> deck) {
  final map = deck['animations'];
  if (map is! Map || map.isEmpty) {
    deck.remove('animations');
    return null;
  }
  final live = <String>{
    for (final s in ((deck['slides'] as List?) ?? const [])
        .whereType<Map>())
      for (final o in ((s['objects'] as List?) ?? const []).whereType<Map>())
        if (o['id'] != null) o['id'].toString(),
  };
  final clean = <String, String>{
    for (final e in map.entries)
      if (live.contains(e.key.toString()) &&
          e.value is String &&
          kEntranceKinds.contains(e.value) &&
          e.value != kEntranceNone)
        e.key.toString(): e.value as String,
  };
  if (clean.isEmpty) {
    deck.remove('animations');
    return null;
  }
  deck['animations'] = clean;
  return clean;
}

Map<String, String> _animationsOf(Map<String, dynamic> deck) {
  final a = deck['animations'];
  if (a is Map) {
    return <String, String>{
      for (final e in a.entries)
        if (e.value is String) e.key.toString(): e.value as String,
    };
  }
  return {};
}

// ---------------------------------------------------------------------------
// The entrance timeline (stagger + overlap, unlike ink replay's equal
// non-overlapping slices: entrances read as one flowing build, not a queue)
// ---------------------------------------------------------------------------

/// One object's effect length, milliseconds.
const double kEntranceEffectMs = 300;

/// Gap between successive starts, milliseconds.
const double kEntranceStaggerMs = 110;

/// Hard ceiling on the whole build — a heavily animated slide still
/// resolves quickly.
const double kEntranceMaxTotalMs = 2400;

/// The whole build's duration: the last start plus its effect, capped.
double entranceTimelineMs(int count) {
  if (count <= 0) return 0;
  if (count == 1) return kEntranceEffectMs;
  var stagger = kEntranceStaggerMs;
  final uncapped = stagger * (count - 1) + kEntranceEffectMs;
  if (uncapped > kEntranceMaxTotalMs) {
    stagger = (kEntranceMaxTotalMs - kEntranceEffectMs) / (count - 1);
  }
  return stagger * (count - 1) + kEntranceEffectMs;
}

/// How far object [index] (of [count], z-order among the animated) has
/// arrived at overall time [t] (0..1 of [entranceTimelineMs]).
double entranceProgress(int index, int count, double t) {
  if (count <= 0) return 1.0;
  if (index < 0) return 0.0;
  if (index >= count) return 1.0;
  final total = entranceTimelineMs(count);
  var stagger = kEntranceStaggerMs;
  if (total > kEntranceMaxTotalMs) {
    stagger = (kEntranceMaxTotalMs - kEntranceEffectMs) / (count - 1);
  }
  final double p =
      (t.clamp(0.0, 1.0) * total - index * stagger) / kEntranceEffectMs;
  return p.clamp(0.0, 1.0).toDouble();
}
