import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/history/history_progress_summary.dart'
    show formatHistoryPosition;
import 'package:wyw/services/storage/video_play_model.dart';

class EpisodeSelectionPanel extends StatefulWidget {
  const EpisodeSelectionPanel({
    super.key,
    required this.title,
    required this.roads,
    required this.selectedRoad,
    required this.selectedEpisode,
    required this.onEpisodeSelected,
    required this.downloads,
    this.onDownload,
    this.isOffline = false,
    this.isPlaying = false,
    this.disableAnimations = false,
    this.currentPositionMs = 0,
    this.currentDurationMs = 0,
  });

  final String title;
  final List<VideoPlaySource> roads;
  final int selectedRoad;
  final int selectedEpisode;
  final void Function(int episode, int road) onEpisodeSelected;
  final ValueChanged<int>? onDownload;
  final Map<String, DownloadEpisode> downloads;
  final bool isOffline;
  final bool isPlaying;
  final bool disableAnimations;

  /// 当前正在播放那一集的**实时**位置/时长（毫秒）。
  ///
  /// 只在 `(selectedRoad, selectedEpisode)` 这一行生效，其余行用集对象里持久化的
  /// 值（`VideoPlayEpisode.positionMs/durationMs`，进入播放页时已从历史回填）。
  /// 播放页把这两个值放在 `Observer` 里读取，因此进度条会随播放实时推进。
  final int currentPositionMs;
  final int currentDurationMs;

  @override
  EpisodeSelectionPanelState createState() => EpisodeSelectionPanelState();
}

class EpisodeSelectionPanelState extends State<EpisodeSelectionPanel> {
  final _scrollController = ScrollController();
  late final _observerController =
      ListObserverController(controller: _scrollController)
        ..cacheJumpIndexOffset = false;
  /// 当前显示的线路；越界的选中线路（历史记录里线路数变少）夹到合法范围，
  /// 否则 `road` 取到 null 会直接显示"这条线路暂无剧集"。
  late int _visibleRoad =
      widget.selectedRoad.clamp(0, math.max(0, widget.roads.length - 1));

  bool get _canLocate =>
      widget.selectedRoad >= 0 &&
      widget.selectedRoad < widget.roads.length &&
      widget.selectedEpisode > 0 &&
      widget.selectedEpisode <=
          widget.roads[widget.selectedRoad].episodes.length;

  double get _toolbarHeight =>
      math.max(56, MediaQuery.textScalerOf(context).scale(20) + 8);

  /// 一键回到列表顶部（连同标题与线路选择器一起滚回去）。
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
  }

  void _selectRoad(int road) {
    if (_visibleRoad == road) return;
    setState(() => _visibleRoad = road);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  void initState() {
    super.initState();
    // 打开即滚到上次看到的那一集：宿主（播放页选集 tab / 历史页选集弹窗）都靠
    // 这一句，不必各自调一次。已经可见时 revealCurrentEpisode 会直接返回。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) revealCurrentEpisode();
    });
  }

  /// 定位到当前观看的那一集（滚动到工具栏下沿）。
  ///
  /// 面板**首次布局会自动调一次**，因此历史页的选集弹窗、播放页的选集 tab
  /// 都不用在宿主里各写一遍。
  Future<void> revealCurrentEpisode() async {
    if (!_canLocate) return;
    if (_visibleRoad != widget.selectedRoad) {
      setState(() => _visibleRoad = widget.selectedRoad);
    }
    // Wait for the observer to bind the new road's sliver after layout.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_scrollController.hasClients ||
        !_canLocate ||
        _visibleRoad != widget.selectedRoad) {
      return;
    }

    final index = widget.selectedEpisode - 1;
    final toolbarHeight = _toolbarHeight;
    final item = _observerController.observeItem(index: index);
    if (item != null) {
      final top = item.renderObject
          .localToGlobal(Offset.zero, ancestor: item.viewport)
          .dy;
      if (top >= toolbarHeight &&
          top + item.renderObject.size.height <= item.viewport.size.height) {
        return;
      }
    }
    await _observerController.jumpTo(
      index: index,
      offset: (_) => toolbarHeight,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final road = _visibleRoad >= 0 && _visibleRoad < widget.roads.length
        ? widget.roads[_visibleRoad]
        : null;
    final count = road?.episodes.length ?? 0;

    return LayoutBuilder(builder: (context, constraints) {
      final textScaler = MediaQuery.textScalerOf(context);
      return ListViewObserver(
        controller: _observerController,
        child: Scrollbar(
          controller: _scrollController,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.title.isEmpty ? '剧集列表' : widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _RoadSelector(
                        roads: widget.roads,
                        visibleRoad: _visibleRoad,
                        isOffline: widget.isOffline,
                        onChanged: _selectRoad,
                        disableAnimations: widget.disableAnimations,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _EpisodeToolbar(
                  height: _toolbarHeight,
                  color: colors.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            textScaler.scale(14) > 21 ||
                                    constraints.maxWidth < 320
                                ? '$count 集'
                                : widget.isOffline
                                    ? '已缓存 · $count 集'
                                    : '全部剧集 · $count 集',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '定位当前集',
                          onPressed: _canLocate ? revealCurrentEpisode : null,
                          icon: const Icon(Icons.my_location_rounded, size: 20),
                        ),
                        IconButton(
                          tooltip: '回到顶部',
                          onPressed: _scrollToTop,
                          icon: const Icon(
                            Icons.vertical_align_top_rounded,
                            size: 20,
                          ),
                        ),
                        if (!widget.isOffline)
                          IconButton.filledTonal(
                            tooltip: '缓存剧集',
                            onPressed: count > 0 && widget.onDownload != null
                                ? () => widget.onDownload!(_visibleRoad)
                                : null,
                            icon: const Icon(Icons.download_rounded, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (count == 0)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: GeneralEmptyState(
                    icon: Icons.video_library_outlined,
                    title: '这条线路暂无剧集',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverList.builder(
                    itemCount: count,
                    itemBuilder: (context, index) {
                      final episode = index + 1;
                      final ep = road!.episodes[index];
                      final name = index < road.episodes.length &&
                              ep.name.trim().isNotEmpty
                          ? ep.name
                          : '第$episode集';
                      final isCurrent = _visibleRoad == widget.selectedRoad &&
                          episode == widget.selectedEpisode;
                      // 当前集用实时值（> 0 时），其余集用持久化的值
                      final positionMs =
                          isCurrent && widget.currentPositionMs > 0
                              ? widget.currentPositionMs
                              : ep.positionMs;
                      final durationMs =
                          isCurrent && widget.currentDurationMs > 0
                              ? widget.currentDurationMs
                              : ep.durationMs;
                      return _EpisodeRow(
                        key: ValueKey('$_visibleRoad:$episode'),
                        name: name,
                        first: index == 0,
                        last: index == count - 1,
                        selected: isCurrent,
                        isPlaying: widget.isPlaying,
                        isOffline: widget.isOffline,
                        positionMs: positionMs,
                        durationMs: durationMs,
                        download: widget
                            .downloads[episodeDownloadKey(_visibleRoad, index)],
                        disableAnimations: widget.disableAnimations,
                        onTap: () =>
                            widget.onEpisodeSelected(episode, _visibleRoad),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _EpisodeToolbar extends SliverPersistentHeaderDelegate {
  const _EpisodeToolbar({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      // Fill minExtent even when desktop controls use a smaller touch target.
      SizedBox.expand(child: ColoredBox(color: color, child: child));

  @override
  bool shouldRebuild(covariant _EpisodeToolbar oldDelegate) =>
      height != oldDelegate.height ||
      color != oldDelegate.color ||
      child != oldDelegate.child;
}

class _RoadSelector extends StatefulWidget {
  const _RoadSelector({
    required this.roads,
    required this.visibleRoad,
    required this.isOffline,
    required this.onChanged,
    required this.disableAnimations,
  });

  final List<VideoPlaySource> roads;
  final int visibleRoad;
  final bool isOffline;
  final ValueChanged<int> onChanged;
  final bool disableAnimations;

  @override
  State<_RoadSelector> createState() => _RoadSelectorState();
}

class _RoadSelectorState extends State<_RoadSelector> {
  final _focusNode = FocusNode(debugLabel: 'Playback road selector');
  FocusNode? _focusBeforeOpen;
  bool _pointerActivation = false;

  String _name(int index) => index >= 0 && index < widget.roads.length
      ? (widget.roads[index].name.trim().isEmpty
          ? '播放线路 ${index + 1}'
          : widget.roads[index].name)
      : '暂无线路';

  void _toggleMenu(MenuController controller) {
    final pointerActivation = _pointerActivation;
    _pointerActivation = false;
    if (controller.isOpen) {
      controller.close();
      return;
    }
    final previousFocus = FocusManager.instance.primaryFocus;
    _focusBeforeOpen =
        pointerActivation && previousFocus == _focusNode ? null : previousFocus;
    controller.open();
  }

  void _handleClose() {
    if (!mounted) return;
    final previousFocus = _focusBeforeOpen;
    _focusBeforeOpen = null;
    if (previousFocus == null ||
        previousFocus.context?.mounted != true ||
        !previousFocus.canRequestFocus) {
      _focusNode.unfocus(
          disposition: UnfocusDisposition.previouslyFocusedChild);
      return;
    }
    if (previousFocus is FocusScopeNode) {
      // Do not restore the scope's last child: it may be this menu button.
      previousFocus.requestScopeFocus();
    } else {
      previousFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildMenuItem(int index, double width) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final road = widget.roads[index];
    final selected = index == widget.visibleRoad;
    final last = index == widget.roads.length - 1;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 2),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: MenuItemButton(
          key: ValueKey('road-option-$index'),
          onPressed: () => widget.onChanged(index),
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(width, 56)),
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: WidgetStatePropertyAll(
              selected ? colors.secondaryContainer : colors.surfaceContainerLow,
            ),
            foregroundColor: WidgetStatePropertyAll(
              selected ? colors.onSecondaryContainer : colors.onSurface,
            ),
            textStyle: WidgetStatePropertyAll(
              theme.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: selected
                  ? BorderRadius.circular(20)
                  : BorderRadius.vertical(
                      top: Radius.circular(index == 0 ? 20 : 4),
                      bottom: Radius.circular(last ? 20 : 4),
                    ),
            )),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name(index), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '${road.episodes.length} 集',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canSwitch = widget.roads.length > 1;
    final reduceMotion =
        widget.disableAnimations || MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);

    return LayoutBuilder(builder: (context, constraints) {
      final width =
          math.min(constraints.maxWidth, MediaQuery.sizeOf(context).width - 32);
      return MenuAnchor(
        childFocusNode: _focusNode,
        crossAxisUnconstrained: false,
        consumeOutsideTap: true,
        animated: !reduceMotion,
        onClose: _handleClose,
        alignmentOffset: const Offset(0, 8),
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainer),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          )),
          minimumSize: WidgetStatePropertyAll(Size(width, 0)),
          maximumSize: WidgetStatePropertyAll(Size(
              width, math.min(400, MediaQuery.sizeOf(context).height - 32))),
          visualDensity: VisualDensity.standard,
        ),
        menuChildren: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text(
              '选择播放线路',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < widget.roads.length; i++)
            _buildMenuItem(i, width - 16),
        ],
        builder: (context, controller, child) {
          final open = controller.isOpen;
          final foreground =
              open ? colors.onSecondaryContainer : colors.onSurface;
          return Semantics(
            button: canSwitch,
            expanded: canSwitch ? open : null,
            label: canSwitch ? '切换播放线路' : null,
            child: Material(
              animationDuration: duration,
              color:
                  open ? colors.secondaryContainer : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(open ? 16 : 20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                focusNode: _focusNode,
                onTapUp: canSwitch ? (_) => _pointerActivation = true : null,
                onTap: canSwitch ? () => _toggleMenu(controller) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isOffline ? '离线观看' : '播放线路',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: foreground),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _name(widget.visibleRoad),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canSwitch) ...[
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          child: Icon(Icons.keyboard_arrow_down_rounded,
                              color: foreground),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    super.key,
    required this.name,
    required this.first,
    required this.last,
    required this.selected,
    required this.isPlaying,
    required this.isOffline,
    required this.disableAnimations,
    required this.onTap,
    this.download,
    this.positionMs = 0,
    this.durationMs = 0,
  });

  final String name;
  final bool first;
  final bool last;
  final bool selected;
  final bool isPlaying;
  final bool isOffline;
  final bool disableAnimations;
  final VoidCallback onTap;
  final DownloadEpisode? download;

  /// 该集观看位置/总时长（毫秒）；0 表示未知。
  final int positionMs;
  final int durationMs;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this);

  bool get _reduceMotion =>
      widget.disableAnimations || MediaQuery.disableAnimationsOf(context);

  void _setPressed(bool pressed) {
    final target = pressed ? 1.0 : 0.0;
    if (_reduceMotion) {
      _press.value = target;
      return;
    }
    _press.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 500,
        ratio: 0.8,
      ),
      _press.value,
      target,
      _press.velocity,
    ));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  /// 观看进度文案：`看到 12:34 / 45:00（28%）` / `看到 12:34` / `时长 45:00`。
  ///
  /// 进度用**百分比**表达（不再单独画进度条）；看完了也照常显示
  /// `（100%）`，不做"已看完"之类的特殊文案。位置与时长都未知（没看过、
  /// 时长也没记录）时返回 null，该行不显示这一项。
  static String? _watchLabel(int positionMs, int durationMs) {
    if (positionMs <= 0 && durationMs <= 0) return null;
    if (positionMs > 0 && durationMs > 0) {
      // 看过就有进度：不足 1% 也显示 1%，不出现 "0%" 这种读起来像没看过的值
      final percent = (positionMs / durationMs * 100).round().clamp(1, 100);
      return '看到 ${formatHistoryPosition(positionMs)}'
          ' / ${formatHistoryPosition(durationMs)}'
          '（$percent%）';
    }
    if (positionMs > 0) return '看到 ${formatHistoryPosition(positionMs)}';
    return '时长 ${formatHistoryPosition(durationMs)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = widget.selected ? colors.onPrimary : colors.onSurface;
    final status =
        widget.isOffline ? DownloadStatus.completed : widget.download?.status;
    final downloadLabel = switch (status) {
      DownloadStatus.completed => '已缓存',
      DownloadStatus.downloading => '正在缓存',
      DownloadStatus.failed => '缓存失败',
      DownloadStatus.paused => '缓存已暂停',
      DownloadStatus.pending => '等待缓存',
      DownloadStatus.resolving => '正在解析',
      _ => null,
    };
    final playbackLabel =
        widget.selected ? (widget.isPlaying ? '正在播放' : '当前选集') : '播放';

    // 观看进度：位置与时长独立判断（时长只有播过之后才知道）。
    final watchLabel = _watchLabel(widget.positionMs, widget.durationMs);

    // 下载状态图标：**未缓存也画**（浅色 outline），让"有没有下载"一眼可扫；
    // 离线态（整条线路都是缓存）不画，避免每行都是同一个图标。
    final downloadIcon = widget.isOffline
        ? null
        : switch (status) {
            DownloadStatus.completed => Icons.download_done_rounded,
            DownloadStatus.downloading ||
            DownloadStatus.resolving ||
            DownloadStatus.pending =>
              Icons.downloading_rounded,
            DownloadStatus.paused => Icons.pause_circle_outline_rounded,
            DownloadStatus.failed => Icons.error_outline_rounded,
            _ => Icons.download_outlined,
          };
    final downloadIconColor = widget.selected
        ? foreground
        : status == DownloadStatus.failed
            ? colors.error
            : widget.download == null
                ? colors.onSurfaceVariant.withValues(alpha: 0.45)
                : colors.primary;

    final downloadText = !widget.isOffline && downloadLabel != null
        ? status == DownloadStatus.downloading
            ? '缓存 ${(widget.download!.progressPercent.clamp(0, 1) * 100).round()}%'
            : downloadLabel
        : null;

    final supportingText = [
      if (widget.selected) playbackLabel,
      if (watchLabel != null) watchLabel,
      if (downloadText != null) downloadText,
    ].join(' · ');

    return Semantics(
      button: true,
      onTap: widget.onTap,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      label: '${widget.name}，$playbackLabel'
          '${watchLabel == null ? '' : '，$watchLabel'}'
          '${widget.isOffline || downloadLabel == null ? '' : '，$downloadLabel'}',
      child: Tooltip(
        message: '${widget.name} · $playbackLabel'
            '${watchLabel == null ? '' : ' · $watchLabel'}'
            '${widget.isOffline || downloadLabel == null ? '' : ' · $downloadLabel'}',
        excludeFromSemantics: true,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            final restShape = widget.selected
                ? BorderRadius.circular(20)
                : BorderRadius.vertical(
                    top: Radius.circular(widget.first ? 20 : 4),
                    bottom: Radius.circular(widget.last ? 20 : 4),
                  );
            final press = _press.value.clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(bottom: widget.last ? 0 : 2),
              child: Material(
                animationDuration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                color: widget.selected
                    ? colors.primary
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.lerp(
                    restShape, BorderRadius.circular(12), press),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            );
          },
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: _setPressed,
            excludeFromSemantics: true,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.focused)) {
                return foreground.withValues(alpha: 0.1);
              }
              if (states.contains(WidgetState.hovered)) {
                return foreground.withValues(alpha: 0.08);
              }
              return null;
            }),
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: foreground,
                                fontWeight: widget.selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            if (supportingText.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                supportingText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: widget.selected
                                      ? foreground
                                      : status == DownloadStatus.failed
                                          ? colors.error
                                          : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (downloadIcon != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          downloadIcon,
                          size: 18,
                          color: downloadIconColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
