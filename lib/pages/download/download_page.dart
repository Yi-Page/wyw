import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/download/download_widgets.dart';
import 'package:wyw/pages/video/video_route_args.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/utils/format.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({
    super.key,
    required this.controller,
  });

  final DownloadController controller;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  DownloadController get downloadController => widget.controller;

  /// Expansion state per record key. Kept outside the record snapshots
  /// because the controller replaces them on every refresh tick.
  final Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    downloadController.refreshRecords();
  }

  bool _isExpanded(String recordKey, DownloadRecord record) {
    return _expanded.putIfAbsent(
      recordKey,
      () => record.episodes.values
          .any((e) => e.status != DownloadStatus.completed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('下载管理'),
        actions: [WywAppBarMenuButton(pagePath: '/settings/download/')],
      ),
      body: Observer(builder: (context) {
        final recordKeys = downloadController.recordKeys.toList();
        // Drop expansion state for deleted records, so a re-downloaded
        // media gets a fresh default instead of a stale cached one.
        _expanded.removeWhere((key, _) => !recordKeys.contains(key));
        if (recordKeys.isEmpty) {
          return const Center(
            child: GeneralEmptyState(
              icon: Icons.download_rounded,
              title: '暂无下载内容',
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: recordKeys.length,
          itemBuilder: (context, index) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: _buildRecordCard(recordKeys[index]),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildRecordCard(String recordKey) {
    return Observer(builder: (context) {
      final record = downloadController.getRecordSnapshot(recordKey);
      if (record == null) {
        return const SizedBox.shrink();
      }

      var totalSpeed = 0.0;
      for (final e in record.episodes.values) {
        if (e.status == DownloadStatus.downloading) {
          totalSpeed += downloadController.getSpeed(
            record.mediaId,
            record.pluginName,
            e.episodeNumber,
          );
        }
      }
      final expanded = _isExpanded(recordKey, record);

      return DownloadRecordCard(
        record: record,
        expanded: expanded,
        onToggle: () {
          setState(() => _expanded[recordKey] = !expanded);
        },
        onResumeAll: () {
          downloadController.resumeAllDownloads(
            record.mediaId,
            record.pluginName,
          );
          WywDialog.showToast(message: '已开始恢复下载');
        },
        onDeleteAll: () => _confirmDeleteRecord(record),
        totalSpeed: totalSpeed,
        episodeTileBuilder: () {
          final episodes = record.episodes.values.toList()
            ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
          return episodes.map((ep) => _buildEpisodeTile(record, ep)).toList();
        },
      );
    });
  }

  Widget _buildEpisodeTile(DownloadRecord record, DownloadEpisode episode) {
    return DownloadEpisodeTile(
      episode: episode,
      statusText: _getStatusText(record, episode),
      actions: _getActionButtons(record, episode),
      onPlay: episode.status == DownloadStatus.completed
          ? () => _playEpisode(record, episode)
          : null,
    );
  }

  String _getStatusText(DownloadRecord record, DownloadEpisode episode) {
    switch (episode.status) {
      case DownloadStatus.completed:
        return '已完成 · ${formatBytes(episode.totalBytes)}';
      case DownloadStatus.downloading:
        final speed = downloadController.getSpeed(
          record.mediaId,
          record.pluginName,
          episode.episodeNumber,
        );
        final speedText = speed > 0 ? ' · ${formatSpeed(speed)}' : '';
        return '${(episode.progressPercent * 100).toStringAsFixed(0)}% · '
            '${episode.downloadedSegments}/${episode.totalSegments} 分片$speedText';
      case DownloadStatus.failed:
        return episode.errorMessage.isNotEmpty ? episode.errorMessage : '下载失败';
      case DownloadStatus.paused:
        return '已暂停 · ${(episode.progressPercent * 100).toStringAsFixed(0)}%';
      case DownloadStatus.pending:
        return '排队中';
      case DownloadStatus.resolving:
        return '正在解析视频源';
      default:
        return '';
    }
  }

  List<Widget> _getActionButtons(
      DownloadRecord record, DownloadEpisode episode) {
    final colorScheme = Theme.of(context).colorScheme;
    final buttons = <Widget>[];

    switch (episode.status) {
      case DownloadStatus.completed:
        buttons.add(IconButton(
          icon: Icon(Icons.play_circle_outline,
              size: 20, color: colorScheme.primary),
          onPressed: () => _playEpisode(record, episode),
          tooltip: '播放',
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.downloading:
        buttons.add(IconButton(
          icon: const Icon(Icons.pause_rounded, size: 20),
          onPressed: () => downloadController.pauseDownload(
            record.mediaId,
            record.pluginName,
            episode.episodeNumber,
          ),
          tooltip: '暂停',
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.paused:
        buttons.add(IconButton(
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          onPressed: () => downloadController.retryDownload(
            mediaId: record.mediaId,
            pluginName: record.pluginName,
            episodeNumber: episode.episodeNumber,
          ),
          tooltip: '继续',
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.failed:
        buttons.add(IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () => downloadController.retryDownload(
            mediaId: record.mediaId,
            pluginName: record.pluginName,
            episodeNumber: episode.episodeNumber,
          ),
          tooltip: '重试',
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.pending:
        buttons.add(IconButton(
          icon: Icon(Icons.priority_high, size: 20, color: colorScheme.primary),
          onPressed: () {
            downloadController.priorityDownload(
              mediaId: record.mediaId,
              pluginName: record.pluginName,
              episodeNumber: episode.episodeNumber,
            );
            WywDialog.showToast(message: '已插队优先下载');
          },
          tooltip: '优先下载',
          visualDensity: VisualDensity.compact,
        ));
        break;
      default:
        break;
    }

    buttons.add(IconButton(
      icon: Icon(Icons.delete_outline,
          size: 20, color: colorScheme.onSurfaceVariant),
      onPressed: () => _confirmDeleteEpisode(record, episode),
      tooltip: '删除',
      visualDensity: VisualDensity.compact,
    ));

    return buttons;
  }

  void _playEpisode(DownloadRecord record, DownloadEpisode episode) {
    final localPath = downloadController.getLocalVideoPath(
      record.mediaId,
      record.pluginName,
      episode.episodeNumber,
    );
    if (localPath == null) {
      WywDialog.showToast(message: '本地文件不存在');
      return;
    }

    final title = episode.episodeName.isNotEmpty
        ? episode.episodeName
        : '第${episode.episodeNumber}集';
    // 结构化进入：本地文件作为单源单集（type=local）
    context.pushNamed(
      '/video/',
      arguments: VideoPageRouteArgs(
        videoId: record.mediaId.toString(),
        title: title,
        cover: record.mediaCover,
        sourceKey: record.pluginName,
        initialSource: 0,
        initialEpisode: 0,
        sources: [
          VideoPlaySource(
            name: '本地文件',
            episodes: [
              VideoPlayEpisode(
                name: title,
                path:
                    PlayResourcePath(url: localPath, type: PlayPathType.local),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteEpisode(
      DownloadRecord record, DownloadEpisode episode) async {
    final ok = await WywDialog.showConfirm(
      title: '删除下载',
      message:
          '确定要删除「${episode.episodeName.isNotEmpty ? episode.episodeName : '第${episode.episodeNumber}集'}」的下载文件吗？',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
      cancelTextStyle: TextStyle(color: Theme.of(context).colorScheme.outline),
    );
    if (!ok) return;
    downloadController.deleteEpisode(
      record.mediaId,
      record.pluginName,
      episode.episodeNumber,
    );
  }

  Future<void> _confirmDeleteRecord(DownloadRecord record) async {
    final ok = await WywDialog.showConfirm(
      title: '删除全部下载',
      message: '确定要删除「${record.mediaName}」的所有下载文件吗？',
      confirmText: '删除',
      confirmTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
      cancelTextStyle: TextStyle(color: Theme.of(context).colorScheme.outline),
    );
    if (!ok) return;
    downloadController.deleteRecord(
      record.mediaId,
      record.pluginName,
    );
  }
}
