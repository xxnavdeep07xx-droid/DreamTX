import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/screens/design_drawer.dart';

/// The Design drawer reports each choice to the editor: a family tile, the
/// shuffle tile, a variant swatch and a background swatch.
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
}
