import 'dart:async';

import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/services/video_source/video_source_service.dart';
import 'package:wyw/services/video_source/webview_video_source_service.dart';

/// 统一解析服务（播放域·解析层）：输入 [PlayResourcePath]，输出最终媒体直链。
///
/// 解析链：
///   - `direct`：无需解析，原样返回；
///   - `resolve`：执行插件方法（plugin/method/args）取真实路径——结果为
///     direct 即完成，为 page 则继续嗅探；
///   - `page`：WebView 资源嗅探；
///   - `local`：不属于解析范畴，原样返回（调用方不应传入）。
///
/// 播放与下载共用本服务；**下载侧不自带任何解析逻辑**，只接收本服务的
/// 成品直链（见 `DownloadController.downloadStructuredEpisode`）。
class ResolutionService {
  ResolutionService({required PluginController pluginController})
      : _pluginController = pluginController;

  final PluginController _pluginController;

  WebViewVideoSourceService? _webviewService;
  StreamSubscription? _logSubscription;

  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// WebView 嗅探日志（视频页调试台消费）。
  Stream<String> get onLog => _logController.stream;

  /// 解析到最终媒体直链。
  ///
  /// [offset] 仅 page 型嗅探时透传给 WebView（页面内视频定位）。
  /// 可能抛出：
  /// - [VideoSourceNotFoundException]：插件缺失 / 解析结果不可用 / 嗅探未命中
  /// - [VideoSourceTimeoutException]：嗅探超时
  /// - [VideoSourceCancelledException]：嗅探被取消
  Future<VideoSource> resolve(PlayResourcePath path, {int offset = 0}) async {
    switch (path.type) {
      case PlayPathType.direct:
      case PlayPathType.local:
        return VideoSource(
          url: path.url,
          offset: offset,
          type: VideoSourceType.online,
        );
      case PlayPathType.resolve:
        final step = await _resolveViaPlugin(path);
        if (step.type == PlayPathType.direct) {
          return VideoSource(
            url: step.url,
            offset: offset,
            type: VideoSourceType.online,
          );
        }
        return _sniff(step.url, offset: offset);
      case PlayPathType.page:
        return _sniff(path.url, offset: offset);
    }
  }

  /// 取消当前正在进行的嗅探（插件解析本身不可取消）。
  void cancel() {
    _webviewService?.cancel();
  }

  /// 释放资源（销毁内部 WebView 实例）。之后可继续调用 [resolve]（惰性重建）。
  Future<void> dispose() async {
    final service = _webviewService;
    _webviewService = null;
    await _logSubscription?.cancel();
    _logSubscription = null;
    if (service != null) {
      await service.dispose();
    }
    if (!_logController.isClosed) {
      await _logController.close();
    }
  }

  /// 执行插件 resolve 方法取真实路径；失败抛 [VideoSourceNotFoundException]。
  Future<PlayResourcePath> _resolveViaPlugin(PlayResourcePath path) async {
    final pluginName = path.plugin;
    final method = path.method;
    if (pluginName == null || pluginName.isEmpty || method == null) {
      throw VideoSourceNotFoundException(
          'resolve 缺少 plugin/method plugin=$pluginName method=$method');
    }
    final plugin = _pluginController.getPlugin(pluginName);
    if (plugin == null || !plugin.isRegistered) {
      throw VideoSourceNotFoundException('插件未注册 plugin=$pluginName');
    }
    try {
      final raw = await plugin.invoke(method, path.args ?? const []);
      final resolved = PlayResourcePath.fromResolveResult(raw);
      if (resolved.type == PlayPathType.resolve || resolved.url.isEmpty) {
        throw VideoSourceNotFoundException(
            '解析结果不可用 plugin=$pluginName method=$method');
      }
      WywLogger().i('${LogTag.player} 插件解析完成 plugin=$pluginName '
          'method=$method type=${resolved.type.value} url=${resolved.url}');
      return resolved;
    } on VideoSourceNotFoundException {
      rethrow;
    } catch (e) {
      WywLogger().e('${LogTag.player} 插件解析失败 plugin=$pluginName method=$method',
          error: e);
      throw VideoSourceNotFoundException(
          '插件执行异常 plugin=$pluginName method=$method');
    }
  }

  /// WebView 嗅探；惰性创建 WebView 实例并转发日志。
  Future<VideoSource> _sniff(String url, {required int offset}) async {
    _webviewService ??= WebViewVideoSourceService();
    await _logSubscription?.cancel();
    _logSubscription = _webviewService!.onLog.listen((log) {
      if (!_logController.isClosed) {
        _logController.add(log);
      }
    });
    return _webviewService!.resolve(url, offset: offset);
  }
}
