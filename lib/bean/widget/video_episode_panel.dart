import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 通用选集/线路面板（纯展示组件，不含播放逻辑）。
///
/// 复用于：
///   - 播放页右侧抽屉 / 下方 tab（video_page.dart，嵌进 `sideTabBody`/`tabBody`）
///   - 历史页点卡片后的选集弹窗（history_card.dart，包进 bottom sheet）
///
/// 内部维护「当前显示的线路」（visibleRoad）；点线路只切换显示，
/// 点集数才回调 [onEpisodeTap]，由调用方决定后续行为（播放/进入播放页）。
class VideoEpisodePanel extends StatefulWidget {
  const VideoEpisodePanel({
    super.key,
    required this.title,
    required this.sources,
    this.currentSourceIndex = 0,
    this.currentEpisodeIndex = 0,
    required this.onEpisodeTap,
    this.onDownloadEpisode,
    this.sourceKey,
    this.videoId,
  });

  final String title;
  final List<VideoPlaySource> sources;

  /// 当前正在播放/上次观看的线路与集（0-based，用于高亮）。
  final int currentSourceIndex;
  final int currentEpisodeIndex;

  /// 点击某集（参数为 0-based sourceIndex / episodeIndex）。
  final void Function(int sourceIndex, int episodeIndex) onEpisodeTap;

  /// 点击某集的下载按钮（参数为 0-based sourceIndex / episodeIndex）；
  /// 为 null 时不显示下载按钮。
  final void Function(int sourceIndex, int episodeIndex)? onDownloadEpisode;

  /// 结构化身份（与 [onDownloadEpisode] 同时提供时，面板可回显每集下载状态）。
  final String? sourceKey;
  final String? videoId;

  @override
  State<VideoEpisodePanel> createState() => _VideoEpisodePanelState();
}

class _VideoEpisodePanelState extends State<VideoEpisodePanel> {
  /// 当前显示的线路（0-based）。
  int _visibleRoad = 0;

  final ScrollController _scrollController = ScrollController();

  static const double _gridMainAxisExtent = 70;
  static const double _gridMainAxisSpacing = 5;
  static const int _gridCrossAxisCount = 3;

  @override
  void initState() {
    super.initState();
    // 打开面板默认显示当前播放（或上次播放）的线路
    final sources = widget.sources;
    if (sources.isNotEmpty) {
      _visibleRoad = widget.currentSourceIndex.clamp(0, sources.length - 1);
    }
    // 首次布局后滚动定位到当前播放/上次播放的集
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动 GridView 定位到当前（或上次播放）的集。
  void _scrollToCurrent() {
    if (!mounted || !_scrollController.hasClients) return;
    final sources = widget.sources;
    if (sources.isEmpty) return;
    final roadIndex = _visibleRoad.clamp(0, sources.length - 1);
    final episodes = sources[roadIndex].episodes;
    if (episodes.isEmpty) return;
    final targetIndex =
        widget.currentEpisodeIndex.clamp(0, episodes.length - 1);
    // 3 列网格：目标集所在行 = index ~/ 3；每行高度 = mainAxisExtent + mainAxisSpacing
    final row = targetIndex ~/ _gridCrossAxisCount;
    final rowHeight = _gridMainAxisExtent + _gridMainAxisSpacing;
    final target = (row * rowHeight).toDouble();
    final max = _scrollController.position.maxScrollExtent;
    // 居中一点：减去可视高度一半，再夹取到合法范围
    final viewport = _scrollController.position.viewportDimension;
    final offset =
        (target - viewport / 2 + _gridMainAxisExtent / 2).clamp(0.0, max);
    _scrollController.jumpTo(offset);
  }

  String _sourceName(int index) {
    final sources = widget.sources;
    if (index >= 0 && index < sources.length) {
      return '${sources[index].name} ';
    }
    return '播放线路${index + 1} ';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMenuBar(context),
        const Divider(height: 0.5),
        Expanded(child: _buildMenuBody(context)),
      ],
    );
  }

  /// 顶部条：标题 + 线路选择。
  Widget _buildMenuBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(' 合集 '),
          Expanded(
            child: Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 10),
          MenuAnchor(
            consumeOutsideTap: true,
            builder: (_, MenuController controller, __) {
              return SizedBox(
                height: 34,
                child: TextButton(
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                  ),
                  onPressed: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  child: Text(
                    _sourceName(_visibleRoad),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );
            },
            menuChildren: List<MenuItemButton>.generate(
              widget.sources.length,
              (int i) => MenuItemButton(
                onPressed: () {
                  // 切换线路只更新当前显示的集数列表，不触发播放。
                  setState(() {
                    _visibleRoad = i;
                  });
                },
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _sourceName(i),
                      style: TextStyle(
                        color: i == _visibleRoad
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 选集 GridView：当前线路的全部集。
  Widget _buildMenuBody(BuildContext context) {
    final sources = widget.sources;
    if (sources.isEmpty) {
      return const Center(child: Text('暂无剧集'));
    }
    final roadIndex = _visibleRoad.clamp(0, sources.length - 1);
    final road = sources[roadIndex];
    final episodes = road.episodes;
    final currentSource = widget.currentSourceIndex;
    final currentEpisode = widget.currentEpisodeIndex;
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 16, left: 8, right: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 5,
        mainAxisExtent: 70,
      ),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final ep = episodes[index];
        final bool selected =
            currentSource == roadIndex && currentEpisode == index;
        final String label = ep.name.isNotEmpty ? ep.name : '第${index + 1}集';
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: Theme.of(context).colorScheme.onInverseSurface,
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.hardEdge,
            child: InkWell(
              onTap: () => widget.onEpisodeTap(roadIndex, index),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (selected)
                          Icon(Icons.play_circle_fill,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (widget.onDownloadEpisode != null)
                          Observer(builder: (context) {
                            return _buildDownloadBadge(
                                context, roadIndex, index);
                          }),
                      ],
                    ),
                    if (ep.positionMs > 0) ..._buildProgressText(context, ep),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 每集下载状态角标：已完成✓ / 下载中% / 失败!（点击重试）/ 排队，
  /// 无任务时显示下载图标。读 DownloadController.recordByKey（Observable）。
  Widget _buildDownloadBadge(
      BuildContext context, int sourceIndex, int episodeIndex) {
    final colorScheme = Theme.of(context).colorScheme;
    final videoId = widget.videoId ?? '';
    final sourceKey = widget.sourceKey ?? '';
    DownloadEpisode? episode;
    if (videoId.isNotEmpty) {
      final plugin = sourceKey.isEmpty ? 'wyw' : sourceKey;
      final record = inject<DownloadController>()
          .getRecordSnapshot('${plugin}_${videoId.hashCode}');
      episode =
          record?.episodes[structuredEpisodeNumber(sourceIndex, episodeIndex)];
    }

    // 无任务：普通下载图标
    if (episode == null) {
      return InkWell(
        onTap: () => widget.onDownloadEpisode!(sourceIndex, episodeIndex),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.download_outlined,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    switch (episode.status) {
      case DownloadStatus.completed:
        return InkWell(
          onTap: () => widget.onDownloadEpisode!(sourceIndex, episodeIndex),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child:
                Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
          ),
        );
      case DownloadStatus.downloading:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: episode.progressPercent > 0 ? episode.progressPercent : null,
            strokeWidth: 2,
          ),
        );
      case DownloadStatus.resolving:
      case DownloadStatus.pending:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.failed:
      case DownloadStatus.paused:
        return InkWell(
          onTap: () => widget.onDownloadEpisode!(sourceIndex, episodeIndex),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              episode.status == DownloadStatus.failed
                  ? Icons.error_outline
                  : Icons.pause_circle_outline,
              size: 14,
              color: episode.status == DownloadStatus.failed
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        );
      default:
        return InkWell(
          onTap: () => widget.onDownloadEpisode!(sourceIndex, episodeIndex),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.download_outlined,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        );
    }
  }

  List<Widget> _buildProgressText(BuildContext context, VideoPlayEpisode ep) {
    final s = (ep.positionMs / 1000).round();
    final m = s ~/ 60;
    final sec = s % 60;
    final pos = '$m:${sec.toString().padLeft(2, '0')}';
    final label = ep.durationMs > 0
        ? '看到 $pos / ${(ep.durationMs / 1000).round() ~/ 60}:${((ep.durationMs / 1000).round() % 60).toString().padLeft(2, '0')}'
        : '看到 $pos';
    return [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    ];
  }
}
