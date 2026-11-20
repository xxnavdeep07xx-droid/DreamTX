import 'package:flutter/services.dart';

/// The Android half of folder import. Android's document picker hands back
/// Storage Access Framework `content://` tree URIs, which dart:io cannot
/// enumerate — the host's `dreamtx/saf` method channel does it instead:
///
///  * `list` — walks one picked tree (files in subfolders included,
///    breadth-first, hard-capped) and returns each file's name, document
///    URI, and size, plus the tree's own display name;
///  * `copyToCache` — streams one document into the app cache and returns
///    the local path, which the resource store then copies into its own
///    documents tree.
///
/// The channel is registered by `MainActivity`, written into the
/// CI-regenerated android/ host by `.github/scripts/write_android_host.py`.
/// It only exists on Android — callers reach for it only when a picked
/// directory URI is a `content://` one, which never happens elsewhere.
class SafFile {
  const SafFile({required this.name, required this.uri, required this.size});

  /// The document's display name (what the folder shows the user).
  final String name;

  /// The document's full `content://` URI — the handle `copyToCache` reads.
  final String uri;

  /// The size the resolver reported, in bytes (0 when it did not).
  final int size;
}

/// One walked folder: its display name and the files found under it.
class SafListing {
  const SafListing({required this.rootName, required this.files});

  final String rootName;
  final List<SafFile> files;
}

class SafBridge {
  static const MethodChannel _channel = MethodChannel('dreamtx/saf');

  /// Lists the files under one SAF tree URI. Throws [MissingPluginException]
  /// where the channel is not registered (never on the Android builds that
  /// ship it) and [PlatformException] when the resolver refuses the walk.
  static Future<SafListing> list(String treeUri) async {
    final raw =
        await _channel.invokeMapMethod<String, dynamic>('list', treeUri);
    if (raw == null) {
      throw MissingPluginException('dreamtx/saf returned no listing');
    }
    final files = (raw['files'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((m) => SafFile(
              name: (m['name'] ?? '').toString(),
              uri: (m['uri'] ?? '').toString(),
              size: m['size'] is num ? (m['size'] as num).toInt() : 0,
            ))
        .where((f) => f.uri.isNotEmpty)
        .toList();
    return SafListing(rootName: (raw['rootName'] ?? '').toString(), files: files);
  }

  /// Copies one document into the cache and returns its local path.
  static Future<String> copyToCache(String uri) async {
    final path = await _channel.invokeMethod<String>('copyToCache', uri);
    if (path == null || path.isEmpty) {
      throw MissingPluginException('dreamtx/saf returned no path');
    }
    return path;
  }
}
