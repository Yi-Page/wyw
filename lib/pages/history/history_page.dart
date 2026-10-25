import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/card/history_card.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/widget/kazumi_menu.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/history/history_controller.dart';
import 'package:wyw/pages/history/history_deleted_dialog.dart';
import 'package:wyw/pages/history/history_entry_launcher.dart';
import 'package:wyw/pages/history/history_progress_summary.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/utils/date_time.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 进度历史页（应用自带资源的观看/阅读进度）。
///
/// 插件浏览历史已整体移入收藏模块（收藏页的「全部」tab），本页只保留进度历史，
/// 两个历史互不耦合。
///
/// 页面能力：
///   - 标题搜索（实时过滤当前列表）
///   - 时间分组（今天/昨天/本周/本月/更早）
///   - 懒加载分页（滚动到底自动追加，避免一次全量渲染）
///   - 单条滑动删除 + Snackbar 撤销
///   - 类型筛选 chips + 「继续观看」置顶横滑区
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const int _pageSize = 30;
  static const int _pageStep = 40;
  static const int _continueLimit = 8;

  HistoryController get _progressController => inject<HistoryController>();

  final TextEditingController _searchController = TextEditingController();

  bool _progressShowDelete = false;

  /// 本次已删除清单（会话级回收站）：存活到本页 dispose，不持久化、不加上限。
  ///
  /// 删除**已经落盘**，这里只是"还来得及反悔"的窗口——比原来的 4 秒 SnackBar
  /// 长，且连续删除不会互相顶掉撤销机会。
  final DeletedLedger<HistoryEntry> _deleted =
      DeletedLedger<HistoryEntry>(keyOf: (entry) => entry.key);

  // 视图状态：搜索词 / 类型筛选 / 分页可见数
  String _query = '';
  HistoryType? _typeFilter;
  int _progressVisible = _pageSize;

  @override
  void initState() {
    super.initState();
    _progressController.init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _progressVisible = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final hasData = _progressController.histories.isNotEmpty;
        return Scaffold(
          appBar: SysAppBar(
            title: const Text('历史'),
            actions: [
              _buildDeletedButton(),
              if (hasData)
                IconButton(
                  onPressed: () => setState(
                      () => _progressShowDelete = !_progressShowDelete),
                  icon: _progressShowDelete
                      ? const Icon(Icons.edit_off_outlined)
                      : const Icon(Icons.edit_outlined),
                  tooltip: _progressShowDelete ? '退出编辑' : '编辑',
                ),
              if (hasData)
                IconButton(
                  onPressed: _showClearDialog,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: '清除进度历史',
                ),
              const WywAppBarMenuButton(pagePath: '/history/'),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildSearchRow(),
                Expanded(child: _buildProgressTab()),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============ 搜索 + 类型筛选 ============

  /// 一行：左侧搜索框（与收藏页同款 `SearchBar`），右侧类型筛选按钮（默认「全部」）。
  ///
  /// 宽度与列表一致走 `_horizontalPadding`（800 内容限宽居中），否则搜索框会
  /// 撑满整个窗口、类型按钮被顶到最右。
  Widget _buildSearchRow() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12 + _horizontalPadding,
        6,
        12 + _horizontalPadding,
        2,
      ),
      child: Row(
        children: [
          Expanded(child: _buildSearchBar()),
          const SizedBox(width: 8),
          _buildTypeFilterButton(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() => Semantics(
        label: '搜索历史记录',
        child: SearchBar(
          controller: _searchController,
          leading: const Icon(Icons.search_rounded, size: 22),
          trailing: [
            if (_query.isNotEmpty)
              IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _searchController.clear();
                  _setQuery('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
          ],
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          constraints: const BoxConstraints(minHeight: 48),
          onChanged: _setQuery,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
      );

  /// 类型筛选按钮（全部 / 视频 / 漫画 / 小说），当前值显示在按钮上。
  Widget _buildTypeFilterButton() {
    final options = <HistoryType?>[
      null,
      HistoryType.video,
      HistoryType.comic,
      HistoryType.novel,
    ];
    final label =
        _typeFilter == null ? '全部' : historyTypeLabel(_typeFilter!);
    return KazumiMenuButton(
      menuChildren: [
        for (final option in options)
          KazumiMenuItem(
            label: option == null ? '全部' : historyTypeLabel(option),
            leadingIcon: Icon(
              option == null
                  ? Icons.filter_list_rounded
                  : historyTypeIcon(option),
            ),
            selected: _typeFilter == option,
            onPressed: () => _setTypeFilter(option),
          ),
      ],
      builder: (context, toggle) => FilledButton.tonalIcon(
        onPressed: toggle,
        icon: const Icon(Icons.filter_list_rounded, size: 18),
        label: Text(label),
      ),
    );
  }

  void _setTypeFilter(HistoryType? type) {
    setState(() {
      _typeFilter = type;
      _progressVisible = _pageSize;
    });
  }

  // ============ 进度列表 ============

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
              if (continueList.isNotEmpty)
                SliverToBoxAdapter(child: _buildContinueSection(continueList)),
              // 类型筛选在顶部的搜索行里（默认「全部」），正文区只处理空态。
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
                    // 单列分组列表（照 Kazumi 重构后的历史页）：同一日期分组视觉上
                    // 并成一块——首行上圆角、末行下圆角、中间行小圆角，行间 2px 缝。
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ProgressHistoryCardV(
                          historyItem: g.$2[i],
                          showDelete: _progressShowDelete,
                          onDeleted: () => _deleteProgress(g.$2[i]),
                          borderRadius: _groupRowShape(i, g.$2.length),
                          margin: _groupRowMargin,
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
    final subtitle = historyProgressSummary(entry);
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

  // ============ 通用部件 ============

  double get _horizontalPadding {
    const maxContentWidth = 800.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth > maxContentWidth
        ? (screenWidth - maxContentWidth) / 2
        : 0;
  }

  /// 分组块内的行间距：卡片上下各 1px → 相邻行之间 2px 缝（照 Kazumi）。
  static const EdgeInsets _groupRowMargin =
      EdgeInsets.symmetric(vertical: 1, horizontal: 8);

  /// 分组块内某一行的圆角（照 Kazumi）：首行上圆角、末行下圆角、中间行小圆角。
  ///
  /// 同一日期分组因此视觉上并成一整块；组只有一行时四角都是大圆角。
  static BorderRadius _groupRowShape(int index, int total) {
    const outer = Radius.circular(24);
    const inner = Radius.circular(4);
    final isFirst = index == 0;
    final isLast = index == total - 1;
    return BorderRadius.only(
      topLeft: isFirst ? outer : inner,
      topRight: isFirst ? outer : inner,
      bottomLeft: isLast ? outer : inner,
      bottomRight: isLast ? outer : inner,
    );
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

  /// 「已删除」入口：数量角标 + 点击打开弹窗；清单为空时禁用（置灰可见）。
  Widget _buildDeletedButton() {
    final count = _deleted.count;
    return IconButton(
      tooltip: count == 0 ? '本次已删除（无）' : '本次已删除（$count 条，可恢复）',
      onPressed: count == 0 ? null : _openDeletedDialog,
      icon: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        child: const Icon(Icons.restore_from_trash_rounded),
      ),
    );
  }

  void _deleteProgress(HistoryEntry entry) {
    _progressController.remove(entry);
    setState(() => _deleted.add(entry));
  }

  Future<void> _openDeletedDialog() async {
    if (_deleted.isEmpty) return;
    await showHistoryDeletedDialog(
      context,
      entries: _deleted.entries,
      onRestore: _restoreFromLedger,
      onRestoreAll: _restoreAllFromLedger,
      onClear: () {
        if (mounted) setState(_deleted.clear);
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _restoreFromLedger(HistoryEntry entry) async {
    await _progressController.restore(entry);
    if (!mounted) return;
    setState(() => _deleted.remove(entry));
    WywDialog.showToast(message: '已恢复「${entry.title}」');
  }

  Future<void> _restoreAllFromLedger(List<HistoryEntry> entries) async {
    for (final entry in entries) {
      await _progressController.restore(entry);
    }
    if (!mounted) return;
    setState(_deleted.clear);
    WywDialog.showToast(message: '已恢复 ${entries.length} 条');
  }

  /// 清除进度历史：输入「清除」二次确认（删除后可在「已删除」中恢复）。
  void _showClearDialog() {
    WywDialog.show(
      builder: (dialogContext) {
        final textController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final confirmed = textController.text.trim() == '清除';
            return AlertDialog(
              title: const Text('清除进度历史'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('将删除全部进度记录。'),
                  const SizedBox(height: 4),
                  const Text('删除后可在顶栏「已删除」中恢复（离开本页后失效）。'),
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
                          // 清空由仓库内部完成 → 先取快照，再落盘删除，
                          // 这样被清掉的条目同样能进「已删除」清单。
                          final removed =
                              _progressController.histories.toList();
                          _progressController.clearAll();
                          setState(() {
                            _deleted.addAll(removed);
                            _progressVisible = _pageSize;
                          });
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
