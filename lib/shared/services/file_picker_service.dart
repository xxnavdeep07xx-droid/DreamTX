import 'package:flutter/services.dart';

/// A document picked through the native Android file picker.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.uri,
    this.sizeBytes,
  });

  final String name;
  final String uri;
  final int? sizeBytes;
}

/// Thrown when the native picker is unavailable (e.g. on non-Android hosts).
class FilePickerUnsupportedException implements Exception {
  const FilePickerUnsupportedException(this.message);

  final String message;

  @override
  String toString() => 'FilePickerUnsupportedException: $message';
}

/// Thin wrapper over the `dreamtx/files` platform channel.
///
/// Implemented natively in `MainActivity.kt` with ACTION_OPEN_DOCUMENT —
/// no third-party plugin needed.
class FilePickerService {
  const FilePickerService();

  static const MethodChannel _channel = MethodChannel('dreamtx/files');

  /// Opens the Android document picker. Returns `null` when the user cancels.
  Future<PickedFile?> pickDocument() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('pickDocument');
      if (result == null) return null;
      return PickedFile(
        name: (result['name'] as String?) ?? 'Document',
        uri: (result['uri'] as String?) ?? '',
        sizeBytes: result['size'] as int?,
      );
    } on PlatformException catch (e) {
      throw FilePickerUnsupportedException(e.message ?? e.code);
    } on MissingPluginException {
      throw const FilePickerUnsupportedException(
        'Native picker unavailable on this platform',
      );
    }
  }
}
