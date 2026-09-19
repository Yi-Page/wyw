import 'dart:async';
import 'dart:convert';

import 'package:webview_windows/webview_windows.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/webview/captcha/captcha_webview_controller.dart';

class CaptchaWebviewWindowsImpl extends CaptchaWebviewController {
  HeadlessWebview? _headlessWebview;
  final List<StreamSubscription> _subscriptions = [];
  String _currentPageUrl = '';

  /// 总超时定时器（到点仍无结果则报错）
  Timer? _captchaVerifyTimer;

  /// 注入 watcher 的重试定时器：导航过程中 executeScript 可能失败/页面重载，需反复尝试注入
  Timer? _injectRetryTimer;

  Completer<WebviewHtmlResult>? _htmlCompleter;

  /// 本次 parseHtml 的等待条件（注入脚本用）
  Map<String, dynamic>? _pendingWaitFor;

  @override
  Future<void> init() async {
    _headlessWebview ??= HeadlessWebview();
    await _headlessWebview!.run();

    await _headlessWebview!.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    _subscriptions.add(_headlessWebview!.webMessage.listen(_onWebMessage));
    _subscriptions.add(
      _headlessWebview!.loadingState.listen((state) async {
        if (state == LoadingState.navigationCompleted) {
          logEventController.add(
            '[Captcha WebView] Navigation completed: $_currentPageUrl',
          );
          // 导航完成后立即尝试注入 watcher（拿不到 HTML 的兜底由重试定时器负责）
          await _injectWatcher();
        }
      }),
    );
    // 跟踪当前 URL（页面自报 location.href 的兜底 / 日志用）
    _subscriptions.add(
      _headlessWebview!.url.listen((u) {
        if (u.isNotEmpty) _currentPageUrl = u;
      }),
    );
    initEventController.add(true);
  }

  void _onWebMessage(dynamic message) {
    final msg = message.toString();
    logEventController.add('[Captcha WebView] WM: $msg');
    if (msg.startsWith('WywHtml:')) {
      final payload = msg.substring('WywHtml:'.length);
      final result = _parsePayload(payload);
      logEventController.add('[Captcha WebView JS] 已获取 HTML');
      _completeResult(result);
    } else if (msg.startsWith('ParsedHtml:')) {
      // 旧协议兜底（兼容历史注入脚本）
      final html = msg.substring('ParsedHtml:'.length);
      _completeResult(WebviewHtmlResult(html: html, finalUrl: _currentPageUrl));
    }
  }

  /// 解析页面 postMessage 回传的负载：`{url, html}` JSON，失败则整段当 HTML。
  WebviewHtmlResult _parsePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return WebviewHtmlResult(
          html: (decoded['html'] as String?) ?? '',
          finalUrl: (decoded['url'] as String?) ?? _currentPageUrl,
        );
      }
    } catch (_) {
      // 静默可接受：负载非 JSON（旧格式裸 HTML）属预期分支，整段当 HTML 处理。
    }
    return WebviewHtmlResult(html: payload, finalUrl: _currentPageUrl);
  }

  void _completeResult(WebviewHtmlResult result) {
    final c = _htmlCompleter;
    if (c != null && !c.isCompleted) {
      c.complete(result);
      _injectRetryTimer?.cancel();
    }
  }

  /// 注入持久 watcher：页面内常驻轮询等待条件，满足后把 `{url, html}` postMessage 回传。
  ///
  /// 只在首次注入（页面重载后 `__wywWatcherInstalled` 会重置，可重新注入）。
  /// 用 `setTimeout` 而非 `requestAnimationFrame`——headless 不可见时 rAF 可能不触发。
  Future<void> _injectWatcher() async {
    final webview = _headlessWebview;
    if (webview == null ||
        _htmlCompleter == null ||
        _htmlCompleter!.isCompleted) {
      return;
    }
    final cond = buildWaitCondition(_pendingWaitFor);
    final script = '''
if (!window.__wywWatcherInstalled) {
  window.__wywWatcherInstalled = true;
  (function () {
    var run = function () {
      try {
        var ok = (function () { return $cond; })();
        if (ok) {
          var html = document.documentElement ? document.documentElement.outerHTML : '';
          if (html.length > 0) {
            try {
              chrome.webview.postMessage('WywHtml:' + JSON.stringify({url: location.href, html: html}));
            } catch (e) {}
            return;
          }
        }
      } catch (e) {}
      setTimeout(run, 150);
    };
    run();
  })();
}
''';
    try {
      await webview.executeScript(script);
    } catch (_) {
      // 静默可接受：导航中页面 JS 上下文未就绪属常态，由重试定时器兜底。
    }
  }

  @override
  Future<WebviewHtmlResult> parseHtml(
    String url, {
    int overTime = 50,
    Map<String, dynamic>? waitFor,
  }) async {
    _htmlCompleter = Completer<WebviewHtmlResult>();
    _pendingWaitFor = waitFor;
    _injectRetryTimer?.cancel();
    try {
      // 先卸载旧页面（about:blank）：销毁上一次请求残留的 watcher/文档，
      // 避免旧页面 HTML 提前满足条件完成本次请求
      await unloadPage();
      await loadPage(url);
      await _injectWatcher();
      // 注入重试兜底：导航/重载过程中 executeScript 会失败，每 300ms 重试一次
      _injectRetryTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _injectWatcher(),
      );
      _captchaVerifyTimer?.cancel();
      _captchaVerifyTimer = Timer(Duration(seconds: overTime), () {
        if (_htmlCompleter != null && !_htmlCompleter!.isCompleted) {
          _htmlCompleter!.completeError('获取 HTML 超时（${overTime}s）');
        }
      });
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.webview} 注入脚本失败 url=$url', error: e, stackTrace: s);
      if (_htmlCompleter != null && !_htmlCompleter!.isCompleted) {
        _htmlCompleter!.completeError('执行脚本失败：$e');
      }
    }
    return _htmlCompleter!.future;
  }

  Future<void> loadPage(String url) async {
    _currentPageUrl = url;
    await _headlessWebview?.loadUrl(url);
  }

  @override
  Future<String> getCookieString(String pageUrl) async {
    try {
      return await _headlessWebview?.getCookies(pageUrl) ?? '';
    } catch (e, s) {
      WywLogger().e('${LogTag.webview} 读取 Cookie 失败 pageUrl=$pageUrl',
          error: e, stackTrace: s);
      return '';
    }
  }

  @override
  Future<void> unloadPage() async {
    try {
      await _headlessWebview?.executeScript(
        "window.location.href = 'about:blank';",
      );
    } catch (e) {
      WywLogger()
          .d('${LogTag.webview} unloadPage 跳转 about:blank 失败（已忽略）', error: e);
    }
  }

  @override
  void dispose() {
    _currentPageUrl = '';
    _captchaVerifyTimer?.cancel();
    _injectRetryTimer?.cancel();
    for (final s in _subscriptions) {
      try {
        s.cancel();
      } catch (_) {
        // 静默可接受：dispose 阶段取消订阅失败属常态，不影响销毁流程。
      }
    }
    _subscriptions.clear();
    try {
      initEventController.close();
      logEventController.close();
    } catch (_) {
      // 静默可接受：dispose 阶段关闭 controller 失败属常态，不影响销毁流程。
    }
    _headlessWebview?.dispose();
    _headlessWebview = null;
  }
}
