import 'dart:async';
import 'dart:convert';

import 'package:webview_windows/webview_windows.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/webview/captcha/captcha_webview_controller.dart';

/// Windows 端验证码 WebView（`webview_windows` 的 `HeadlessWebview`）。
///
/// ## 页面 → Dart 的消息协议（`chrome.webview.postMessage`，前置前缀 + 文本负载）
///
/// | 前缀             | 负载                        | 映射到                                                     |
/// | ---------------- | --------------------------- | ---------------------------------------------------------- |
/// | `captchaImage:`  | `data:image/png;base64,...` | [CaptchaWebviewController.onCaptchaImageFound]              |
/// | `captchaGone:`   | 原因文本（可为空）          | [CaptchaWebviewController.onCaptchaDisappeared]              |
/// | `buttonClicked:` | 提示文本                    | 标记「已自动点击」，之后若导航 ⇒ onCaptchaDisappeared        |
/// | `captchaLog:`    | 日志文本                    | [CaptchaWebviewController.onLog]                            |
/// | `captchaStatus:` | `present` / `absent`        | 仅日志（`onLog`），不直接触发事件                            |
/// | `WywHtml:`       | `{url, html}` JSON          | 一次性 [CaptchaWebviewController.parseHtml] 的返回值         |
/// | `ParsedHtml:`    | 裸 HTML                     | 旧协议兜底（兼容历史注入脚本）                               |
///
/// 页面侧 watcher 由 [buildInteractionWatcherScript] 生成（`window.__wywCaptcha` 协议）。
class CaptchaWebviewWindowsImpl extends CaptchaWebviewController {
  HeadlessWebview? _headlessWebview;
  final List<StreamSubscription> _subscriptions = [];
  String _currentPageUrl = '';

  /// 总超时定时器（到点仍无结果则报错）
  Timer? _captchaVerifyTimer;

  /// 注入 watcher 的重试定时器：导航过程中 executeScript 可能失败/页面重载，需反复尝试注入
  Timer? _injectRetryTimer;

  /// 交互 watcher 的重试定时器（有次数上限，装好即由次数/事件自然收敛）
  Timer? _interactionInjectTimer;
  int _interactionInjectAttempts = 0;

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
          // 交互会话：重新注入交互 watcher + 判定「导航后验证码是否已消失」
          await _onInteractionNavigationCompleted();
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
    // 验证码图是几十~几百 KB 的 dataURL，日志里只留长度，避免刷屏/污染日志
    if (msg.startsWith('captchaImage:')) {
      final dataUrl = msg.substring('captchaImage:'.length);
      logEventController.add(
        '[Captcha WebView] WM: captchaImage(${dataUrl.length} chars)',
      );
      emitCaptchaImage(dataUrl);
      return;
    }
    logEventController.add('[Captcha WebView] WM: $msg');
    if (msg.startsWith('captchaGone:')) {
      emitCaptchaDisappeared(reason: '页面 watcher 上报验证码元素消失');
    } else if (msg.startsWith('buttonClicked:')) {
      buttonWasClicked = true;
      logEventController.add(
        '[Captcha WebView] 按钮已自动点击，等待页面跳转判定验证通过',
      );
    } else if (msg.startsWith('captchaStatus:')) {
      // 页面自报状态：只做日志，真正判定由导航后的 Dart 侧复查负责（避免误报）
      logEventController.add(
        '[Captcha WebView JS] 页面验证码状态: '
        '${msg.substring('captchaStatus:'.length)}',
      );
    } else if (msg.startsWith('captchaLog:')) {
      logEventController
          .add('[Captcha WebView JS] ${msg.substring('captchaLog:'.length)}');
    } else if (msg.startsWith('WywHtml:')) {
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

  // ---------------------------------------------------------------------------
  // 交互会话（留页式：取验证码图 → 用户输入 → 回填点击 → 取 HTML/UA/Cookie）
  // ---------------------------------------------------------------------------

  @override
  Future<void> loadPageForInteraction(
    String url, {
    required WebviewLoadMode mode,
    String captchaXpath = '',
    String inputXpath = '',
    String buttonXpath = '',
    String script = '',
  }) async {
    beginInteractionSession(
      mode: mode,
      captchaXpath: captchaXpath,
      inputXpath: inputXpath,
      buttonXpath: buttonXpath,
      script: script,
    );
    _currentPageUrl = url;
    _stopInteractionInjectRetry();
    try {
      // 注意：与 parseHtml 不同，这里不做 unload 前置——页面要留住给用户看验证码
      await _headlessWebview?.loadUrl(url);
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.webview} 交互会话加载页面失败 url=$url', error: e, stackTrace: s);
      if (!logEventController.isClosed) {
        logEventController.add('[Captcha WebView] 交互会话加载页面失败: $e');
      }
    }
    // 立即注入一次（有的站点导航事件晚到/不触发），再由有上限的重试兜底
    await _injectInteractionWatcher();
    _startInteractionInjectRetry();
  }

  /// 重新注入交互 watcher；`interactionToken` 保证同一轮会话幂等。
  Future<void> _injectInteractionWatcher() async {
    final webview = _headlessWebview;
    final mode = interactionMode;
    if (webview == null || mode == null) return;
    final js = buildInteractionWatcherScript(
      token: interactionToken,
      mode: mode,
      captchaXpath: interactionCaptchaXpath,
      inputXpath: interactionInputXpath,
      buttonXpath: interactionButtonXpath,
      script: interactionScript,
      post: _postToDart,
    );
    try {
      await webview.executeScript(js);
    } catch (_) {
      // 静默可接受：导航中页面 JS 上下文未就绪属常态，由重试定时器兜底。
    }
  }

  /// 有上限的注入重试（500ms × 20 次 ≈ 10s），避免无限轮询。
  void _startInteractionInjectRetry() {
    _interactionInjectAttempts = 0;
    _interactionInjectTimer?.cancel();
    _interactionInjectTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (t) {
        if (!hasActiveInteraction ||
            _headlessWebview == null ||
            _interactionInjectAttempts >= 20) {
          t.cancel();
          _interactionInjectTimer = null;
          return;
        }
        _interactionInjectAttempts++;
        _injectInteractionWatcher();
      },
    );
  }

  void _stopInteractionInjectRetry() {
    _interactionInjectAttempts = 0;
    _interactionInjectTimer?.cancel();
    _interactionInjectTimer = null;
  }

  Future<void> _onInteractionNavigationCompleted() async {
    if (!hasActiveInteraction) return;
    await _injectInteractionWatcher();
    await _checkInteractionDoneAfterNavigation();
  }

  /// 导航后兜底判定：验证码图已不在 / 自动点击过按钮后发生跳转 ⇒ 验证通过。
  Future<void> _checkInteractionDoneAfterNavigation() async {
    if (!hasActiveInteraction || captchaGoneEmitted) return;
    if (buttonWasClicked) {
      buttonWasClicked = false;
      emitCaptchaDisappeared(reason: '按钮已点击且页面发生跳转');
      return;
    }
    if (interactionMode != WebviewLoadMode.image || !captchaWasFound) return;
    // 导航后验证码图可能还没渲染完，最多复查三次（0 / 400 / 1300ms）再判定「已消失」，避免误报
    for (final delayMs in const [0, 400, 900]) {
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      if (!hasActiveInteraction || captchaGoneEmitted) return;
      if (await _isInteractionNodePresent()) return;
    }
    emitCaptchaDisappeared(reason: '导航后验证码元素已不在');
  }

  /// 当前页面里 `interactionCaptchaXpath` 指向的节点是否还存在。
  Future<bool> _isInteractionNodePresent() async {
    final xpath = interactionCaptchaXpath;
    if (xpath.isEmpty) return false;
    final result = await executeScript('''
(function () {
  try {
    var r = document.evaluate(${jsStringLiteral(xpath)}, document, null,
      XPathResult.FIRST_ORDERED_NODE_TYPE, null);
    return r && r.singleNodeValue ? 'present' : 'absent';
  } catch (e) { return 'absent'; }
})();
''');
    return (result ?? '').contains('present');
  }

  /// 生成「发一条消息回 Dart」的 JS 语句：Windows 走 `chrome.webview.postMessage`。
  String _postToDart(String channel, String payloadJs) {
    final prefix = switch (channel) {
      CaptchaEventChannel.image => 'captchaImage:',
      CaptchaEventChannel.gone => 'captchaGone:',
      CaptchaEventChannel.clicked => 'buttonClicked:',
      CaptchaEventChannel.status => 'captchaStatus:',
      _ => 'captchaLog:',
    };
    return 'try { if (window.chrome && window.chrome.webview) { '
        "window.chrome.webview.postMessage('$prefix' + String($payloadJs)); } } "
        'catch (e) {}';
  }

  @override
  Future<String?> executeScript(String js) async {
    final webview = _headlessWebview;
    if (webview == null) return null;
    try {
      return normalizeScriptResult(await webview.executeScript(js));
    } catch (e) {
      WywLogger().d('${LogTag.webview} executeScript 失败（已忽略）', error: e);
      return null;
    }
  }

  @override
  Future<String> getPageHtml() async {
    final html = await executeScript(
      "document.readyState === 'loading' ? '' : "
      "(document.documentElement ? document.documentElement.outerHTML : '')",
    );
    return html ?? '';
  }

  @override
  Future<String> getUserAgent() async {
    final ua = await executeScript('navigator.userAgent');
    return ua ?? '';
  }

  @override
  Future<WebviewHtmlResult> parseHtml(
    String url, {
    int overTime = 50,
    Map<String, dynamic>? waitFor,
  }) async {
    // 一次性取 HTML 路径：先结束交互会话，避免交互 watcher 干扰本次结果
    _stopInteractionInjectRetry();
    endInteractionSession();
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

  /// 释放 WebView 资源。
  ///
  /// [clearCookies] 在本平台**不产生清理动作**：`HeadlessWebview` 只有全局
  /// `clearCookies()`（没有按域清理），而历史行为是 Windows 侧 `dispose()` 从不清 Cookie，
  /// `js_network` 的空闲释放也依赖 Cookie 留存（登录态/CF 通过态），因此这里始终保留。
  /// 需要清 Cookie 的调用方应使用宿主侧的 Cookie 库。参数保留是为了与契约一致。
  @override
  void dispose({bool clearCookies = true}) {
    _currentPageUrl = '';
    endInteractionSession();
    _captchaVerifyTimer?.cancel();
    _injectRetryTimer?.cancel();
    _stopInteractionInjectRetry();
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
      captchaImageFoundController.close();
      captchaDisappearedController.close();
    } catch (_) {
      // 静默可接受：dispose 阶段关闭 controller 失败属常态，不影响销毁流程。
    }
    _headlessWebview?.dispose();
    _headlessWebview = null;
  }
}
