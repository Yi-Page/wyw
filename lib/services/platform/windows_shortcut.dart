import 'dart:io';
import 'package:flutter/services.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

class WindowsShortcut {
  static const _channel = MethodChannel('com.yi.wyw/shortcut');

  static Future<bool> createDesktopShortcut() async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('createDesktopShortcut') ??
          false;
    } catch (e, s) {
      WywLogger().e('${LogTag.platform} 创建桌面快捷方式失败', error: e, stackTrace: s);
      return false;
    }
  }
}
