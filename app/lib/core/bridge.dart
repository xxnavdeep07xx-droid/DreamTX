import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'dart:ffi' as ffi;

/// FFI bridge to the Rust deck-core (`libdreamtx.so` on Android).
/// One C entry point, JSON protocol — identical to the Worker's wasm surface.
class Bridge {
  Bridge._();

  /// Widget-test seam: when non-null, commands are answered by this
  /// in-memory engine instead of crossing FFI into the Rust core (the host
  /// test runner has no libdreamtx.so). Production never sets it.
  static Map<String, dynamic> Function(Map<String, dynamic> req)? testOverride;

  static ffi.DynamicLibrary? _lib;

  static ffi.DynamicLibrary get lib {
    if (_lib != null) return _lib!;
    _lib = Platform.isAndroid
        ? ffi.DynamicLibrary.open('libdreamtx.so')
        : ffi.DynamicLibrary.process(); // desktop dev target arrives post-v1
    return _lib!;
  }

  static int Function(
          ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Pointer<ffi.Uint8>>)
      _command() => lib.lookupFunction<
          ffi.Int32 Function(
              ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Pointer<ffi.Uint8>>),
          int Function(ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Pointer<ffi.Uint8>>)>('dreamtx_command');

  static void Function(ffi.Pointer<ffi.Uint8>) _free() => lib.lookupFunction<
      ffi.Void Function(ffi.Pointer<ffi.Uint8>),
      void Function(ffi.Pointer<ffi.Uint8>)>('dreamtx_free');

  /// Run a JSON command against the Rust core.
  ///
  /// Every native allocation is freed on every path: the request string,
  /// the out-slot, and the engine's response string all live inside one
  /// try/finally, so a throw anywhere (a malformed payload, a decode error)
  /// can never leak native memory.
  static Map<String, dynamic> command(Map<String, dynamic> req) {
    final override = testOverride;
    if (override != null) return override(req);
    ffi.Pointer<ffi.Uint8>? reqPtr;
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>? outPtr;
    try {
      reqPtr = jsonEncode(req).toNativeUtf8().cast<ffi.Uint8>();
      outPtr = calloc<ffi.Pointer<ffi.Uint8>>();
      final rc = _command()(reqPtr, outPtr);
      if (rc != 0) {
        throw StateError('deck-core rejected the request (rc=$rc)');
      }
      final respPtr = outPtr.value;
      try {
        final respText = respPtr.cast<Utf8>().toDartString();
        final decoded = jsonDecode(respText);
        if (decoded is! Map<String, dynamic>) {
          throw StateError('deck-core returned an unexpected payload');
        }
        return decoded;
      } finally {
        // The engine's response string is ours to free either way.
        _free()(respPtr);
      }
    } finally {
      if (outPtr != null) calloc.free(outPtr);
      if (reqPtr != null) calloc.free(reqPtr.cast());
    }
  }

  /// Run a heavy command on a background isolate so the UI never freezes
  /// while the engine works (exports serialize and zip whole decks, and
  /// large decks with embedded images can take hundreds of milliseconds).
  ///
  /// The request map crosses the isolate boundary (it must be plain JSON
  /// data — it always is: every command is JSON), the isolate opens the
  /// same native library and runs the call there, and the response map
  /// crosses back. Test overrides stay on the calling isolate: they are
  /// closures, not sendable, so the seam routes to the synchronous
  /// [command] instead.
  static Future<Map<String, dynamic>> commandHeavy(
      Map<String, dynamic> req) async {
    if (testOverride != null) return command(req);
    return Isolate.run(() => command(req));
  }
}
