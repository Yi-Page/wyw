import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/plugins/plugin_type.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/widget/error_widget.dart';
import 'package:wyw/bean/widget/loading_indicator.dart';
import 'search_controller.dart';

/// 搜索页面 UI
///
/// **tab 列表**：派生自 `PluginController.plugins`，**无"全部"聚合 tab**。
///
/// **搜索触发**：仅由用户主动提交触发（搜索框回车 / 搜索按钮）。
/// 切 tab、调整聚合插件选择、点选历史词都只更新状态，不自动搜索；
/// 下拉刷新与失败重试是保留的用户手势入口。
/// 输入 keyword 只更新 `controller.keyword`，不直接调 search。
///
/// **A 方案**：本页面**不持有 Renderer**，不再调 `plugin.invokeWidgets`，
/// 只从 `SearchState.results`（已经是 `List<Widget>`）消费，零渲染代码。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  final TextEditingController _keywordController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final SearchPageController _searchController = inject<SearchPageController>();
  final PluginController _pluginController = inject<PluginController>();
  TabController? _tabController;

  /// 当前分类筛选（null = 全部）
  PluginType? _selectedCategory;

  /// 聚合区块的展开状态（默认折叠：只展示一行结果）。
  final Set<String> _expandedSections = {};

  /// 聚合搜索选中的插件名；null = 全部可见插件（未自定义过）。
  Set<String>? _aggregateSelection;

  /// 聚合页顶部「搜索插件」选择面板是否展开（**默认收起**，点头部展开）。
  bool _aggregateSelectorExpanded = false;

  /// 每个插件的滚动控制器（TabBarView 多个 ScrollView 不能共用一个 controller）。
  final Map<String, ScrollController> _scrollControllers = {};

  ScrollController _scrollControllerFor(String pluginName) =>
      _scrollControllers.putIfAbsent(pluginName, () => ScrollController());

  /// 当前 tab controller（懒初始化，plugins 加载后才有值）
  TabController get tabController => _tabController!;

  @override
  void initState() {
    super.initState();
    // 页面重建（底部 tab 切走再切回，State 被 dispose 后重新创建）时，
    // 从单例 controller 恢复上次搜索词，避免输入框空白却仍持有旧 keyword。
    _keywordController.text = _searchController.keyword;
    _rebuildTabController();
  }

  /// 当前分类筛选下的可见插件（已启用 + 分类过滤；禁用插件不在 plugins 中）。
  List<Plugin> _visiblePlugins() {
    final all = _pluginController.plugins;
    if (_selectedCategory == null) return all.toList();
    return all.where((p) => p.type == _selectedCategory).toList();
  }

  /// tab 单元 key 的有序列表：首位是聚合 tab（全部），其后是各插件名。
  ///
  /// 无可见插件时返回空（页面显示"请先添加插件 / 该分类暂无插件"）。
  List<String> _tabKeys() {
    final visible = _visiblePlugins();
    if (visible.isEmpty) return const [];
    return [searchAllKey, ...visible.map((p) => p.name)];
  }

  /// 重建 tabController（plugins / 分类变化时 dispose 旧 + 建新）
  ///
  /// **原因**：`TabController.length` 是 final，必须 dispose + 重建。
  /// [force] 为 true 时即使长度不变也强制重建（分类切换场景）。
  /// 重建时用 `initialIndex` 恢复上次激活的 tab（controller 是单例，
  /// `activeTabKey` 跨页面存活），避免切页回来后 tab 被重置到 0，
  /// 与持久化的激活状态不一致。
  void _rebuildTabController({bool force = false}) {
    final keys = _tabKeys();
    final length = keys.length;
    if (length == 0) {
      final old = _tabController;
      if (old != null) {
        old.removeListener(_onTabChanged);
        old.dispose();
        _tabController = null;
      }
      return;
    }
    if (!force && _tabController != null && _tabController!.length == length) {
      return;
    }
    // 先释放旧 controller 再创建新的：本 State 用 TickerProviderStateMixin，
    // 允许生命周期内多次重建 TabController；先释放旧的避免旧 TabBar/TabBarView
    // 在下一帧重建前仍引用已被替换的 controller。
    final old = _tabController;
    if (old != null) {
      old.removeListener(_onTabChanged);
      old.dispose();
    }
    final activeIndex = _searchController.activeTabKey == null
        ? 0
        : keys.indexOf(_searchController.activeTabKey!);
    _tabController = TabController(
      length: length,
      initialIndex: activeIndex < 0 ? 0 : activeIndex,
      vsync: this,
    );
    _tabController!.addListener(_onTabChanged);
    // 新 controller 建立后立即激活默认 tab，否则 activeTabKey 保持 null，
    // 聚合视图不知道该展示哪些源的状态。
    // 用 activateTab（不触发搜索）：这里是程序化恢复，恢复页面时不应
    // 自动发起搜索，搜索只由用户主动提交触发。
    final current = _searchController.activeTabKey;
    if (current == null || !keys.contains(current)) {
      _searchController.activateTab(keys[0]); // 默认聚合 tab
    }
  }

  /// 切换分类筛选
  void _selectCategory(PluginType? type) {
    if (_selectedCategory == type) return;
    setState(() {
      _selectedCategory = type;
      _aggregateSelection = null; // 分类变了，选择重置为「全部」
    });
    _rebuildTabController(force: true);
  }

  void _onTabChanged() {
    // 动画过程中也会触发；只在真正切换完成时通知 controller
    if (tabController.indexIsChanging) return;
    final keys = _tabKeys();
    final i = tabController.index;
    if (i < 0 || i >= keys.length) return;
    // 切 tab 只切换视图（activateTab 不触发搜索）：已搜过的 tab 显示
    // 已有结果；未搜过的显示占位，等用户再次主动提交。
    _searchController.activateTab(keys[i]);
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _scrollControllers.clear();
    _keywordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String keyword) {
    _focusNode.unfocus(); // 提交后收起键盘
    // 记录历史 + 按当前 tab 分发：聚合 → 选中的插件（未自定义则全部可见）；
    // 单源 → 该插件
    _searchController.submitSearch(
      keyword,
      pluginNames: _aggregateNames(),
    );
  }

  /// 聚合搜索实际参与的插件名（未自定义选择时 = 全部可见插件）。
  List<String> _aggregateNames() {
    final visible = _visiblePlugins().map((p) => p.name).toList();
    final sel = _aggregateSelection;
    if (sel == null) return visible;
    // 显式清空选择（「一键取消」）时不选择任何插件
    if (sel.isEmpty) return const [];
    final filtered = visible.where((n) => sel.contains(n)).toList();
    // 选择里已没有任何可见插件（分类切换/插件删除）时兜底为全部
    return filtered.isEmpty ? visible : filtered;
  }

  /// 清空输入框（同步清空 keyword，避免切 tab 用旧词搜索）。
  void _clearKeyword() {
    _keywordController.clear();
    _searchController.setKeyword('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: Container(
          color: Theme.of(context).appBarTheme.backgroundColor,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordController,
                  focusNode: _focusNode,
                  cursorColor: Theme.of(context).colorScheme.primary,
                  // 点输入框以外的任何地方 → 输入框失焦（键盘收起）。
                  // TapRegion 只做通知，不拦截事件：点击仍会正常落到
                  // 被点的卡片/Tab 上，不会影响其自身点击。
                  onTapOutside: (_) => _focusNode.unfocus(),
                  // 输入实时同步 controller.keyword（不触发搜索，仅更新状态），
                  // 保证清空输入框后 keyword 同步清空，切 tab 不会用旧词搜索；
                  // 搜索只在用户主动提交（回车 / 搜索按钮）时触发。
                  onChanged: _searchController.setKeyword,
                  decoration: InputDecoration(
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelText: '输入搜索内容',
                    alignLabelWithHint: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    // 有内容时显示「清空」；「最近搜索」弹层入口；搜索键
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _keywordController,
                      builder: (_, value, __) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (value.text.isNotEmpty)
                            IconButton(
                              tooltip: '清空',
                              icon: const Icon(Icons.clear),
                              onPressed: _clearKeyword,
                            ),
                          IconButton(
                            tooltip: '最近搜索',
                            icon: const Icon(Icons.manage_history),
                            onPressed: _showSearchHistoryPopup,
                          ),
                          IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () => _onSearch(_keywordController.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                  onSubmitted: _onSearch,
                ),
              ),
            ],
          ),
        ),
        actions: const [WywAppBarMenuButton(pagePath: '/tab/search/')],
      ),
      floatingActionButton: _buildFloatButton(),
      body: SafeArea(
        // 页面主体保持普通结构（无叠层）；「最近搜索」走 WywDialog 弹层
        child: Observer(
          builder: (_) {
            final plugins = _pluginController.plugins;
            final visible = _visiblePlugins();
            final keys = _tabKeys();
            final hasDisabled =
                _pluginController.disabledPluginNames.isNotEmpty;
            // tab 单元数变化（plugins 加载 / 分类切换）时重建 tabController
            if (_tabController == null ||
                _tabController!.length != keys.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_tabController == null ||
                    _tabController!.length != keys.length) {
                  _rebuildTabController(force: true);
                  if (mounted) setState(() {});
                }
              });
            }
            final tc = _tabController;
            return Column(
              children: [
                if (plugins.isNotEmpty)
                  Container(
                    color: Theme.of(context).appBarTheme.backgroundColor,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '选择分类',
                          onPressed: _showCategoryPicker,
                          icon: const Icon(Icons.list),
                        ),
                        if (tc != null && tc.length == keys.length)
                          Expanded(
                            child: TabBar(
                              isScrollable: true,
                              controller: tc,
                              tabs: _buildTabList(keys),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: plugins.isEmpty
                      ? _buildCenterMessage(
                          icon: Icons.extension_off,
                          title: hasDisabled ? '当前没有启用的插件' : '请先添加插件',
                        )
                      : visible.isEmpty
                          ? _buildCenterMessage(
                              icon: Icons.category_outlined,
                              title: '该分类暂无插件',
                            )
                          : tc == null || tc.length != keys.length
                              ? const Center(child: LoadingIndicator())
                              : TabBarView(
                                  controller: tc,
                                  children: keys
                                      .map((k) => _buildTabContent(k))
                                      .toList(),
                                ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 单个 tab 的内容（四态：初始 / loading / error / results）。
  /// [key] 为聚合 key（`searchAllKey`）时渲染聚合视图。
  Widget _buildTabContent(String key) {
    if (key == searchAllKey) return _buildAllTab();
    final pluginName = key;
    return Observer(builder: (_) {
      final state = _searchController.tabStates[pluginName];
      // 初始：未搜索过
      if (state == null) {
        return _buildCenterMessage(
          icon: Icons.search,
          title: '请输入关键词',
        );
      }
      // 加载中
      if (state.loading) {
        return const Center(child: LoadingIndicator());
      }
      // 错误
      if (state.error != null) {
        return SelectableRegion(
          selectionControls: materialTextSelectionControls,
          child: Center(
            child: GeneralErrorWidget(
              errMsg: state.error!,
              onRetry: () => _searchController.search(
                  pluginName, _searchController.keyword),
            ),
          ),
        );
      }
      // 空结果（⑥：带换关键词引导）
      if (state.results.isEmpty) {
        return _buildCenterMessage(
          icon: Icons.search_off,
          title: '未找到结果',
          subtitle: '换个关键词试试',
        );
      }
      // 有结果：直接消费 Widget 列表（A 方案）
      return SelectableRegion(
          selectionControls: materialTextSelectionControls,
          child: _buildResultsGrid(pluginName, state));
    });
  }

  /// 结果网格 + 无限滚动 + 底部 footer。
  ///
  /// 滚动接近底部（距底部 200px）时触发 `loadMore`；`loadMore` 内部有
  /// `loadingMore`/`hasMore` 防重，重复触发安全。
  ///
  /// **内容不足一屏**时无法通过滚动触发 loadMore，改由右下角浮动按钮的
  /// 下箭头手动搜索下一页。
  ///
  /// **⑥ 自适应高度**：不用固定 `mainAxisExtent`，改为按行 `IntrinsicHeight`
  /// 取本行最高卡片的高度——不同插件卡片高度不同也不会裁剪/留白。
  Widget _buildResultsGrid(String pluginName, SearchState state) {
    final crossCount = _crossCount();
    final cards = state.results;
    final controller = _scrollControllerFor(pluginName);

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (_isNearBottom(n.metrics)) {
          _searchController.loadMore(pluginName);
        }
        return false;
      },
      child: RefreshIndicator(
        // 下拉刷新：重新搜索该插件第一页；关键词为空时无操作（返回已完成的 Future）
        onRefresh: () async {
          final kw = _searchController.keyword;
          if (kw.trim().isEmpty) return;
          await _searchController.search(pluginName, kw);
        },
        child: CustomScrollView(
          controller: controller,
          // AlwaysScrollable：内容不足一屏时也允许下拉触发刷新
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildCardRow(
                      _chunkCards(cards, index * crossCount), crossCount),
                  childCount: (cards.length / crossCount).ceil(),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildLoadMoreFooter(pluginName, state),
            ),
          ],
        ),
      ),
    );
  }

  /// 结果列数：宽屏 3 列 / 平板 2 列 / 手机 1 列。
  int _crossCount() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth > 900) return 3;
    if (screenWidth > 600) return 2;
    return 1;
  }

  /// 从 [list] 的 [start] 起取至多 [crossCount] 个元素（最后一行可能不满）。
  List<Widget> _chunkCards(List<Widget> list, int start) {
    final end = (start + _crossCount()).clamp(0, list.length);
    return list.sublist(start, end);
  }

  /// 自适应行：`IntrinsicHeight` 取本行最高卡片的高度，行内所有卡片撑满该高度
  /// （比固定 `mainAxisExtent` 更稳——不同插件卡片高度不同也不会裁剪/留白）。
  Widget _buildCardRow(List<Widget> cards, int crossCount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < crossCount; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 4, right: i == crossCount - 1 ? 0 : 4),
                  child: i < cards.length ? cards[i] : const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============ ⑤ 聚合 tab（全部） ============

  /// 聚合视图：顶部是可收起的「搜索插件」选择面板（默认全选，随内容滚动，
  /// 滚到顶部即可调整参与搜索的插件），下方按源分组展示各源结果；
  /// 每个区块默认折叠（只展示一行结果）。
  Widget _buildAllTab() {
    final selectedNames = _aggregateNames();
    final selected =
        _visiblePlugins().where((p) => selectedNames.contains(p.name)).toList();
    return Observer(builder: (_) {
      final anySearched =
          selected.any((p) => _searchController.tabStates[p.name] != null);
      final anyLoading = selected
          .any((p) => _searchController.tabStates[p.name]?.loading ?? false);
      final anyResults = selected.any((p) =>
          (_searchController.tabStates[p.name]?.results ?? const [])
              .isNotEmpty);

      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildAggregateSelector(selectedNames)),
          if (selected.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildCenterMessage(
                icon: Icons.extension_off,
                title: '未选择搜索插件',
                subtitle: '展开上方面板，选择要搜索的插件',
              ),
            )
          else if (!anySearched)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildCenterMessage(
                icon: Icons.search,
                title: '输入关键词搜索选中来源',
              ),
            )
          else if (!anyResults && !anyLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildCenterMessage(
                icon: Icons.search_off,
                title: '选中来源均未找到结果',
                subtitle: '换个关键词或调整搜索插件试试',
              ),
            )
          else ...[
            if (anyLoading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: LoadingIndicator(size: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '正在搜索 ${selected.where((p) => _searchController.tabStates[p.name]?.loading ?? false).length}/${selected.length} 个来源…',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            for (final p in selected)
              SliverToBoxAdapter(child: _buildAllSection(p)),
          ],
        ],
      );
    });
  }

  /// 聚合搜索的插件选择面板：头部可收起；展开时列出当前分类全部插件的
  /// 多选 chip。改动选择只更新选择状态，**不自动重搜**；新选择在用户
  /// 下次主动提交搜索时生效。
  Widget _buildAggregateSelector(List<String> selectedNames) {
    final visible = _visiblePlugins();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 0, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(
                () => _aggregateSelectorExpanded = !_aggregateSelectorExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '搜索插件（${selectedNames.length}/${visible.length}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  // 「全选 / 一键取消」：与标题同行，点击不会展开/收起面板
                  TextButton.icon(
                    style: _compactTextButtonStyle(),
                    onPressed: _selectAllAggregatePlugins,
                    icon: const Icon(Icons.select_all, size: 14),
                    label: const Text('全选'),
                  ),
                  const SizedBox(width: 2),
                  TextButton.icon(
                    style: _compactTextButtonStyle(),
                    onPressed: _clearAllAggregatePlugins,
                    icon: const Icon(Icons.deselect, size: 14),
                    label: const Text('取消全选'),
                  ),
                  Icon(
                    _aggregateSelectorExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_aggregateSelectorExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in visible)
                    FilterChip(
                      label: Text(p.name, style: const TextStyle(fontSize: 13)),
                      selected: selectedNames.contains(p.name),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _toggleAggregatePlugin(p.name),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 勾选/取消一个聚合搜索插件（只更新选择，不自动重搜；
  /// 新选择在下次主动提交时生效）。
  void _toggleAggregatePlugin(String name) {
    setState(() {
      final visible = _visiblePlugins().map((p) => p.name).toSet();
      _aggregateSelection ??= visible;
      final sel = Set<String>.from(_aggregateSelection!);
      if (sel.contains(name)) {
        sel.remove(name);
      } else {
        sel.add(name);
      }
      // 取消到 0 个 = 显式「不选任何插件」，与「取消全选」同一语义；
      // 空集不再回落成 null（null 表示未自定义 = 全部）。
      _aggregateSelection = sel;
      // 选择变化后各区块折叠态重置意义不大，保留即可
    });
  }

  /// 全选：回到默认「全部插件」状态。
  void _selectAllAggregatePlugins() {
    setState(() {
      _aggregateSelectorExpanded = true;
      _aggregateSelection = null;
    });
  }

  /// 一键取消：清空聚合插件选择（不选择任何插件）。
  void _clearAllAggregatePlugins() {
    setState(() {
      _aggregateSelectorExpanded = true;
      _aggregateSelection = <String>{};
    });
  }

  /// 紧凑型文本按钮样式（用于聚合选择面板头部行的「全选 / 取消全选」）。
  ButtonStyle _compactTextButtonStyle() {
    return TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    );
  }

  /// 单个来源的聚合区块：头（可点展开/收起）+ 该源结果。
  /// **默认折叠**：只展示一行结果；展开才显示全部已加载结果。
  Widget _buildAllSection(Plugin p) {
    final name = p.name;
    return Observer(builder: (_) {
      final st = _searchController.tabStates[name];
      final rs = st?.results ?? const <Widget>[];
      final expanded = _expandedSections.contains(name);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expandedSections.remove(name);
              } else {
                _expandedSections.add(name);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
              child: Row(
                children: [
                  Icon(p.type.icon, size: 16, color: p.type.color),
                  const SizedBox(width: 6),
                  Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  if (st != null &&
                      !st.loading &&
                      st.error == null &&
                      rs.isNotEmpty)
                    Text(
                      '${rs.length} 条',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  const Spacer(),
                  if (st != null && st.error != null)
                    TextButton.icon(
                      onPressed: () => _searchController.search(
                          name, _searchController.keyword),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                    ),
                  if (rs.isNotEmpty)
                    TextButton(
                      onPressed: () => _goToPluginTab(name),
                      child: const Text('查看全部'),
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (st == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('未搜索',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            )
          else if (st.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: LoadingIndicator(size: 20),
                ),
              ),
            )
          else if (st.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                st.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else if (rs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('无结果',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            )
          else if (expanded)
            _buildSectionGrid(rs)
          else
            // 折叠：只展示一行结果
            _buildSectionGrid(rs.take(_crossCount()).toList()),
        ],
      );
    });
  }

  /// 聚合区块里的非滚动网格（shrinkWrap，不嵌套滚动）。
  Widget _buildSectionGrid(List<Widget> cards) {
    final crossCount = _crossCount();
    final rowCount = (cards.length / crossCount).ceil();
    return Column(
      children: [
        for (var r = 0; r < rowCount; r++)
          _buildCardRow(_chunkCards(cards, r * crossCount), crossCount),
      ],
    );
  }

  /// 切到某插件的完整 tab（该 tab 缓存未过期，不会重复搜索）。
  void _goToPluginTab(String name) {
    final keys = _tabKeys();
    final idx = keys.indexOf(name);
    if (idx < 0) return;
    _tabController?.animateTo(
      idx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ============ TabBar 列表 ============

  /// 构造 TabBar 的 tab 列表：首位「全部」聚合 tab，其后各插件 tab。
  List<Widget> _buildTabList(List<String> keys) {
    final pluginByName = {
      for (final p in _visiblePlugins()) p.name: p,
    };
    return [
      for (final k in keys)
        if (k == searchAllKey)
          Tab(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.apps, size: 16),
                SizedBox(width: 4),
                Text('全部'),
              ],
            ),
          )
        else
          Tab(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pluginByName[k]?.type.icon,
                  size: 16,
                  color: pluginByName[k]?.type.color,
                ),
                const SizedBox(width: 4),
                Text(k),
              ],
            ),
          ),
    ];
  }

  // ============ ④ 搜索历史面板（WywDialog 弹层，顶部对齐） ============

  /// 打开「最近搜索」弹层。
  ///
  /// 走项目验证过的 WywDialog（原生 showDialog 通道，分类选择弹窗同款）：
  ///   - 蒙层点击**只关闭面板**，不触发页面其它交互（barrierDismissible）；
  ///   - 面板浮在内容上方，不挤占布局；
  ///   - chip 点选 / 单条删除 / 一键清空都在 dialog 子树里，交互可靠。
  void _showSearchHistoryPopup() {
    if (_searchController.recentKeywords.isEmpty) {
      WywDialog.showToast(message: '暂无搜索记录');
      return;
    }
    WywDialog.show(
      clickMaskDismiss: true,
      builder: (dialogContext) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // 顶到 appbar 下方（showDialog 默认已套 SafeArea）
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(dialogContext).top + kToolbarHeight + 8,
            left: 16,
            right: 16,
          ),
          child: Material(
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(dialogContext).colorScheme.surfaceContainerLow,
            // Observer：面板打开期间删除/清空历史词时内容实时更新
            child: Observer(builder: (_) {
              final recent = _searchController.recentKeywords;
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('最近搜索',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const Spacer(),
                        IconButton(
                          tooltip: '清空历史',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            _searchController.clearRecentKeywords();
                            WywDialog.dismiss();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final k in recent)
                          InputChip(
                            label:
                                Text(k, style: const TextStyle(fontSize: 13)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _useRecentKeyword(k),
                            onDeleted: () =>
                                _searchController.removeRecentKeyword(k),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// 点选历史词：回填输入框 → 关闭面板 → 聚焦输入框。
  ///
  /// **不自动提交**：由用户按键盘搜索键/回车或点搜索按钮确认提交，
  /// 避免误点历史词立即发起搜索。
  void _useRecentKeyword(String k) {
    WywDialog.dismiss();
    _keywordController.text = k;
    _keywordController.selection = TextSelection.collapsed(offset: k.length);
    _focusNode.requestFocus();
  }

  /// 右下角浮动按钮。
  ///
  /// - 页面在顶部：显示下箭头，点击搜索下一页（`loadMore`）；
  /// - 页面不在顶部：显示上箭头，点击回到顶部。
  ///
  /// 只有当前 tab 有结果时才显示；顶部且已无更多页时不显示。
  Widget _buildFloatButton() {
    return Observer(builder: (_) {
      final pluginName = _searchController.activeTabPluginName;
      if (pluginName == null) return const SizedBox.shrink();
      final state = _searchController.tabStates[pluginName];
      if (state == null || state.results.isEmpty) {
        return const SizedBox.shrink();
      }

      final controller = _scrollControllerFor(pluginName);
      // ScrollController 会在滚动位置变化时 notifyListeners，
      // 用 AnimatedBuilder 监听以实时切换箭头方向。
      return AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final atTop = !controller.hasClients || controller.offset <= 0;
          // 顶部且没有下一页时无需显示按钮
          if (atTop && !state.hasMore) return const SizedBox.shrink();

          final loadingMore = state.loadingMore;
          final Widget child = atTop && loadingMore
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: LoadingIndicator(size: 20),
                )
              : Icon(atTop ? Icons.arrow_downward : Icons.arrow_upward);

          return FloatingActionButton(
            tooltip: atTop ? '搜索下一页' : '回到顶部',
            onPressed: atTop
                ? (state.hasMore && !loadingMore
                    ? () => _searchController.loadMore(pluginName)
                    : null)
                : () => controller.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    ),
            child: child,
          );
        },
      );
    });
  }

  /// 是否已接近滚动底部（内容不足一屏无法滚动时不算，交由浮动按钮处理）。
  bool _isNearBottom(ScrollMetrics metrics) =>
      metrics.maxScrollExtent > 0 &&
      metrics.pixels >= metrics.maxScrollExtent - 200;

  /// 列表底部 footer：加载中 / 加载失败重试 / 没有更多。
  Widget _buildLoadMoreFooter(String pluginName, SearchState state) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: LoadingIndicator(size: 20),
          ),
        ),
      );
    }
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: TextButton.icon(
            onPressed: () => _searchController.loadMore(pluginName),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text('加载失败，点击重试（${state.loadMoreError}）'),
          ),
        ),
      );
    }
    if (!state.hasMore && state.results.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// 打开分类选择弹窗（由列表按钮触发）。
  ///
  /// 必须用 [WywDialog] 挂在 **root navigator** 上：搜索页位于
  /// `RouterOutlet` 内部的 pages 式嵌套 Navigator 里，若直接
  /// `showDialog(context: context)` 会把 dialog 压进该 Navigator，
  /// 在弹窗关闭 + 分类切换触发 pages 重建时会触发
  /// `Navigator.pages must not be empty` / `_History[-1]` 崩溃。
  void _showCategoryPicker() {
    WywDialog.show(
      clickMaskDismiss: true,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择分类'),
        children: [
          _buildCategoryDialogOption(
            dialogContext,
            null,
            '全部',
            Icons.all_inclusive,
          ),
          for (final t in PluginType.values)
            _buildCategoryDialogOption(dialogContext, t, t.label, t.icon),
        ],
      ),
    );
  }

  Widget _buildCategoryDialogOption(
    BuildContext dialogContext,
    PluginType? type,
    String label,
    IconData icon,
  ) {
    final selected = _selectedCategory == type;
    return SimpleDialogOption(
      onPressed: () {
        Navigator.of(dialogContext).pop();
        _selectCategory(type);
      },
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: type?.color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (selected)
            Icon(
              Icons.check,
              size: 18,
              color: Theme.of(dialogContext).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildCenterMessage({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return GeneralEmptyState(icon: icon, title: title, subtitle: subtitle);
  }
}
