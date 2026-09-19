import 'dart:async';
import 'dart:convert';

import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/webview/captcha/captcha_webview_controller.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:wyw/utils/http_headers.dart';

class CaptchaWebviewInAppWebviewImpl extends CaptchaWebviewController {
  PlatformHeadlessInAppWebView? _headlessWebView;
  PlatformInAppWebViewController? _webviewController;

  Completer<WebviewHtmlResult>? _htmlCompleter;

  /// 条件感知轮询定时器
  Timer? _htmlFetchTimer;

  /// 本次 parseHtml 的等待条件
  Map<String, dynamic>? _pendingWaitFor;

  @override
  Future<void> init() async {
    _headlessWebView ??= PlatformHeadlessInAppWebView(
      PlatformHeadlessInAppWebViewCreationParams(
        initialSettings: InAppWebViewSettings(
          userAgent: getRandomUA(),
          mediaPlaybackRequiresUserGesture: true,
          cacheEnabled: true,
          blockNetworkImage: false,
          loadsImagesAutomatically: true,
          upgradeKnownHostsToHTTPS: false,
          safeBrowsingEnabled: false,
        ),
        onWebViewCreated: (controller) {
          logEventController.add('[Captcha WebView] Created');
          _webviewController = controller;
          initEventController.add(true);
        },
        onLoadStart: (controller, url) {
          logEventController.add('[Captcha WebView] Load start: $url');
        },
        // 注意：不依赖 onDomContentLoaded（当前平台接口未暴露），
        // 由 parseHtml 中的条件感知轮询尽早取 HTML
        onLoadStop: (controller, url) async {
          logEventController.add('[Captcha WebView] Load stop: $url');
          await _tryFetchHtml();
        },
        onReceivedError: (controller, request, error) {
          logEventController.add(
            '[Captcha WebView] Error: ${error.description}',
          );
        },
      ),
    );
    await _headlessWebView!.run();
  }

  /// 条件感知取 HTML：单次 evaluateJavascript 返回 `JSON.stringify({url, html})`，
  /// 等待条件满足才返回 HTML，否则返回空串（由轮询定时器继续）。
  Future<void> _tryFetchHtml() async {
    if (_htmlCompleter == null || _htmlCompleter!.isCompleted) {
      _htmlFetchTimer?.cancel();
      return;
    }
    try {
      final cond = buildWaitCondition(_pendingWaitFor);
      // 每次求值重新执行 IIFE（条件里可能含 document.querySelector 等实时查询）
      final js = 'JSON.stringify({url: location.href, html: (function(){'
          'try { return ($cond) ? document.documentElement.outerHTML : ""; }'
          'catch (e) { return ""; }})()})';
      final raw = await _webviewController?.evaluateJavascript(source: js);
      if (raw == null) return;
      final decoded = jsonDecode(raw.toString());
      final html = (decoded is Map && decoded['html'] is String)
          ? decoded['html'] as String
          : '';
      if (html.trim().isNotEmpty && !_htmlCompleter!.isCompleted) {
        logEventController.add('[Captcha WebView] 已获取页面 HTML（轮询）');
        _htmlCompleter!.complete(
          WebviewHtmlResult(
            html: html,
            finalUrl: (decoded is Map && decoded['url'] is String)
                ? decoded['url'] as String
                : '',
          ),
        );
        _htmlFetchTimer?.cancel();
      }
    } catch (_) {
      // 静默可接受：页面未就绪时 evaluate 失败属常态，由轮询定时器继续。
    }
  }

  @override
  Future<WebviewHtmlResult> parseHtml(
    String url, {
    int overTime = 50,
    Map<String, dynamic>? waitFor,
  }) async {
    try {
      _htmlFetchTimer?.cancel();
      _htmlCompleter = Completer<WebviewHtmlResult>();
      _pendingWaitFor = waitFor;

      // 先卸载旧页面（about:blank）：避免旧页面的 HTML 在目标页加载前被轮询拿到，
      // 提前完成本次请求（默认阈值 outerHTML > 100 可过滤 about:blank）
      await unloadPage();

      await _webviewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );

      // 条件感知轮询：不等 onLoadStop（重页面 load 很慢），尽早拿到 HTML；一旦拿到即取消
      _htmlFetchTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _tryFetchHtml(),
      );
      _tryFetchHtml();

      // 总超时（overTime 秒）
      Future.delayed(Duration(seconds: overTime), () {
        if (_htmlCompleter != null && !_htmlCompleter!.isCompleted) {
          _htmlCompleter!.completeError('获取 HTML 超时（${overTime}s）');
        }
      });
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.webview} 加载页面失败 url=$url', error: e, stackTrace: s);
      if (_htmlCompleter != null && !_htmlCompleter!.isCompleted) {
        _htmlCompleter!.completeError('加载页面失败: $e');
      }
    }

    return _htmlCompleter!.future;
  }

  @override
  Future<String> getCookieString(String pageUrl) async {
    try {
      final PlatformCookieManager cookieManager = PlatformCookieManager(
        PlatformCookieManagerCreationParams(),
      );
      final cookies = await cookieManager.getCookies(url: WebUri(pageUrl));
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (e, s) {
      WywLogger().e('${LogTag.webview} 读取 Cookie 失败 pageUrl=$pageUrl',
          error: e, stackTrace: s);
      return '';
    }
  }

  @override
  Future<void> unloadPage() async {
    try {
      await _webviewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    } catch (e) {
      WywLogger()
          .d('${LogTag.webview} unloadPage 跳转 about:blank 失败（已忽略）', error: e);
    }
  }

  @override
  void dispose() {
    try {
      PlatformCookieManager(
        const PlatformCookieManagerCreationParams(),
      ).deleteAllCookies();
    } catch (_) {
      // 静默可接受：dispose 阶段清理 Cookie 失败属常态，不影响销毁流程。
    }
    try {
      initEventController.close();
      logEventController.close();
      _htmlFetchTimer?.cancel();
    } catch (_) {
      // 静默可接受：dispose 阶段关闭 controller/取消定时器失败属常态，不影响销毁流程。
    }
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _webviewController = null;
  }
}
