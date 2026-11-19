import 'dart:convert';
import 'dart:io';

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
  static Map<String, dynamic> command(Map<String, dynamic> req) {
    final override = testOverride;
    if (override != null) return override(req);
    final reqPtr = jsonEncode(req).toNativeUtf8().cast<ffi.Uint8>();
    final outPtr = calloc<ffi.Pointer<ffi.Uint8>>();
    final rc = _command()(reqPtr, outPtr);
    if (rc != 0) {
      calloc.free(outPtr);
      calloc.free(reqPtr.cast());
      throw StateError('deck-core rejected the request (rc=$rc)');
    }
    final respPtr = outPtr.value;
    final respText = respPtr.cast<Utf8>().toDartString();
    _free()(respPtr);
    calloc.free(outPtr);
    calloc.free(reqPtr.cast());

    final decoded = jsonDecode(respText);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('deck-core returned an unexpected payload');
    }
    return decoded;
  }
}
