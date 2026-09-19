import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Orientation;
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/platform/platform_environment_service.dart';
import 'package:wyw/utils/device.dart';
import 'package:window_manager/window_manager.dart';

class DisplayModeService {
  DisplayModeService._();

  static Future<void> enterFullScreen({bool lockOrientation = true}) async {
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
      if (!lockOrientation) {
        return;
      }
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      return;
    }
    // iOS 端启用沉浸式
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!lockOrientation) {
      return;
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> exitFullScreen({bool lockOrientation = true}) async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      await windowManager.setFullScreen(false);
    }
    // 安卓端退出播放页时恢复系统状态栏与导航栏
    if (Platform.isAndroid) {
      await PlatformEnvironmentService.exitAndroidFullscreen();
      return;
    }
    try {
      if (Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        if (isCompact() && lockOrientation) {
          await verticalScreen();
        }
      }
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.platform} 退出全屏失败',
        error: e,
        stackTrace: s,
      );
    }
  }

  static Future<void> verticalScreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  /// 锁定屏幕方向为当前方向：横屏则锁定横屏，竖屏则锁定竖屏。
  static Future<void> lockOrientation(Orientation orientation) async {
    if (orientation == Orientation.landscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  static Future<void> unlockScreenRotation() async {
    await SystemChrome.setPreferredOrientations([]);
  }
}
