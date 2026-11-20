library;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// The device pickers behind Insert · Image and Insert · Media, wrapped in
/// one seam: production calls the platform plugins; tests swap
/// [ImagePickers.testOverride] with an in-memory picker so the whole
/// insert flow (import into the deck's resources, place the object) runs
/// under the host test runner.

class ImagePickers {
  ImagePickers._();

  /// Test seam: (source, kind) -> a path to a "picked" file, or null when
  /// the user dismisses the picker.
  ///
  ///  * source: 'gallery' | 'camera' (an image in both cases)
  ///  * kind:   'image' | 'video' | 'audio' (the document browser)
  static Future<String?> Function(String source, String kind)? testOverride;

  /// Picks an image — the gallery chooser or a camera capture.
  static Future<String?> pickImage({required bool camera}) async {
    final override = testOverride;
    if (override != null) {
      return override(camera ? 'camera' : 'gallery', 'image');
    }
    try {
      final x = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 92,
      );
      return x?.path;
    } catch (_) {
      return null; // no camera / permission denied — nothing inserted
    }
  }

  /// Picks an existing video or audio file from the device's documents.
  static Future<String?> pickMedia({required String kind}) async {
    final override = testOverride;
    if (override != null) {
      return override('documents', kind);
    }
    try {
      final type = kind == 'video' ? FileType.video : FileType.audio;
      final x = await FilePicker.pickFile(type: type);
      return x?.path;
    } catch (_) {
      return null;
    }
  }
}

/// Whether a file path looks like an image the canvas can render.
bool isImagePath(String path) =>
    switch (path.toLowerCase().split('.').last) {
      'png' || 'jpg' || 'jpeg' || 'webp' || 'gif' || 'bmp' || 'heic' => true,
      _ => false,
    };

/// Human display name for a file path.
String baseNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

/// The file's rough media kind from its extension.
String mediaKindOfPath(String path) {
  switch (path.toLowerCase().split('.').last) {
    case 'mp4':
    case 'mov':
    case 'webm':
    case 'mkv':
    case 'avi':
      return 'video';
    default:
      return 'audio';
  }
}
