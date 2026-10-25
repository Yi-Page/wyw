import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:wyw/js/js_extends/html/html_registry.dart';
import 'package:wyw/js/js_extends/js_codec.dart';
import 'package:wyw/js/js_extends/js_dialog.dart';
import 'package:wyw/js/js_extends/js_network.dart';
import 'package:wyw/js/js_extends/js_webview.dart';
import 'package:wyw/repositories/collect_repository.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';

/// JS ↔ Dart 桥接 mixin。
///
/// **职责**：作为「JS 端 sendMessage 消息 → Dart 处理」的路由层（薄 dispatch）。
///
/// **组成**：
///   - [HtmlRegistry] — HTML 文档 + XPath（按四大类 handler 分发）
///   - [JsCodec] — 编码 / 加密 / 随机 / UUID
///   - [JsNetwork] — HTTP 请求（Dio），纯请求侧
///   - [JsWebview] — WebView 一次性取页 + 交互会话（留页验证码流程）
///   - 直接处理：log / clip / platform / delay（无需工具类）
///
/// **两模块的关系**：HTTP 与 WebView 生命周期诉求相反（请求短命高频，WebView 是
/// 重资源、验证类场景还要长时间留页），故各自成模块；但 Cookie 库只有一份——
/// 由 [JsWebview] 按 session 分库持有，[JsNetwork] 请求前注入、响应后摄入都走它。
///
/// **使用方式**：被 [BaseJsEngine] 继承，
/// [JSEngineCommonApi.handleCommonMessage] 暴露为子类入口（`ScriptEngine` 通过 `handleMessage` 包装一层测试捕获）。
mixin class JSEngineCommonApi {
  /// JS 端 `dialog.showToast` 消息回调。
  ///
  /// 由宿主应用在启动时设置（如 `JSEngineCommonApi.onShowToast = WywDialog.showToast`）。
  /// 设置后 JS 代码 `sendMessage({method: 'dialog', function: 'showToast', message: '...'})`
  /// 会触发此回调。默认 null（即 no-op）。
  ///
  /// 设为静态字段是为了让纯 JS 层（`js_dialog.dart`）不反向依赖 UI 层。
  static void Function(String message)? onShowToast;

  /// JS 端 `dialog.showDialog` 消息回调。
  ///
  /// 对应 venera 的 `UI.showDialog(title, content, actions)`；[actions] 每项为
  /// `{text, callback, style}`，`callback` 是 JS 函数（`JSInvokable`），由宿主在
  /// 按钮点击时调用。宿主未设置时该调用为 no-op。
  static void Function({
    required String title,
    required String content,
    List<Map<String, dynamic>> actions,
  })? onShowDialog;

  /// JS 端 `dialog.showInputDialog` 消息回调（缺口 G1）。
  ///
  /// 返回用户输入的文本；取消返回 null。`validator` 是插件传入的 JS 校验函数
  /// （可为 null），宿主可在确认时调用它做校验。
  static Future<String?> Function({
    required String title,
    Object? image,
    Object? validator,
  })? onShowInputDialog;

  /// JS 端 `dialog.showSelectDialog` 消息回调（缺口 G3）。返回选中下标，取消返回 null。
  static Future<int?> Function({
    required String title,
    required List<String> options,
    int? initialIndex,
  })? onShowSelectDialog;

  /// JS 端 `dialog.showLoading` 消息回调（缺口 G2）。返回可用于取消的 id。
  static int Function({Object? onCancel})? onShowLoading;

  /// JS 端 `dialog.cancelLoading` 消息回调（缺口 G2）。
  static void Function(int id)? onCancelLoading;

  /// JS 端 `isLogged` 消息回调。
  ///
  /// `init.js` 的 `PluginSource.get isLogged` 会发 `{method:'isLogged', key}`；
  /// 宿主未设置时返回 **false**（明确的未登录），而不是让调用落到 `return null`
  /// 产生「看起来正常但恒为未登录」的隐蔽行为。
  static bool Function(String pluginKey)? onIsLogged;

  /// JS 端 `navigateToVideo` 消息回调。
  ///
  /// 用于从 JS 侧跳转到视频播放页面。
  /// 设置后 JS 代码 `sendMessage({method: 'navigateToVideo', url: '...'})`
  /// 会触发此回调。默认 null（即 no-op）。
  static void Function(String videoUrl,
      {String? title,
      String? cover,
      String? videoId,
      String? sourceKey,
      int? initialSource,
      int? initialEpisode,
      List<Map<String, dynamic>>? sources})? onNavigateToVideo;

  /// JS 端 `navigateToWebview` 消息回调。
  ///
  /// 用于从 JS 侧跳转到 WebView 页面。
  /// 设置后 JS 代码 `sendMessage({method: 'navigateToWebview', url: '...'})`
  /// 会触发此回调。默认 null（即 no-op）。
  static void Function(String url)? onNavigateToWebview;

  /// JS 端 `openExternalBrowser` 消息回调。
  ///
  /// 用于从 JS 侧在外部浏览器打开链接（宿主负责弹确认框）。
  /// 设置后 JS 代码 `sendMessage({method: 'openExternalBrowser', url: '...'})`
  /// 会触发此回调。默认 null（即 no-op）。
  static void Function(String url)? onOpenExternalBrowser;

  /// JS 端 `navigateToReader` 消息回调。
  ///
  /// 用于从 JS 侧跳转到漫画阅读器页面。
  /// 设置后 JS 代码 `sendMessage({method: 'navigateToReader', ...})`
  /// 会触发此回调。默认 null（即 no-op）。
  ///
  /// [chapters] 为 `[{id, title, images: [url...]}]` 的章节列表（图片列表需已就绪）。
  static void Function(
    String comicId,
    String comicTitle,
    List<Map<String, dynamic>> chapters, {
    String? sourceKey,
    int initialChapter,
    int initialPage,
  })? onNavigateToReader;

  /// JS 端 `onNavigate`（UI descriptor）回调。
  ///
  /// 用于从 JS 描述符按钮跳转到 descriptor 页面。
  /// 由 page 层（持有 BuildContext）注册。
  /// 默认 null（即 no-op）。
  static void Function(Map<String, dynamic> args)? onNavigateToDescriptor;

  /// JS 端 `navigateToNovelReader` 消息回调。
  ///
  /// 用于从 JS 侧跳转到小说阅读器页面（与漫画的 `navigateToReader` 对应，
  /// 但章节内容是文本而非图片）。
  /// 设置后 JS 代码 `sendMessage({method: 'navigateToNovelReader', ...})`
  /// 会触发此回调。默认 null（即 no-op）。
  ///
  /// [chapters] 为 `[{id, title, content}]` 或 `[{id, title, plugin, method, args}]`
  /// 的章节列表（正文文本已就绪 / 惰性加载）。
  static void Function(
    String novelId,
    String novelTitle,
    List<Map<String, dynamic>> chapters, {
    String? sourceKey,
    int initialChapter,
  })? onNavigateToNovelReader;

  /// 收藏仓库（= 插件浏览足迹 + 收藏状态，由宿主应用在启动时注入）。
  ///
  /// JS 端 `PluginBrowse.*` API 走 `sendMessage({method:'plugin_history', ...})` 路由到此仓库。
  /// 默认 null（即 no-op）。
  static CollectRepository? collectRepository;

  /// 插件点击浏览历史条目时的回调（由 UI 层注册）。
  /// 应用只负责"用户点了 id"，插件自己解析 kv 决定跳详情页/播放页。
  /// 通过 `sendMessage({method:'plugin_browse_entry', id})` 触发。
  static void Function(String pluginName, String id)? onPluginBrowseEntry;

  final _html = HtmlRegistry();
  final _codec = JsCodec();
  final _dialog = JsDialog();

  /// WebView 能力实例（一次性取页 + 交互会话 + 会话 Cookie 库），引擎级单例。
  final _webview = JsWebview();

  /// HTTP 请求（Dio）。构造时注入 [_webview]：两模块共用同一份会话 Cookie 库，
  /// 避免各持一套导致登录态 / clearance cookie 分叉。
  ///
  /// 这里必须是 `late final`：Dart **普通**字段的初始化式里读不到 `this`，也就取不到
  /// 上面的 `_webview` 字段（写 `final _network = JsNetwork(webview: _webview);` 会报
  /// "The instance member '_webview' can't be accessed in an initializer"）。
  /// `late` 的初始化式里 `this` 可用，且仍然只在首次访问时建一次。
  late final JsNetwork _network = JsNetwork(webview: _webview);

  /// 统一的 JS→Dart 消息入口。
  ///
  /// JS 端调用 `sendMessage({method: ..., ...})` 时触发。
  Object? handleCommonMessage(dynamic message) {
    try {
      if (message is Map<dynamic, dynamic>) {
        if (message['method'] == null) return null;
        final method = message['method'] as String;
        switch (method) {
          case 'html':
            return _html.handleHtmlCallback(Map.from(message));
          case 'dialog':
            return _dialog.handleDialogCallback(Map.from(message));
          case 'log':
            _log(message);
          case 'convert':
            return _codec.convert(Map.from(message));
          case 'random':
            return _codec.random(
              message['min'] ?? 0,
              message['max'] ?? 1,
              message['type'],
            );
          case 'uuid':
            return _codec.uuidV1();
          case 'delay':
            return Future.delayed(Duration(milliseconds: message['time']));
          case 'getPlatform':
            return Platform.operatingSystem;
          case 'isLogged':
            // init.js 的 PluginSource.get isLogged 走这里。宿主未接入账号体系时
            // 返回明确的 false（旧实现落到函数末尾 return null，语义含糊）。
            return onIsLogged?.call(message['key']?.toString() ?? '') ?? false;
          case 'setClipboard':
            Clipboard.setData(ClipboardData(text: message['text']));
          case 'getClipboard':
            return Future.sync(() async {
              final res = await Clipboard.getData(Clipboard.kTextPlain);
              return res?.text;
            });
          case 'http':
            return _network.request(Map.from(message));
          case 'get_cookies':
            // Cookie 真理源已随 WebView 迁到 JsWebview（按 session 分库）；
            // 返回结构不变，仍是 {cookies: "k=v; k2=v2"}。
            return _webview.getCookies(
              session: message['session'] as String?,
              url: message['url'] as String? ?? '',
            );
          case 'webview_html':
            // 一次性取页：入参（url / overTime|timeout / waitFor / session）与返回
            // 结构（{html, finalUrl} | {error}）一律不变。waitFor 原样透传，归一由
            // JsWebview 内部完成（含 'selector:x' 之类的字符串简写）。
            return _webview.fetchHtml(
              url: message['url'] as String,
              session: message['session'] as String?,
              overTime:
                  ((message['overTime'] ?? message['timeout']) as num?)
                          ?.toInt() ??
                      50,
              waitFor: message['waitFor'],
            );
          case 'webview':
            // 交互会话（留页式验证码流程）：按 function 子分派，见 _handleWebview。
            return _handleWebview(Map.from(message));
          case 'navigateToVideo':
            // 结构化进入（videoId+sources）时没有 url 字段，url 可为 null，
            // 所以这里不再以 url != null 作为进入条件。
            if (onNavigateToVideo != null) {
              final rawSources = message['sources'];
              final sources = rawSources is List
                  ? rawSources
                      .whereType<Map>()
                      .map((m) => Map<String, dynamic>.from(m))
                      .toList()
                  : null;
              // videoUrl 位置参数必填：优先 url，缺省回退 videoId（结构化分支不使用它）
              final url = (message['url'] as String?) ??
                  (message['videoId'] as String?) ??
                  '';
              onNavigateToVideo!(
                url,
                title: message['title'] as String?,
                cover: message['cover'] as String?,
                videoId: message['videoId'] as String?,
                sourceKey: message['sourceKey'] as String?,
                initialSource: (message['initialSource'] as num?)?.toInt(),
                initialEpisode: (message['initialEpisode'] as num?)?.toInt(),
                sources: sources,
              );
            }
          case 'navigateToWebview':
            final url = message['url'] as String?;
            if (url != null && onNavigateToWebview != null) {
              onNavigateToWebview!(url);
            }
          case 'openExternalBrowser':
            final url = message['url'] as String?;
            if (url != null &&
                url.isNotEmpty &&
                onOpenExternalBrowser != null) {
              onOpenExternalBrowser!(url);
            }
          case 'navigateToReader':
            final comicId = message['comicId'] as String? ?? '';
            final comicTitle = message['comicTitle'] as String? ?? '';
            final rawChapters = message['chapters'];
            if (comicId.isEmpty ||
                comicTitle.isEmpty ||
                rawChapters is! List ||
                onNavigateToReader == null) {
              break;
            }
            final chapters = <Map<String, dynamic>>[];
            for (final c in rawChapters) {
              if (c is Map) {
                final m = Map<String, dynamic>.from(c);
                final images = m['images'];
                if (images is List) {
                  m['images'] = images.whereType<String>().toList();
                }
                chapters.add(m);
              }
            }
            onNavigateToReader!(
              comicId,
              comicTitle,
              chapters,
              sourceKey: message['sourceKey'] as String?,
              initialChapter: (message['initialChapter'] as num?)?.toInt() ?? 1,
              initialPage: (message['initialPage'] as num?)?.toInt() ?? 1,
            );
            break;
          case 'navigateToNovelReader':
            final novelId = message['novelId'] as String? ?? '';
            final novelTitle = message['novelTitle'] as String? ?? '';
            final rawNovelChapters = message['chapters'];
            if (novelId.isEmpty ||
                novelTitle.isEmpty ||
                rawNovelChapters is! List ||
                onNavigateToNovelReader == null) {
              break;
            }
            final novelChapters = <Map<String, dynamic>>[];
            for (final c in rawNovelChapters) {
              if (c is Map) {
                novelChapters.add(Map<String, dynamic>.from(c));
              }
            }
            onNavigateToNovelReader!(
              novelId,
              novelTitle,
              novelChapters,
              sourceKey: message['sourceKey'] as String?,
              initialChapter: (message['initialChapter'] as num?)?.toInt() ?? 1,
            );
            break;
          case 'navigateToDescriptor':
            onNavigateToDescriptor?.call(<String, dynamic>{
              'plugin': message['plugin'],
              'method': message['initMethod'],
              'args': message['args'],
              'title': message['title'],
              'actions': message['actions'],
            });
          case 'plugin_history':
            return _handlePluginHistory(Map.from(message));
          case 'plugin_browse_entry':
            final pluginName = message['pluginName'] as String? ?? '';
            final id = message['id'] as String? ?? '';
            onPluginBrowseEntry?.call(pluginName, id);
            return null;
          // ===== 插件存储（PluginSource 的 loadData/loadSetting/saveData/deleteData）=====
          // 命名空间就是插件名：JS 侧 `PluginSource.get key()` 从类名派生，而类名已由
          // 命名链校验为「= 插件名」（见 docs/plugin-storage-spec.md）。
          case 'load_data':
            return GStorage.getSettingByName(
              'plugin_data:${message["key"]}:${message["data_key"]}',
            );
          case 'save_data':
            return GStorage.putSettingByName(
              'plugin_data:${message["key"]}:${message["data_key"]}',
              message['data'],
            );
          case 'delete_data':
            return GStorage.deleteSettingByName(
              'plugin_data:${message["key"]}:${message["data_key"]}',
            );
          case 'load_setting':
            return GStorage.getSettingByName(
              'plugin_setting:${message["key"]}:${message["setting_key"]}',
            );
          case 'save_setting':
            return GStorage.putSettingByName(
              'plugin_setting:${message["key"]}:${message["setting_key"]}',
              message['data'] ?? message['value'],
            );
        }
      }
      return null;
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.js} 处理 JS 消息失败 message=$message',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  // ===== 私有：log =====

  void _log(Map message) {
    final level = message['level'];
    final content = message['message'] ?? '';
    switch (level) {
      case 'error':
        WywLogger().e('${LogTag.js} 插件日志: $content');
      case 'warn':
        WywLogger().w('${LogTag.js} 插件日志: $content');
      case 'info':
        WywLogger().i('${LogTag.js} 插件日志: $content');
    }
  }

  // ===== Plugin Browse History（Hive 后端，插件侧定义 schema） =====

  Future<Map<String, dynamic>> _handlePluginHistory(Map message) async {
    final repo = collectRepository;
    if (repo == null) {
      return {'ok': false, 'error': 'collectRepository not initialized'};
    }
    final fn = message['function'] as String?;
    final pluginName = message['pluginName'] as String? ?? '';
    try {
      switch (fn) {
        case 'upsert':
          await repo.upsert(
            pluginName: pluginName,
            id: message['id'] as String? ?? '',
            title: message['title'] as String? ?? '',
            cover: message['cover'] as String?,
            kv: (message['kv'] as Map?)?.cast<String, dynamic>(),
          );
          return {'ok': true};
        case 'find':
          final e = await repo.find(
            pluginName: pluginName,
            id: message['id'] as String? ?? '',
          );
          return {'ok': true, 'data': e?.toJson()};
        default:
          return {'ok': false, 'error': 'unknown function: $fn'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ===== WebView 交互会话（method: 'webview'）=====

  /// `sendMessage({method: 'webview', function: ...})` 的子分派。
  ///
  /// **派发表**（与 [HtmlRegistry.handleHtmlCallback] / [JsDialog.handleDialogCallback]
  /// 同构：显式列举全部 function，形成自解释的"目录"）：
  ///   - `open`          → [JsWebview.open]：留页 + 按 mode 注入 watcher
  ///   - `exec`          → [JsWebview.exec]：页面内执行任意 JS
  ///   - `getHtml`       → [JsWebview.getPageHtml]：取当前页面 HTML + 地址
  ///   - `getUserAgent`  → [JsWebview.getUserAgent]：取 WebView 实际 UA
  ///   - `fillAndClick`  → [JsWebview.fillAndClick]：回填验证码并提交
  ///   - `awaitImage`    → [JsWebview.awaitCaptchaImage]：等验证码图（dataURL）
  ///   - `awaitGone`     → [JsWebview.awaitCaptchaGone]：等验证通过
  ///   - `close`         → [JsWebview.close]：收尾（保留 / 清理 Cookie、是否立即销毁）
  ///
  /// **字段与返回值**：见各分支。成功一律 `{ok: true, ...}`，失败 `{error:
  /// {message, kind, retryable, status}}`——都直接来自 [JsWebview]，本层只做
  /// 字段收敛（补默认值 / 归一 session），不改语义。
  ///
  /// **默认值在本层收敛**：JS 侧可能省略字段（`undefined` 会到成 null），而
  /// [JsWebview] 的选择器等参数是**非空 String**，因此这里把 null 一律降级为
  /// 空串 / 契约默认值，避免在类型转换处炸掉。
  Object? _handleWebview(Map<String, dynamic> message) {
    final function = message['function'] as String?;
    // 交互类方法（open/exec/...）的 session 是 required 非空：null 归默认会话 ''，
    // 由 JsWebview 内部按空串分库（与重构前 _sessionFor 的默认会话一致）。
    final session = message['session'] as String? ?? '';

    switch (function) {
      case 'open':
        return _webview.open(
          session: session,
          url: message['url'] as String? ?? '',
          mode: message['mode'] as String? ?? 'image',
          captchaXpath: message['captchaXpath'] as String? ?? '',
          inputXpath: message['inputXpath'] as String? ?? '',
          buttonXpath: message['buttonXpath'] as String? ?? '',
          script: message['script'] as String? ?? '',
          timeout: (message['timeout'] as num?)?.toInt() ?? 30,
          // 可选：null = 用 JsWebview 的默认最长寿命
          maxLifetimeMs: (message['maxLifetimeMs'] as num?)?.toInt(),
        );

      case 'exec':
        return _webview.exec(
          session: session,
          js: message['js'] as String? ?? '',
        );

      case 'getHtml':
        return _webview.getPageHtml(session: session);

      case 'getUserAgent':
        return _webview.getUserAgent(session: session);

      case 'fillAndClick':
        return _webview.fillAndClick(
          session: session,
          code: message['code'] as String? ?? '',
          inputXpath: message['inputXpath'] as String? ?? '',
          buttonXpath: message['buttonXpath'] as String? ?? '',
        );

      case 'awaitImage':
        return _webview.awaitCaptchaImage(
          session: session,
          timeout: (message['timeout'] as num?)?.toInt() ?? 30,
        );

      case 'awaitGone':
        return _webview.awaitCaptchaGone(
          session: session,
          timeout: (message['timeout'] as num?)?.toInt() ?? 60,
        );

      case 'close':
        return _webview.close(
          session: session,
          // 默认保留 Cookie：验证刚拿到的 clearance cookie 通常马上要用
          keepCookies: message['keepCookies'] != false,
          dispose: message['dispose'] == true,
        );

      // ===== 未知 function =====
      // 与 html 的 _unknown 一致：记日志 + 返回 null（不抛），避免插件笔误
      // （比如 function 拼错）把整条消息连同引擎调用链一起炸掉。
      default:
        WywLogger().w('${LogTag.js} 未知的 webview function: $function');
        return null;
    }
  }

  /// 释放桥接层持有的外部资源（HTTP + WebView）。JS 引擎销毁时调用。
  void disposeCommon() {
    // 成对释放：JsNetwork 只做 HTTP（无可释放资源，空实现），WebView 会话池在
    // JsWebview 里，必须显式销毁——否则引擎重建时会攒下 WebView2 环境/进程。
    _network.dispose();
    _webview.dispose();
  }
}

/// JS 回调的 Finalizer 包装：避免 JSInvokable 引用泄漏。
class JSAutoFreeFunction {
  final JSInvokable func;

  /// Automatically free the function when it's not used anymore
  JSAutoFreeFunction(this.func) {
    func.dup();
    finalizer.attach(this, func);
  }

  dynamic call(List<dynamic> args) {
    return func(args);
  }

  static final finalizer = Finalizer<JSInvokable>((func) {
    func.destroy();
  });
}
