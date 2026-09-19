import 'dart:async';
import 'package:webview_windows/webview_windows.dart';
import 'package:wyw/webview/video/video_webview_controller.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

class VideoWebviewWindowsImpl
    extends VideoWebviewController<WebviewController> {
  final List<StreamSubscription> subscriptions = [];

  HeadlessWebview? headlessWebview;

  @override
  Future<void> init() async {
    headlessWebview ??= HeadlessWebview();
    await headlessWebview!.run();
    await headlessWebview!.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    initEventController.add(true);
  }

  @override
  Future<void> loadUrl(String url, {int offset = 0}) async {
    await unloadPage();
    count = 0;
    this.offset = offset;
    isIframeLoaded = false;
    isVideoSourceLoaded = false;
    videoLoadingEventController.add(true);
    subscriptions.add(headlessWebview!.onM3USourceLoaded.listen((data) {
      if (headlessWebview == null) return;
      String url = data['url'] ?? '';
      if (url.isEmpty) {
        return;
      }
      unloadPage();
      isIframeLoaded = true;
      isVideoSourceLoaded = true;
      videoLoadingEventController.add(false);
      logEventController.add('Loading m3u8 source: $url');
      videoParserEventController.add((url, offset));
    }));
    subscriptions.add(headlessWebview!.onVideoSourceLoaded.listen((data) {
      if (headlessWebview == null) return;
      String url = data['url'] ?? '';
      if (url.isEmpty) {
        return;
      }
      unloadPage();
      isIframeLoaded = true;
      isVideoSourceLoaded = true;
      videoLoadingEventController.add(false);
      logEventController.add('Loading video source: $url');
      videoParserEventController.add((url, offset));
    }));
    await headlessWebview!.loadUrl(url);
  }

  @override
  Future<void> unloadPage() async {
    for (final s in subscriptions) {
      try {
        s.cancel();
      } catch (_) {
        // 静默可接受：清理路径中取消订阅失败属常态（订阅可能已被取消），无需处理
      }
    }
    subscriptions.clear();
    await redirect2Blank();
  }

  @override
  Future<void> dispose() async {
    for (final s in subscriptions) {
      try {
        s.cancel();
      } catch (_) {
        // 静默可接受：清理路径中取消订阅失败属常态（订阅可能已被取消），无需处理
      }
    }
    subscriptions.clear();
    await headlessWebview?.dispose();
    headlessWebview = null;
    disposeEventControllers();
  }

  // The webview_windows package does not have a method to unload the current page.
  // The loadUrl method opens a new tab, which can lead to memory leaks.
  // Directly disposing of the webview controller would require reinitialization when switching episodes, which is costly.
  // Therefore, this method is used to redirect to a blank page instead.
  Future<void> redirect2Blank() async {
    if (headlessWebview == null) return;
    try {
      await headlessWebview!.executeScript('''
        window.location.href = 'about:blank';
      ''');
    } catch (e) {
      WywLogger().d('${LogTag.webview} 跳转 about:blank 失败（WebView 可能已释放，已忽略）',
          error: e);
    }
  }
}
