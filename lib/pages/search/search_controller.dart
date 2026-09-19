import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/js/js_extends/js_bridge.dart';
import 'package:wyw/js/entity/js_entity.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';
import '../plugin/plugin_controller.dart';
import 'package:wyw/js/js_extends/js_descriptor.dart';
import 'package:wyw/utils/plugin_action.dart';

part 'search_controller.g.dart';

/// 聚合 tab 的稳定 key（不可能是真实插件名）。
const String searchAllKey = '__all__';

// ignore: library_private_types_in_public_api
class SearchPageController = _SearchPageController with _$SearchPageController;

/// 单个 tab 的搜索状态。
///
/// 不可变值对象：每次状态变化都通过 [copyWith] 返回新引用，
/// 让 MobX `ObservableMap` 检测到引用变化从而触发 Observer rebuild。
class SearchState {
  /// 是否正在加载
  final bool loading;

  /// 搜索结果 Widget 列表
  final List<Widget> results;

  /// 错误信息（null 表示无错误）
  final String? error;

  /// 上次搜索时间（用于判断缓存是否过期）
  final DateTime? lastSearchTime;

  /// 已加载到的页码（从 1 起）
  final int page;

  /// 是否还有下一页
  final bool hasMore;

  /// 是否正在加载更多（loadMore 进行中）
  final bool loadingMore;

  /// 加载更多失败的错误信息（null = 无错误）
  final String? loadMoreError;

  const SearchState({
    this.loading = false,
    this.results = const [],
    this.error,
    this.lastSearchTime,
    this.page = 1,
    this.hasMore = true,
    this.loadingMore = false,
    this.loadMoreError,
  });

  SearchState copyWith({
    bool? loading,
    List<Widget>? results,
    String? error,
    DateTime? lastSearchTime,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    String? loadMoreError,
  }) =>
      SearchState(
        loading: loading ?? this.loading,
        results: results ?? this.results,
        error: error,
        lastSearchTime: lastSearchTime ?? this.lastSearchTime,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: loadMoreError,
      );
}

/// 搜索页控制器（mobx 版）。
///
/// **生命周期**：应用级单例（`IndexModule.binds` 注册为 singleton）。
/// `init()` 必须在 `PluginController.init()` 之后调用——由 `init_page._pluginInit`
/// 顺序触发。
///
/// **状态机**：
///   - `keyword` 当前搜索关键词
///   - `activeTabKey` 当前激活的 tab 单元（[searchAllKey] = 聚合 / 插件名 = 单源；
///     null = 未选）；`activeTabPluginName` 为其派生（聚合时为 null）
///   - `recentKeywords` 最近搜索词（本地持久化）
///   - `tabStates` 每个插件的搜索状态 map（聚合视图按源读取这些状态）
///
/// **错误传播**：
///   - `EntityInvokeException` → `tabStates[p].error = e.message`（页面显示 GeneralErrorWidget）
///   - `TimeoutException` → `tabStates[p].error = "搜索超时"` + `WywDialog.showToast`
abstract class _SearchPageController with Store {
  ReactionDisposer? _pluginsReaction;
  bool _initialized = false;

  /// 每个插件的搜索请求序号（竞态防护）。
  ///
  /// 快速切换 tab / 连续提交不同关键词时，旧请求可能比新请求晚返回；
  /// 只有「当前 token == 发起请求时的 token」的结果才允许写入 tabStates，
  /// 过期请求（含失败路径）一律丢弃，避免旧结果覆盖新结果。
  final Map<String, int> _searchTokens = {};

  _SearchPageController();

  // ===== Observables =====

  /// 搜索历史保存键（存 Hive `_setting` box 的动态字符串列表）。
  static const String _recentKey = 'search_history';
  static const int _maxRecent = 10;

  @observable
  String keyword = '';

  /// 当前激活的 tab 单元 key：`searchAllKey`（聚合）或插件名。
  @observable
  String? activeTabKey;

  /// 当前激活的插件名；聚合 tab 时为 null。
  String? get activeTabPluginName =>
      activeTabKey == searchAllKey ? null : activeTabKey;

  /// 聚合 tab 是否激活。
  bool get isAggregateActive => activeTabKey == searchAllKey;

  /// 最近搜索词（最新的在前，最长 [_maxRecent] 条，本地持久化）。
  @observable
  List<String> recentKeywords = const [];

  @observable
  ObservableMap<String, SearchState> tabStates = ObservableMap.of({});

  // ===== 生命周期 =====

  /// 注册 plugins 变化反应（清理已删除插件的 state）。
  ///
  /// **幂等**：重复调用无副作用。
  @action
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // 读取本地持久化的最近搜索词（GStorage.init 必须先完成）
    try {
      recentKeywords =
          List.unmodifiable(GStorage.getStringListSettingByName(_recentKey));
    } catch (e) {
      // 持久化不可用时不阻塞搜索页
      WywLogger().d('${LogTag.search} 读取最近搜索词失败（已忽略）', error: e);
    }
    final pluginController = inject<PluginController>();
    _pluginsReaction = reaction(
      (_) => pluginController.plugins.map((p) => p.name).toList(),
      (names) {
        // 清理已删除插件的 state
        for (final k in tabStates.keys.toList()) {
          if (!names.contains(k)) tabStates.remove(k);
        }
        _searchTokens.removeWhere((k, _) => !names.contains(k));
        // 如果当前 active 是已删除的插件，重置（聚合 tab 不受影响）
        if (activeTabKey != null &&
            activeTabKey != searchAllKey &&
            !names.contains(activeTabKey)) {
          activeTabKey = null;
        }
      },
    );
  }

  /// 释放 reaction（应用退出/单例销毁时调用）
  void dispose() {
    _pluginsReaction?.call();
    _pluginsReaction = null;
    _initialized = false;
  }

  // ===== Actions =====

  @action
  void setKeyword(String k) {
    keyword = k;
  }

  /// 激活 tab（聚合 [searchAllKey] 或插件名），**不**触发搜索。
  ///
  /// 搜索只由用户主动提交（搜索框回车 / 搜索按钮）触发；切 tab 仅切换
  /// 视图：已搜过的 tab 显示已有结果，未搜过的显示占位，等下次提交。
  void activateTab(String? key) {
    activeTabKey = key;
  }

  /// 提交搜索：记录历史 → 按当前激活 tab 分发。
  ///
  /// - 聚合 tab：对所有 [pluginNames]（默认全部启用插件）并发搜索；
  /// - 单插件 tab：只搜该插件。
  @action
  Future<void> submitSearch(String keyword, {List<String>? pluginNames}) async {
    final k = keyword.trim();
    setKeyword(k);
    _recordKeyword(k);
    if (activeTabKey == searchAllKey) {
      final names = pluginNames ??
          inject<PluginController>().plugins.map((p) => p.name).toList();
      await searchAll(k, names);
    } else if (activeTabKey != null) {
      await search(activeTabKey!, k);
    }
  }

  /// 聚合搜索：对指定插件并发搜索。
  ///
  /// 每个插件独立走 [search]（自带请求 token 竞态防护），失败源只影响自身
  /// 的 tabStates，不阻断其它源。
  @action
  Future<void> searchAll(String keyword, List<String> pluginNames) async {
    await Future.wait(pluginNames.map((n) => search(n, keyword)));
  }

  /// 记录最近搜索词（去重置顶、上限 [_maxRecent] 条、本地持久化）。
  void _recordKeyword(String k) {
    if (k.isEmpty) return;
    final list = List<String>.from(recentKeywords)..remove(k);
    list.insert(0, k);
    if (list.length > _maxRecent) list.removeRange(_maxRecent, list.length);
    recentKeywords = List.unmodifiable(list);
    GStorage.putStringListSettingByName(_recentKey, list);
  }

  @action
  void removeRecentKeyword(String k) {
    final list = List<String>.from(recentKeywords)..remove(k);
    recentKeywords = List.unmodifiable(list);
    GStorage.putStringListSettingByName(_recentKey, list);
  }

  @action
  void clearRecentKeywords() {
    recentKeywords = const [];
    GStorage.putStringListSettingByName(_recentKey, const []);
  }

  /// 执行搜索：写入 loading → 调 `Plugin.invokeWidgets` → 写入 results (Widget) / error。
  ///
  /// **竞态防护**：发起时取 token，`await` 返回后若 token 已过期（期间有更新的
  /// 搜索），丢弃本次结果（含失败路径），不写 tabStates。
  @action
  Future<void> search(String pluginName, String keyword) async {
    final plugin = inject<PluginController>().getPlugin(pluginName);
    if (plugin == null) return;

    final token = (_searchTokens[pluginName] ?? 0) + 1;
    _searchTokens[pluginName] = token;

    // 每次 copyWith 返回新引用，让 ObservableMap 检测到引用变化触发 Observer rebuild
    final base = tabStates[pluginName] ?? const SearchState();
    tabStates[pluginName] = base.copyWith(
      loading: true,
      error: null,
      page: 1,
      hasMore: true,
      loadingMore: false,
      loadMoreError: null,
    );

    try {
      // 选项 A：直接拿 List<Widget>，不再返回 List<Map>
      final widgets = await plugin.invokeWidgets(
        'search',
        args: [keyword, 1],
        onAction: (action) => _handleAction(pluginName, action),
        onNavigate: (nav, sourcePluginName) async {
          JSEngineCommonApi.onNavigateToDescriptor?.call({
            'plugin': sourcePluginName,
            'method': nav.method,
            'args': nav.args,
            'title': nav.title,
            'actions': nav.actions,
          });
          return;
        },
        sourcePluginName: pluginName,
      );
      if (_searchTokens[pluginName] != token) return; // 过期：已有更新的搜索
      tabStates[pluginName] = (tabStates[pluginName] ?? const SearchState())
          .copyWith(
              loading: false,
              results: widgets,
              lastSearchTime: DateTime.now(),
              page: 1,
              hasMore: widgets.isNotEmpty);
    } on TimeoutException {
      if (_searchTokens[pluginName] != token) return;
      tabStates[pluginName] = (tabStates[pluginName] ?? const SearchState())
          .copyWith(
              loading: false,
              error: '搜索超时',
              lastSearchTime: DateTime.now(),
              hasMore: false);
      WywDialog.showToast(message: '搜索超时');
    } on EntityInvokeException catch (e, s) {
      if (_searchTokens[pluginName] != token) return;
      tabStates[pluginName] = (tabStates[pluginName] ?? const SearchState())
          .copyWith(
              loading: false,
              error: e.message,
              lastSearchTime: DateTime.now(),
              hasMore: false);
      WywLogger().e(
          '${LogTag.search} 搜索方法执行失败 plugin=$pluginName keyword=$keyword',
          error: e,
          stackTrace: s);
    } catch (e, s) {
      if (_searchTokens[pluginName] != token) return;
      tabStates[pluginName] = (tabStates[pluginName] ?? const SearchState())
          .copyWith(
              loading: false,
              error: e.toString(),
              lastSearchTime: DateTime.now(),
              hasMore: false);
      WywLogger().e(
          '${LogTag.search} 搜索出现未知错误 plugin=$pluginName keyword=$keyword',
          error: e,
          stackTrace: s);
    }
  }

  /// 加载下一页：请求 `page+1` 并**追加**到现有结果后。
  ///
  /// **终止条件**：下一页返回空列表，或追加后结果总数未增加（防止旧插件忽略
  /// page 参数导致无限重复第一页），此时 `hasMore=false`。
  ///
  /// **失败处理**：保留已加载结果，`loadMoreError` 记录错误，`hasMore` 保持 true，
  /// 页面 footer 显示重试按钮（再次调用本方法）。
  @action
  Future<void> loadMore(String pluginName) async {
    final state = tabStates[pluginName];
    if (state == null || state.loading || state.loadingMore || !state.hasMore) {
      return;
    }
    final plugin = inject<PluginController>().getPlugin(pluginName);
    if (plugin == null) return;

    // 记录本次 loadMore 所属的搜索会话 token；期间若发生新搜索（token 变化），
    // 本次追加结果作废，避免旧分页内容拼进新搜索结果里。
    final sessionToken = _searchTokens[pluginName];
    final nextPage = state.page + 1;
    tabStates[pluginName] =
        state.copyWith(loadingMore: true, loadMoreError: null);

    try {
      final widgets = await plugin.invokeWidgets(
        'search',
        args: [keyword, nextPage],
        onAction: (action) => _handleAction(pluginName, action),
        onNavigate: (nav, sourcePluginName) async {
          JSEngineCommonApi.onNavigateToDescriptor?.call({
            'plugin': sourcePluginName,
            'method': nav.method,
            'args': nav.args,
            'title': nav.title,
            'actions': nav.actions,
          });
          return;
        },
        sourcePluginName: pluginName,
      );
      if (_searchTokens[pluginName] != sessionToken) return;
      final current = tabStates[pluginName] ?? state;
      final merged = [...current.results, ...widgets];
      final hasMore =
          widgets.isNotEmpty && merged.length > current.results.length;
      tabStates[pluginName] = current.copyWith(
        loadingMore: false,
        results: merged,
        page: nextPage,
        hasMore: hasMore,
        loadMoreError: null,
      );
    } on TimeoutException {
      if (_searchTokens[pluginName] != sessionToken) return;
      tabStates[pluginName] = (tabStates[pluginName] ?? state)
          .copyWith(loadingMore: false, loadMoreError: '加载超时（30s）');
      WywDialog.showToast(message: '加载超时');
    } on EntityInvokeException catch (e, s) {
      if (_searchTokens[pluginName] != sessionToken) return;
      tabStates[pluginName] = (tabStates[pluginName] ?? state)
          .copyWith(loadingMore: false, loadMoreError: e.message);
      WywLogger().e(
          '${LogTag.search} 加载下一页方法执行失败 plugin=$pluginName keyword=$keyword page=$nextPage',
          error: e,
          stackTrace: s);
    } catch (e, s) {
      if (_searchTokens[pluginName] != sessionToken) return;
      tabStates[pluginName] = (tabStates[pluginName] ?? state)
          .copyWith(loadingMore: false, loadMoreError: e.toString());
      WywLogger().e(
          '${LogTag.search} 加载下一页出现未知错误 plugin=$pluginName keyword=$keyword page=$nextPage',
          error: e,
          stackTrace: s);
    }
  }

  /// 按钮点击回调（由 Plugin.invokeWidgets 的 onAction 闭包捕获）
  ///
  /// **职责**：根据 [UiAction.plugin] / `__self__` 解析目标插件，
  /// 调 `plugin.invoke(action.method, action.args)`。
  Future<void> _handleAction(String sourcePluginName, UiAction action) async {
    await invokePluginAction(
      defaultPluginName: sourcePluginName,
      action: action,
    );
  }
}
