import 'package:flutter/material.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/modules/danmaku/danmaku_library_ref.dart';

/// 封面高度与宽高比。
///
/// 照 Kazumi 详情页（Android 形态）的头图做法：宽高比 0.65（海报 2:3 一档），
/// 宽度由高度推出来。**改这里就同时改了卡片版式**，所以两个值放一起。
const double _coverHeight = 120;
const double _coverAspectRatio = 0.65;

/// 弹幕库卡片：**"当前使用"和"刚在搜索结果里选中"共用这一个组件**。
///
/// 之前是两张卡片（持久化的一张、选中的另一张），长的不一样、字段也不一样，
/// 反馈就是"选中与展示的卡片为什么不一致"。现在只认一个数据源 [ref]：
/// 快照给什么就画什么，详情 [detail] 只是"能多给一点的补充数据"
/// （多语言标题、标签、长简介、分集列表），拿不到时卡片依然完整可读。
class DanmakuLibraryCard extends StatefulWidget {
  const DanmakuLibraryCard({
    super.key,
    required this.ref,
    this.detail,
    this.loading = false,
    this.error,
    this.isCurrent = false,
    this.onRefresh,
  });

  /// 库快照。就是进度记录里存的那个东西（id / 标题 / 封面 / 简介 / 评分 / 集数）。
  final DanmakuLibraryRef ref;

  /// 库详情（来自磁盘缓存或 `/bangumi/{id}`）。
  final DanmakuBangumiDetail? detail;

  /// 详情是否正在取。
  final bool loading;

  /// 取详情失败的原因。
  final String? error;

  /// 这个库是不是"当前使用"的那个（决定是否打「使用中」标记）。
  final bool isCurrent;

  /// 刷新（重新拉这个库的详情）。
  final VoidCallback? onRefresh;

  @override
  State<DanmakuLibraryCard> createState() => _DanmakuLibraryCardState();
}

class _DanmakuLibraryCardState extends State<DanmakuLibraryCard> {
  /// 多语言标题当前展示到第几个。
  int _titleIndex = 0;
  bool _introExpanded = false;

  @override
  void initState() {
    super.initState();
    // 详情可能已经缓存好了（进场即从磁盘缓存读到），所以初始化时也要定位一次。
    _syncTitleIndex();
  }

  @override
  void didUpdateWidget(covariant DanmakuLibraryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref.refreshableId != widget.ref.refreshableId) {
      // 换了一个库：标题轮换与简介展开都回到初始态，否则会把上一部作品的状态带过来。
      _titleIndex = 0;
      _introExpanded = false;
      _syncTitleIndex();
      return;
    }
    // 详情刚到手：按快照标题定位一次。只在 null → 非 null 这个跃迁做，
    // 免得每次重建都把用户点标题切换的结果重置掉。
    if (oldWidget.detail == null && widget.detail != null) {
      _syncTitleIndex();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = widget.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(theme, detail),
        const SizedBox(height: 8),
        _intro(theme, detail),
        if (detail != null && detail.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          _tags(theme, detail),
        ],
        const SizedBox(height: 4),
        _footer(theme),
      ],
    );
  }

  /// 封面 + 标题（可点标题轮流切换多语言名）+ 指标格。
  ///
  /// 指标**不再拼成一行字符串**（`"TV动画 · 2024 年 · 12 集 · 评分 7.5 · 连载中"`
  /// 既难扫读，又会被省略号从尾巴切掉）。照 Kazumi 详情页信息块的做法：每项
  /// **标签在上、值在下**，值用加粗主色（那边是 `fontSize: 20 / bold / primary`，
  /// 这里按面板宽度缩到 titleSmall），评分再带一颗星；「连载中」做成标题右侧的
  /// 小徽标——它是状态，不该混进数值里。
  Widget _headerRow(ThemeData theme, DanmakuBangumiDetail? detail) {
    final ref = widget.ref;
    final titles = detail?.titles ?? const <DanmakuTitle>[];
    final index = titles.isEmpty ? -1 : _titleIndex.clamp(0, titles.length - 1);
    final title = index < 0 ? ref.libraryTitle : titles[index].title;
    final episodeCount = detail != null && detail.episodes.isNotEmpty
        ? detail.episodes.length
        : ref.episodeCount;
    final typeDescription = detail?.typeDescription ?? '';
    // 年份兜底：快照里的 0 表示"当时没拿到"（老记录，或选中时接口没给 startDate）。
    // 详情里每集都带 airDate，用它推一次，卡片就不会永远显示 `—`；用户下次点分集或
    // 刷新时 `fromDetail` 还会把年份写回快照（自愈）。
    final year = ref.year > 0 ? ref.year : (detail?.firstAirYear ?? 0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面：照 **Kazumi 详情页（Android 形态，`BangumiInfoCardV`）** 的做法——
        // `AspectRatio(0.65)` + 由**高度决定宽度**，而不是写死一个小尺寸
        // （那边卡片高 300、封面约 150×230）。
        //
        // 这里是 280px 宽的分屏面板，高度只能缩到 [_coverHeight]：再高就会把标题
        // 那列挤成一条缝，也会让卡片占满整个面板。120 高 ≈ 78 宽，是"明显变大
        // 又不喧宾夺主"的折中（此前写死的 56×80 被反馈偏小）。
        SizedBox(
          height: _coverHeight,
          child: AspectRatio(
            aspectRatio: _coverAspectRatio,
            child: LayoutBuilder(
              builder: (context, box) => NetworkImgLayer(
                src: ref.imageUrl,
                width: box.maxWidth,
                height: box.maxHeight,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    // 有多个语言版本时点标题轮流切换（不再另起一行写"语言 ·
                    // 点标题切换"，那行提示按反馈去掉了）。
                    child: GestureDetector(
                      onTap: titles.length > 1
                          ? () => setState(
                              () => _titleIndex = (index + 1) % titles.length)
                          : null,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (detail?.isOnAir ?? false) ...[
                    const SizedBox(width: 6),
                    _onAirChip(theme),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child:
                        _metric(theme, '类型', _metricText(theme, typeDescription)),
                  ),
                  Expanded(
                    child: _metric(
                      theme,
                      '年份',
                      _metricText(theme, year > 0 ? '$year 年' : ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      theme,
                      '集数',
                      _metricText(theme, episodeCount > 0 ? '$episodeCount 集' : ''),
                    ),
                  ),
                  Expanded(
                    child:
                        _metric(theme, '评分', _ratingValue(theme, ref.rating)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 一格指标：标签在上（小字、次要色），值在下（加粗主色）——照 Kazumi 的
  /// 「放送开始: / 2024-01-06」那种排版。整格不可点，避免误触。
  Widget _metric(ThemeData theme, String label, Widget value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 1),
        value,
      ],
    );
  }

  /// 指标值文本；未知（空串）显示 `—`，与 `video_details_content` 的口径一致。
  Widget _metricText(ThemeData theme, String value) {
    return Text(
      value.isEmpty ? '—' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: value.isEmpty
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary,
      ),
    );
  }

  /// 评分：加粗数值 + 一颗星（Kazumi 那边是数值 + 5 颗星，面板窄只留一颗）。
  Widget _ratingValue(ThemeData theme, double rating) {
    if (rating <= 0) return _metricText(theme, '');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 2),
        _metricText(theme, rating.toStringAsFixed(1)),
      ],
    );
  }

  /// 「连载中」徽标：状态而非数值，所以贴在标题右侧。
  Widget _onAirChip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '连载中',
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }

  /// 按快照标题定位初始标题下标：优先展示与快照同名的那一条（通常是中文名）。
  ///
  /// 只在"详情刚到 / 换了一个库"时调用一次。**不能**放在 `build` 里做——那样每次
  /// 重建都会把用户点标题切到的下标重置回去，表现就是"点标题切换没生效"。
  void _syncTitleIndex() {
    final titles = widget.detail?.titles ?? const <DanmakuTitle>[];
    if (titles.isEmpty) {
      _titleIndex = 0;
      return;
    }
    final wanted = widget.ref.libraryTitle.trim();
    final hit = wanted.isEmpty
        ? -1
        : titles.indexWhere((item) => item.title.trim() == wanted);
    _titleIndex = hit >= 0 ? hit : 0;
  }

  /// 简介：默认 3 行，可展开。
  Widget _intro(ThemeData theme, DanmakuBangumiDetail? detail) {
    final fromDetail = detail?.displayIntro ?? '';
    final text = fromDetail.isNotEmpty ? fromDetail : widget.ref.displayIntro;
    if (text.isEmpty) {
      return Text(
        '该作品没有简介',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: _introExpanded ? null : 3,
          overflow: _introExpanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        GestureDetector(
          onTap: () => setState(() => _introExpanded = !_introExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _introExpanded ? '收起' : '展开',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  /// 标签（最多 4 个，超出的不展示）。
  Widget _tags(ThemeData theme, DanmakuBangumiDetail detail) {
    final tags = detail.tags.take(4).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tag.name,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
      ],
    );
  }

  /// 底部：使用中标记 / 加载与错误提示 / 刷新。
  Widget _footer(ThemeData theme) {
    return Row(
      children: [
        if (widget.isCurrent) _currentBadge(theme),
        if (widget.error != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                widget.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          )
        else
          const Spacer(),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          tooltip: '刷新这个库的分集与简介',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: widget.loading ? null : widget.onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
        ),
      ],
    );
  }

  Widget _currentBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded,
              size: 12, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 3),
          Text(
            '使用中',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}
