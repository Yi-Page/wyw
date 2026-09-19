import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:wyw/app_module.dart';
import 'package:wyw/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wyw/services/network/image_cache_manager.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wyw/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wyw/utils/device.dart';
import 'package:wyw/services/platform/webview_feature_service.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/navigation.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 主 isolate 未捕获错误的兜底监听端口。
///
/// 必须持有顶层引用防止 RawReceivePort 被 GC 回收（见日志规范 docs/logging.md）。
final RawReceivePort _isolateErrorListener = RawReceivePort((Object? pair) {
  if (pair is List && pair.length == 2) {
    WywLogger().f(
      '${LogTag.app} isolate 未捕获错误',
      error: pair[0]?.toString(),
      stackTrace:
          pair[1] == null ? null : StackTrace.fromString(pair[1] as String),
    );
  }
});

/// 安装全局错误兜底：让任何逃逸到框架层的错误都落进日志文件（f 级）。
///
/// 覆盖三类：
/// 1. [FlutterError.onError] — widget 构建/布局/绘制异常（链回原 handler 保留
///    开发期红屏与控制台输出）；
/// 2. [PlatformDispatcher.onError] — 未捕获的 Dart 异步异常（记录后返回 true
///    继续运行，避免单次异常直接杀死应用；日志页可查现场）；
/// 3. [Isolate.addErrorListener] — 上述两者覆盖不到的 isolate 层未捕获错误。
void _installGlobalErrorHandlers() {
  final originalFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    WywLogger().f(
      '${LogTag.app} Flutter 框架异常 library=${details.library ?? 'unknown'}',
      error: details.exception,
      stackTrace: details.stack,
    );
    originalFlutterError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    WywLogger().f('${LogTag.app} 未捕获异常', error: error, stackTrace: stackTrace);
    return true;
  };

  Isolate.current.addErrorListener(_isolateErrorListener.sendPort);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();

  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }

  if (Platform.isAndroid) {
    await WebViewFeatureService.initialize();
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    // WywLogger 仅懒加载单例，不依赖存储通道；此处即使文件落盘失败也会
    // 在 output 里 print 兜底，日志页/控制台至少一处可见。
    WywLogger().f('${LogTag.app} 存储初始化失败', error: e);

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // window_manager controls desktop visibility to avoid startup flicker.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')
        ],
        locale: const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
        builder: (context, child) {
          return const StorageErrorPage();
        }));
    return;
  }
  bool showWindowButton =
      await GStorage.getSetting(SettingsKeys.showWindowButton);
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    // 初始窗口大小：优先使用「界面设置」中的预设；'auto' 或未知值时
    // 由应用按屏幕分辨率决定（低分辨率屏用较小窗口，其余用默认大窗口）。
    final initialWindowSize = GStorage.getSetting<String>(
      SettingsKeys.initialWindowSize,
    );
    final presetSize = initialWindowSizeSizes[initialWindowSize];
    final Size windowSize = presetSize ??
        (lowResolution ? const Size(840, 600) : const Size(1440, 900));
    WindowOptions windowOptions = WindowOptions(
      size: windowSize,
      center: true,
      skipTaskbar: false,
      // macOS always hide title bar regardless of showWindowButton setting
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      title: 'Wyw',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // window_manager controls desktop visibility to avoid startup flicker.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  // 统一图片缓存管理器（无代理），供 CachedNetworkImageProvider 使用。
  CachedNetworkImageProvider.defaultCacheManager =
      AppImageCacheManager.instance;
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [WywDialog.observer],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );
}
