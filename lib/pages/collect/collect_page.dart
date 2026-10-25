import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/card/collect_entry_card.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/settings/capsule_tab_strip.dart';
import 'package:wyw/bean/widget/collect_button.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/widget/kazumi_menu.dart';
import 'package:wyw/pages/collect/collect_controller.dart';
import 'package:wyw/pages/collect/collect_deleted_dialog.dart';
import 'package:wyw/pages/collect/collect_library_query.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/plugins/plugin_category.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/date_time.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 收藏页的 7 个 tab（顺序固定：全部、未收藏、在看、想看、看过、搁置、抛弃）。
///
/// `null` = 「全部」：**全部浏览历史条目（含未收藏）**。
/// 其余各项 = `collectType` 筛选；「未收藏」也是状态之一（条目默认状态）。
///
/// 注意：tab 的**展示顺序**（看过在搁置之前）与 [CollectType] 的**数值顺序**
/// （`onHold=3` < `watched=4`，照 Kazumi）不同——数值是持久化数据，顺序是 UI。
const List<CollectType?> collectCategories = <CollectType?>[
  null,
  CollectType.none,
  CollectType.watching,
  CollectType.planToWatch,
  CollectType.watched,
  CollectType.onHold,
  CollectType.abandoned,
];

/// 「进入时的默认 tab」设置值 → tab 下标。
///
/// 设置值编码：`-1` = 全部，其余 = [CollectType] 的数值
/// （不用下标存，避免 tab 顺序调整后设置错位）。未知值一律回退「全部」。
int collectTabIndexForSetting(int value) {
  if (value < 0) return 0; // 全部
  final type = CollectType.fromValue(value);
  // fromValue 对未知数值回退 none；这里要求数值原样往返，
  // 否则（未知值）统一回退「全部」而不是误判成「未收藏」。
  if (type.value != value) return 0;
  final index = collectCategories.indexOf(type);
  return index < 0 ? 0 : index;
}

/// 插件维度筛选的取值：全部 / 某个分类 / **仅已删除插件**。
enum _PluginFilterKind { all, category, deleted }

class _PluginFilter {
  const _PluginFilter.all()
      : kind = _PluginFilterKind.all,
        category = null;
  const _PluginFilter.category(PluginCategory this.category)
      : kind = _PluginFilterKind.category;
  const _PluginFilter.deleted()
      : kind = _PluginFilterKind.deleted,
        category = null;

  final _PluginFilterKind kind;
  final PluginCategory? category;
}

/// 收藏页：单路由页面（不在菜单里），7 个 tab 的单列分组列表。
///
/// 数据 = 插件浏览足迹（`PluginBrowse.open` 写入）+ 用户设置的收藏状态。
/// 删除 = 删除整条浏览历史（收藏状态随条目一起消失），4 秒内可撤销。
class CollectPage extends StatefulWidget {
  const CollectPage({super.key});

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage>
    with TickerProviderStateMixin {
  static const int _pageSize = 30;
  static const int _pageStep = 40;

  CollectController get _controller => inject<CollectController>();

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _pageFocus = FocusNode();

  int _visible = _pageSize;
  bool _searchExpanded = false;

  /// 多选管理状态：`_selected` 存条目 key（`pluginName::id`），仅作用于当前 tab。
  bool _selecting = false;
  final Set<String> _selected = {};

  /// 本次已删除清单（会话级回收站）：存活到本页 dispose，不持久化、不加上限。
  ///
  /// 删除**已经落盘**（语义不变：删除 = 删除整条浏览历史），这里只是"还来得及
  /// 反悔"的窗口——比原来的 4 秒 SnackBar 长，且不会被后续删除顶掉。
  final DeletedLedger<CollectEntry> _deleted =
      DeletedLedger<CollectEntry>(keyOf: (entry) => entry.key);

  /// 插件维度筛选；默认「全部」。取值见 [_PluginFilter]（全部 / 分类 / 已删除）。
  _PluginFilter _filter = const _PluginFilter.all();

  CollectType? get _type => collectCategories[_tabController.index];

  @override
  void initState() {
    super.initState();
    _controller.init();
    _tabController = TabController(
      length: collectCategories.length,
      // 进入时的默认 tab 由设置决定（-1 = 全部）。
      initialIndex: collectTabIndexForSetting(
        GStorage.getSetting(SettingsKeys.collectDefaultTab),
      ),
      vsync: this,
    )..addListener(_onTabChanged);
    // tab 初值来自设置，未必是 controller 上次的状态（模块单例跨次访问保留），
    // 所以显式同步一次筛选/排序。
    _controller.setType(_type);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _controller.setType(_type);
    setState(() {
      _visible = _pageSize;
      _selected.clear();
    });
  }

  void _onQueryChanged(String value) {
    _controller.setQuery(value);
    setState(() {
      _visible = _pageSize;
      _selected.clear();
    });
  }

  void _focusSearch() {
    setState(() => _searchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _pageFocus.requestFocus();
    _searchController.clear();
    _controller.setQuery('');
    setState(() {
      _searchExpanded = false;
      _visible = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final query = CollectLibraryQuery(
          _controller.entries,
          _controller.query,
          // 插件维度筛选（全部 / 分类 / 已删除）→ 允许的插件名集合
          allowedPlugins: _allowedPluginsFor(_filter),
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _focusSearch,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _focusSearch,
            const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
          },
          child: Focus(
            focusNode: _pageFocus,
            autofocus: true,
            child: Scaffold(
              appBar: SysAppBar(
                title: Text(_selecting ? '已选 ${_selected.length} 条' : '收藏'),
                actions: _buildAppBarActions(query),
              ),
              body: SafeArea(
                top: false,
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 600;
                    final inset = _inset(constraints.maxWidth);
                    return Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          child: _buildHeader(query, compact: compact),
                        ),
                        Expanded(child: _buildResults(query, inset: inset)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============ 头部：页签 + 搜索 + 排序 ============

  Widget _buildHeader(CollectLibraryQuery query, {required bool compact}) {
    final type = _type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildCategories(query)),
            if (!compact)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16),
                child: _countLabel(query.count(type)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (!compact)
              // 整行铺满（与历史页一致）。Kazumi 在这里限宽 360，是因为它的收藏页
              // 是 1560 宽的网格、搜索框要与同行更多控件并排；wyw 内容上限 800
              // 且本行只有搜索框 + 插件分类 + 排序菜单，限宽会在中间留出大片空白。
              Expanded(child: _buildSearchBar())
            else
              Expanded(child: _countLabel(query.count(type))),
            const SizedBox(width: 12),
            _buildCategoryFilterButton(compact: compact),
            const SizedBox(width: 8),
            _SortMenu(
              value: _controller.sort,
              showLabel: !compact,
              onChanged: (value) {
                _controller.setSort(value);
                setState(() => _visible = _pageSize);
              },
            ),
            if (compact)
              IconButton(
                tooltip: _searchExpanded ? '收起搜索' : '搜索收藏',
                isSelected: _searchExpanded,
                selectedIcon: const Icon(Icons.search_off_rounded),
                icon: const Icon(Icons.search_rounded),
                onPressed: _searchExpanded ? _closeSearch : _focusSearch,
              ),
          ],
        ),
        if (compact && _searchExpanded) ...[
          const SizedBox(height: 12),
          _buildSearchBar(),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _countLabel(int count) => Text(
        '$count 条',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );

  /// 页签条（照 Kazumi 追番页：可滚动 + 胶囊指示器 + 计数语义标签）。
  ///
  /// 样式来自 [CapsuleTabStrip]（与播放器分屏面板共用），本页不再自持常量。
  Widget _buildCategories(CollectLibraryQuery query) {
    return CapsuleTabStrip(
      tabBarKey: const PageStorageKey('collect-filter-strip'),
      controller: _tabController,
      tabs: [
        for (final type in collectCategories)
          CapsuleTab(
            label: type?.label ?? '全部',
            semanticsLabel: '${type?.label ?? '全部'}，${query.count(type)} 条',
          ),
      ],
    );
  }

  Widget _buildSearchBar() => Semantics(
        label: '搜索收藏',
        child: SearchBar(
          controller: _searchController,
          focusNode: _searchFocus,
          leading: const Icon(Icons.search_rounded, size: 22),
          trailing: [
            if (_controller.query.isNotEmpty)
              IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _searchController.clear();
                  _onQueryChanged('');
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
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _pageFocus.requestFocus(),
        ),
      );

  /// 插件维度筛选按钮（默认「全部」）。
  ///
  /// 菜单结构：
  ///   全部
  ///   视频 / 漫画 / 小说 / 其他（内置固定序，当前收藏里实际出现的）
  ///   ── Divider ──（仅当有自定义分类）
  ///   自定义分类（按展示名排序）
  ///   ── Divider ──（始终存在）
  ///   **已删除**（红色，`destructive`）—— 筛选插件本体已删除的条目
  ///
  /// 分隔线样式照 Kazumi 收藏菜单（`_CollectEntryMenu` 状态组与「取消收藏」之间）。
  /// ⚠ 不能按 label 排序：中文按 Unicode 码点排时「其」(0x5176) 在「小/漫/视」
  /// 之前，会让「其他」冒顶到最上。
  Widget _buildCategoryFilterButton({required bool compact}) {
    final present = <PluginCategory>{
      for (final entry in _controller.entries) _categoryOf(entry),
    };
    final registry = inject<PluginController>().categories;
    final customs = [
      for (final category in registry.custom)
        if (present.contains(category)) category,
    ];
    final label = switch (_filter.kind) {
      _PluginFilterKind.all => '全部',
      _PluginFilterKind.category => _filter.category!.label,
      _PluginFilterKind.deleted => '已删除',
    };
    return KazumiMenuButton(
      menuChildren: [
        KazumiMenuItem(
          label: '全部',
          leadingIcon: const Icon(Icons.category_rounded),
          selected: _filter.kind == _PluginFilterKind.all,
          onPressed: () => _setFilter(const _PluginFilter.all()),
        ),
        for (final category in registry.builtins)
          if (present.contains(category))
            KazumiMenuItem(
              label: category.label,
              leadingIcon: Icon(category.icon),
              selected: _filter.kind == _PluginFilterKind.category &&
                  _filter.category == category,
              onPressed: () => _setFilter(_PluginFilter.category(category)),
            ),
        if (customs.isNotEmpty) ...[
          const Divider(indent: 16, endIndent: 16),
          for (final category in customs)
            KazumiMenuItem(
              label: category.label,
              leadingIcon: Icon(category.icon),
              selected: _filter.kind == _PluginFilterKind.category &&
                  _filter.category == category,
              onPressed: () => _setFilter(_PluginFilter.category(category)),
            ),
        ],
        const Divider(indent: 16, endIndent: 16),
        KazumiMenuItem(
          label: '已删除',
          leadingIcon: const Icon(Icons.extension_off),
          destructive: true,
          selected: _filter.kind == _PluginFilterKind.deleted,
          onPressed: () => _setFilter(const _PluginFilter.deleted()),
        ),
      ],
      builder: (context, toggle) => compact
          ? IconButton(
              onPressed: toggle,
              tooltip: '插件筛选：$label',
              icon: const Icon(Icons.category_rounded),
            )
          : FilledButton.tonalIcon(
              onPressed: toggle,
              icon: const Icon(Icons.category_rounded, size: 18),
              label: Text(label),
            ),
    );
  }

  void _setFilter(_PluginFilter filter) {
    setState(() {
      _filter = filter;
      _visible = _pageSize;
      _selected.clear();
    });
  }

  /// 当前插件维度筛选允许的插件名集合；[all] 时返回 null（不过滤）。
  ///
  /// 按「分类 → 属于它的插件名」/「已删除 → 插件文件已移除的插件名」换算，
  /// 条目经此集合过滤（标题搜索与计数同理）。
  Set<String>? _allowedPluginsFor(_PluginFilter filter) {
    switch (filter.kind) {
      case _PluginFilterKind.all:
        return null;
      case _PluginFilterKind.category:
        final category = filter.category!;
        return {
          for (final entry in _controller.entries)
            if (_categoryOf(entry) == category) entry.pluginName,
        };
      case _PluginFilterKind.deleted:
        final controller = inject<PluginController>();
        return {
          for (final entry in _controller.entries)
            if (controller.presenceOf(entry.pluginName) ==
                PluginPresence.deleted)
              entry.pluginName,
        };
    }
  }

  /// 条目所属插件分类；插件未加载（停用/未知）时归入「其他」。
  PluginCategory _categoryOf(CollectEntry entry) {
    final controller = inject<PluginController>();
    final plugin = controller.getPlugin(entry.pluginName);
    return plugin == null
        ? PluginCategory.unknown
        : controller.categoryOf(plugin);
  }

  // ============ 结果列表 ============

  Widget _buildResults(CollectLibraryQuery query, {required double inset}) {
    final type = _type;
    final sort = _controller.sort;
    final results = query.results(type, sort);
    // 分组日期键跟随排序主键（最近访问 → 访问时间；最近变更 → 收藏时间，
    // 未收藏回退访问时间），所以同一日期分组必然连续；名称排序无日期语义 → 平铺。
    final grouped = sort.groupsByDate;
    final visible = results.take(_visible).toList();
    final groups = grouped
        ? groupByTimeLabel<CollectEntry>(visible, sort.groupTimeOf)
        : <(String, List<CollectEntry>)>[];

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (_visible < results.length &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          setState(() => _visible += _pageStep);
        }
        return false;
      },
      child: CustomScrollView(
        key: PageStorageKey('collect-results-${type?.value ?? 'all'}'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (results.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(query, type),
            )
          else if (!grouped)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _buildRow(visible[i], i, visible.length),
                  childCount: visible.length,
                ),
              ),
            )
          else ...[
            for (final group in groups) ...[
              SliverToBoxAdapter(child: _buildGroupHeader(group.$1)),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildRow(
                      group.$2[i],
                      i,
                      group.$2.length,
                    ),
                    childCount: group.$2.length,
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: _buildListFooter(
                hasMore: _visible < results.length,
                shown: visible.length,
                total: results.length,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(CollectEntry entry, int index, int total) {
    return CollectEntryCard(
      entry: entry,
      borderRadius: _groupRowShape(index, total),
      margin: _groupRowMargin,
      selecting: _selecting,
      selected: _selected.contains(entry.key),
      onToggleSelect: () => _toggleSelect(entry),
      onChangedType: (type) => _changeType(entry, type),
      onDeleted: () => _delete(entry),
    );
  }

  /// 分组块内的行间距：卡片上下各 1px → 相邻行之间 2px 缝（照 Kazumi）。
  static const EdgeInsets _groupRowMargin =
      EdgeInsets.symmetric(vertical: 1, horizontal: 8);

  /// 分组块内某一行的圆角（照 Kazumi）：首行上圆角、末行下圆角、中间行小圆角。
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
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16 + _inset(MediaQuery.sizeOf(context).width),
          12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildListFooter({
    required bool hasMore,
    required int shown,
    required int total,
  }) {
    if (total == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          hasMore ? '上拉加载更多（$shown/$total）' : '共 $total 条',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ),
    );
  }

  Widget _emptyState(CollectLibraryQuery query, CollectType? type) {
    final searching = _controller.query.trim().isNotEmpty;
    final IconData icon;
    final String title;
    if (searching) {
      icon = Icons.search_off_rounded;
      title = query.total > 0 ? '当前分类没有匹配的记录' : '未找到匹配的记录';
    } else {
      icon = switch (type) {
        null || CollectType.none => Icons.history_rounded,
        _ => Icons.favorite_border_rounded,
      };
      title = switch (type) {
        null => '还没有浏览记录',
        CollectType.none => '没有未收藏的记录',
        CollectType.watching => '还没有在看的内容',
        CollectType.planToWatch => '还没有想看的内容',
        CollectType.watched => '还没有看过的内容',
        CollectType.onHold => '没有搁置的内容',
        CollectType.abandoned => '没有抛弃的内容',
      };
    }
    return GeneralEmptyState(icon: icon, title: title);
  }

  /// 内容限宽（与历史页一致：超过 800 后居中留白）。
  double _inset(double width) {
    const maxContentWidth = 800.0;
    final base =
        width > maxContentWidth ? (width - maxContentWidth) / 2 : 0.0;
    return base + 16;
  }

  // ============ 操作 ============

  /// AppBar 动作：多选模式下是批量操作，否则是「多选 / 清空」。
  List<Widget> _buildAppBarActions(CollectLibraryQuery query) {
    final targets = _selectedEntries(query);
    if (_selecting) {
      return [
        IconButton(
          tooltip: _selected.isEmpty ? '全选当前分类' : '取消全选',
          onPressed: () => _toggleSelectAll(query),
          icon: Icon(
            _selected.isEmpty
                ? Icons.select_all_rounded
                : Icons.deselect_rounded,
          ),
        ),
        KazumiMenuButton(
          enabled: targets.isNotEmpty,
          menuChildren: [
            for (final type in CollectType.values)
              KazumiMenuItem(
                label: type.label,
                leadingIcon: Icon(CollectButton.iconFor(type)),
                onPressed: targets.isEmpty
                    ? null
                    : () => _applyBatchType(targets, type),
              ),
          ],
          builder: (context, toggle) => IconButton(
            onPressed: toggle,
            tooltip: '设置所选条目的收藏状态',
            icon: const Icon(Icons.favorite_border_rounded),
          ),
        ),
        IconButton(
          tooltip: '删除所选',
          onPressed: targets.isEmpty ? null : () => _deleteBatch(targets),
          icon: const Icon(Icons.delete_outline),
        ),
        IconButton(
          tooltip: '退出多选',
          onPressed: _exitSelecting,
          icon: const Icon(Icons.edit_off_outlined),
        ),
      ];
    }
    return [
      _buildDeletedButton(),
      if (_controller.entries.isNotEmpty)
        IconButton(
          tooltip: '多选管理',
          onPressed: () => setState(() => _selecting = true),
          icon: const Icon(Icons.edit_outlined),
        ),
      if (_controller.entries.isNotEmpty) _buildClearMenu(),
      const WywAppBarMenuButton(pagePath: '/collect/'),
    ];
  }

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

  /// 当前 tab（含搜索过滤与排序）的全部条目。
  List<CollectEntry> _currentResults(CollectLibraryQuery query) =>
      query.results(_type, _controller.sort);

  List<CollectEntry> _selectedEntries(CollectLibraryQuery query) =>
      _currentResults(query)
          .where((e) => _selected.contains(e.key))
          .toList();

  void _toggleSelect(CollectEntry entry) {
    setState(() {
      if (!_selected.remove(entry.key)) _selected.add(entry.key);
    });
  }

  void _toggleSelectAll(CollectLibraryQuery query) {
    setState(() {
      if (_selected.isEmpty) {
        _selected.addAll(_currentResults(query).map((e) => e.key));
      } else {
        _selected.clear();
      }
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _applyBatchType(
    List<CollectEntry> targets,
    CollectType type,
  ) async {
    await _controller.setCollectTypeBatch(targets, type);
    if (!mounted) return;
    WywDialog.showToast(message: '已把 ${targets.length} 条设为「${type.label}」');
    _exitSelecting();
  }

  Future<void> _deleteBatch(List<CollectEntry> targets) async {
    await _controller.removeBatch(targets);
    if (!mounted) return;
    setState(() => _deleted.addAll(targets));
    _exitSelecting();
  }

  Future<void> _changeType(CollectEntry entry, CollectType type) async {
    await _controller.setCollectType(entry, type);
  }

  void _delete(CollectEntry entry) {
    _controller.remove(entry);
    setState(() => _deleted.add(entry));
  }

  // ============ 本次已删除（回收站）============

  Future<void> _openDeletedDialog() async {
    if (_deleted.isEmpty) return;
    await showCollectDeletedDialog(
      context,
      entries: _deleted.entries,
      displayNameOf: (pluginName) =>
          inject<PluginController>().displayNameOf(pluginName),
      onRestore: _restoreFromLedger,
      onRestoreAll: _restoreAllFromLedger,
      onClear: () {
        if (mounted) setState(_deleted.clear);
      },
    );
    // 弹窗内恢复是逐个 setState 的；关闭后兜底同步一次角标。
    if (mounted) setState(() {});
  }

  /// 恢复单条：仓库 `restore` 已处理「同 key 已被插件重新 upsert」的合并语义。
  Future<void> _restoreFromLedger(CollectEntry entry) async {
    await _controller.restore(entry);
    if (!mounted) return;
    setState(() => _deleted.remove(entry));
    WywDialog.showToast(message: '已恢复「${entry.title}」');
  }

  Future<void> _restoreAllFromLedger(List<CollectEntry> entries) async {
    await _controller.restoreBatch(entries);
    if (!mounted) return;
    setState(_deleted.clear);
    WywDialog.showToast(message: '已恢复 ${entries.length} 条');
  }

  /// 清空入口：清空未收藏 / 清空全部（都需输入「清除」二次确认）。
  Widget _buildClearMenu() {
    return KazumiMenuButton(
      menuChildren: [
        KazumiMenuItem(
          label: '清空未收藏',
          onPressed: () => _confirmClear(uncollectedOnly: true),
        ),
        KazumiMenuItem(
          label: '清空全部',
          destructive: true,
          onPressed: () => _confirmClear(uncollectedOnly: false),
        ),
      ],
      builder: (context, toggle) => IconButton(
        onPressed: toggle,
        tooltip: '清空收藏',
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    );
  }

  void _confirmClear({required bool uncollectedOnly}) {
    WywDialog.show(
      builder: (dialogContext) {
        final textController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final confirmed = textController.text.trim() == '清除';
            return AlertDialog(
              title: Text(uncollectedOnly ? '清空未收藏' : '清空全部收藏'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(uncollectedOnly
                      ? '将删除全部「未收藏」记录，已收藏的条目会保留。'
                      : '将删除全部收藏与浏览记录。'),
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
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.outline,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: confirmed
                      ? () {
                          WywDialog.dismiss();
                          // 清空是仓库内部完成的，所以先按当前列表取快照，
                          // 再落盘删除——这样被清掉的条目同样能进「已删除」清单。
                          final removed = uncollectedOnly
                              ? _controller.entries
                                  .where((e) => !e.type.isCollected)
                                  .toList()
                              : _controller.entries.toList();
                          if (uncollectedOnly) {
                            _controller.clearUncollected();
                          } else {
                            _controller.clearAll();
                          }
                          setState(() {
                            _deleted.addAll(removed);
                            _visible = _pageSize;
                          });
                        }
                      : null,
                  child: Text(
                    '清除',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 排序菜单（照 Kazumi `_CollectSortMenu`）。
class _SortMenu extends StatelessWidget {
  const _SortMenu({
    required this.value,
    required this.showLabel,
    required this.onChanged,
  });

  final CollectSort value;
  final bool showLabel;
  final ValueChanged<CollectSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return KazumiMenuButton(
      menuChildren: [
        for (final sort in CollectSort.values)
          KazumiMenuItem(
            label: sort.label,
            selected: value == sort,
            onPressed: () => onChanged(sort),
          ),
      ],
      builder: (context, toggle) => Tooltip(
        message: '排序：${value.label}',
        child: showLabel
            ? TextButton.icon(
                onPressed: toggle,
                style: TextButton.styleFrom(
                  foregroundColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.sort_rounded, size: 20),
                label: Text(value.label),
              )
            : IconButton(
                onPressed: toggle,
                icon: const Icon(Icons.sort_rounded),
              ),
      ),
    );
  }
}
