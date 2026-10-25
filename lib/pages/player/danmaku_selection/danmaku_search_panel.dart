import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/connected_tabs.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/modules/danmaku/danmaku_library_ref.dart';
import 'package:wyw/modules/danmaku/danmaku_search_response.dart';
import 'package:wyw/modules/danmaku/danmaku_type_filter.dart';
import 'package:wyw/pages/player/danmaku_selection/widgets/library_card.dart';
import 'package:wyw/repositories/danmaku_library_cache_repository.dart';
import 'package:wyw/request/apis/danmaku_api.dart'
    show DandanNotConfiguredException;
import 'package:wyw/services/danmaku/danmaku_library_service.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/utils/constants.dart';

/// 弹幕选择页：**一页搞定**「卡片 → 吸顶区 → 内容」。
///
/// 版式（自 2026-10 反馈重做）：
/// ```text
/// ┌ 库卡片 ─────────────────────────────┐   ← 只有"选中过 / 持久化过"才出现；
/// │ 封面 标题 元信息 简介 标签 刷新       │     选中与"当前使用"共用同一个组件，
/// └────────────────────────────────────┘     所以两处长得完全一样
/// ┌ 搜索 | 选集 ──────────────── 吸顶 ──┐   ← 长列表（柯南 1372 集）滚到一半也能
/// │ 【搜索】搜索框 ＋ 类型下拉           │     切页签、换关键词、筛分集
/// │ 【选集】筛选框                      │     （两个页签各自的搜索框都挂顶）
/// └────────────────────────────────────┘
/// │ 候选列表 / 分集列表（随页滚动）      │
/// ```
/// 整页**只有一个滚动体**（`CustomScrollView`）：卡片、吸顶区、列表一起滚，
/// 而不是"只有搜索结果能滚"。吸顶区里的切换行用 `ConnectedTabs`（M3
/// connected-button 组，Kazumi 播放器的弹幕设置弹窗用的就是它；wyw 里
/// `视频信息` 二级页的「概览/日志」同款），它会按可用宽度把剩余空间平分给各段，
/// 所以天然铺满整行。外层用 `Material` 而不是 `ColoredBox`，否则里面的水波纹会被
/// 带色 ColoredBox 吞掉（同 ListTile 那条断言的老问题）。
///
/// 分集从**磁盘缓存**读（`DanmakuLibraryCacheRepository`）：进度记录里只存库的
/// 小快照 + 引用，重数据（分集/多语言标题/标签）单独按库 id 缓存，因此进场就能
/// 默认展示选集，既不请求网络、也不让每 5–15 秒的进度写入变重。
///
/// 搜索走 `/api/v2/search/anime`（**不**走 `/search/adv`：现有 AppId 实测
/// `errorCode=11 验证用户权限失败`；也刻意不混入 `/search/tmdb`：它的
/// `episodeCount` 恒为 1、`episodeId` 取弹幕为空）。曾经还有一条
/// `/search/episodes`「剧集搜索」兜底入口，按反馈**已删除**（见
/// `docs/danmaku-selection-plan.md`）。
class DanmakuSearchPanel extends StatefulWidget {
  const DanmakuSearchPanel({
    super.key,
    required this.initialKeyword,
    required this.localEpisodeIndex,
    required this.onEpisodeSelected,
    this.current,
    this.onLibraryPersist,
  });

  /// 预填进输入框的关键词（当前剧名）。
  final String initialKeyword;

  /// 正在播放的本地集下标（0-based），用于告诉用户"这一集"是第几集。
  final int localEpisodeIndex;

  /// 用户选定「库 + 分集」：交回外壳取那一集的弹幕并应用。
  ///
  /// 返回 **true 表示这一集真的出弹幕了**——外壳据此决定是否把库写进进度记录：
  /// 只有出得来弹幕的库才值得被记住，所以持久化放在应用成功之后，由本面板发起
  /// （本面板才知道用户正在看的是哪一份快照、年份是多少）。
  final Future<bool> Function(DanmakuBangumiDetail detail, int episodeIndex)
      onEpisodeSelected;

  /// 入场时从进度记录读回的"当前使用"库（null = 还没选过）。
  final DanmakuLibraryRef? current;

  /// 把点选/刷新得到的库条目交回外壳写入进度记录。
  final ValueChanged<DanmakuLibraryRef>? onLibraryPersist;

  @override
  State<DanmakuSearchPanel> createState() => _DanmakuSearchPanelState();
}

/// `/search/anime` 的硬上限：达到这个条数就说明结果被服务端截断了。
const int _searchAnimeLimit = 25;

/// 「搜索 / 选集」切换行高度（`ConnectedTabs` 的 40 + 8 下间距）。
const double _tabsRowHeight = 48;

/// 吸顶区里那一行"搜索/筛选框"的高度（M3 outlined dense 输入框 + 8 下间距）。
const double _searchRowHeight = 52;

/// 吸顶区总高度 = 切换行 + 搜索行。
///
/// 两个页签**各自**的搜索框都挂在这里（反馈："两边搜索框也都做成挂顶"）：长结果
/// 列表或上千集的分集列表滚到一半时，换关键词/筛分集都不用先滚回顶部。
const double _pinnedHeaderHeight = _tabsRowHeight + _searchRowHeight;

class _DanmakuSearchPanelState extends State<DanmakuSearchPanel>
    with SingleTickerProviderStateMixin {
  final DanmakuLibraryService _service = DanmakuLibraryService.instance;
  final DanmakuLibraryCacheRepository _cache =
      DanmakuLibraryCacheRepository.instance;

  /// 「搜索 / 选集」两段切换。用共享的 `ConnectedTabs`（与 Kazumi 播放器弹幕设置
  /// 弹窗、`视频信息` 二级页同一套）。
  ///
  /// **默认落在哪一段看有没有已选库**：选过库时用户要的多半是"这一集用库里的哪一集"，
  /// 所以直接落在「选集」；没选过才从「搜索」开始。
  late final TabController _tabsController = TabController(
    length: 2,
    vsync: this,
    initialIndex: _defaultTabIndex,
  );

  /// 未选库 = 0（搜索）；已选库 = 1（选集）。
  int get _defaultTabIndex => widget.current == null ? 0 : 1;

  late final TextEditingController _keywordController =
      TextEditingController(text: widget.initialKeyword);
  final TextEditingController _episodeFilterController =
      TextEditingController();

  DanmakuTypeFilter _type = DanmakuTypeFilter.all;

  List<DanmakuSearchAnime> _candidates = const [];

  /// 面板内展示的快照（在搜索结果里选中、或刷新后就地更新）。
  ///
  /// 为 null 时才用 `widget.current`（进度记录里那个）。之所以自己持一份：点选/
  /// 刷新要立刻反映在卡片上，而外壳写进度记录**不一定会重建本面板**。
  DanmakuLibraryRef? _shownOverride;

  /// 与当前展示的快照对应的详情（分集/多语言标题/标签）。
  DanmakuBangumiDetail? _detail;
  bool _detailLoading = false;
  String? _detailError;

  bool _searching = false;
  String? _error;

  /// 当前页签（0=搜索，1=选集）。单独存一份是为了只在**真的换页签**时 setState：
  /// `TabController` 的监听在切换动画期间会连发多次。
  int _tabIndex = 0;
  /// 每次搜索自增：封面打分的异步结果回来时据此判断是否已过期。
  int _generation = 0;

  /// 会话内缓存：同一 `(关键词, 类型)` 不重复请求，同一作品详情只取一次。
  ///
  /// 官方文档明确建议缓存搜索结果（2–6 小时）并提醒搜索接口有速率检测机制；
  /// 在面板里来回切条目不该每次都打网络。
  final Map<String, List<DanmakuSearchAnime>> _searchCache = {};
  final Map<int, DanmakuBangumiDetail?> _detailCache = {};

  @override
  void initState() {
    super.initState();
    // 与 `_tabsController.initialIndex` 保持一致，否则监听里的"变了才 setState"
    // 判断会把初值当成一次切换。
    _tabIndex = _tabsController.index;
    _tabsController.addListener(_onTabChanged);
    _seedDetailFromCache();
  }

  @override
  void didUpdateWidget(covariant DanmakuSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.current?.refreshableId;
    final newId = widget.current?.refreshableId;
    if (oldId == newId) return;
    // 外壳换了另一个库（例如用户在别的入口点了分集）：丢掉面板内的覆盖，改用新快照
    // 与它的缓存。若外壳记下来的正是面板刚点过的那个库，则保留覆盖（免得把面板里
    // 刚刷新到的详情回灌成外壳的旧快照）。
    if (_shownOverride?.refreshableId == newId) return;
    _shownOverride = null;
    _detail = newId == null ? null : _cache.read(newId);
    _detailError = null;
  }

  @override
  void dispose() {
    _tabsController.dispose();
    _keywordController.dispose();
    _episodeFilterController.dispose();
    super.dispose();
  }

  // ===== 派生状态 =====

  /// 当前展示的库：面板内选中/刷新的优先，其次才是进度记录里的。
  DanmakuLibraryRef? get _shownRef => _shownOverride ?? widget.current;

  /// 展示的是不是"当前使用"的那个库（决定卡片上是否打「使用中」）。
  bool get _shownIsCurrent {
    final current = widget.current;
    final shown = _shownRef;
    if (current == null || shown == null) return false;
    return current.refreshableId == shown.refreshableId;
  }

  String get _cacheKey =>
      '${_keywordController.text.trim()}|${_type.apiValue ?? ''}';

  /// 进场先用磁盘缓存把分集补上：「当前使用」一进来就能默认展示选集，
  /// 不必等网络（也不产生任何请求）。
  void _seedDetailFromCache() {
    final ref = widget.current;
    if (ref == null) return;
    _detail = _cache.read(ref.refreshableId);
  }

  void _onTabChanged() {
    if (!mounted || _tabsController.index == _tabIndex) return;
    setState(() => _tabIndex = _tabsController.index);
  }

  // ===== 搜索 =====

  Future<void> _search({String? keyword}) async {
    final text = (keyword ?? _keywordController.text).trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入番剧名称');
      return;
    }
    // 接口要求关键词至少 2 个字符，本地先拦一次能省一次无效请求。
    if (text.length < 2) {
      setState(() => _error = '关键词至少 2 个字');
      return;
    }
    if (!_service.isConfigured) {
      setState(() => _error = '未配置弹弹play 凭证，无法检索');
      return;
    }
    _keywordController.text = text;

    final generation = ++_generation;
    final cached = _searchCache[_cacheKey];
    if (cached != null) {
      setState(() {
        _error = null;
        _searching = false;
        _candidates = cached;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _candidates = const [];
      _episodeFilterController.clear();
      // 刻意不清 `_shownOverride`/`_detail`：换关键词只是换候选列表，用户正看着的
      // 那张卡片（以及它的分集）不该跟着消失。
    });

    try {
      final animes = await _service.searchAnime(text, type: _type.apiValue);
      if (!mounted || generation != _generation) return;
      _searchCache[_cacheKey] = animes;
      setState(() {
        _searching = false;
        // **保持弹弹play 自己的相关度顺序**，不重排、不打分。
        //
        // 曾经按「标题 bigram + 封面感知哈希 + 集数接近度」加权重排并在每条上显示
        // 一个"匹配度"百分比，两个问题让那个数字必须拿掉：
        //   1. **不可比**：封面分只给前 10 条算（要下载图片），没算到的按剩余权重
        //      归一化，于是同一列里有的行是三项加权、有的只是两项——两个百分比不是
        //      一把尺子量出来的；
        //   2. **信号本身是噪声**：`/search/anime` 的 `episodeCount` 是弹弹play 侧的
        //      系列总集数，本地集数是插件给的（TMDB 源恒为 1）；封面又是插件图 vs
        //      弹弹play 图，裁剪/水印都不同。
        // 搜索接口本身带相关度排序，用户要的是"能看出来是哪一部"，不是假精确的分数。
        _candidates = animes;
        if (_candidates.isEmpty) _error = '未找到作品';
      });
    } catch (error) {
      WywLogger()
          .w('${LogTag.danmaku} 检索候选作品失败 keyword=$text', error: error);
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is DandanNotConfiguredException) {
      return '未配置弹弹play 凭证，无法检索';
    }
    return '请求失败，请稍后重试';
  }

  // ===== 详情 =====

  /// 取某个库的详情：会话缓存 → 磁盘缓存 → 网络；网络结果写进磁盘缓存。
  ///
  /// 磁盘缓存只在"选中某部作品 / 点刷新"时写（不跟进度一起重写），所以这里是
  /// 唯一写入点之一。
  Future<void> _loadDetailFor(DanmakuLibraryRef ref, {bool force = false}) async {
    if (!force) {
      if (_detailCache.containsKey(ref.animeId)) {
        final cached = _detailCache[ref.animeId];
        setState(() {
          _detail = cached;
          _detailLoading = false;
          _detailError = cached == null ? '该作品在弹弹play 没有详情' : null;
        });
        return;
      }
      final fromDisk = _cache.read(ref.refreshableId);
      if (fromDisk != null) {
        _detailCache[ref.animeId] = fromDisk;
        setState(() {
          _detail = fromDisk;
          _detailLoading = false;
          _detailError = null;
        });
        return;
      }
    }

    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      // 刷新/请求优先用字符串形式 bangumiId（接口两种都接受，字符串是它的规范 id）。
      final detail = await _service.loadDetail(ref.refreshableId);
      if (!mounted || _shownRef?.refreshableId != ref.refreshableId) return;
      _detailCache[ref.animeId] = detail;
      if (detail == null) {
        setState(() {
          _detailLoading = false;
          _detailError = '该作品在弹弹play 没有详情';
        });
        return;
      }
      await _cache.save(ref.refreshableId, detail);
      if (!mounted || _shownRef?.refreshableId != ref.refreshableId) return;
      setState(() {
        _detail = detail;
        _detailLoading = false;
        // 快照补全：集数改以详情列表为准（搜索接口的 episodeCount 对 TMDB 源恒为 1），
        // 年份只有搜索接口有，所以要显式带过去。
        //
        // 无条件写覆盖（哪怕原本展示的是进度记录里那个）：外壳写进度记录**不会**
        // 重建本面板，若只依赖 `widget.current`，刷新后卡片会停在旧快照上。
        _shownOverride = DanmakuLibraryRef.fromDetail(
          detail,
          year: ref.year,
          savedAtMs: ref.savedAtMs,
        );
      });
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 取作品详情失败 id=${ref.refreshableId}',
          error: error);
      if (!mounted || _shownRef?.refreshableId != ref.refreshableId) return;
      setState(() {
        _detailLoading = false;
        _detailError = _friendlyError(error);
      });
    }
  }

  /// 在搜索结果/兜底列表里选中一条：**只换卡片与分集，不动列表**。
  Future<void> _previewAnime(DanmakuSearchAnime anime) async {
    final ref = DanmakuLibraryRef(
      animeId: anime.animeId,
      bangumiId: anime.bangumiId,
      libraryTitle: anime.animeTitle,
      imageUrl: anime.imageUrl,
      rating: anime.rating,
      episodeCount: anime.episodeCount,
      year: anime.year ?? 0,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      _shownOverride = ref;
      _detail = _detailCache[anime.animeId];
      _detailError = null;
    });
    await _loadDetailFor(ref);
  }

  /// 点某一集：立刻把卡片切到这一部，交回外壳取弹幕；**成功才写进度记录**。
  Future<void> _pickEpisode(DanmakuBangumiDetail detail, int index) async {
    final base = _shownRef;
    final ref = DanmakuLibraryRef.fromDetail(
      detail,
      year: base?.year ?? 0,
      savedAtMs: base?.savedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    setState(() => _shownOverride = ref);
    final applied = await widget.onEpisodeSelected(detail, index);
    if (!mounted || !applied) return;
    widget.onLibraryPersist?.call(ref);
  }

  /// 刷新当前展示的库：**绕过会话缓存**（命中缓存等于没刷），拿最新详情覆盖卡片；
  /// 只有刷新的就是"当前使用"那个库时才回写进度记录——预览别的库不该动事实源。
  Future<void> _refreshShown() async {
    final ref = _shownRef;
    if (ref == null || _detailLoading) return;
    await _loadDetailFor(ref, force: true);
    if (!mounted) return;
    final detail = _detail;
    if (detail == null) {
      _toast('刷新失败，请检查网络');
      return;
    }
    final refreshed = DanmakuLibraryRef.fromDetail(
      detail,
      year: ref.year,
      savedAtMs: ref.savedAtMs,
    );
    setState(() => _shownOverride = refreshed);
    if (ref.refreshableId == widget.current?.refreshableId) {
      widget.onLibraryPersist?.call(refreshed);
    }
    _toast('已刷新「${refreshed.libraryTitle}」');
  }

  void _toast(String message) {
    if (!mounted) return;
    WywDialog.showToast(message: message);
  }

  /// 25 条上限的显式提示：**被截断这件事必须让用户看见**，否则他会以为
  /// "搜不到就是没有"，而实测搜"柯南"时主系列恰恰被剧场版挤出了这 25 条。
  String? get _truncationHint {
    if (_candidates.length < _searchAnimeLimit) return null;
    final hasTv = _candidates.any((c) => c.type == 'tvseries');
    if (_type == DanmakuTypeFilter.all && !hasTv) {
      return '结果已达 25 条上限，且都是剧场版/OVA——试试右上角的「TV」筛选';
    }
    return '结果已达 25 条上限（接口不能翻页），换更具体的关键词或换类型筛选';
  }

  // ===== 构建 =====

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shownRef;
    // 选集页签只在**真的有分集**时才多挂一行筛选框：没有分集时那一行无从筛起，
    // 多出来的高度会白占面板（面板最窄只有 ~280px）。
    final showFilterRow = _tabIndex == 1
        ? (_detail?.episodes.isNotEmpty ?? false)
        : true;
    return CustomScrollView(
      slivers: [
        if (shown != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
              child: DanmakuLibraryCard(
                ref: shown,
                detail: _detail,
                loading: _detailLoading,
                error: _detailError,
                isCurrent: _shownIsCurrent,
                onRefresh: () => unawaited(_refreshShown()),
              ),
            ),
          ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeaderDelegate(
            color: theme.colorScheme.surface,
            height: showFilterRow ? _pinnedHeaderHeight : _tabsRowHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _tabsRowHeight,
                  child: ConnectedTabs(
                    controller: _tabsController,
                    labels: const ['搜索', '选集'],
                    // 左右留边距，横向 12 与本页的搜索框/筛选框对齐（底部 sheet 里
                    // Kazumi 用的是 24，面板更窄所以等比收一半）；下间距 8 与卡片、
                    // 列表之间的节奏一致。
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  ),
                ),
                if (showFilterRow)
                  SizedBox(
                    height: _searchRowHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _tabIndex == 1
                          ? _episodeFilterField(context)
                          : _keywordField(context),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_tabIndex == 1)
          ..._episodeSlivers(context)
        else
          ..._searchSlivers(context),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
      ],
    );
  }

  /// 吸顶「搜索 / 选集」切换行。
  ///
  /// 整页只有一个滚动体，长分集列表（实测柯南 1372 集）滚到一半时，这一行仍然
  /// 停在顶部，用户随时能切回搜索。
  Widget _loadingSliver() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  // ===== 搜索页签 =====

  List<Widget> _searchSlivers(BuildContext context) {
    final theme = Theme.of(context);
    final slivers = <Widget>[
      // 凭证没配置时给一行说明（以前挤在类型 chips 下面；chips 变成吸顶行里的
      // 下拉后，这行挪到内容区第一项）。
      if (!_service.isConfigured)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(
              '未配置弹弹play 凭证（构建时注入 DANDANAPI_APPID / DANDANAPI_KEY）',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ),
    ];
    if (_searching) {
      slivers.add(_loadingSliver());
      return slivers;
    }
    if (_candidates.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _emptyHint(
            context,
            icon: Icons.search_rounded,
            title: _error ?? '搜索弹弹play 作品',
            subtitle: _error == null
                ? '输入番剧名后回车；选中条目会在上方显示封面与简介'
                : '换个更具体的关键词，或换上面的类型筛选',
          ),
        ),
      );
      return slivers;
    }

    final hint = _truncationHint;
    if (hint != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(
              hint,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        sliver: SliverList.builder(
          itemCount: _candidates.length,
          itemBuilder: (context, index) {
            final anime = _candidates[index];
            return _CandidateTile(
              anime: anime,
              selected: _shownRef?.animeId == anime.animeId,
              onTap: () => unawaited(_previewAnime(anime)),
            );
          },
        ),
      ),
    );
    return slivers;
  }

  /// 搜索框 + 类型下拉，**同一行**。
  ///
  /// 搜索框放在卡片下方（反馈要求）：卡片说明"我现在用/选了哪一个"，输入框属于
  /// "换一个"，顺序反过来会让人以为卡片是搜索结果的标题。
  ///
  /// 类型筛选原本是搜索框下方一排 chips，两点不好：占掉一整行高度，且与搜索框分属
  /// 两处、不像同一个筛选条件。改成同行紧凑下拉。它仍然是**服务端**过滤：泛关键词
  /// 会把主系列挤出 25 条上限，只有这里能救。
  Widget _keywordField(BuildContext context) {
    return Row(
      children: [
        Expanded(
          // 用 ValueListenableBuilder 而不是 setState：清空按钮的显隐只依赖输入值，
          // 每次按键都 setState 会让整页（含候选列表）重建。
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _keywordController,
            builder: (context, value, _) => TextField(
              controller: _keywordController,
              // 刻意不 autofocus：本页是播放器的常驻页签，抢走焦点会让空格/方向键
              // 等播放快捷键失效。
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(_search()),
              decoration: InputDecoration(
                isDense: true,
                hintText: '番剧名称（至少 2 字）',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: StyleString.fieldContentPadding,
                border: const OutlineInputBorder(
                  borderRadius: StyleString.controlBorderRadius,
                ),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () => _keywordController.clear(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 与相邻 TextField 同款外观（`SelectField` 就是为此设计的），高度天然对齐。
        //
        // 宽度 118 是**量出来的**、不是随手写的：`SelectField` 的触发内容 =
        // contentPadding(12×2) + 最宽的类型名（「剧场版」3 个 CJK 字 ≈ 42）
        // + ▾ 图标的交互宽度（48），也就是 114 才不溢出（实测 110 当场
        // RenderFlex overflow，面板最窄只有 280 宽，容不下拍脑袋的值）。
        SizedBox(
          width: 118,
          child: SelectField<DanmakuTypeFilter>(
            value: _type,
            options: [
              for (final type in DanmakuTypeFilter.values)
                SelectOption<DanmakuTypeFilter>(
                  value: type,
                  label: type.label,
                ),
            ],
            onChanged: _onTypeChanged,
          ),
        ),
      ],
    );
  }

  void _onTypeChanged(DanmakuTypeFilter type) {
    if (_type == type) return;
    setState(() => _type = type);
    if (_keywordController.text.trim().length >= 2) {
      unawaited(_search());
    }
  }

  /// 分集筛选框（同样挂顶：上千集的长列表滚到一半也能直接筛）。
  Widget _episodeFilterField(BuildContext context) {
    final filter = _episodeFilterController.text.trim().toLowerCase();
    return TextField(
      controller: _episodeFilterController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        hintText: '筛选标题或集号',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        contentPadding: StyleString.fieldContentPadding,
        border: const OutlineInputBorder(
          borderRadius: StyleString.controlBorderRadius,
        ),
        suffixIcon: filter.isEmpty
            ? null
            : IconButton(
                tooltip: '清空',
                onPressed: () =>
                    setState(() => _episodeFilterController.clear()),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
      ),
    );
  }

  // ===== 选集页签 =====

  List<Widget> _episodeSlivers(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shownRef;
    if (shown == null) {
      return [
        SliverToBoxAdapter(
          child: _emptyHint(
            context,
            icon: Icons.playlist_play_rounded,
            title: '还没有选中作品',
            subtitle: '先在「搜索」里找到并选中一部作品，这里就会列出它的分集',
          ),
        ),
      ];
    }

    final detail = _detail;
    if (detail == null || detail.episodes.isEmpty) {
      if (_detailLoading) return [_loadingSliver()];
      return [
        SliverToBoxAdapter(
          child: _emptyHint(
            context,
            icon: Icons.playlist_remove_rounded,
            title: _detailError ?? '还没有这一部的分集',
            subtitle: '分集来自弹弹play 的作品详情，取一次就会缓存下来，下次进场直接展示',
            action: FilledButton.tonalIcon(
              onPressed: () => unawaited(_loadDetailFor(shown)),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('取分集'),
            ),
          ),
        ),
      ];
    }

    final filter = _episodeFilterController.text.trim().toLowerCase();
    final visible = <MapEntry<int, DanmakuEpisodeRef>>[];
    for (var i = 0; i < detail.episodes.length; i++) {
      final episode = detail.episodes[i];
      final label = _episodeLabel(i, episode);
      if (filter.isNotEmpty &&
          !label.toLowerCase().contains(filter) &&
          !(i + 1).toString().contains(filter)) {
        continue;
      }
      visible.add(MapEntry(i, episode));
    }

    return [
      // 筛选框不在这里：它已经挂到吸顶区（`_episodeFilterField`），滚多远都能改。
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
          child: Text(
            '正在播放第 ${widget.localEpisodeIndex + 1} 集 · 点一集即用它的弹幕'
            '${visible.length == detail.episodes.length ? '' : '　显示 ${visible.length}/${detail.episodes.length} 集'}',
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
      if (visible.isEmpty)
        SliverToBoxAdapter(
          child: _emptyHint(
            context,
            icon: Icons.filter_list_off_rounded,
            title: '未找到分集',
            subtitle: '换个关键词试试',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          sliver: SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final entry = visible[index];
              return ListTile(
                dense: true,
                title: Text(
                  _episodeLabel(entry.key, entry.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: entry.value.airDateLabel.isEmpty
                    ? null
                    : Text(
                        entry.value.airDateLabel,
                        style: theme.textTheme.labelSmall,
                      ),
                onTap: () => unawaited(_pickEpisode(detail, entry.key)),
              );
            },
          ),
        ),
    ];
  }

  /// 分集展示名：优先 `episodeNumber`（接口说明它可能含字母，如实测的 `C146`），
  /// 否则退回完整标题，最后才用序号兜底。
  String _episodeLabel(int index, DanmakuEpisodeRef episode) {
    if (episode.episodeNumber.isNotEmpty) {
      return '${episode.episodeNumber} ${episode.episodeTitle}'.trim();
    }
    if (episode.episodeTitle.isNotEmpty) {
      return episode.episodeTitle;
    }
    return '第 ${index + 1} 集';
  }

  Widget _emptyHint(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }
}

/// 吸顶区代理：固定高度、始终不收缩。
///
/// 里面是两行（「搜索 / 选集」切换 + 当前页签的搜索/筛选框）——**两个页签各自的
/// 搜索框都挂顶**：长结果或上千集的分集列表滚到一半时，改关键词/筛分集不必先滚回
/// 顶部。选集页签没有分集时不挂第二行，所以高度由调用方按需给。
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.child,
    required this.color,
    required this.height,
  });

  final Widget child;
  final Color color;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 用 Material 而不是 ColoredBox：里面是 `ConnectedTabs` 与输入框（ink 画在最近的
    // Material 上），夹一层带色 ColoredBox 会把水波纹吞掉（同 ListTile 那条断言的
    // 老问题）。这里必须是不透明底色，否则内容会从吸顶区下面透出来。
    return Material(color: color, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.color != color ||
        oldDelegate.height != height;
  }
}

/// 候选条目：封面 + 标题 + 元信息。
///
/// **不显示任何"匹配度"**：曾经在这里挂一个百分比角标 + 一行「标题 92% · 封面 87% ·
/// 集数 88%」的打分依据，但那个数字在同一列里都不可比（封面分只算前 10 条），
/// 见 `_search` 里的说明。用户要的是能认出是哪一部，列表顺序交给弹弹play 自己。
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.anime,
    required this.selected,
    required this.onTap,
  });

  final DanmakuSearchAnime anime;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (anime.typeDescription.isNotEmpty) anime.typeDescription,
      if (anime.year != null) '${anime.year} 年',
      if (anime.episodeCount > 0) '${anime.episodeCount} 集',
      if (anime.rating > 0) '评分 ${anime.rating.toStringAsFixed(1)}',
    ].join(' · ');

    return ListTile(
      dense: true,
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: NetworkImgLayer(src: anime.imageUrl, width: 40, height: 54),
      title: Text(
        anime.animeTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: meta.isEmpty
          ? null
          : Text(
              meta,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
      onTap: onTap,
    );
  }
}
