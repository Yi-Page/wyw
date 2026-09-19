import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/card/history_card.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/bean/card/plugin_history_card.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/navigation.dart';
import 'package:wyw/pages/history/history_controller.dart';
import 'package:wyw/pages/history/history_entry_launcher.dart';
import 'package:wyw/pages/history/plugin_history_controller.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/plugin_history_entry.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/utils/date_time.dart';

/// 历史页顶部 Tab。
enum HistoryTab { progress, browse }

/// 合并版历史页：进度历史（视频/漫画/小说）+ 插件浏览历史，单页 Tab 切换。
///
/// 两个 tab 共有能力：
///   - 标题搜索（实时过滤当前列表）
///   - 时间分组（今天/昨天/本周/本月/更早）
///   - 懒加载分页（滚动到底自动追加，避免一次全量渲染）
///   - 单条滑动删除 + Snackbar 撤销
/// 进度 tab 额外：类型筛选 chips + 「继续观看」置顶横滑区。
/// 横滑区能滑时只滑列表，滑到尽头继续拖拽则翻 Tab（解决与 TabBarView 的同向手势冲突）。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.initialTab = HistoryTab.progress});

  final HistoryTab initialTab;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with TickerProviderStateMixin {
  static const int _pageSize = 30;
  static const int _pageStep = 40;
  static const int _continueLimit = 8;

  HistoryController get _progressController => inject<HistoryController>();
  PluginHistoryController get _browseController =>
      inject<PluginHistoryController>();

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _progressShowDelete = false;
  bool _browseShowDelete = false;

  // Tab 嵌套横滑冲突处理（见 _handleTabEdgeOverscroll）：
  // 内层横滑列表手动拖拽过界的累计量 / 方向（+1 末边，-1 起始边）/ 本轮拖拽是否允许翻页
  static const double _edgeFlipThreshold = 48;
  double _edgeAccum = 0;
  int _edgeDir = 0;
  bool _edgeArmed = false;

  // 视图状态：搜索词 / 类型筛选 / 分页可见数
  String _query = '';
  HistoryType? _typeFilter;
  int _progressVisible = _pageSize;
  int _browseVisible = _pageSize;

  @override
  void initState() {
    super.initState();
    _progressController.init();
    _browseController.init();
    _tabController = TabController(
      length: 2,
      initialIndex: widget.initialTab == HistoryTab.browse ? 1 : 0,
      vsync: this,
    );
    _tabController.addListener(() {
      // 只在真正切换完成时刷新 AppBar 上下文动作
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isProgressTab => _tabController.index == 0;

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _progressVisible = _pageSize;
      _browseVisible = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final hasProgress = _progressController.histories.isNotEmpty;
        final hasBrowse = _browseController.histories.isNotEmpty;
        final hasData = _isProgressTab ? hasProgress : hasBrowse;
        final showDelete =
            _isProgressTab ? _progressShowDelete : _browseShowDelete;
        return Scaffold(
          appBar: SysAppBar(
            title: const Text('历史'),
            actions: [
              if (hasData)
                IconButton(
                  onPressed: () => setState(() {
                    if (_isProgressTab) {
                      _progressShowDelete = !_progressShowDelete;
                    } else {
                      _browseShowDelete = !_browseShowDelete;
                    }
                  }),
                  icon: showDelete
                      ? const Icon(Icons.edit_off_outlined)
                      : const Icon(Icons.edit_outlined),
                  tooltip: showDelete ? '退出编辑' : '编辑',
                ),
              if (hasData)
                IconButton(
                  onPressed: _showClearDialog,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: '清除当前列表',
                ),
              const WywAppBarMenuButton(pagePath: '/history/'),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildSearchField(),
                TabBar(
                  controller: _tabController,
                  tabs: const [Tab(text: '进度'), Tab(text: '浏览')],
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleTabEdgeOverscroll,
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildProgressTab(), _buildBrowseTab()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============ 搜索 ============

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: TextField(
        controller: _searchController,
        onChanged: _setQuery,
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索历史记录',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _setQuery('');
                  },
                ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
      ),
    );
  }

  // ============ Tab 嵌套横滑冲突 ============

  /// 「继续观看」/ 类型筛选 chips 是 TabBarView 内的横滑 ListView，手势竞技场中
  /// 最内层滚动视图永远优先：这两块区域会抢走全部横向手势，滑到尽头再滑是"死区"，
  /// 无法翻 tab。这里监听内层列表的手动拖拽过界（Android 为 OverscrollNotification，
  /// iOS bounce 为 pixels 越界的 ScrollUpdateNotification），累计超过阈值即翻页；
  /// 只认手指拖拽产生的过界（dragDetails 非空），惯性甩到边缘不触发，避免误翻。
  bool _handleTabEdgeOverscroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.horizontal) return false;
    if (n is ScrollStartNotification) {
      _edgeAccum = 0;
      _edgeDir = 0;
      _edgeArmed = true;
      return false;
    }
    double out;
    int dir;
    if (n is OverscrollNotification && n.dragDetails != null) {
      out = n.overscroll.abs();
      dir = n.overscroll.isNegative ? -1 : 1;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final m = n.metrics;
      if (m.pixels > m.maxScrollExtent) {
        out = m.pixels - m.maxScrollExtent;
        dir = 1;
      } else if (m.pixels < m.minScrollExtent) {
        out = m.minScrollExtent - m.pixels;
        dir = -1;
      } else {
        return false;
      }
    } else {
      return false;
    }
    if (_edgeDir != dir) {
      // 拖拽方向翻转：重新累计
      _edgeDir = dir;
      _edgeAccum = out;
    } else {
      _edgeAccum += out;
    }
    if (_edgeArmed && _edgeAccum >= _edgeFlipThreshold) {
      _edgeArmed = false;
      final target = _tabController.index + dir;
      if (target >= 0 && target < _tabController.length) {
        _tabController.animateTo(target);
      }
    }
    return false;
  }

  // ============ 进度 tab ============

  Widget _buildProgressTab() {
    return Observer(
      builder: (_) {
        final all = _progressController.histories;
        if (all.isEmpty) {
          return _emptyView(Icons.history_rounded, '没有播放历史');
        }
        final filtered = _filterProgress(all);
        final visible = filtered.take(_progressVisible).toList();
        final groups =
            groupByTimeLabel<HistoryEntry>(visible, (e) => e.lastWatchTime);
        final continueList = (_query.trim().isEmpty && _typeFilter == null)
            ? _continueWatching(all)
            : const <HistoryEntry>[];

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis != Axis.vertical) return false;
            if (_progressVisible < filtered.length &&
                n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
              setState(() => _progressVisible += _pageStep);
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildTypeFilterChips()),
              if (continueList.isNotEmpty)
                SliverToBoxAdapter(child: _buildContinueSection(continueList)),
              // 某分类/搜索无结果时保留筛选 chips，仅正文区显示空态，避免无法切回「全部」
              if (groups.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _emptyView(Icons.search_off, '未找到匹配的记录'),
                )
              else ...[
                for (final g in groups) ...[
                  SliverToBoxAdapter(child: _buildGroupHeader(g.$1)),
                  SliverPadding(
                    padding:
                        EdgeInsets.symmetric(horizontal: _horizontalPadding),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        mainAxisSpacing: 2,
                        crossAxisSpacing: StyleString.cardSpace,
                        crossAxisCount: _crossCount,
                        mainAxisExtent: 136,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ProgressHistoryCardV(
                          historyItem: g.$2[i],
                          showDelete: _progressShowDelete,
                          onDeleted: () => _deleteProgress(g.$2[i]),
                        ),
                        childCount: g.$2.length,
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: _buildListFooter(
                    hasMore: _progressVisible < filtered.length,
                    shown: visible.length,
                    total: filtered.length,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<HistoryEntry> _filterProgress(List<HistoryEntry> all) {
    final q = _query.trim().toLowerCase();
    return all.where((e) {
      if (_typeFilter != null && e.type != _typeFilter) return false;
      if (q.isNotEmpty && !e.title.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  Widget _buildTypeFilterChips() {
    final options = <(HistoryType?, String)>[
      (null, '全部'),
      (HistoryType.video, '视频'),
      (HistoryType.comic, '漫画'),
      (HistoryType.novel, '小说'),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12 + _horizontalPadding),
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(o.$2),
                selected: _typeFilter == o.$1,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() {
                  _typeFilter = o.$1;
                  _progressVisible = _pageSize;
                }),
              ),
            ),
        ],
      ),
    );
  }

  // ============ 继续观看置顶区 ============

  /// 未看完的最近记录（视频未播完 / 漫画未读到最后一页 / 小说未读到最后一章）。
  List<HistoryEntry> _continueWatching(List<HistoryEntry> all) {
    final out = <HistoryEntry>[];
    for (final e in all) {
      if (!_isEntryFinished(e)) out.add(e);
      if (out.length >= _continueLimit) break;
    }
    return out;
  }

  bool _isEntryFinished(HistoryEntry e) {
    final p = e.parseProgress();
    switch (e.type) {
      case HistoryType.video:
        if (p is! VideoPlaybackProgress) return false;
        if (p.sources.isEmpty) return false;
        final srcIdx = p.lastSourceIndex.clamp(0, p.sources.length - 1);
        final src = p.sources[srcIdx];
        if (src.episodes.isEmpty) return false;
        final epIdx = p.lastEpisodeIndex.clamp(0, src.episodes.length - 1);
        final isLastOfLast =
            srcIdx == p.sources.length - 1 && epIdx == src.episodes.length - 1;
        final ep = src.episodes[epIdx];
        final watchedOut =
            ep.durationMs > 0 && ep.positionMs >= ep.durationMs * 0.75;
        return watchedOut && isLastOfLast;
      case HistoryType.comic:
        if (p is! ComicProgress) return false;
        if (p.chapters.isEmpty) return false;
        final idx = HistoryEntryLauncher.comicChapterIndex(p);
        if (idx < p.chapters.length - 1) return false;
        // 已在最后一章：用**水位线**判定（曾经到达过的最大图片序号 == 图片总数），
        // 与"当前看到第几张"解耦，末图比视口矮也不会漏判。
        final id = p.chapters[idx]['id'] as String? ?? '';
        for (final cp in p.chapterProgress) {
          if (cp['chapterId'] == id) return isComicChapterFinished(cp);
        }
        return false;
      case HistoryType.novel:
        if (p is! ReadProgress) return false;
        return p.chapters.isNotEmpty && p.chapter >= p.chapters.length;
      default:
        return false;
    }
  }

  Widget _buildContinueSection(List<HistoryEntry> items) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16 + _horizontalPadding, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.play_circle_filled_rounded,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('继续观看',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        SizedBox(
          height: 206,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12 + _horizontalPadding),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _buildContinueCard(items[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildContinueCard(HistoryEntry entry) {
    final theme = Theme.of(context);
    final subtitle = _continueSubtitle(entry);
    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        HistoryEntryLauncher(context, entry).open();
      },
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NetworkImgLayer(
                src: entry.cover,
                width: 112,
                height: 150,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
          ],
        ),
      ),
    );
  }

  String? _continueSubtitle(HistoryEntry e) {
    final p = e.parseProgress();
    switch (e.type) {
      case HistoryType.video:
        if (p is! VideoPlaybackProgress) return null;
        final ep = p.currentEpisode;
        if (ep == null) return null;
        final epLabel = '第 ${p.lastEpisodeIndex + 1} 集';
        if (ep.durationMs > 0) return '$epLabel · ${_formatMs(ep.positionMs)}';
        return epLabel;
      case HistoryType.comic:
        if (p is! ComicProgress) return null;
        if (p.chapters.isEmpty) return null;
        final idx = HistoryEntryLauncher.comicChapterIndex(p);
        return '第 ${idx + 1}/${p.chapters.length} 话';
      case HistoryType.novel:
        if (p is! ReadProgress) return null;
        if (p.chapters.isEmpty) return null;
        return '第 ${p.chapter}/${p.chapters.length} 章';
      default:
        return null;
    }
  }

  String _formatMs(int ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  // ============ 浏览 tab ============

  Widget _buildBrowseTab() {
    return Observer(
      builder: (_) {
        final all = _browseController.histories;
        if (all.isEmpty) {
          return _emptyView(Icons.history_rounded, '没有浏览历史');
        }
        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? all.toList()
            : all.where((e) => e.title.toLowerCase().contains(q)).toList();
        final visible = filtered.take(_browseVisible).toList();
        final groups =
            groupByTimeLabel<PluginHistoryEntry>(visible, (e) => e.visitTime);

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis != Axis.vertical) return false;
            if (_browseVisible < filtered.length &&
                n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
              setState(() => _browseVisible += _pageStep);
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              // 搜索无结果时正文区显示空态（搜索框在页面顶部，不受影响）
              if (groups.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _emptyView(Icons.search_off, '未找到匹配的记录'),
                )
              else ...[
                for (final g in groups) ...[
                  SliverToBoxAdapter(child: _buildGroupHeader(g.$1)),
                  SliverPadding(
                    padding:
                        EdgeInsets.symmetric(horizontal: _horizontalPadding),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        mainAxisSpacing: 2,
                        crossAxisSpacing: StyleString.cardSpace,
                        crossAxisCount: _crossCount,
                        mainAxisExtent: 136,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => PluginHistoryCard(
                          historyItem: g.$2[i],
                          showDelete: _browseShowDelete,
                          onDeleted: () => _deleteBrowse(g.$2[i]),
                        ),
                        childCount: g.$2.length,
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: _buildListFooter(
                    hasMore: _browseVisible < filtered.length,
                    shown: visible.length,
                    total: filtered.length,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ============ 通用部件 ============

  int get _crossCount {
    final w = MediaQuery.sizeOf(context).width;
    if (w > LayoutBreakpoint.medium['width']!) return 3;
    if (w > LayoutBreakpoint.compact['width']!) return 2;
    return 1;
  }

  double get _horizontalPadding {
    const maxContentWidth = 1000.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth > maxContentWidth
        ? (screenWidth - maxContentWidth) / 2
        : 0;
  }

  Widget _buildGroupHeader(String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16 + _horizontalPadding, 12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildListFooter(
      {required bool hasMore, required int shown, required int total}) {
    if (total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          hasMore ? '上拉加载更多（$shown/$total）' : '共 $total 条',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }

  Widget _emptyView(IconData icon, String title) {
    return GeneralEmptyState(icon: icon, title: title);
  }

  // ============ 删除 / 清除 ============

  void _deleteProgress(HistoryEntry entry) {
    _progressController.remove(entry);
    _showUndoSnackBar(
        '已删除「${entry.title}」', () => _progressController.restore(entry));
  }

  void _deleteBrowse(PluginHistoryEntry entry) {
    _browseController.remove(entry);
    _showUndoSnackBar(
        '已删除「${entry.title}」', () => _browseController.restore(entry));
  }

  /// 单条删除后的撤销提示（4 秒内可撤销）。
  void _showUndoSnackBar(String message, Future<void> Function() onUndo) {
    rootScaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: '撤销', onPressed: () => onUndo()),
        ),
      );
  }

  /// 清除当前 tab 全部记录：输入「清除」二次确认（不可撤销，需防误触）。
  void _showClearDialog() {
    final isProgress = _isProgressTab;
    WywDialog.show(
      builder: (dialogContext) {
        final textController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final confirmed = textController.text.trim() == '清除';
            return AlertDialog(
              title: Text(isProgress ? '清除进度历史' : '清除浏览历史'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('将删除该列表的全部记录，且无法撤销。'),
                  const SizedBox(height: 12),
                  const Text('输入「清除」以确认：'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: WywDialog.dismiss,
                  child: Text('取消',
                      style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.outline)),
                ),
                TextButton(
                  onPressed: confirmed
                      ? () {
                          WywDialog.dismiss();
                          if (isProgress) {
                            _progressController.clearAll();
                            setState(() => _progressVisible = _pageSize);
                          } else {
                            _browseController.clearAll();
                            setState(() => _browseVisible = _pageSize);
                          }
                        }
                      : null,
                  child: Text('清除',
                      style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
