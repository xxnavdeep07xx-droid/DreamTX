import 'package:flutter/services.dart';

import 'link_math.dart';

/// Opens a web link on the device, through the media channel that the CI
/// script's Android host serves (`openUrl`: ACTION_VIEW, http/https/mailto
/// only). Returns false when the platform cannot open it (no channel, no
/// handler, or a scheme that is refused) — the caller tells the user.
class LinkOpen {
  LinkOpen._();

  static const MethodChannel _channel = MethodChannel('dreamtx/media');

  static Future<bool> openUrl(String url) async {
    if (!isSafeLinkUrl(url)) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', url.trim());
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
