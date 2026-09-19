import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

class PlatformEnvironmentService {
  PlatformEnvironmentService._();

  static const _intentChannel = MethodChannel('com.yi.wyw/intent');

  static Future<bool> isInMultiWindowMode() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _intentChannel.invokeMethod('checkIfInMultiWindowMode');
    } catch (e, s) {
      // 原生端未实现该 method channel 时会抛 MissingPluginException（不是
      // PlatformException 子类），这里统一按非多窗口处理，避免影响调用方。
      WywLogger()
          .e('${LogTag.platform} 检查 Android 多窗口模式失败', error: e, stackTrace: s);
      return false;
    }
  }

  static Future<bool> isRunningOnX11() async {
    if (!Platform.isLinux) {
      return false;
    }
    try {
      return await _intentChannel.invokeMethod('isRunningOnX11');
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.platform} 检查 Linux X11 环境失败', error: e, stackTrace: s);
      return false;
    }
  }

  static Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) {
      return 0;
    }
    try {
      return await _intentChannel.invokeMethod('getAndroidSdkVersion');
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.platform} 获取 Android SDK 版本失败', error: e, stackTrace: s);
      return 0;
    }
  }

  /// 通过原生 WindowInsetsController 隐藏 Android 系统状态栏与导航栏。
  /// 相比 SystemChrome 更底层可靠（尤其 Android 15 edge-to-edge 强制下）。
  static Future<void> enterAndroidFullscreen() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _intentChannel.invokeMethod('enterFullscreen');
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.platform} 进入 Android 全屏失败', error: e, stackTrace: s);
    }
  }

  /// 恢复 Android 系统状态栏与导航栏显示。
  static Future<void> exitAndroidFullscreen() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _intentChannel.invokeMethod('exitFullscreen');
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.platform} 退出 Android 全屏失败', error: e, stackTrace: s);
    }
  }
}
