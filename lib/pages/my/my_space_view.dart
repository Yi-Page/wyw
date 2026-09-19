import 'package:flutter/material.dart';

import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/widget/split_list_row.dart';

/// 「我的」页入口目的地，供 [MyPage] 经 `onOpen` 回调映射到具体路由动作。
enum MySpaceDestination {
  manualPlay,
  jsConsole,
  history,
  downloads,
  settings,
}

/// 入口强调色档位：只表达「取 ColorScheme 的哪一组 role」，不写死颜色。
enum _EntryTone { surface, secondary, tertiary }

/// 「我的」页入口的唯一数据源。
///
/// 磁贴 / 列表行、竖屏 / 宽屏都从这份定义取内容，增删入口只改这里。此前入口
/// 定义分散在多个布局分支里，导致宽屏下「设置」同时以 hero 卡和列表行出现两次。
class _MyEntry {
  const _MyEntry({
    required this.destination,
    required this.icon,
    required this.title,
    required this.caption,
    required this.tone,
  });

  final MySpaceDestination destination;
  final IconData icon;
  final String title;
  final String caption;
  final _EntryTone tone;
}

const List<_MyEntry> _entries = <_MyEntry>[
  _MyEntry(
    destination: MySpaceDestination.history,
    icon: Icons.history_rounded,
    title: '历史记录',
    caption: '查看历史记录',
    tone: _EntryTone.secondary,
  ),
  _MyEntry(
    destination: MySpaceDestination.downloads,
    icon: Icons.download_rounded,
    title: '离线下载',
    caption: '缓存任务与本地文件',
    tone: _EntryTone.tertiary,
  ),
  _MyEntry(
    destination: MySpaceDestination.manualPlay,
    icon: Icons.play_circle_outline_rounded,
    title: '手动播放',
    caption: '输入播放页网址 / 直链播放',
    tone: _EntryTone.surface,
  ),
  // U6：与「历史记录」区分，不复用 history_rounded。
  _MyEntry(
    destination: MySpaceDestination.jsConsole,
    icon: Icons.terminal_rounded,
    title: 'JS控制台',
    caption: '运行 js 脚本',
    tone: _EntryTone.surface,
  ),
  _MyEntry(
    destination: MySpaceDestination.settings,
    icon: Icons.settings_rounded,
    title: '设置',
    caption: '播放、外观与规则',
    tone: _EntryTone.surface,
  ),
];

/// 磁贴化的两个内容向入口；其余入口走 split-list 行，避免整页磁贴化。
const Set<MySpaceDestination> _quickTileDestinations = {
  MySpaceDestination.history,
  MySpaceDestination.downloads,
};

/// 内容区限宽：规范第三部分第 9 节的 `ContentWidth.page`（my_page = 800）。
/// 该 token 尚未落地，先在此具名；token 落地后改为引用。
const double _pageMaxWidth = 800;

/// 极窄视口下磁贴竖排的兜底阈值——是内容可读性下限，不是设备断点。
const double _stackTilesBelowWidth = 280;

/// 磁贴圆角：规范第 7 节 `radiusMd`(16)「页面级卡片组（my_page）」。
const double _tileRadius = 16;

/// 按下形变目标半径：规范第 7 节 `radiusXs`(8)。
const double _tilePressedRadius = 8;

/// 「我的」页入口视图：两个内容向入口用磁贴，其余走 split-list 行。
///
/// 单一排布 + 800 限宽居中，不做横竖屏两套信息架构（同名分组指向不同集合、
/// 同一入口两种配色都会随两套布局出现）。页面名已由 SysAppBar 承担，故页内
/// 不再重复标题，也不放无数据、不可点的装饰面板。
class MySpaceView extends StatelessWidget {
  const MySpaceView({super.key, required this.onOpen});

  final ValueChanged<MySpaceDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final quickTiles = [
      for (final entry in _entries)
        if (_quickTileDestinations.contains(entry.destination)) entry,
    ];
    final rows = [
      for (final entry in _entries)
        if (!_quickTileDestinations.contains(entry.destination)) entry,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTiles =
            constraints.maxWidth < _stackTilesBelowWidth || largeText;
        return SingleChildScrollView(
          key: const PageStorageKey('my-space'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _QuickTileRow(
                    entries: quickTiles,
                    stack: stackTiles,
                    onOpen: onOpen,
                  ),
                  const SizedBox(height: 12),
                  SplitListGroup(
                    outerRadius: _tileRadius,
                    children: [
                      for (final entry in rows)
                        SettingsTile(
                          title: Text(entry.title),
                          description: Text(entry.caption),
                          leading: entry.icon,
                          trailing:
                              const Icon(Icons.chevron_right_rounded, size: 20),
                          onPressed: (_) => onOpen(entry.destination),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickTileRow extends StatelessWidget {
  const _QuickTileRow({
    required this.entries,
    required this.stack,
    required this.onOpen,
  });

  final List<_MyEntry> entries;
  final bool stack;
  final ValueChanged<MySpaceDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i != 0) const SizedBox(height: 12),
            _QuickTile(
              entry: entries[i],
              onTap: () => onOpen(entries[i].destination),
            ),
          ],
        ],
      );
    }
    // 单层 IntrinsicHeight 取两列等高；不再嵌套（每次测量都遍历子树）。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i != 0) const SizedBox(width: 12),
            Expanded(
              child: _QuickTile(
                entry: entries[i],
                onTap: () => onOpen(entries[i].destination),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.entry, required this.onTap});

  final _MyEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (background, foreground) =
        _toneColors(Theme.of(context).colorScheme, entry.tone);

    return _ExpressiveAction(
      color: background,
      foreground: foreground,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(entry.icon, size: 24, color: foreground),
            const SizedBox(height: 10),
            Text(
              entry.title,
              style: text.titleSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            // 说明文字用容器配对的 on* 全值：叠 alpha 会把对比度压到 4.5:1 以下。
            Text(entry.caption, style: text.bodySmall?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

/// 档位 → ColorScheme 角色对。新增档位必须在这里映射，不允许字面色。
(Color, Color) _toneColors(ColorScheme colors, _EntryTone tone) {
  switch (tone) {
    case _EntryTone.surface:
      return (colors.surfaceContainer, colors.onSurface);
    case _EntryTone.secondary:
      return (colors.secondaryContainer, colors.onSecondaryContainer);
    case _EntryTone.tertiary:
      return (colors.tertiaryContainer, colors.onTertiaryContainer);
  }
}

/// 磁贴：按下时整体轻微缩放 + 圆角收缩 + 前景色覆盖层。
class _ExpressiveAction extends StatefulWidget {
  const _ExpressiveAction({
    required this.color,
    required this.foreground,
    required this.onTap,
    required this.child,
  });

  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_ExpressiveAction> createState() => _ExpressiveActionState();
}

class _ExpressiveActionState extends State<_ExpressiveAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : Duration(milliseconds: _pressed ? 150 : 300);
    return Semantics(
      // 与内层 InkWell 的 tap 语义合并进同一节点（不产生重复节点），
      // 补上读屏需要的 button 角色。
      button: true,
      child: AnimatedScale(
        scale: _pressed && !reducedMotion ? .97 : 1,
        duration: duration,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(
                _pressed ? _tilePressedRadius : _tileRadius),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.foreground.withValues(alpha: .10);
                }
                if (states.contains(WidgetState.focused)) {
                  return widget.foreground.withValues(alpha: .12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return widget.foreground.withValues(alpha: .08);
                }
                return null;
              }),
              child: IconTheme.merge(
                data: IconThemeData(color: widget.foreground),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: widget.foreground,
                      ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
