import 'dart:io';
import 'dart:async';

import 'package:wyw/webview/video/impl/video_webview_android_impl.dart';
import 'package:wyw/webview/video/impl/video_webview_impl.dart';
import 'package:wyw/webview/video/impl/video_webview_windows_impl.dart';
import 'package:wyw/webview/video/impl/video_webview_linux_impl.dart';
import 'package:wyw/webview/video/impl/video_webview_apple_impl.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/platform/webview_feature_service.dart';

/// headless WebView 创建串行队列的尾部（链式串行化）。
Future<void> _webviewCreateTail = Future<void>.value();

/// 全局串行化 headless WebView 的创建 + run。
///
/// Android 上 flutter_inappwebview 的 headless WebView 并发创建会抛出
/// environment_creation_failed。播放/下载两侧的解析（ResolutionService、
/// 解析池）会各自初始化 WebView，因此把创建动作排队执行，避免并发创建竞态。
Future<T> serializeWebviewCreation<T>(Future<T> Function() action) {
  final result = _webviewCreateTail.then((_) => action());
  _webviewCreateTail =
      result.then<void>((_) {}, onError: (Object e, StackTrace s) {
    WywLogger().w('${LogTag.webview} 串行队列中 WebView 创建后台任务失败（不影响主流程）', error: e);
  });
  return result;
}

abstract class VideoWebviewController<T> {
  // WebView controller.
  T? webviewController;

  // Retry count
  int count = 0;
  // Last watched position
  int offset = 0;
  bool isIframeLoaded = false;
  bool isVideoSourceLoaded = false;

  /// WebView initialization method.
  Future<void> init();

  final StreamController<bool> initEventController =
      StreamController<bool>.broadcast();

  // Stream to notify when the webview is initialized
  Stream<bool> get onInitialized => initEventController.stream;

  final StreamController<String> logEventController =
      StreamController<String>.broadcast();

  // Stream to subscribe to webview logs
  Stream<String> get onLog => logEventController.stream;

  final StreamController<bool> videoLoadingEventController =
      StreamController<bool>.broadcast();

  // Stream to notify when the video source is loaded
  Stream<bool> get onVideoLoading => videoLoadingEventController.stream;

  // Stream to notify video source URL when the video source is loaded
  // The first parameter is the video source URL and the second parameter is the video offset (start position)
  final StreamController<(String, int)> videoParserEventController =
      StreamController<(String, int)>.broadcast();

  Stream<(String, int)> get onVideoURLParser =>
      videoParserEventController.stream;

  void disposeEventControllers() {
    if (!initEventController.isClosed) {
      initEventController.close();
    }
    if (!logEventController.isClosed) {
      logEventController.close();
    }
    if (!videoLoadingEventController.isClosed) {
      videoLoadingEventController.close();
    }
    if (!videoParserEventController.isClosed) {
      videoParserEventController.close();
    }
  }

  /// WebView load URL method.
  Future<void> loadUrl(String url, {int offset = 0});

  /// WebView unload page method.
  Future<void> unloadPage();

  /// WebView dispose method.
  Future<void> dispose();
}

class VideoWebviewControllerFactory {
  static VideoWebviewController getController() {
    if (Platform.isWindows) {
      return VideoWebviewWindowsImpl();
    }
    if (Platform.isLinux) {
      return VideoWebviewLinuxImpl();
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return VideoWebviewAppleImpl();
    }
    if (Platform.isAndroid &&
        WebViewFeatureService.isDocumentStartScriptSupported) {
      return VideoWebviewAndroidImpl();
    }
    return VideoWebviewImpl();
  }
}
