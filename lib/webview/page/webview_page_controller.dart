import 'dart:io';
import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'impl/webview_page_inappwebview_impl.dart';
import 'impl/webview_page_windows_impl.dart';

abstract class WebviewPageController {
  final StreamController<bool> initEventController =
      StreamController<bool>.broadcast();

  /// WebView 初始化完成事件
  Stream<bool> get onInitialized => initEventController.stream;

  VoidCallback? onStateChanged;

  /// 初始化 WebView
  Future<void> init();

  /// 加载指定网页，并注入监听验证码图片的 JS 脚本（类型1：图片验证码）
  ///
  /// [url] 要加载的页面地址（一般为搜索 URL）
  Widget buildWebViewWidget(BuildContext context, String initialUrl);

  Widget buildUrlBar();

  List<Widget>? buildAppbarActions();

  /// 获取当前页面的 Cookie 字符串（"key1=val1; key2=val2"）
  ///
  /// [pageUrl] 当前加载的页面地址，部分平台用于精确过滤 Cookie
  Future<String> getCookieString(String pageUrl);

  /// 卸载当前页面（跳转到 about:blank）
  Future<void> unloadPage();

  /// 释放 WebView 资源
  void dispose();
}

class WebviewPageControllerFactory {
  static WebviewPageController getController() {
    if (Platform.isWindows) {
      return WebviewPageWindowsImpl();
    }
    // Android, iOS, macOS
    return WebviewPageInAppWebviewImpl();
  }
}
