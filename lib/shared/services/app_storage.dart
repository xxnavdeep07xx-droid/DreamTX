import 'dart:io';

import 'package:flutter/services.dart';

/// Access to on-device storage locations.
///
/// Implemented over the `dreamtx/files` platform channel (see
/// `MainActivity.kt`) — no third-party plugins required.
class AppStorage {
  const AppStorage._();

  static const MethodChannel _channel = MethodChannel('dreamtx/files');

  /// Path of the app-internal files directory (Android `Context.filesDir`).
  ///
  /// Returns `null` when the native side is unavailable — tests and
  /// non-Android hosts. Callers must treat that as "storage not ready"
  /// rather than pretending a save succeeded.
  static Future<String?> filesDirectoryPath() async {
    try {
      return await _channel.invokeMethod<String>('getFilesDirectory');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Directory that holds the `.dreamtx` project documents, created on
  /// first use. Returns `null` when native storage is unavailable.
  static Future<Directory?> projectsDirectory() async {
    final basePath = await filesDirectoryPath();
    if (basePath == null) return null;
    final directory = Directory('$basePath/projects');
    await directory.create(recursive: true);
    return directory;
  }
}
