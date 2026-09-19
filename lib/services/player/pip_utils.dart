import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wyw/utils/device.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';

class PipUtils {
  static bool androidPIPInited = false;

  // 比例约分
  static Size getPIPAspectSize({required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      return const Size(16, 9);
    }
    final int divisor = width.gcd(height);
    return Size(width / divisor, height / divisor);
  }

  static Future<bool> isAndroidPIPSupported() async {
    if (!Platform.isAndroid) {
      return false;
    }
    const pipChannel = MethodChannel('com.yi.wyw/pip');
    try {
      final bool? supported =
          await pipChannel.invokeMethod('isPictureInPictureSupported');
      return supported ?? false;
    } on PlatformException catch (e, s) {
      WywLogger()
          .e('${LogTag.player} 检查 Android PIP 支持失败', error: e, stackTrace: s);
      return false;
    }
  }

  static Future<bool> enterAndroidPIPWindow(
      {int width = 16, int height = 9}) async {
    if (!Platform.isAndroid) {
      return false;
    }
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    const pipChannel = MethodChannel('com.yi.wyw/pip');
    try {
      final bool? entered =
          await pipChannel.invokeMethod('enterPictureInPictureMode', {
        'width': aspectSize.width.toInt(),
        'height': aspectSize.height.toInt(),
      });
      return entered ?? false;
    } on PlatformException catch (e, s) {
      WywLogger().e(
          '${LogTag.player} 进入 Android PIP 模式失败 width=$width height=$height',
          error: e,
          stackTrace: s);
      return false;
    }
  }

  static Future<void> updateAndroidPIPActions({
    required bool playing,
    int width = 16,
    int height = 9,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    const pipChannel = MethodChannel('com.yi.wyw/pip');
    try {
      await pipChannel.invokeMethod('updatePictureInPictureActions', {
        'playing': playing,
        'width': aspectSize.width.toInt(),
        'height': aspectSize.height.toInt(),
      });
    } on PlatformException catch (e, s) {
      WywLogger().e('${LogTag.player} 更新 Android PIP 操作失败 playing=$playing',
          error: e, stackTrace: s);
    }
  }

  static Future<void> setAndroidAutoEnterPIPEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      return;
    }
    const pipChannel = MethodChannel('com.yi.wyw/pip');
    try {
      await pipChannel.invokeMethod('setAndroidAutoEnterPIPEnabled', {
        'enabled': enabled,
      });
    } on PlatformException catch (e, s) {
      WywLogger().e('${LogTag.player} 设置 Android 自动进入 PIP 失败 enabled=$enabled',
          error: e, stackTrace: s);
    }
  }

  static Future<void> setAndroidPIPInPlayerPage(bool inPlayerPage) async {
    if (!Platform.isAndroid) {
      return;
    }
    const pipChannel = MethodChannel('com.yi.wyw/pip');
    try {
      await pipChannel.invokeMethod('setAndroidPIPInPlayerPage', {
        'inPlayerPage': inPlayerPage,
      });
    } on PlatformException catch (e, s) {
      WywLogger().e(
          '${LogTag.player} 设置 Android PIP 页面状态失败 inPlayerPage=$inPlayerPage',
          error: e,
          stackTrace: s);
    }
  }

  // 进入桌面设备小窗模式，并用播放源比例固定窗口宽高比
  static Future<void> enterDesktopPIPWindow(
      {int width = 16, int height = 9}) async {
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    final double aspectRatio = aspectSize.width / aspectSize.height;
    const double pipWidth = 480;
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setAspectRatio(aspectRatio);
    await windowManager.setSize(Size(pipWidth, pipWidth / aspectRatio));
  }

  // 退出桌面设备小窗模式
  static Future<void> exitDesktopPIPWindow() async {
    final lowResolution = await isLowResolution();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setAspectRatio(0);
    await windowManager
        .setSize(lowResolution ? const Size(800, 600) : const Size(1280, 860));
    await windowManager.center();
  }

  /// 切换画中画：桌面端在独立小窗/正常窗口间切换，Android 端尝试进入系统 PIP。
  ///
  /// 桌面端返回切换后的 PIP 状态；Android 端返回是否成功进入系统 PIP。
  /// 调用方仅在桌面端用返回值维护 [VideoPageController.isPip]（Android 端
  /// 的 PIP 状态由系统回调维护，不应由本方法写入）。
  static Future<bool> togglePip({
    required bool isPip,
    required bool isPlaying,
    required int width,
    required int height,
  }) async {
    if (isDesktop()) {
      if (isPip) {
        await exitDesktopPIPWindow();
      } else {
        // 进入画中画时使用播放源比例，避免窗口比例与视频比例不一致产生黑边
        await enterDesktopPIPWindow(width: width, height: height);
      }
      return !isPip;
    }
    if (!Platform.isAndroid) return false;
    final bool supported = await isAndroidPIPSupported();
    if (!supported) {
      WywDialog.showToast(message: '当前设备不支持画中画');
      return false;
    }
    await updateAndroidPIPActions(
      playing: isPlaying,
      width: width,
      height: height,
    );
    final bool entered = await enterAndroidPIPWindow(
      width: width,
      height: height,
    );
    if (!entered) {
      WywDialog.showToast(message: '进入画中画失败');
    }
    return entered;
  }

  static void initPipHandler({
    required Future<void> Function(String action) onAction,
  }) {
    const MethodChannel pipChannel = MethodChannel('com.yi.wyw/pip');
    if (androidPIPInited) return;
    androidPIPInited = true;

    pipChannel.setMethodCallHandler((call) async {
      if (!Platform.isAndroid || call.method != 'onAction') {
        return;
      }

      final args = call.arguments;
      final String? action = (args is Map) ? args['action'] as String? : null;

      if (action != null) {
        await onAction(action);
      }
    });
  }

  static void disposePipHandler() {
    const MethodChannel pipChannel = MethodChannel('com.yi.wyw/pip');
    pipChannel.setMethodCallHandler(null);
    androidPIPInited = false;
  }
}
