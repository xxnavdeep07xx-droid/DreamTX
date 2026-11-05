import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/features/projects/models/slide_size.dart';

void main() {
  group('SlideSize presets', () {
    test('widescreen is 13.33 x 7.5 in (12192000 x 6858000 EMU)', () {
      expect(SlideSize.widescreen.widthEmu, 12192000);
      expect(SlideSize.widescreen.heightEmu, 6858000);
      expect(SlideSize.widescreen.preset, SlideSizePreset.widescreen);
      expect(SlideSize.widescreen.isPortrait, isFalse);
      expect(SlideSize.widescreen.label(), '13.33 × 7.5 in');
    });

    test('standard is 10 x 7.5 in (9144000 x 6858000 EMU)', () {
      expect(SlideSize.standard.widthEmu, 9144000);
      expect(SlideSize.standard.heightEmu, 6858000);
      expect(SlideSize.standard.label(), '10 × 7.5 in');
    });

    test('portrait is 7.5 x 13.33 in (6858000 x 12192000 EMU)', () {
      expect(SlideSize.portrait.widthEmu, 6858000);
      expect(SlideSize.portrait.heightEmu, 12192000);
      expect(SlideSize.portrait.isPortrait, isTrue);
      expect(SlideSize.portrait.label(), '7.5 × 13.33 in');
    });

    test('fromEmu recognises presets and falls back to custom', () {
      expect(SlideSize.fromEmu(12192000, 6858000).preset,
          SlideSizePreset.widescreen);
      expect(SlideSize.fromEmu(9144000, 6858000).preset,
          SlideSizePreset.standard);
      expect(SlideSize.fromEmu(6858000, 12192000).preset,
          SlideSizePreset.portrait);
      expect(SlideSize.fromEmu(9000000, 6000000).preset,
          SlideSizePreset.custom);
    });

    test('metric labels convert inches to centimetres', () {
      expect(SlideSize.widescreen.label(metric: true), '33.87 × 19.05 cm');
      expect(SlideSize.standard.label(metric: true), '25.4 × 19.05 cm');
    });
  });

  group('SlideSize custom validation', () {
    test('accepts sizes within the 1–56 in range', () {
      final size = SlideSize.tryCustom(widthInches: 10, heightInches: 7.5);
      expect(size, isNotNull);
      expect(size!.widthEmu, 9144000);
      expect(size.heightEmu, 6858000);
      expect(size.preset, SlideSizePreset.custom);
    });

    test('rejects sizes outside the supported range', () {
      expect(SlideSize.tryCustom(widthInches: 0.5, heightInches: 7), isNull);
      expect(SlideSize.tryCustom(widthInches: 7, heightInches: 0.5), isNull);
      expect(SlideSize.tryCustom(widthInches: 57, heightInches: 7), isNull);
      expect(SlideSize.tryCustom(widthInches: 56, heightInches: 56),
          isNotNull);
      expect(SlideSize.tryCustom(widthInches: 1, heightInches: 1), isNotNull);
    });

    test('parses user measurements leniently', () {
      expect(SlideSize.tryParseMeasurement('10'), 10);
      expect(SlideSize.tryParseMeasurement(' 13.33 '), 13.33);
      expect(SlideSize.tryParseMeasurement('13,5'), 13.5);
      expect(SlideSize.tryParseMeasurement(''), isNull);
      expect(SlideSize.tryParseMeasurement('abc'), isNull);
      expect(SlideSize.tryParseMeasurement('-5'), isNull);
      expect(SlideSize.tryParseMeasurement('0'), isNull);
    });

    test('round-trips through EMU', () {
      final size = SlideSize.tryCustom(widthInches: 11.25, heightInches: 6)!;
      expect(size.widthInches, closeTo(11.25, 1e-9));
      expect(size.heightInches, closeTo(6, 1e-9));
    });
  });
}
