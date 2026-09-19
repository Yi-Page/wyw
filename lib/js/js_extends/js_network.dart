import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:wyw/js/js_extends/js_cookie_store.dart';
import 'package:wyw/request/core/dio_factory.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/webview/captcha/captcha_webview_controller.dart';

/// JS 端 HTTP 请求 / WebView 取 HTML 的统一处理。
///
/// 对应 `sendMessage({method: 'http'})` 与 `sendMessage({method: 'webview_html'})`。
///
/// **http 消息字段**（兼容 init.js 中 `Network` 工具类与全局 `http()` 两套调用）：
///   - url {string} — 请求地址
///   - httpMethod {string?} — HTTP 方法（兼容旧字段 `http_method`），默认 GET
///   - headers {Object?} — 请求头
///   - body / data {any?} — 请求体
///   - bytes {bool?} — true 时响应 body 返回原始字节（ArrayBuffer），否则返回字符串
///   - extra {Object?} — 每请求扩展参数（已生效）：
///       - timeout {number} — 超时毫秒数（覆盖全局，同时作用于 connect/send/receive）
///       - retries {number} — 失败重试次数（0-5，仅 kind 可重试时重试，带退避）
///       - redirect {'follow'|'manual'} — 是否跟随重定向（manual 时不跟随，
///         插件可从错误对象 e.headers 的 location 读取跳转目标）
///       - backend {'http'|'webview'|'auto'} — 默认 http；webview 强制用 WebView 渲染；
///         auto 时 HTTP 若疑似反爬（403/429/5xx/超时）自动级联降级到 WebView，返回
///         HTML 并标记 via='webview'（bytes 模式下不降级）
///       - webviewTimeout {number} — webview / auto 降级时的总超时秒数（默认 20，5-90）
///       - waitFor {Map|string?} — webview / auto 降级时的等待条件（见 normalizeWaitFor）
///
/// 成功返回 `{status, headers, body}`（webview/降级额外带 `finalUrl`、`via='webview'`）；
/// **失败返回 `{error: {message, kind, retryable, status, headers?}}`**：
///   - kind — timeout / connect / dns / ssl / http / cancel / webview / other
///   - retryable — 是否值得重试（5xx/429/408/超时/断连 → true）
///
/// **Cookie 同步**：HTTP 响应的 Set-Cookie 自动摄入；WebView 页面 Cookie（登录态 /
/// CF 验证）在 parseHtml 成功后自动导入，同域名后续请求自动带 Cookie。
///
/// **会话（session）隔离**：请求 / WebView 调用可指定 `session` 键
/// （extra.session 或 webview_html.session），不同会话持有独立的请求侧 Cookie 库，
/// 且各自**串行化**执行 WebView 操作（并发安全）；默认会话键为 `''`。
///
/// **webview_html 消息字段**：
///   - url {string} — 要加载的页面地址
///   - overTime / timeout {number?} — 总超时秒数（默认 50）
///   - waitFor {Map|string?} — 等待条件（见 [normalizeWaitFor] / [buildWaitCondition]）
///   - session {string?} — 会话键（默认 ''）
///
/// 成功返回 `{html: string, finalUrl: string}`；失败返回 `{error: {...}}`（kind = 'webview'）。
class JsNetwork {
  // ===== HTTP =====

  Future<Map<String, dynamic>> request(Map message) async {
    final url = message['url'] as String;
    final httpMethod =
        ((message['httpMethod'] ?? message['http_method']) as String? ?? 'GET')
            .toUpperCase();
    final headers = message['headers'];
    final body = message['body'] ?? message['data'];
    final bytes = message['bytes'] == true;
    final extra = message['extra'] is Map
        ? Map<String, dynamic>.from(message['extra'] as Map)
        : const <String, dynamic>{};

    // extra 生效：每请求超时 / 重试次数 / 重定向策略 / 后端选择 / 会话
    final timeoutMs = (extra['timeout'] as num?)?.toInt();
    final retries = ((extra['retries'] as num?)?.toInt() ?? 0).clamp(0, 5);
    final manualRedirect = extra['redirect']?.toString() == 'manual';
    final backend = (extra['backend']?.toString() ?? 'http').toLowerCase();
    final waitFor = normalizeWaitFor(extra['waitFor']);
    final webviewTimeout =
        ((extra['webviewTimeout'] as num?)?.toInt() ?? 20).clamp(5, 90);
    final session = _sessionFor(extra['session']?.toString());

    switch (backend) {
      case 'webview':
        return _webviewFetch(session, url, bytes, webviewTimeout, waitFor);
      case 'auto':
        return _autoFetch(
          session,
          url,
          httpMethod,
          headers,
          body,
          bytes,
          timeoutMs: timeoutMs,
          retries: retries,
          manualRedirect: manualRedirect,
          webviewTimeout: webviewTimeout,
          waitFor: waitFor,
        );
      case 'http':
      default:
        return _httpFetch(
          session,
          url,
          httpMethod,
          headers,
          body,
          bytes,
          timeoutMs: timeoutMs,
          retries: retries,
          manualRedirect: manualRedirect,
        );
    }
  }

  /// 纯 HTTP（Dio）路径：带 Cookie 注入/摄入 + 重试。Cookie 库取自会话。
  Future<Map<String, dynamic>> _httpFetch(
    _WebviewSession session,
    String url,
    String httpMethod,
    dynamic headers,
    dynamic body,
    bool bytes, {
    int? timeoutMs,
    int retries = 0,
    bool manualRedirect = false,
  }) async {
    final cookies = session.cookies;
    var attempt = 0;
    while (true) {
      // Cookie 注入：已同步的页面 Cookie 自动带上（插件显式传 Cookie 时不覆盖）
      final mergedHeaders = <String, dynamic>{};
      if (headers is Map) {
        mergedHeaders.addAll(
          headers.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
      final cookieHeader = cookies.cookieHeader(url);
      if (cookieHeader.isNotEmpty &&
          !mergedHeaders.keys.any((k) => k.toLowerCase() == 'cookie')) {
        mergedHeaders['Cookie'] = cookieHeader;
      }
      try {
        final response = await DioFactory.apiDio.request(
          url,
          data: body,
          options: Options(
            method: httpMethod,
            headers: mergedHeaders.isEmpty ? null : mergedHeaders,
            // bytes 模式返回原始字节；否则返回字符串，避免 Dio 默认 json 模式
            // 把响应解析成对象后再 toString（会丢失 JSON 引号，插件侧 JSON.parse 失败）
            responseType: bytes ? ResponseType.bytes : ResponseType.plain,
            connectTimeout:
                timeoutMs != null ? Duration(milliseconds: timeoutMs) : null,
            receiveTimeout:
                timeoutMs != null ? Duration(milliseconds: timeoutMs) : null,
            sendTimeout:
                timeoutMs != null ? Duration(milliseconds: timeoutMs) : null,
            followRedirects: !manualRedirect,
          ),
        );
        cookies.ingestFromHeaders(url, response.headers['set-cookie']);
        return {
          'status': response.statusCode ?? 0,
          'headers': _flattenHeaders(response.headers.map),
          'body': bytes ? response.data as Uint8List : response.data.toString(),
        };
      } on DioException catch (e) {
        cookies.ingestFromHeaders(url, e.response?.headers['set-cookie']);
        final info = _classifyDio(e);
        if (attempt < retries && info.retryable) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 200 * attempt));
          continue;
        }
        final errorMap = <String, dynamic>{
          'message': _dioFriendlyMessage(e, info),
          'kind': info.kind,
          'retryable': info.retryable,
          'status': e.response?.statusCode ?? 0,
        };
        final respHeaders = e.response?.headers;
        if (respHeaders != null) {
          // manual 重定向场景：插件可从这里读 location 等头
          errorMap['headers'] = _flattenHeaders(respHeaders.map);
        }
        return {'error': errorMap};
      } catch (e) {
        return {
          'error': {
            'message': e.toString(),
            'kind': 'other',
            'retryable': true,
            'status': 0,
          }
        };
      }
    }
  }

  /// HTTP 疑似反爬（403/429/5xx/超时/断连）时级联降级到 WebView。
  Future<Map<String, dynamic>> _autoFetch(
    _WebviewSession session,
    String url,
    String httpMethod,
    dynamic headers,
    dynamic body,
    bool bytes, {
    int? timeoutMs,
    int retries = 0,
    bool manualRedirect = false,
    int webviewTimeout = 20,
    Map<String, dynamic>? waitFor,
  }) async {
    final httpResult = await _httpFetch(
      session,
      url,
      httpMethod,
      headers,
      body,
      bytes,
      timeoutMs: timeoutMs,
      retries: retries,
      manualRedirect: manualRedirect,
    );
    final error = httpResult['error'];
    if (error == null) return httpResult; // HTTP 成功，直接用
    if (!_isBotBlock(error)) return httpResult; // 非疑似反爬，返回原始错误

    final wv =
        await _webviewFetch(session, url, bytes, webviewTimeout, waitFor);
    if (wv.containsKey('error')) return httpResult; // WebView 也失败 → 原始错误
    return wv; // 级联成功，body 为渲染后 HTML，via='webview'
  }

  bool _isBotBlock(Map<dynamic, dynamic> error) {
    final kind = error['kind'];
    if (kind == 'timeout' || kind == 'connect') return true;
    if (kind == 'http') {
      final s = (error['status'] as num?)?.toInt() ?? 0;
      return s == 403 || s == 429 || s >= 500;
    }
    return false;
  }

  /// WebView 后端：加载渲染并返回 HTML（附带 Cookie 同步）。
  Future<Map<String, dynamic>> _webviewFetch(
    _WebviewSession session,
    String url,
    bool bytes,
    int overTime,
    Map<String, dynamic>? waitFor,
  ) async {
    if (bytes) {
      return {
        'error': {
          'message': 'webview 后端不支持 bytes 模式',
          'kind': 'other',
          'retryable': false,
          'status': 0,
        }
      };
    }
    final result = await _parseHtmlWithCookies(session, url, overTime, waitFor);
    if (result.containsKey('error')) return result;
    return {
      'status': 200,
      'headers': {'content-type': 'text/html', 'x-wyw-via': 'webview'},
      'body': result['html'] ?? '',
      'finalUrl': result['finalUrl'] ?? '',
      'via': 'webview',
    };
  }

  /// 把 Dio 异常归类为结构化信息（kind + 是否可重试）。
  ({String kind, bool retryable}) _classifyDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return (kind: 'timeout', retryable: true);
      case DioExceptionType.connectionError:
        final msg = e.message ?? '';
        final inner = e.error;
        if (inner is SocketException) {
          final osMsg = inner.osError?.message ?? '';
          if (msg.contains('Failed host lookup') ||
              msg.contains('No address associated') ||
              osMsg.contains('No address associated')) {
            return (kind: 'dns', retryable: true);
          }
        }
        return (kind: 'connect', retryable: true);
      case DioExceptionType.badCertificate:
        return (kind: 'ssl', retryable: false);
      case DioExceptionType.cancel:
        return (kind: 'cancel', retryable: false);
      case DioExceptionType.badResponse:
        final s = e.response?.statusCode ?? 0;
        return (kind: 'http', retryable: s >= 500 || s == 408 || s == 429);
      case DioExceptionType.unknown:
      default:
        final inner = e.error;
        if (inner is HandshakeException) return (kind: 'ssl', retryable: false);
        if (inner is SocketException) return (kind: 'dns', retryable: true);
        return (kind: 'other', retryable: true);
    }
  }

  String _dioFriendlyMessage(
    DioException e,
    ({String kind, bool retryable}) info,
  ) {
    switch (info.kind) {
      case 'timeout':
        return '请求超时（${e.type.name}）';
      case 'connect':
        return '连接失败: ${e.message ?? e.type.name}';
      case 'dns':
        return 'DNS 解析失败: ${e.message ?? ''}';
      case 'ssl':
        return 'SSL/TLS 错误: ${e.message ?? ''}';
      case 'http':
        return 'HTTP ${e.response?.statusCode ?? ''}';
      case 'cancel':
        return '请求已取消';
      default:
        return '请求失败: ${e.message ?? e.type.name}';
    }
  }

  /// 多值响应头拍平为单值 map（JS 侧按普通对象访问）。
  Map<String, String> _flattenHeaders(Map<String, List<String>> headers) {
    return <String, String>{
      for (final e in headers.entries)
        if (e.value.isNotEmpty) e.key: e.value.first,
    };
  }

  // ===== WebView 会话池（复用 + 串行化 + 空闲自动释放） =====
  //
  // 为什么不是每次调用创建、用完立即销毁（即毁即建的模式）：
  //   WebView2 的环境/浏览器进程销毁是**异步**的，且所有实例共享默认
  //   user data folder。用完立即重建会撞上 folder 锁，环境创建失败/挂起，
  //   init 或取页面一直超时。即毁即建只适用于使用间隔是
  //   "用户关闭对话框"级（数秒以上）的场景；而 Network.getHtml 是插件 API，
  //   一次搜索流程内会密集调用。
  // 因此：调用期间复用同一个 WebView，空闲 [idleDisposeDelay] 后自动释放，
  //   既避免密集重建，又不让 WebView 常驻内存。
  //
  // 为什么用会话池而不是单个共享 WebView：
  //   - 并发安全：同一 WebView 上并发 parseHtml 会互相打断（unloadPage/loadPage
  //     竞态），同一会话内用队列**串行化**执行；
  //   - Cookie 隔离：插件可用 extra.session / {session} 指定会话，不同会话持有
  //     独立的请求侧 Cookie 库（WebView 侧因共享 WebView2 profile 仍互通）。

  static const _idleDisposeDelay = Duration(seconds: 15);
  static const _defaultSession = '';

  final Map<String, _WebviewSession> _sessions = {};

  _WebviewSession _sessionFor(String? key) {
    final k = key == null || key.isEmpty ? _defaultSession : key;
    return _sessions.putIfAbsent(k, () => _WebviewSession(k));
  }

  Future<Map<String, dynamic>> webviewHtml(Map message) async {
    final url = message['url'] as String;
    final overTime =
        ((message['overTime'] ?? message['timeout']) as num?)?.toInt() ?? 50;
    final waitFor = normalizeWaitFor(message['waitFor']);
    final session = _sessionFor(message['session'] as String?);
    return _parseHtmlWithCookies(session, url, overTime, waitFor);
  }

  /// 加载并解析页面，成功后把页面 Cookie 导入会话 Cookie 库（WebView → Dio 同步）。
  /// 同一会话内串行执行，避免并发踩踏。
  Future<Map<String, dynamic>> _parseHtmlWithCookies(
    _WebviewSession session,
    String url,
    int overTime,
    Map<String, dynamic>? waitFor,
  ) {
    session.idleTimer?.cancel();
    return session.runQueued(() async {
      try {
        final webview = await _getWebview(session);
        final result = await webview.parseHtml(
          url,
          overTime: overTime,
          waitFor: waitFor,
        );
        // WebView 页面设置的 Cookie（登录态 / CF 验证）→ 会话 Cookie 库
        await _syncWebviewCookies(webview, session, url, result.finalUrl);
        return {'html': result.html, 'finalUrl': result.finalUrl};
      } catch (e) {
        return {
          'error': {
            'message': e.toString(),
            'kind': 'webview',
            'retryable': true,
            'status': 0,
          }
        };
      } finally {
        // 无论成功/超时/异常，调用结束后进入空闲计时，到期自动释放
        _scheduleIdleDispose(session);
      }
    });
  }

  Future<void> _syncWebviewCookies(
    CaptchaWebviewController webview,
    _WebviewSession session,
    String url,
    String finalUrl,
  ) async {
    for (final u in {url, if (finalUrl.isNotEmpty) finalUrl}) {
      try {
        final cookies = await webview.getCookieString(u);
        session.cookies.importFromString(u, cookies);
      } catch (e) {
        // 单个域失败不影响整体同步
      }
    }
  }

  /// 查询某会话当前已同步的 Cookie 字符串（"k1=v1; k2=v2"）。
  Map<String, dynamic> getCookies(Map message) {
    final url = message['url'] as String? ?? '';
    final session = _sessionFor(message['session'] as String?);
    return {'cookies': session.cookies.cookieHeader(url)};
  }

  Future<CaptchaWebviewController> _getWebview(_WebviewSession session) {
    return session.initFuture ??= () async {
      final webview =
          session.webview ??= CaptchaWebviewControllerFactory.getController();
      // 先订阅再 init：broadcast 事件流，避免错过 init 过程中已发出的事件
      final ready = Completer<void>();
      final sub = webview.onInitialized.listen((_) {
        if (!ready.isCompleted) ready.complete();
      });
      try {
        await webview.init();
        await ready.future.timeout(const Duration(seconds: 30));
      } finally {
        sub.cancel();
      }
      return webview;
    }();
  }

  void _scheduleIdleDispose(_WebviewSession session) {
    session.idleTimer?.cancel();
    session.idleTimer = Timer(_idleDisposeDelay, () {
      session.initFuture = null;
      final webview = session.webview;
      session.webview = null;
      webview?.dispose();
    });
  }

  /// 立即释放所有会话的 WebView（JS 引擎销毁时由 [JSEngineCommonApi.disposeCommon] 调用）。
  void dispose() {
    for (final s in _sessions.values) {
      s.idleTimer?.cancel();
      s.idleTimer = null;
      s.initFuture = null;
      final webview = s.webview;
      s.webview = null;
      webview?.dispose();
    }
    _sessions.clear();
  }
}

/// 一个 WebView 会话：独立的 WebView 实例 + 独立的请求侧 Cookie 库 + 操作串行队列。
class _WebviewSession {
  _WebviewSession(this.key);

  final String key;
  final JsCookieStore cookies = JsCookieStore();
  CaptchaWebviewController? webview;
  Future<CaptchaWebviewController>? initFuture;
  Timer? idleTimer;
  Future<void> _opQueue = Future<void>.value();

  /// 串行化 WebView 操作：同一会话内的加载/取 HTML 按序执行，避免并发踩踏。
  Future<T> runQueued<T>(Future<T> Function() op) {
    final result = _opQueue.then((_) => op());
    // 吞掉前一个失败，避免队列断链；错误仍由调用方拿到
    _opQueue = result.then<void>((_) {}, onError: (Object e, StackTrace s) {
      WywLogger().w('${LogTag.js} WebView 会话队列任务失败 key=$key（不影响主流程）', error: e);
    });
    return result;
  }
}
