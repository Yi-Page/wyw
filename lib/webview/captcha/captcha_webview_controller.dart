import 'dart:io';
import 'dart:async';

import 'package:wyw/webview/captcha/impl/captcha_webview_inappwebview_impl.dart';
import 'package:wyw/webview/captcha/impl/captcha_webview_windows_impl.dart';

/// WebView 取 HTML 的结果：渲染后的 HTML + 最终 URL（跟随 JS 跳转/302 后的落地地址）。
class WebviewHtmlResult {
  final String html;
  final String finalUrl;

  const WebviewHtmlResult({required this.html, this.finalUrl = ''});

  bool get isEmpty => html.isEmpty;
}

/// 把 Dart 字符串转成 JS 字符串字面量（拼注入脚本用，防引号/换行破坏）。
String jsStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', '')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
  return "'$escaped'";
}

/// 由 waitFor 配置生成一个「布尔 JS 表达式」，供页面脚本每次轮询求值：
///   - `{type: 'selector', value: '.a > img'}` → document.querySelector 非空
///   - `{type: 'text', value: 'xxx'}`          → body.innerText 包含指定文本
///   - `{type: 'js', value: '<JS 布尔表达式>'}` → 原样作为表达式求值
///   - null / 空                               → 默认等页面出现有意义内容（outerHTML > 100）
String buildWaitCondition(Map<String, dynamic>? waitFor) {
  if (waitFor == null || waitFor.isEmpty) {
    return 'document.documentElement != null && '
        'document.documentElement.outerHTML.length > 100';
  }
  final type = (waitFor['type'] ?? 'js').toString();
  final value = waitFor['value']?.toString() ?? '';
  switch (type) {
    case 'selector':
      return 'document.querySelector(${jsStringLiteral(value)}) != null';
    case 'text':
      return 'document.body != null && document.body.innerText && '
          'document.body.innerText.indexOf(${jsStringLiteral(value)}) >= 0';
    case 'js':
      return value.isEmpty ? 'true' : value;
    default:
      return 'document.documentElement != null && '
          'document.documentElement.outerHTML.length > 100';
  }
}

/// 把插件传来的 waitFor 归一化为 [buildWaitCondition] 可用的 Map。
/// 支持 Map `{type, value}` 或字符串简写 `'selector:.x'` / `'text:xxx'` / `'js:expr'`。
Map<String, dynamic>? normalizeWaitFor(dynamic waitFor) {
  if (waitFor is Map) {
    return Map<String, dynamic>.from(waitFor);
  }
  if (waitFor is String && waitFor.trim().isNotEmpty) {
    final idx = waitFor.indexOf(':');
    if (idx > 0) {
      final type = waitFor.substring(0, idx).trim();
      final value = waitFor.substring(idx + 1);
      if (value.isNotEmpty) return {'type': type, 'value': value};
    }
  }
  return null;
}

abstract class CaptchaWebviewController {
  final StreamController<bool> initEventController =
      StreamController<bool>.broadcast();
  final StreamController<String> logEventController =
      StreamController<String>.broadcast();

  /// WebView 初始化完成事件
  Stream<bool> get onInitialized => initEventController.stream;

  /// 调试日志
  Stream<String> get onLog => logEventController.stream;

  /// 初始化 WebView
  Future<void> init();

  /// 加载指定 URL，等待 [waitFor] 条件满足后返回渲染后的 HTML 与最终 URL。
  ///
  /// [url] 要加载的页面地址（一般为搜索 URL）
  /// [overTime] 获取 HTML 的总超时秒数（默认 50）
  /// [waitFor] 等待条件（见 [buildWaitCondition]）。默认等页面出现有意义内容。
  Future<WebviewHtmlResult> parseHtml(
    String url, {
    int overTime = 50,
    Map<String, dynamic>? waitFor,
  });

  /// 获取当前页面的 Cookie 字符串（"key1=val1; key2=val2"）
  ///
  /// [pageUrl] 当前加载的页面地址，部分平台用于精确过滤 Cookie
  Future<String> getCookieString(String pageUrl);

  /// 卸载当前页面（跳转到 about:blank）
  Future<void> unloadPage();

  /// 释放 WebView 资源
  void dispose();
}

class CaptchaWebviewControllerFactory {
  static CaptchaWebviewController getController() {
    if (Platform.isWindows) {
      return CaptchaWebviewWindowsImpl();
    }
    // Android, iOS, macOS
    return CaptchaWebviewInAppWebviewImpl();
  }
}
