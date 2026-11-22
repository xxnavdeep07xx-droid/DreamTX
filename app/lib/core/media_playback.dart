library;

import 'package:flutter/services.dart';

/// The playback half of media objects — deliberately tiny: no bundled
/// video/audio SDK, no new dependency, no APK impact. The channel hands a
/// resolved local file to the system's own player (Android's
/// `ACTION_VIEW` via a FileProvider URI — registered by the same CI script
/// that writes the host activity). Audio and video both open the device
/// player; the deck stays a slide tool.
///
/// Registered by `MainActivity` (`.github/scripts/write_android_host.py`);
/// missing everywhere else (tests, desktop dev) — callers treat a
/// `MissingPluginException` as "not available here".
class MediaPlayback {
  MediaPlayback._();

  static const MethodChannel _channel = MethodChannel('dreamtx/media');

  /// Opens [path] (an already-resolved local file) with the device player.
  /// Returns false when the platform cannot play it (no channel, no
  /// activity, unreadable file) — the caller surfaces that, never a crash.
  static Future<bool> open(String path, {required String mime}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('open', {
        'path': path,
        'mime': mime,
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
