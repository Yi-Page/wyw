import 'package:flutter/services.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

class ExternalPlayer {
  // 注意：仍需开发 iOS/Linux 设备的外部播放功能。
  // 在 Windows 设备上，对于其他可能的实现，使用 scheme 的方案没有效果。VLC / PotPlayer 等主流播放器更倾向于使用 CLI 命令。
  // 可行的 iOS 处理代码，请参见 ios/Runner/AppDelegate.swift 的注释部分。
  static const platform = MethodChannel('com.yi.wyw/intent');

  static Future<bool> launchURLWithMIME(String url, String mimeType) async {
    try {
      await platform.invokeMethod(
          'openWithMime', <String, String>{'url': url, 'mimeType': mimeType});
      return true;
    } on PlatformException catch (e, s) {
      WywLogger().e(
          '${LogTag.player} 外部播放器按 MIME 打开失败 mimeType=$mimeType url=$url',
          error: e,
          stackTrace: s);
      return false;
    }
  }

  static Future<bool> launchURLWithReferer(String url, String referer) async {
    try {
      await platform.invokeMethod(
          'openWithReferer', <String, String>{'url': url, 'referer': referer});
      return true;
    } on PlatformException catch (e, s) {
      WywLogger().e('${LogTag.player} 外部播放器带 referer 打开失败 url=$url',
          error: e, stackTrace: s);
      return false;
    }
  }
}
