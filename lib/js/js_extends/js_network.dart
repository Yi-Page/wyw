import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:wyw/js/js_extends/js_cookie_store.dart';
import 'package:wyw/js/js_extends/js_webview.dart';
import 'package:wyw/request/core/dio_factory.dart';

/// JS 端 HTTP 请求的统一处理（**纯请求侧**，Dio）。
///
/// 对应 `sendMessage({method: 'http'})`。
///
/// **职责边界**：本类只管 HTTP。WebView 的一切（一次性取页 `/webview_html`、
/// 交互会话、会话 Cookie 库）都归 [JsWebview]；`backend: 'webview'` 与 `auto`
/// 降级只是把请求**委托**过去，再把 `{html, finalUrl}` 包装成与 HTTP 一致的响应
/// 结构，让插件侧两条路径可以无差别消费。
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
///       - waitFor {Map|string?} — webview / auto 降级时的等待条件。**原样透传**给
///         [JsWebview.fetchHtml]，归一（`{type, value}` 或 `'selector:x'` /
///         `'text:x'` / `'js:expr'` 简写）由它内部完成，本类不依赖 captcha 层
///       - session {string?} — 会话键（默认 ''）。Cookie 库归 [JsWebview]（按 session
///         分库），本类请求前从它注入 Cookie、响应后向它摄入 Set-Cookie
///
/// 成功返回 `{status, headers, body}`（webview / 降级额外带 `finalUrl`、`via='webview'`）；
/// **失败返回 `{error: {message, kind, retryable, status, headers?, body?}}`**：
///   - kind — timeout / connect / dns / ssl / http / cancel / webview / other
///   - retryable — 是否值得重试（5xx/429/408/超时/断连 → true）
///
/// **Cookie 同步**：HTTP 响应的 Set-Cookie 自动摄入；WebView 页面 Cookie（登录态 /
/// CF 验证）由 [JsWebview] 在取页成功后导入**同一个**会话 Cookie 库，同域名后续
/// 请求自动带 Cookie。两边共用一份，避免各自维护导致分叉。
///
/// **会话（session）隔离**：请求 / WebView 调用可指定 `session` 键（extra.session），
/// 不同会话持有独立的 Cookie 库、各自**串行化**执行 WebView 操作（并发安全）；
/// 默认会话键为 `''`，Cookie 库由 [JsWebview.cookiesFor] 惰性创建。
class JsNetwork {
  /// 构造时注入 WebView 模块：两模块共用同一份会话 Cookie 库。
  ///
  /// 用**构造注入**而非 setter：让"没有 WebView 模块就建不出网络模块"成为类型层面的
  /// 约束，避免出现忘记注入、Cookie 静默不生效的实例（setter 注入是可以漏调的）。
  JsNetwork({required JsWebview webview}) : _webview = webview;

  final JsWebview _webview;

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
    // waitFor 保持**原始值**透传：归一逻辑已随 WebView 一起搬到 [JsWebview]，
    // 本类因此不再 import captcha 层（行为与原 normalizeWaitFor 一致）。
    final waitFor = extra['waitFor'];
    final webviewTimeout =
        ((extra['webviewTimeout'] as num?)?.toInt() ?? 20).clamp(5, 90);
    final session = _sessionKey(extra['session']);

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

  /// 会话键归一：null 与空串都落到默认会话 `''`（与重构前 `_sessionFor` 逐字一致）。
  ///
  /// 在这里归一（而不是把 null 往下传），使 [JsWebview] 的交互类方法能安全地收
  /// 非空 `session`。
  String _sessionKey(dynamic key) => key?.toString() ?? '';

  /// 纯 HTTP（Dio）路径：带 Cookie 注入/摄入 + 重试。Cookie 库取自 [JsWebview]。
  Future<Map<String, dynamic>> _httpFetch(
    String session,
    String url,
    String httpMethod,
    dynamic headers,
    dynamic body,
    bool bytes, {
    int? timeoutMs,
    int retries = 0,
    bool manualRedirect = false,
  }) async {
    // Cookie 真理源在 WebView 模块（按 session 分库），本类只借它读写。
    final JsCookieStore cookies = _webview.cookiesFor(session);
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
        // 失败响应的 Set-Cookie 同样要摄入（登录失败也会下发/续期 Cookie）
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
        // 非 2xx 时带上响应体（截断）：反爬/参数错误/接口变更的真实原因通常
        // 只写在 body 里，不带上就只能看到笼统的 "HTTP 400"，排查全靠猜。
        final bodyData = e.response?.data;
        if (bodyData is String && bodyData.isNotEmpty) {
          errorMap['body'] = bodyData.length > 2000
              ? '${bodyData.substring(0, 2000)}…'
              : bodyData;
        }
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
    String session,
    String url,
    String httpMethod,
    dynamic headers,
    dynamic body,
    bool bytes, {
    int? timeoutMs,
    int retries = 0,
    bool manualRedirect = false,
    int webviewTimeout = 20,
    Object? waitFor,
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

    final wv = await _webviewFetch(session, url, bytes, webviewTimeout, waitFor);
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

  /// WebView 后端：委托 [JsWebview.fetchHtml] 渲染取页，再包装成 HTTP 同构响应。
  ///
  /// 包装结构与重构前 `_webviewFetch` **逐字一致**（插件的 `via='webview'` /
  /// `finalUrl` / `x-wyw-via` 判定不变）；[JsWebview] 返回的 `{error: ...}`
  /// 原样透传，不做二次包装——它给的 kind 已经是 `webview`。
  Future<Map<String, dynamic>> _webviewFetch(
    String session,
    String url,
    bool bytes,
    int overTime,
    Object? waitFor,
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
    final result = await _webview.fetchHtml(
      url: url,
      session: session,
      overTime: overTime,
      waitFor: waitFor,
    );
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

  /// 释放本类持有的资源。
  ///
  /// HTTP 侧用的是 [DioFactory] 的全局 Dio，本类不持有可释放资源；WebView 实例
  /// 归 [JsWebview]，由 `JSEngineCommonApi.disposeCommon` 直接释放。保留空实现是
  /// 为了不让调用方的"成对释放"出现缺口（旧版这里负责释放 WebView 会话池）。
  void dispose() {}
}
