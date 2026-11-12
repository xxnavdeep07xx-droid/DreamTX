import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/shared/widgets/app_logo.dart';

void main() {
  testWidgets('brand SVG assets compile through the real pipeline',
      (tester) async {
    // Loads and compiles the exact bytes the app ships with; fails loudly
    // if a gradient or path feature ever falls out of vector_graphics.
    final sizes = <String, Size>{
      'assets/brand/dreamtx_mark.svg': const Size(341, 288),
      'assets/brand/dreamtx_mark_compact.svg': const Size(512, 512),
    };
    for (final entry in sizes.entries) {
      final info = await vg.loadPicture(SvgAssetLoader(entry.key), null);
      expect(info.size, entry.value, reason: '${entry.key} viewBox changed');
      info.picture.dispose();
    }
  });

  testWidgets('AppLogo renders the full mark at brand sizes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: AppLogo(size: 34)))),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(AppLogo)), const Size(34, 34));
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('AppLogo switches to the compact mark below 26dp', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: AppLogo(size: 18)))),
    );
    await tester.pumpAndSettle();

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = picture.bytesLoader;
    expect(loader, isA<SvgAssetLoader>());
    expect((loader as SvgAssetLoader).assetName,
        'assets/brand/dreamtx_mark_compact.svg');
  });
}
