import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:wyw/js/js_extends/html/html_registry.dart';
import 'package:wyw/js/js_extends/js_codec.dart';
import 'package:wyw/js/js_extends/js_dialog.dart';
import 'package:wyw/js/js_extends/js_network.dart';
import 'package:wyw/repositories/plugin_history_repository.dart';
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
///   - [JsNetwork] — HTTP 请求 + WebView 取页面 HTML
///   - 直接处理：log / clip / platform / delay（无需工具类）
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

  /// 插件浏览历史仓库（由宿主应用在启动时注入）。
  ///
  /// JS 端 `PluginBrowse.*` API 走 `sendMessage({method:'plugin_history', ...})` 路由到此仓库。
  /// 默认 null（即 no-op）。
  static PluginHistoryRepository? pluginHistoryRepository;

  /// 插件点击浏览历史条目时的回调（由 UI 层注册）。
  /// 应用只负责"用户点了 id"，插件自己解析 kv 决定跳详情页/播放页。
  /// 通过 `sendMessage({method:'plugin_browse_entry', id})` 触发。
  static void Function(String pluginName, String id)? onPluginBrowseEntry;

  final _html = HtmlRegistry();
  final _codec = JsCodec();
  final _dialog = JsDialog();
  final _network = JsNetwork();

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
            return _network.getCookies(Map.from(message));
          case 'webview_html':
            return _network.webviewHtml(Map.from(message));
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
            if (url != null && url.isNotEmpty && onOpenExternalBrowser != null) {
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

  // ===== Plugin Browse History（JSON 后端，插件侧定义 schema） =====

  Future<Map<String, dynamic>> _handlePluginHistory(Map message) async {
    final repo = pluginHistoryRepository;
    if (repo == null) {
      return {'ok': false, 'error': 'pluginHistoryRepository not initialized'};
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

  /// 释放桥接层持有的外部资源（WebView 等）。JS 引擎销毁时调用。
  void disposeCommon() {
    _network.dispose();
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
