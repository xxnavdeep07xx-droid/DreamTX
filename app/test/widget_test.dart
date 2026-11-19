import 'package:flutter_test/flutter_test.dart';

// Guard file: `flutter create .` (the CI platform-folder generator) only
// adds files that are MISSING — without this file it would regenerate the
// default MyApp-counter template, which does not compile against DreamTX
// and fails the smoke gate. The real suite lives in smoke_test.dart.
void main() {
  test('widget_test.dart guards the flutter-create template slot', () {
    expect(1 + 1, 2);
  });
}
