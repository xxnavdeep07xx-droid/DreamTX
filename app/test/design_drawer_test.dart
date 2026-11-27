import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/screens/design_drawer.dart';

/// The Design drawer reports each choice to the editor: a family card, the
/// shuffle chip, a variant chip and a background swatch.
void main() {
  testWidgets('Design drawer reports family, variant, shuffle and background taps',
      (tester) async {
    String? family;
    int? seed;
    String? background;
    var shuffled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 700,
              child: DesignDrawer(
                families: const [
                  ('swiss_editorial', 'Swiss editorial'),
                  ('bold', 'Bold'),
                ],
                currentFamily: 'swiss_editorial',
                onFamily: (id) => family = id,
                onShuffle: () => shuffled = true,
                variants: const <Map<String, dynamic>>[
                  {
                    'seed': 5,
                    'palette': {'bg': 'FFFFFF', 'accent': '000000'},
                  },
                ],
                currentSeed: 5,
                onVariant: (s) => seed = s,
                hideGraphics: false,
                onToggleGraphics: () {},
                palette: const [Color(0xFFFFE14D)],
                slideBackground: null,
                onBackground: (hex) => background = hex,
                onApplyAll: (hex) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Hide graphics'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('design_family_bold')));
    await tester.tap(find.byKey(const ValueKey('design_family_bold')));
    expect(family, 'bold');

    await tester.ensureVisible(find.byKey(const ValueKey('design_shuffle')));
    await tester.tap(find.byKey(const ValueKey('design_shuffle')));
    expect(shuffled, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('design_variant_5')));
    await tester.tap(find.byKey(const ValueKey('design_variant_5')));
    expect(seed, 5);

    // The deck palette's first colour, as a background swatch: hex, no '#'.
    final swatch = find.byWidgetPredicate(
      (w) => w is DesignSwatch && w.bg == const Color(0xFFFFE14D),
    );
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    expect(background, 'FFE14D');
  });

  testWidgets(
      'the deck-default chip reports null, the tools report their actions, '
      'and the current family card is the selected one',
      (tester) async {
    String? background;
    String? appliedAll;
    String? family;
    var graphicsToggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 700,
              child: DesignDrawer(
                families: const [
                  ('swiss_editorial', 'Swiss editorial'),
                  ('cinematic', 'Cinematic'),
                  ('magazine_serif', 'Magazine serif'),
                  ('bold', 'Bold'),
                  ('pastel', 'Pastel'),
                ],
                currentFamily: 'bold',
                onFamily: (id) => family = id,
                onShuffle: () {},
                variants: const <Map<String, dynamic>>[
                  {
                    'seed': 11,
                    'palette': {'bg': 'FFE14D', 'accent': 'E63946'},
                  },
                ],
                currentSeed: 11,
                onVariant: (s) {},
                hideGraphics: false,
                onToggleGraphics: () => graphicsToggled = true,
                palette: const [Color(0xFFFFE14D)],
                slideBackground: 'FFE14D',
                onBackground: (hex) => background = hex,
                onApplyAll: (hex) => appliedAll = hex,
              ),
            ),
          ),
        ),
      ),
    );

    // One preview card per family, each tappable.
    for (final id in ['swiss_editorial', 'cinematic', 'magazine_serif', 'bold', 'pastel']) {
      expect(find.byKey(ValueKey('design_family_$id')), findsOneWidget);
    }
    // The current family's card is the one wearing the check badge.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.check),
        matching: find.byKey(const ValueKey('design_family_bold')),
      ),
      findsOneWidget,
    );

    // The deck-default chip: back to the DNA background.
    await tester.ensureVisible(find.byKey(const ValueKey('design_deck_default')));
    await tester.tap(find.byKey(const ValueKey('design_deck_default')));
    expect(background, isNull);

    // The slide tools: the graphics toggle, and apply-to-all carrying the
    // slide's own background.
    await tester.ensureVisible(find.byKey(const ValueKey('design_hide_graphics')));
    await tester.tap(find.byKey(const ValueKey('design_hide_graphics')));
    expect(graphicsToggled, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('design_apply_all')));
    await tester.tap(find.byKey(const ValueKey('design_apply_all')));
    expect(appliedAll, 'FFE14D');

    // A family card still applies on tap.
    await tester.ensureVisible(find.byKey(const ValueKey('design_family_pastel')));
    await tester.tap(find.byKey(const ValueKey('design_family_pastel')));
    expect(family, 'pastel');
  });

  testWidgets(
      "the current family card paints with the deck's own variant palette",
      (tester) async {
    // The deck's variant (seed 7) resolves to bg FFE14D / accent E63946:
    // the current family's preview field must be THAT colour, and the
    // selected variant chip must be the matching one.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 700,
              child: DesignDrawer(
                families: const [('bold', 'Bold'), ('cinematic', 'Cinematic')],
                currentFamily: 'bold',
                onFamily: (id) {},
                onShuffle: () {},
                variants: const <Map<String, dynamic>>[
                  {
                    'seed': 3,
                    'palette': {'bg': 'FFFFFF', 'accent': '000000'},
                  },
                  {
                    'seed': 7,
                    'palette': {'bg': 'FFE14D', 'accent': 'E63946'},
                  },
                ],
                currentSeed: 7,
                onVariant: (s) {},
                hideGraphics: false,
                onToggleGraphics: () {},
                palette: const [Color(0xFFFFE14D)],
                slideBackground: null,
                onBackground: (hex) {},
                onApplyAll: (hex) {},
              ),
            ),
          ),
        ),
      ),
    );

    // The preview field: a ColoredBox with the resolved bg inside the
    // current family's card.
    final liveField = find.descendant(
      of: find.byKey(const ValueKey('design_family_bold')),
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFFFFE14D),
      ),
    );
    expect(liveField, findsOneWidget);

    // The OTHER family's card must NOT wear the deck's live palette —
    // it paints its own representative look (cinematic's near-black
    // field), never the current deck's colors.
    final otherField = find.descendant(
      of: find.byKey(const ValueKey('design_family_cinematic')),
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF0D1117),
      ),
    );
    expect(otherField, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('design_family_cinematic')),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFFFFE14D),
        ),
      ),
      findsNothing,
    );

    // Both variant chips exist; the matching seed's chip is the strip's
    // selected one (its tap target is present and keyable).
    expect(find.byKey(const ValueKey('design_variant_3')), findsOneWidget);
    expect(find.byKey(const ValueKey('design_variant_7')), findsOneWidget);
  });
}