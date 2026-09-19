import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/services/video_source/resolution_service.dart';
import 'package:wyw/pages/video/video_route_args.dart';

/// 播放方式弹窗的用户选择。
enum PlayIntentChoice {
  /// 直接播放（在线，不与下载合流）
  directPlay,

  /// 合流播放（边下边播）
  mergePlay,

  /// 只下载，不进入播放
  downloadOnly,

  /// 暂不播放（关闭弹窗不做事）
  none,
}

/// 决策结果：进播放页的方式 + 静默代理挂靠开关。
class PlayIntentDecision {
  final VideoPlayMode mode;

  /// 用户明确选择「直接播放」时为 false，保证与「合流播放」语义可区分。
  final bool allowProxyPlayback;

  const PlayIntentDecision(this.mode, {this.allowProxyPlayback = true});
}

/// 播放方式决策弹窗（决策层的 UI 出口）。
///
/// 选项可用性由状态决定：
///   - 有进行中下载任务：合流推荐（可免解析直用任务直链），「只下载」置灰；
///   - 全新内容：四项全可用。
/// 返回 null（下滑/关闭）等同 [PlayIntentChoice.none]。
Future<PlayIntentChoice?> showPlayIntentDialog(
  BuildContext context, {
  required String episodeName,
  required String statusLine,
  required bool downloadAvailable,
}) {
  Widget option({
    required IconData icon,
    required String title,
    String? subtitle,
    required PlayIntentChoice value,
    bool enabled = true,
  }) {
    final tile = ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null || subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      enabled: enabled,
      onTap: () => Navigator.of(context).pop(value),
    );
    return enabled ? tile : Opacity(opacity: 0.4, child: tile);
  }

  return showAdaptiveBottomSheet<PlayIntentChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      // 矮屏/横屏下内容可能超出可用高度，包一层滚动避免 RenderFlex 溢出
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择播放方式',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  episodeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            option(
              icon: Icons.play_circle_outline,
              title: '直接播放',
              subtitle: '在线观看，不与下载关联',
              value: PlayIntentChoice.directPlay,
            ),
            option(
              icon: Icons.download_done_outlined,
              title: '合流播放',
              subtitle: statusLine.isEmpty ? '边下边播，观看进度即下载进度' : statusLine,
              value: PlayIntentChoice.mergePlay,
            ),
            option(
              icon: Icons.download_outlined,
              title: '只下载',
              subtitle: downloadAvailable ? '不进入播放' : '该集已在下载中',
              value: PlayIntentChoice.downloadOnly,
              enabled: downloadAvailable,
            ),
            option(
              icon: Icons.close,
              title: '暂不播放',
              value: PlayIntentChoice.none,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// 播放方式决策层（进播放页之前，全部零解析零网络查询）。
///
/// 决策序：
///   ① type=local → 本地播放；
///   ② 身份查下载已完成 → 本地播放；
///   ③ 有缓存直链（历史合并产物）→ 在线播放（不弹窗）；
///   ④ 有进行中下载任务 → 弹窗（合流推荐，可直用任务直链免解析）；
///   ⑤ 全新内容 → 弹窗（四项全可用）。
///
/// 「只下载」在本层执行：解析（唯一在播放页之外发生的解析）→ 建任务 →
/// toast，不进入播放页。
abstract final class PlayIntentDecider {
  /// 进行中 = 未到终态（completed/failed/paused 之外）。
  static bool _isActive(int status) =>
      status == DownloadStatus.pending ||
      status == DownloadStatus.resolving ||
      status == DownloadStatus.downloading;

  /// 决策并执行（弹窗/只下载副作用都在此完成）。
  ///
  /// 返回进播放页时应使用的 [PlayIntentDecision]；返回 null 表示不进入
  /// 播放页（用户选了「暂不播放」，或「只下载」已完成下载动作）。
  static Future<PlayIntentDecision?> decide({
    required BuildContext context,
    required PlayResourcePath path,
    required String sourceKey,
    required String videoId,
    required int sourceIndex,
    required int episodeIndex,
    required String episodeName,
    required String sourceName,
    required String videoTitle,
    required String videoCover,
    required String cachedUrl,
  }) async {
    // ① 本地资源
    if (path.type == PlayPathType.local) {
      return const PlayIntentDecision(VideoPlayMode.local);
    }

    final downloadController = inject<DownloadController>();
    // ② 已下载完成 → 本地播放
    final localPath = downloadController.findLocalVideoPathByIdentity(
      sourceKey: sourceKey,
      videoId: videoId,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
    );
    if (localPath != null && localPath.isNotEmpty) {
      return const PlayIntentDecision(VideoPlayMode.local);
    }

    // ③ 有缓存直链 → 在线播放，不弹窗
    if (cachedUrl.isNotEmpty) {
      return const PlayIntentDecision(VideoPlayMode.online);
    }

    // ④/⑤ 需要用户选择
    final taskEpisode = downloadController.findEpisodeByIdentity(
      sourceKey: sourceKey,
      videoId: videoId,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
    );
    final inProgress = taskEpisode != null && _isActive(taskEpisode.status);
    final statusLine = inProgress
        ? '正在下载 ${(taskEpisode.progressPercent * 100).toStringAsFixed(0)}%'
        : '';

    final choice = await showPlayIntentDialog(
      context,
      episodeName: episodeName,
      statusLine: statusLine,
      downloadAvailable: !inProgress,
    );

    switch (choice) {
      case PlayIntentChoice.directPlay:
        // 明确「直接播放」：禁用静默代理挂靠，与「合流播放」语义可区分
        return const PlayIntentDecision(VideoPlayMode.online,
            allowProxyPlayback: false);
      case PlayIntentChoice.mergePlay:
        return const PlayIntentDecision(VideoPlayMode.merge);
      case PlayIntentChoice.downloadOnly:
        await _downloadOnly(
          path: path,
          sourceKey: sourceKey,
          videoId: videoId,
          sourceIndex: sourceIndex,
          episodeIndex: episodeIndex,
          episodeName: episodeName,
          sourceName: sourceName,
          videoTitle: videoTitle,
          videoCover: videoCover,
          cachedUrl: cachedUrl,
        );
        return null;
      case PlayIntentChoice.none:
      case null:
        return null;
    }
  }

  /// 「只下载」：解析（唯一在播放页之外发生的解析）→ 建任务 → toast。
  ///
  /// 生命周期三段式：预创建（resolving，下载页立即可见）→ 解析 →
  /// 入队（downloading）/ 标记失败。
  static Future<void> _downloadOnly({
    required PlayResourcePath path,
    required String sourceKey,
    required String videoId,
    required int sourceIndex,
    required int episodeIndex,
    required String episodeName,
    required String sourceName,
    required String videoTitle,
    required String videoCover,
    required String cachedUrl,
  }) async {
    final downloadController = inject<DownloadController>();
    var mediaUrl = cachedUrl;
    final needsResolve = mediaUrl.isEmpty && path.type != PlayPathType.direct;
    if (needsResolve) {
      await downloadController.prepareStructuredEpisode(
        sourceKey: sourceKey,
        videoId: videoId,
        title: videoTitle,
        cover: videoCover,
        sourceIndex: sourceIndex,
        episodeIndex: episodeIndex,
        episodeName: episodeName,
        sourceName: sourceName,
      );
    } else if (mediaUrl.isEmpty) {
      mediaUrl = path.url;
    }
    if (needsResolve) {
      final resolver =
          ResolutionService(pluginController: inject<PluginController>());
      try {
        mediaUrl = (await resolver.resolve(path)).url;
      } catch (e) {
        WywLogger()
            .w('${LogTag.download} 下载前解析播放地址失败 name=$episodeName', error: e);
        await downloadController.failPreparedEpisode(
          sourceKey: sourceKey,
          videoId: videoId,
          sourceIndex: sourceIndex,
          episodeIndex: episodeIndex,
          message: '解析播放地址失败',
        );
        WywDialog.showToast(message: '解析播放地址失败，无法下载');
        return;
      } finally {
        await resolver.dispose();
      }
    }
    final ok = await downloadController.downloadStructuredEpisode(
      sourceKey: sourceKey,
      videoId: videoId,
      title: videoTitle,
      cover: videoCover,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      sourceName: sourceName,
      resolvedUrl: mediaUrl,
    );
    WywDialog.showToast(message: ok ? '已加入下载队列' : '下载失败');
  }
}
