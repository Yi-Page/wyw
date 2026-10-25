import 'package:flutter/material.dart';
import 'package:wyw/bean/settings/capsule_tab_strip.dart';

/// 分屏面板的**外壳**：页签条（或二级页头部）+ 内容区 + 关闭按钮。
///
/// 刻意不含内容、不依赖任何控制器：外壳只做 chrome，因此可以脱离
/// `PlayerController` 单测（`test/split_panel_scaffold_test.dart`）。
/// `PlayerSplitPanel` 只负责把 `SplitPanelTab` / `SplitSubPage` 映射成标签与内容。
class SplitPanelScaffold extends StatefulWidget {
  const SplitPanelScaffold({
    super.key,
    required this.tabs,
    required this.bodies,
    required this.index,
    required this.onTabChanged,
    required this.onClose,
    this.subPageTitle,
    this.subPageBody,
    this.onBack,
  }) : assert(tabs.length == bodies.length, '页签与内容数量必须一致');

  /// 页签文案（顺序即显示顺序）。
  final List<String> tabs;

  /// 每个页签的内容（与 [tabs] 等长）。
  final List<Widget> bodies;

  /// 当前页签下标（受控；外壳自己不持有它）。
  final int index;

  final ValueChanged<int> onTabChanged;

  /// 收起面板。
  final VoidCallback onClose;

  /// 非空表示正在显示二级页：隐藏页签条、显示返回箭头与标题。
  final String? subPageTitle;
  final Widget? subPageBody;
  final VoidCallback? onBack;

  @override
  State<SplitPanelScaffold> createState() => _SplitPanelScaffoldState();
}

class _SplitPanelScaffoldState extends State<SplitPanelScaffold>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.tabs.length,
      initialIndex: widget.index,
      vsync: this,
    )..addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(covariant SplitPanelScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（快捷键 / 二级页返回）改了页签时同步过来。
    if (widget.index != _tabController.index) {
      _tabController.animateTo(widget.index);
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    widget.onTabChanged(_tabController.index);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subPageTitle = widget.subPageTitle;
    // 面板底色用 **Material** 而不是 `Container(color:)`：本面板里全是靠 ink 画出来的
    // 控件（ListTile、IconButton、TabBar、InkWell），而 ListTile 的背景与水波纹是画在
    // 最近的 `Material` 祖先上的。若这里只放一个 `ColoredBox`（`Container(color:)`
    // 就是它），Flutter 会在 debug 里对每个 ListTile 报
    // "ListTile background color or ink splashes may be invisible"（每帧一次，刷爆日志，
    // 且水波纹真的被吞掉）。换成同色 Material 即可，视觉不变。
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: _headerPadding,
            child: subPageTitle == null
                ? _buildTabHeader()
                : _buildSubPageHeader(subPageTitle, theme),
          ),
          const Divider(height: 1),
          Expanded(
            child: subPageTitle == null
                ? TabBarView(
                    controller: _tabController,
                    // 每个页签保活：TabBarView 会销毁离屏页，若不保活则
                    // 「切 tab 不丢状态」的契约无法成立（滚动位置、检索结果、
                    // 滑杆等都会重置）。
                    children: [
                      for (final body in widget.bodies)
                        _KeepAlive(child: body),
                    ],
                  )
                : (widget.subPageBody ?? const SizedBox.shrink()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabHeader() {
    return Row(
      children: [
        Expanded(
          child: CapsuleTabStrip(
            controller: _tabController,
            tabs: [
              for (final label in widget.tabs) CapsuleTab(label: label),
            ],
          ),
        ),
        _closeButton(),
      ],
    );
  }

  /// 二级页头部：返回箭头 + 标题（隐藏页签条，避免与"当前在哪一层"打架）。
  Widget _buildSubPageHeader(String title, ThemeData theme) {
    return Row(
      children: [
        IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        _closeButton(),
      ],
    );
  }

  Widget _closeButton() => IconButton(
        tooltip: '收起面板',
        icon: const Icon(Icons.close_rounded),
        onPressed: widget.onClose,
      );
}

/// 让 `TabBarView` 的离屏页不被销毁。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// 面板头部外边距。
///
/// 刻意留在本文件且私有：面板专属边距**不允许**被设置层 import（v1 就是设置层
/// 为了一个 `EdgeInsets` 反向 import 播放器面板文件）。设置内容件一律由外壳
/// 通过参数传入边距。
const EdgeInsets _headerPadding = EdgeInsets.fromLTRB(8, 4, 4, 4);
