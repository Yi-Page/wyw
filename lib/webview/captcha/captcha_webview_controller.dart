import 'dart:convert';
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

/// 页面加载模式（对齐 Kazumi 的三种验证码流程，供「留页式交互会话」使用）。
enum WebviewLoadMode {
  /// 等验证码图出现 → 抓成 dataURL → 交给用户识别 → 回填点击。
  image,

  /// 页面里点一下按钮即可（例如「点击开始验证」）。
  button,

  /// 站点自定义规则脚本（见 [buildInteractionWatcherScript] 里的 `window.WywCaptcha` 协议）。
  script,
}

/// JS 侧回传通道名（[CaptchaJsPostHandler] 的第一个参数）。
///
/// 各平台把同名通道映射成自己的传输方式：
///   - Windows：`chrome.webview.postMessage('captchaImage:' + payload)` 等前缀消息；
///   - Android/iOS/macOS：`window.flutter_inappwebview.callHandler('CaptchaImage', payload)`。
abstract final class CaptchaEventChannel {
  /// 验证码图（canvas.toDataURL('image/png') 的 dataURL）。
  static const String image = 'image';

  /// 验证码消失 / 验证通过。
  static const String gone = 'gone';

  /// 自动化流程点击了按钮（之后若页面发生跳转即认为验证通过）。
  static const String clicked = 'clicked';

  /// 页面自报验证码元素当前是否存在（`'present'` / `'absent'`），仅用于日志。
  static const String status = 'status';

  /// 页面内调试日志。
  static const String log = 'log';
}

/// 生成「把一条消息发回 Dart」的 JS 语句。
///
/// [channel] 取 [CaptchaEventChannel] 中的常量；[payloadJs] 是一段 JS 表达式源码
/// （通常就是变量名 `payload`），生成结果会被直接嵌入页面的 `send()` 函数体。
typedef CaptchaJsPostHandler = String Function(String channel, String payloadJs);

/// 生成注入到页面里的「交互 watcher」脚本（两个平台实现共用）。
///
/// ## 页面内协议
///
/// 脚本只装一次（`window.__wywCaptchaToken` 做幂等 + 版本标记），注入后：
///
///   - `image` 模式：先按 [inputXpath] 触发输入框 focus（优先 `$(el).trigger('focus')` /
///     `jQuery(el).trigger('focus')`，兜底 `el.focus()`，部分站点 focus 后才下发验证码图）；
///     再按 [captchaXpath] 用 `document.evaluate` 找图，img 走 canvas 抓
///     `toDataURL('image/png')`（canvas 元素直接 toDataURL），上报 [CaptchaEventChannel.image]；
///     未命中 500ms 轮询，命中后降频到 1500ms 继续盯着「换图」（验证码填错后站点换一张）；
///     挂 `MutationObserver(document.documentElement, {childList, subtree, attributes})`，
///     节点消失 → 上报 [CaptchaEventChannel.gone]。
///   - `button` 模式：按 [buttonXpath] 找到即 focus + `el.click()`（只点一次），
///     上报 [CaptchaEventChannel.clicked]；挂同款 MutationObserver，按钮消失 → gone。
///   - `script` 模式：先挂 `window.WywCaptcha`，再把 [script] 包进 IIFE 执行：
///
///     ```js
///     window.WywCaptcha = {
///       log(msg),      // → onLog / [CaptchaEventChannel.log]
///       clicked(msg),  // → 标记「已点击」，之后若导航即视为验证通过
///       done(msg),     // → onCaptchaDisappeared / [CaptchaEventChannel.gone]
///       fail(msg),     // → onLog（前缀 custom script failed:）
///     };
///     ```
///
///     规则脚本 `return true` 等价于调一次 `done()`；异常自动走 `fail()`。
///     规则脚本里可以 `WywCaptcha.log('...')` 打点，也可以用
///     `WywCaptcha.done()` 显式宣告验证完成。
///
/// [token] 是 Dart 侧的会话序号：同序号重复注入（导航后重试注入等）直接返回，
/// 不同序号则先销毁页内旧 watcher 再装新的。
String buildInteractionWatcherScript({
  required int token,
  required WebviewLoadMode mode,
  required String captchaXpath,
  required String inputXpath,
  required String buttonXpath,
  required String script,
  required CaptchaJsPostHandler post,
}) {
  final channelBranches = <String>[
    CaptchaEventChannel.image,
    CaptchaEventChannel.gone,
    CaptchaEventChannel.clicked,
    CaptchaEventChannel.status,
    CaptchaEventChannel.log,
  ].map((c) => "      if (channel === '$c') { ${post(c, 'payload')} }").join('\n');

  final scriptBody = script.trim().isEmpty
      ? "        window.WywCaptcha.fail('empty captchaScript');"
      : script;

  final sb = StringBuffer();
  sb.write('''
(function () {
  if (window.top !== window.self) return 'frame-skip';
  var TOKEN = $token;
  if (window.__wywCaptchaToken === TOKEN) return 'already-installed';
  try { if (window.__wywCaptcha && window.__wywCaptcha.destroy) window.__wywCaptcha.destroy(); } catch (e) {}
  window.__wywCaptchaToken = TOKEN;

  var MODE = '${mode.name}';
  var CAPTCHA_XPATH = ${jsStringLiteral(captchaXpath)};
  var INPUT_XPATH = ${jsStringLiteral(inputXpath)};
  var BUTTON_XPATH = ${jsStringLiteral(buttonXpath)};

  var poller = null;
  var period = 0;
  var observer = null;
  var goneSent = false;
  var captured = false;
  var clicked = false;
  var focusDone = false;
  var imgNode = null;
  var statusSent = false;
  var captureErrLogged = false;

  function alive() { return window.__wywCaptchaToken === TOKEN; }

  function send(channel, payload) {
    try {
$channelBranches
    } catch (e) {}
  }

  function q(xpath) {
    if (!xpath) return null;
    try {
      var r = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
      return r ? r.singleNodeValue : null;
    } catch (e) { return null; }
  }

  function stopPoller() {
    if (poller) { try { clearInterval(poller); } catch (e) {} poller = null; period = 0; }
  }

  function stopAll() {
    stopPoller();
    if (observer) { try { observer.disconnect(); } catch (e) {} observer = null; }
  }

  function destroy() {
    goneSent = true;
    stopAll();
    window.__wywCaptcha = null;
    if (window.__wywCaptchaToken === TOKEN) window.__wywCaptchaToken = 0;
  }

  function ensurePoller(next) {
    if (!alive() || goneSent) return;
    if (poller && period === next) return;
    stopPoller();
    period = next;
    poller = setInterval(function () { if (alive() && !goneSent) tick(); }, next);
  }

  function sendGone(reason) {
    if (goneSent) return;
    goneSent = true;
    stopAll();
    send('gone', String(reason || ''));
  }

  function watchGone(check) {
    if (observer || goneSent || !document.documentElement) return;
    try {
      observer = new MutationObserver(function () {
        if (goneSent || !alive()) return;
        if (!check()) sendGone('node-removed');
      });
      observer.observe(document.documentElement,
        { childList: true, subtree: true, attributes: true });
    } catch (e) { observer = null; }
  }

  function focusInput() {
    if (focusDone || !INPUT_XPATH) return;
    var el = q(INPUT_XPATH);
    if (!el) return;
    try {
      if (typeof \$ !== 'undefined' && \$) { \$(el).trigger('focus'); }
      else if (typeof jQuery !== 'undefined' && jQuery) { jQuery(el).trigger('focus'); }
      else if (el.focus) { el.focus(); }
      focusDone = true;
      send('log', 'input focused');
    } catch (e) {
      try { if (el.focus) { el.focus(); focusDone = true; } } catch (e2) {}
      send('log', 'input focus failed: ' + (e && e.message ? e.message : e));
    }
  }

  function captureImage(node) {
    var tag = node.tagName ? String(node.tagName).toLowerCase() : '';
    try {
      if (tag === 'canvas') { send('image', node.toDataURL('image/png')); return true; }
      if (tag === 'img') {
        var canvas = document.createElement('canvas');
        canvas.width = node.naturalWidth || node.width || 100;
        canvas.height = node.naturalHeight || node.height || 40;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(node, 0, 0);
        send('image', canvas.toDataURL('image/png'));
        return true;
      }
      if (!captureErrLogged) {
        captureErrLogged = true;
        send('log', 'captcha node is not img/canvas: ' + tag);
      }
      return false;
    } catch (e) {
      if (!captureErrLogged) {
        captureErrLogged = true;
        send('log', 'captcha capture failed: ' + (e && e.message ? e.message : e));
      }
      return false;
    }
  }

  function tryCapture(node) {
    if (!node) return false;
    var tag = node.tagName ? String(node.tagName).toLowerCase() : '';
    if (tag === 'img' && !(node.complete && node.naturalWidth > 0)) {
      if (!node.__wywCaptchaBound) {
        node.__wywCaptchaBound = true;
        node.addEventListener('load', function () {
          if (!alive() || goneSent) return;
          if (captureImage(node)) captured = true;
        });
        node.addEventListener('error', function () {
          if (alive()) send('log', 'captcha image failed to load');
        });
      }
      return false;
    }
    return captureImage(node);
  }

  function checkImage() {
    var node = q(CAPTCHA_XPATH);
    if (!node) return false;
    watchGone(function () { return q(CAPTCHA_XPATH); });
    if (captured && node === imgNode) return true;
    imgNode = node;
    if (tryCapture(node)) {
      captured = true;
      send('log', 'captcha image captured on ' + String(window.location.href));
      return true;
    }
    return captured;
  }

  function checkButton() {
    var btn = q(BUTTON_XPATH);
    if (!btn) return false;
    watchGone(function () { return q(BUTTON_XPATH); });
    if (clicked) return true;
    clicked = true;
    try { if (btn.focus) btn.focus(); } catch (e) {}
    try { btn.click(); } catch (e) {
      send('log', 'button click failed: ' + (e && e.message ? e.message : e));
    }
    send('clicked', 'button clicked');
    send('log', 'button clicked: ' + BUTTON_XPATH);
    return true;
  }

  function tick() {
    if (!document.documentElement) return;
    if (!statusSent && CAPTCHA_XPATH) {
      statusSent = true;
      send('status', q(CAPTCHA_XPATH) ? 'present' : 'absent');
    }
    if (MODE === 'image') {
      focusInput();
      if (checkImage()) ensurePoller(1500);
    } else if (MODE === 'button') {
      if (checkButton()) ensurePoller(1500);
    }
  }

  window.__wywCaptcha = { token: TOKEN, destroy: destroy };
  send('log', 'watcher installed on ' + String(window.location.href) + ' mode=' + MODE);

  if (MODE === 'script') {
    stopPoller();
    window.WywCaptcha = {
      log: function (message) { send('log', String(message)); },
      clicked: function (message) { send('clicked', String(message || '')); },
      done: function (message) { sendGone(String(message || 'script-done')); },
      fail: function (message) { send('log', 'custom script failed: ' + String(message)); }
    };
    try {
      var __wywResult = (function () {
$scriptBody
      })();
      if (__wywResult === true) window.WywCaptcha.done('script-returned-true');
    } catch (e) {
      window.WywCaptcha.fail(e && e.message ? e.message : e);
    }
  } else {
    ensurePoller(500);
    tick();
  }

  return 'installed:' + MODE;
})();
''');
  return sb.toString();
}

/// 把 `executeScript` / `evaluateJavascript` 的原始返回归一化为字符串。
///
/// 页面返回对象/数组时序列化成 JSON；JS 返回 `undefined`（Dart 侧为 null）时返回 null；
/// 无法序列化时退回 `toString()`，实在不行返回 null。
String? normalizeScriptResult(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) return raw;
  if (raw is num || raw is bool) return raw.toString();
  try {
    return jsonEncode(raw);
  } catch (_) {
    return raw.toString();
  }
}

abstract class CaptchaWebviewController {
  final StreamController<bool> initEventController =
      StreamController<bool>.broadcast();
  final StreamController<String> logEventController =
      StreamController<String>.broadcast();

  /// 交互会话事件：验证码图（dataURL）
  final StreamController<String> captchaImageFoundController =
      StreamController<String>.broadcast();

  /// 交互会话事件：验证码消失 / 验证通过
  final StreamController<void> captchaDisappearedController =
      StreamController<void>.broadcast();

  /// WebView 初始化完成事件
  Stream<bool> get onInitialized => initEventController.stream;

  /// 调试日志
  Stream<String> get onLog => logEventController.stream;

  /// 验证码图（`canvas.toDataURL('image/png')` 的 dataURL），只在交互会话期间才有事件。
  ///
  /// 注意：broadcast 流不缓存历史事件，订阅方应在
  /// [loadPageForInteraction] 前后就订阅（页面加载本身耗时，通常来得及）。
  Stream<String> get onCaptchaImageFound => captchaImageFoundController.stream;

  /// 验证码元素消失（`image`/`button` 模式由 MutationObserver 上报；`script` 模式由
  /// `WywCaptcha.done()` 或「点击后导航」上报）。每轮交互会话最多上报一次。
  Stream<void> get onCaptchaDisappeared => captchaDisappearedController.stream;

  // ---------------------------------------------------------------------------
  // 交互会话内部状态（两个平台实现共用；只在本目录内使用，命名不带下划线是为了跨文件访问）。
  // ---------------------------------------------------------------------------

  /// 当前交互会话的加载模式；null 表示没有交互会话（一次性 `parseHtml` 路径）。
  WebviewLoadMode? interactionMode;

  String interactionCaptchaXpath = '';
  String interactionInputXpath = '';
  String interactionButtonXpath = '';
  String interactionScript = '';

  /// 交互会话序号：页内 watcher 用它做幂等/换代标记。
  int interactionToken = 0;

  /// 本轮会话是否已经抓到过验证码图（导航后判断「图已不在 ⇒ 验证通过」用）。
  bool captchaWasFound = false;

  /// 本轮会话是否已经自动点过按钮（点击后发生导航 ⇒ 视为验证通过）。
  bool buttonWasClicked = false;

  /// 本轮会话是否已经上报过 onCaptchaDisappeared（幂等保护）。
  bool captchaGoneEmitted = false;

  /// 是否处于交互会话中（决定导航完成后要不要补注入 watcher）。
  bool get hasActiveInteraction => interactionMode != null;

  /// 内部辅助：开始一轮交互会话（重置状态 + 序号自增）。
  void beginInteractionSession({
    required WebviewLoadMode mode,
    String captchaXpath = '',
    String inputXpath = '',
    String buttonXpath = '',
    String script = '',
  }) {
    interactionMode = mode;
    interactionCaptchaXpath = captchaXpath;
    interactionInputXpath = inputXpath;
    interactionButtonXpath = buttonXpath;
    interactionScript = script;
    interactionToken++;
    captchaWasFound = false;
    buttonWasClicked = false;
    captchaGoneEmitted = false;
  }

  /// 内部辅助：结束交互会话（一次性 `parseHtml` 路径开头调用，避免旧 watcher 干扰结果）。
  void endInteractionSession() {
    interactionMode = null;
    interactionCaptchaXpath = '';
    interactionInputXpath = '';
    interactionButtonXpath = '';
    interactionScript = '';
    // 序号自增：页内旧 watcher 的 token 随之失效（它再回传也不会被事件流采纳）
    interactionToken++;
    captchaWasFound = false;
    buttonWasClicked = false;
    captchaGoneEmitted = false;
  }

  /// 内部辅助：上报验证码图（只在交互会话中生效，且空字符串忽略）。
  void emitCaptchaImage(String dataUrl) {
    if (dataUrl.isEmpty || !hasActiveInteraction) return;
    captchaWasFound = true;
    if (!captchaImageFoundController.isClosed) {
      captchaImageFoundController.add(dataUrl);
    }
  }

  /// 内部辅助：上报验证码消失/验证通过（每轮会话幂等，非交互会话忽略）。
  void emitCaptchaDisappeared({String reason = ''}) {
    if (!hasActiveInteraction || captchaGoneEmitted) return;
    captchaGoneEmitted = true;
    captchaWasFound = false;
    buttonWasClicked = false;
    if (reason.isNotEmpty && !logEventController.isClosed) {
      logEventController.add('[Captcha WebView] 验证码消失/验证通过（$reason）');
    }
    if (!captchaDisappearedController.isClosed) {
      captchaDisappearedController.add(null);
    }
  }

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

  /// 加载页面并注入交互 watcher（不做 unload 前置，页面留住供后续人工输入），
  /// 供「留页式交互会话」使用：取图 → 用户输入 → 回填点击 → 取 HTML/UA/Cookie。
  ///
  /// [mode] 三态见 [WebviewLoadMode]；对应模式用到的 XPath/脚本参数：
  ///   - [WebviewLoadMode.image]：`captchaXpath`（必需）、`inputXpath`（可选，先 focus 输入框）
  ///   - [WebviewLoadMode.button]：`buttonXpath`（必需）
  ///   - [WebviewLoadMode.script]：`script`（必需，页面内 `window.WywCaptcha` 协议）
  Future<void> loadPageForInteraction(
    String url, {
    required WebviewLoadMode mode,
    String captchaXpath = '',
    String inputXpath = '',
    String buttonXpath = '',
    String script = '',
  });

  /// 页面内执行任意 JS，返回字符串结果；不可序列化/失败返回 null。
  Future<String?> executeScript(String js);

  /// 当前页面 HTML；`document.readyState === 'loading'` 时返回 ''。
  Future<String> getPageHtml();

  /// 当前页面 `navigator.userAgent`。
  Future<String> getUserAgent();

  /// 获取当前页面的 Cookie 字符串（"key1=val1; key2=val2"）
  ///
  /// [pageUrl] 当前加载的页面地址，部分平台用于精确过滤 Cookie
  Future<String> getCookieString(String pageUrl);

  /// 卸载当前页面（跳转到 about:blank）
  Future<void> unloadPage();

  /// 释放 WebView 资源。
  ///
  /// [clearCookies] 为 false 时**不得**调用 `deleteAllCookies()`——交互会话结束后
  /// 往往要留住登录态/已通过的人机验证 Cookie 供后续 HTTP 请求复用。
  void dispose({bool clearCookies = true});
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
