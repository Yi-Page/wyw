import 'dart:async';
import 'dart:convert';

import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/webview/captcha/captcha_webview_controller.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:wyw/utils/http_headers.dart';

/// Android / iOS / macOS 端验证码 WebView（`flutter_inappwebview` 的 headless 实现）。
///
/// ## 页面 → Dart 的桥协议（`window.flutter_inappwebview.callHandler(name, payload)`）
///
/// | handler 名       | 负载                        | 映射到                                                |
/// | ---------------- | --------------------------- | ----------------------------------------------------- |
/// | `CaptchaImage`   | `data:image/png;base64,...` | [CaptchaWebviewController.onCaptchaImageFound]         |
/// | `CaptchaGone`    | 原因文本（可为空）          | [CaptchaWebviewController.onCaptchaDisappeared]         |
/// | `ButtonClicked`  | 提示文本                    | 标记「已自动点击」，之后若导航 ⇒ onCaptchaDisappeared   |
/// | `CaptchaLog`     | 日志文本                    | [CaptchaWebviewController.onLog]                       |
/// | `CaptchaStatus`  | `present` / `absent`        | 仅日志（`onLog`），不直接触发事件                       |
///
/// 桥由 [PlatformInAppWebViewController.addJavaScriptHandler] 注册（在 `onWebViewCreated`
/// 与 `onLoadStop` 各注册一次，用 `_handlersRegistered` 幂等），页面侧 watcher 由
/// [buildInteractionWatcherScript] 生成（`window.__wywCaptcha` 协议）。
///
/// 保留 250ms 的 `evaluateJavascript` 轮询作为 `parseHtml` 兜底；交互会话则在
/// `onLoadStop` 后注入 watcher 并做有上限的重试（桥断了也不会完全失效）。
class CaptchaWebviewInAppWebviewImpl extends CaptchaWebviewController {
  PlatformHeadlessInAppWebView? _headlessWebView;
  PlatformInAppWebViewController? _webviewController;

  /// JS 桥是否已注册（webview 重建后需要重新注册）
  bool _handlersRegistered = false;

  Completer<WebviewHtmlResult>? _htmlCompleter;

  /// 条件感知轮询定时器
  Timer? _htmlFetchTimer;

  /// 交互 watcher 注入重试定时器（有次数上限）
  Timer? _interactionInjectTimer;
  int _interactionInjectAttempts = 0;

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
          // JS → Dart 通道必须尽早挂上，页面注入脚本才可能 callHandler 成功
          _registerHandlers();
          initEventController.add(true);
        },
        onLoadStart: (controller, url) {
          logEventController.add('[Captcha WebView] Load start: $url');
        },
        // 注意：不依赖 onDomContentLoaded（当前平台接口未暴露），
        // 由 parseHtml 中的条件感知轮询尽早取 HTML
        onLoadStop: (controller, url) async {
          logEventController.add('[Captcha WebView] Load stop: $url');
          _registerHandlers();
          await _tryFetchHtml();
          // 交互会话：导航完成后补注入 watcher + 判定「验证码是否已消失」
          await _onInteractionNavigationCompleted();
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

  /// 注册 5 个 JS 桥（幂等）。
  void _registerHandlers() {
    final controller = _webviewController;
    if (_handlersRegistered || controller == null) return;
    try {
      controller.addJavaScriptHandler(
        handlerName: 'CaptchaImage',
        callback: (args) {
          emitCaptchaImage(args.isNotEmpty ? args[0].toString() : '');
        },
      );
      controller.addJavaScriptHandler(
        handlerName: 'CaptchaGone',
        callback: (args) {
          emitCaptchaDisappeared(reason: '页面 watcher 上报验证码元素消失');
        },
      );
      controller.addJavaScriptHandler(
        handlerName: 'ButtonClicked',
        callback: (args) {
          buttonWasClicked = true;
          if (!logEventController.isClosed) {
            logEventController.add(
              '[Captcha WebView] 按钮已自动点击，等待页面跳转判定验证通过',
            );
          }
        },
      );
      controller.addJavaScriptHandler(
        handlerName: 'CaptchaLog',
        callback: (args) {
          if (args.isNotEmpty && !logEventController.isClosed) {
            logEventController
                .add('[Captcha WebView JS] ${args[0].toString()}');
          }
        },
      );
      controller.addJavaScriptHandler(
        handlerName: 'CaptchaStatus',
        callback: (args) {
          // 页面自报状态：只做日志，真正判定由导航后的 Dart 侧复查负责（避免误报）
          if (args.isNotEmpty && !logEventController.isClosed) {
            logEventController
                .add('[Captcha WebView JS] 页面验证码状态: ${args[0].toString()}');
          }
        },
      );
      _handlersRegistered = true;
      logEventController.add('[Captcha WebView] JS handlers registered');
    } catch (e) {
      // 静默可接受：极端情况下（controller 已销毁）注册失败，轮询/重注入仍可兜底
      WywLogger().d('${LogTag.webview} 注册 JS handler 失败（已忽略）', error: e);
    }
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
    _registerHandlers();
    _stopInteractionInjectRetry();
    try {
      // 注意：与 parseHtml 不同，这里不做 unload 前置——页面要留住给用户看验证码
      await _webviewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.webview} 交互会话加载页面失败 url=$url', error: e, stackTrace: s);
      if (!logEventController.isClosed) {
        logEventController.add('[Captcha WebView] 交互会话加载页面失败: $e');
      }
    }
    // onLoadStop 后还会再注入一次；这里先尝试一次（部分站点 onLoadStop 触发很晚）
    await _injectInteractionWatcher();
    _startInteractionInjectRetry();
  }

  /// 重新注入交互 watcher；`interactionToken` 保证同一轮会话幂等。
  Future<void> _injectInteractionWatcher() async {
    final mode = interactionMode;
    final controller = _webviewController;
    if (mode == null || controller == null) return;
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
      final raw = await controller.evaluateJavascript(source: js);
      final result = normalizeScriptResult(raw);
      if (result != null && result.contains('installed') &&
          !logEventController.isClosed) {
        logEventController.add('[Captcha WebView] 交互 watcher 已注入: $result');
        _stopInteractionInjectRetry();
      }
    } catch (_) {
      // 静默可接受：导航中页面 JS 上下文未就绪属常态，由重试定时器兜底。
    }
  }

  /// 有上限的注入重试（500ms × 20 次 ≈ 10s），注入成功或会话结束即取消。
  void _startInteractionInjectRetry() {
    _interactionInjectAttempts = 0;
    _interactionInjectTimer?.cancel();
    _interactionInjectTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (t) {
        if (!hasActiveInteraction ||
            _webviewController == null ||
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

  /// 生成「发一条消息回 Dart」的 JS 语句：Android/iOS/macOS 走 `callHandler`。
  String _postToDart(String channel, String payloadJs) {
    const handlerNames = {
      CaptchaEventChannel.image: 'CaptchaImage',
      CaptchaEventChannel.gone: 'CaptchaGone',
      CaptchaEventChannel.clicked: 'ButtonClicked',
      CaptchaEventChannel.status: 'CaptchaStatus',
      CaptchaEventChannel.log: 'CaptchaLog',
    };
    final name = handlerNames[channel] ?? 'CaptchaLog';
    return 'try { if (window.flutter_inappwebview '
        '&& window.flutter_inappwebview.callHandler) { '
        "window.flutter_inappwebview.callHandler('$name', String($payloadJs)); } } "
        'catch (e) {}';
  }

  @override
  Future<String?> executeScript(String js) async {
    final controller = _webviewController;
    if (controller == null) return null;
    try {
      return normalizeScriptResult(
        await controller.evaluateJavascript(source: js),
      );
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
    try {
      // 一次性取 HTML 路径：先结束交互会话，避免交互 watcher 干扰本次结果
      _stopInteractionInjectRetry();
      endInteractionSession();
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

  /// 释放 WebView 资源。
  ///
  /// [clearCookies] 为 true（默认，与历史行为一致）才调用 `deleteAllCookies()`；
  /// 传 false 时**不动**平台 Cookie——交互会话刚通过人机验证/登录，Cookie 要留给
  /// 后续请求复用，清掉就白验证了。
  @override
  void dispose({bool clearCookies = true}) {
    endInteractionSession();
    _htmlFetchTimer?.cancel();
    _stopInteractionInjectRetry();
    if (clearCookies) {
      try {
        PlatformCookieManager(
          const PlatformCookieManagerCreationParams(),
        ).deleteAllCookies();
      } catch (_) {
        // 静默可接受：dispose 阶段清理 Cookie 失败属常态，不影响销毁流程。
      }
    }
    try {
      initEventController.close();
      logEventController.close();
      captchaImageFoundController.close();
      captchaDisappearedController.close();
    } catch (_) {
      // 静默可接受：dispose 阶段关闭 controller 失败属常态，不影响销毁流程。
    }
    _handlersRegistered = false;
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _webviewController = null;
  }
}
