import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/platform/platform_environment_service.dart';
import 'package:window_manager/window_manager.dart';

/// 全屏 / 系统栏的开关。
///
/// **屏幕方向不在这里**：方向由 `ScreenOrientationService` 统一管理（唯一状态源），
/// 这样按钮状态与真实生效策略不会脱节。
class DisplayModeService {
  DisplayModeService._();

  static Future<void> enterFullScreen() async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      await windowManager.setFullScreen(true);
      return;
    }
    // 安卓端进入全屏：隐藏系统状态栏与导航栏（沉浸式），避免遮挡应用内顶栏。
    // 分屏/多窗口模式下不强行隐藏，交给系统管理。
    if (Platform.isAndroid) {
      bool inMultiWindow = false;
      try {
        inMultiWindow = await PlatformEnvironmentService.isInMultiWindowMode();
      } catch (e, s) {
        // 多窗口检测失败时按普通全屏处理，不影响隐藏系统栏。
        WywLogger().w(
          '${LogTag.platform} 检查 Android 多窗口模式失败',
          error: e,
          stackTrace: s,
        );
      }
      if (!inMultiWindow) {
        // 用原生 WindowInsetsController 隐藏系统栏，比 SystemChrome 更可靠。
        await PlatformEnvironmentService.enterAndroidFullscreen();
      }
      return;
    }
    // iOS 端启用沉浸式
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  static Future<void> exitFullScreen() async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      await windowManager.setFullScreen(false);
      return;
    }
    // 安卓端退出播放页时恢复系统状态栏与导航栏
    if (Platform.isAndroid) {
      await PlatformEnvironmentService.exitAndroidFullscreen();
      return;
    }
    try {
      if (Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.platform} 退出全屏失败',
        error: e,
        stackTrace: s,
      );
    }
  }
}
