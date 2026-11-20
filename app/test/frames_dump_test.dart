import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/aspects.dart';
import 'package:dreamtx/core/bridge.dart';
import 'package:dreamtx/screens/editor_screen.dart';

/// Dev-tool recorder, env-gated: `DREAMTX_DUMP=1 flutter test
/// test/frames_dump_test.dart` walks the Files sheet's entrance and exit at
/// 60 FPS steps (16ms per frame — the recorder the spec asks for when the
/// platform supports it) and writes every frame as raw RGBA plus a manifest
/// under $DREAMTX_DUMP_DIR (default /home/z/my-project/download/frames).
/// scripts/frames_to_png.py turns the dump into PNGs for eyeballing.
///
/// CI runs this file with the env var absent: every test returns immediately
/// and passes as a no-op — the recording is a local dev artifact, never a
/// shipped contract (smoke_test.dart owns the contracts).
Map<String, dynamic> _fakeEngine(Map<String, dynamic> req) {
  switch (req['op']) {
    case 'meta':
      return {
        'ok': true,
        'object_presets': <Map<String, dynamic>>[],
        'archetypes': <String>[],
        'aspects': <String>['16:9', '16:10', '4:3', '1:1'],
      };
    case 'get_layout':
      final deck = req['deck'] as Map?;
      final (w, h) = deckDimsOf(deck?['aspect'] as String?);
      return {
        'ok': true,
        'layout': <String, dynamic>{
          'elements': <Map<String, dynamic>>[],
          'w': w,
          'h': h,
        },
      };
    default:
      return {'ok': false, 'error': 'unsupported: ${req['op']}'};
  }
}

void _mockStorage({required String dir}) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getApplicationDocumentsDirectory') return dir;
    throw PlatformException(code: 'unimplemented');
  });
}

Map<String, dynamic> _deck(String id, int n) => {
      'id': id,
      'title': 'Test deck',
      'dna': {'family': 'swiss_editorial'},
      'slides': List.generate(
          n,
          (i) => <String, dynamic>{
                'id': 's${i + 1}',
                'archetype': 'title',
                'content': {'title': 'Slide ${i + 1}'},
                'objects': <Map<String, dynamic>>[],
              }),
    };

typedef SnapFn = Future<void> Function(int frame, int ms);
typedef DriveFn = Future<void> Function(SnapFn snap);

Future<void> _record(WidgetTester tester, String out, String run, DriveFn drive) async {
  Directory('$out/$run').createSync(recursive: true);
  final frames = <Map<String, dynamic>>[];
  final root = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture_root')));
  Future<void> snap(int i, int ms) async {
    late ui.Image image;
    final f = '$run/f${i.toString().padLeft(3, '0')}.rgba';
    await tester.runAsync(() async {
      image = await root.toImage(pixelRatio: 1);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      await File('$out/$f').writeAsBytes(bytes.buffer.asUint8List());
    });
    frames.add({'file': f, 'ms': ms, 'w': image.width, 'h': image.height});
  }

  await drive(snap);
  final manifestFile = File('$out/manifest.json');
  final manifest = manifestFile.existsSync()
      ? jsonDecode(manifestFile.readAsStringSync())
          as Map<String, dynamic>
      : <String, dynamic>{'dir': out, 'fps': 60, 'runs': []};
  (manifest['runs']! as List)
      .removeWhere((r) => (r as Map)['run'] == run);
  manifest['runs'].add({'run': run, 'frames': frames});
  manifestFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest));
}

void main() {
  final enabled = Platform.environment['DREAMTX_DUMP'] == '1';
  final out = Platform.environment['DREAMTX_DUMP_DIR'] ??
      '/home/z/my-project/download/frames';

  testWidgets('record: files entrance with the tray expanded (60fps)', (tester) async {
    if (!enabled) return;
    Bridge.testOverride = _fakeEngine;
    final tmp = Directory.systemTemp.createTempSync('dump');
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('capture_root'),
        child: MaterialApp(
            home: EditorScreen(deck: _deck('d1', 8)))));
    await tester.pumpAndSettle();

    await _record(tester, out, 'entrance_expanded', (snap) async {
      await snap(0, 0); // the steady editor before
      await tester.tap(find.text('Files'));
      await tester.pump();
      await snap(1, 0); // THE FIRST VISIBLE FRAME of the mount: nothing
      await tester.pump(const Duration(milliseconds: 16)); // the retarget
      var ms = 16;
      for (var i = 2; i <= 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        ms += 16;
        await snap(i, ms);
      }
      await tester.pumpAndSettle();
      await snap(17, ms); // settled
    });
    tmp.deleteSync(recursive: true);
  });

  testWidgets('record: files entrance with the tray collapsed (60fps)', (tester) async {
    if (!enabled) return;
    Bridge.testOverride = _fakeEngine;
    final tmp = Directory.systemTemp.createTempSync('dump');
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('capture_root'),
        child: MaterialApp(
            home: EditorScreen(deck: _deck('d1', 8)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filmstrip_handle')));
    await tester.pumpAndSettle();

    await _record(tester, out, 'entrance_collapsed', (snap) async {
      await snap(0, 0);
      await tester.tap(find.text('Files'));
      await tester.pump();
      await snap(1, 0);
      await tester.pump(const Duration(milliseconds: 16));
      var ms = 16;
      for (var i = 2; i <= 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        ms += 16;
        await snap(i, ms);
      }
      await tester.pumpAndSettle();
      await snap(17, ms);
    });
    tmp.deleteSync(recursive: true);
  });

  testWidgets('record: files exit (60fps)', (tester) async {
    if (!enabled) return;
    Bridge.testOverride = _fakeEngine;
    final tmp = Directory.systemTemp.createTempSync('dump');
    _mockStorage(dir: tmp.path);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('capture_root'),
        child: MaterialApp(
            home: EditorScreen(deck: _deck('d1', 8)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    await _record(tester, out, 'exit_expanded', (snap) async {
      await snap(0, 0); // open at rest
      await tester.tap(find.text('Files').first);
      await tester.pump();
      await snap(1, 0); // the exit's first frame
      var ms = 0;
      for (var i = 2; i <= 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        ms += 16;
        await snap(i, ms);
      }
      await tester.pumpAndSettle();
      await snap(17, ms); // unmounted — the plain editor
    });
    tmp.deleteSync(recursive: true);
  });
}
