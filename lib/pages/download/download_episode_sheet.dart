import 'package:flutter/material.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/dialog/material_bottom_sheet.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/utils/device.dart';

/// 批量选集下载 sheet（照抄 Kazumi 的 `download_episode_sheet.dart`）。
///
/// 与 Kazumi 的唯一差异在**构造参数**：那边收 `road + VideoPageController`
/// 自己去解析下载；wyw 有两个入口（播放页 / 历史页续播），后者没有
/// VideoPageController，所以这里改成宿主无关的契约——传剧集列表、下载任务表
/// 与「下一集怎么下」的回调，UI 与交互一行未改。
class DownloadEpisodeSheet extends StatefulWidget {
  const DownloadEpisodeSheet({
    super.key,
    required this.road,
    required this.roads,
    required this.downloads,
    required this.onDownloadEpisode,
    this.initialEpisodeIndex = 0,
  });

  /// 当前线路 index（0-based）。
  final int road;

  final List<VideoPlaySource> roads;

  /// 本作每集的下载任务（键为 `线路:集数`），用于标记已入队/已缓存的集。
  final Map<String, DownloadEpisode> downloads;

  /// 下载某一集（参数为 0-based 线路 / 集数）。
  final void Function(int sourceIndex, int episodeIndex) onDownloadEpisode;

  /// 打开时滚到哪一集（0-based），通常是正在播的那一集。
  final int initialEpisodeIndex;

  @override
  State<DownloadEpisodeSheet> createState() => _DownloadEpisodeSheetState();
}

class _DownloadEpisodeSheetState extends State<DownloadEpisodeSheet> {
  final GridObserverController _observerController = GridObserverController();

  final Set<int> _selectedEpisodes = {};
  bool _didJumpToPlayingEpisode = false;

  /// 高度范围（**相对窗口**，窗口高度 = 1）。
  ///
  /// 初始 = 最小 = 0.5，可拉高到最高 0.85。父面板（选集面板）高 0.85，
  /// 所以子面板**始终小于父面板**（最高也只到 0.85），不会把选集面板盖掉。
  /// 调用方把 `showAdaptiveBottomSheet` 的 `maxHeightFactor` 设为 1.0，
  /// 让这个比例盒 = 窗口，这里的分数才是真正的窗口比例。
  static const double minHeightFraction = 0.5;
  static const double maxHeightFraction = 0.85;

  /// 面板高度目标（相对窗口）。桌面端拖动不顺手，用头部按钮在
  /// 「初始（0.5）/ 最高（0.8）」之间切换；移动端照常手势拖动。
  double? _sheetSize;

  VideoPlaySource get currentRoadData => widget.roads[widget.road];
  int get episodeCount => currentRoadData.episodes.length;

  /// 本线路已入队/已缓存的集数（0-based）。
  ///
  /// Kazumi 用剧集页 URL 去重；wyw 的 [DownloadEpisode] 没有 URL 字段，改用
  /// 结构化「线路:集数」当键（见 `DownloadController.episodeDownloadsFor`）。
  Set<int> _collectDownloadedEpisodes() {
    final downloaded = <int>{};
    for (var index = 0; index < episodeCount; index++) {
      final task = widget.downloads[episodeDownloadKey(widget.road, index)];
      if (task == null) continue;
      if (task.status == DownloadStatus.completed ||
          task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.pending) {
        downloaded.add(index);
      }
    }
    return downloaded;
  }

  @override
  Widget build(BuildContext context) {
    final downloadedEpisodes = _collectDownloadedEpisodes();
    final selectableEpisodes = <int>[
      for (int i = 1; i <= episodeCount; i++)
        if (!downloadedEpisodes.contains(i - 1)) i,
    ];
    final downloadedCount = episodeCount - selectableEpisodes.length;
    final allSelected = selectableEpisodes.isNotEmpty &&
        _selectedEpisodes.length == selectableEpisodes.length;
    final size =
        (_sheetSize ?? minHeightFraction).clamp(minHeightFraction, maxHeightFraction);
    return DraggableScrollableSheet(
      initialChildSize: size,
      minChildSize: minHeightFraction,
      maxChildSize: maxHeightFraction,
      expand: false,
        builder: (context, scrollController) {
          _observerController.controller = scrollController;
          if (!_didJumpToPlayingEpisode) {
            _didJumpToPlayingEpisode = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await Future<void>.delayed(Duration.zero);
              if (!mounted ||
                  episodeCount == 0 ||
                  !scrollController.hasClients) {
                return;
              }
              final index =
                  widget.initialEpisodeIndex.clamp(0, episodeCount - 1);
              await _observerController.jumpTo(
                index: index,
                isFixedHeight: true,
              );
            });
          }
          return Column(
            children: [
              MaterialBottomSheetHeader(
                title: '下载选集',
                description: downloadedCount > 0
                    ? '$episodeCount 集 · 已下载 $downloadedCount 集'
                    : '共 $episodeCount 集',
                onClose: isDesktop()
                    ? null
                    : () => Navigator.of(context).pop(),
                trailing: isDesktop()
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '初始高度',
                            onPressed: () =>
                                setState(() => _sheetSize = minHeightFraction),
                            icon: const Icon(Icons.close_fullscreen_rounded),
                          ),
                          IconButton(
                            tooltip: '最高高度',
                            onPressed: () =>
                                setState(() => _sheetSize = maxHeightFraction),
                            icon: const Icon(Icons.open_in_full_rounded),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      )
                    : null,
              ),
              Expanded(
                child: GridViewObserver(
                  controller: _observerController,
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent: 56,
                    ),
                    itemCount: episodeCount,
                    itemBuilder: (context, index) {
                      final episodeNumber = index + 1;
                      final isDownloaded = downloadedEpisodes.contains(index);
                      final isSelected =
                          _selectedEpisodes.contains(episodeNumber);
                      return _EpisodeTile(
                        identifier: currentRoadData.episodes[index].name,
                        isDownloaded: isDownloaded,
                        isSelected: isSelected,
                        onTap: isDownloaded
                            ? null
                            : () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedEpisodes.remove(episodeNumber);
                                  } else {
                                    _selectedEpisodes.add(episodeNumber);
                                  }
                                });
                              },
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: selectableEpisodes.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _selectedEpisodes.clear();
                                  if (!allSelected) {
                                    _selectedEpisodes
                                        .addAll(selectableEpisodes);
                                  }
                                });
                              },
                        // Reserve the widest label to keep the action width stable.
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Opacity(opacity: 0, child: Text('取消全选')),
                            Text(allSelected ? '取消全选' : '全选'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: _selectedEpisodes.isEmpty
                              ? null
                              : () => _startBatchDownload(context),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(_selectedEpisodes.isEmpty
                              ? '选择集数'
                              : '下载 ${_selectedEpisodes.length} 集'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
  }

  void _startBatchDownload(BuildContext context) {
    Navigator.pop(context);

    final sortedEpisodes = _selectedEpisodes.toList()..sort();

    for (final episodeNumber in sortedEpisodes) {
      // 逐集入队：宿主负责「预创建 → 解析 → 入队」，这里不等每一集解析完。
      widget.onDownloadEpisode(widget.road, episodeNumber - 1);
    }

    WywDialog.showToast(
      message: '已添加 ${sortedEpisodes.length} 集到下载队列，可在下载管理中查看',
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.identifier,
    required this.isDownloaded,
    required this.isSelected,
    this.onTap,
  });

  final String identifier;
  final bool isDownloaded;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isDownloaded
        ? colorScheme.surfaceContainerLow
        : isSelected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerLow;
    final foregroundColor = isDownloaded
        ? colorScheme.outline
        : isSelected
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(isSelected ? 28 : 16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(isSelected ? 28 : 16),
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    identifier,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: foregroundColor),
                  ),
                ),
              ),
              if (isDownloaded)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    Icons.download_done_rounded,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                )
              else
                Positioned(
                  top: 4,
                  right: 4,
                  child: AnimatedScale(
                    scale: isSelected ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
