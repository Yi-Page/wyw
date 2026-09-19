import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';

/// 顶栏统一导航入口的一条菜单项。
class AppBarMenuEntry {
  const AppBarMenuEntry({
    required this.label,
    required this.leadingIcon,
    required this.route,
  });

  final String label;
  final IconData leadingIcon;

  /// 目标路由（带尾斜杠的完整路径，见路由规范 A3）。
  final String route;
}

/// 顶栏统一导航入口（「更多」菜单按钮）。
///
/// 解决各页 appbar 右侧动作不一致的问题：历史/下载/设置等全局导航收进
/// 同一个菜单（规范 docs/ui-routing-design-spec.md B9 节）。用法：
///
/// ```dart
/// SysAppBar(
///   title: ...,
///   actions: [WywAppBarMenuButton(pagePath: '/history/')],
/// )
/// ```
///
/// [pagePath] 是宿主页面自己注册的路由路径。**必须显式传入**：modular 7
/// 的 `routeState()` 只反映栈底（push 的页面刻意不进 URL），组件无法从
/// context 读到「自己在哪一页」。
///
/// 跳转语义（一个出栈循环，见 [_go]）：
/// 1. 已在本页 → 条目禁用（置灰可见）；
/// 2. 从栈顶向下循环：栈顶是**其他菜单区块** → 出栈继续；栈顶是**目标**
///    → 停止（回到既有实例，不嵌套）；栈顶是**非菜单层**（播放器/阅读器/
///    普通内容页，原样保留）或**出到了栈底** → 跳转目标路由；
/// 3. 设置壳特例：壳内（SettingsPaneScope 可见）可见页不在根栈——指向
///    设置根的条目改走壳内 `onBack`（单栏）/禁用（双栏），其余条目一律
///    根栈 push（壳保留在栈下，返回键可回原详情页）。
///
/// 页面特有动作（历史页的编辑/清空、descriptor 的插件动作等）继续放在
/// 各自 actions 里，本按钮固定放最后。语义回归测试：
/// `test/app_bar_menu_button_test.dart`。
class WywAppBarMenuButton extends StatelessWidget {
  const WywAppBarMenuButton({
    super.key,
    required this.pagePath,
    this.entries = defaultEntries,
  });

  /// 宿主页面自己注册的路由路径（带尾斜杠），用于本页禁用判断。
  /// 见类注释——modular 的 routeState 读不到它。
  final String pagePath;

  /// 覆盖默认条目（一般不需要；新增全局入口直接改 [defaultEntries]）。
  final List<AppBarMenuEntry> entries;

  static const List<AppBarMenuEntry> defaultEntries = [
    AppBarMenuEntry(
      label: '历史记录',
      leadingIcon: Icons.history_rounded,
      route: '/history/',
    ),
    AppBarMenuEntry(
      label: '离线下载',
      leadingIcon: Icons.download_rounded,
      route: '/settings/download/',
    ),
    AppBarMenuEntry(
      label: '设置',
      leadingIcon: Icons.settings_outlined,
      route: '/settings/',
    ),
  ];

  /// 设置壳根路径。宿主页在设置壳内部（SettingsPaneScope 可见）时，
  /// 指向该路径的条目改走壳内回退（见 _onPressed）。
  static const String _settingsRootRoute = '/settings/';

  /// 是否为菜单可达路由（出栈循环的判定集合）。
  bool _isMenuRoute(String path) => entries.any((e) => e.route == path);

  VoidCallback? _onPressed(
    BuildContext context,
    AppBarMenuEntry entry,
    SettingsPaneScope? paneScope,
  ) {
    // 已在本页 → 禁用（置灰可见）。
    if (entry.route == pagePath) return null;

    // 设置壳内部（单栏详情/双栏嵌入）：可见页挂在壳的内部 Navigator 上，
    // 不在根栈——根栈的出栈循环在这里全部失效，走壳内分支。
    if (paneScope != null) {
      if (entry.route == _settingsRootRoute) {
        // 单栏详情 → 回到设置分类列表；双栏嵌入 → 人已在设置界面 → 禁用。
        return paneScope.onBack;
      }
      // 其余全局入口：一律根栈 push。壳保留在栈下，返回键可回到原详情页。
      return () => _push(context, entry);
    }

    // 常规根栈页面：走出栈循环。
    return () => _go(context, entry);
  }

  void _push(BuildContext context, AppBarMenuEntry entry) {
    Navigator.of(context, rootNavigator: true)
        .context
        .pushNamed(entry.route);
  }

  /// 出栈循环（一次 `popUntil` 表达）：
  ///
  /// ```
  /// while (栈顶在可达集合里 && 栈顶 != 目标) 出栈;
  /// ```
  ///
  /// 循环结束的三种落点：
  /// - 栈顶 == 目标 → 已回到既有实例，不嵌套，完成；
  /// - 栈顶是非菜单层（播放器/阅读器/普通内容页）→ 原样保留，跳转目标；
  /// - 出到了栈底 → 跳转目标。
  ///
  /// 落点判别用 predicate 闭包捕获（delegate 的 popUntil 会对每一层栈顶
  /// 调用 predicate，含最终停止的那层；只剩栈底时不再调用，两个标记均为
  /// false → 跳转），无需读取框架私有栈。
  void _go(BuildContext context, AppBarMenuEntry entry) {
    final target = entry.route;
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    // 栈底即目标（目标是主栈基的极端情况）→ 无需动作。
    if (rootContext.routeState(listen: false).uri.path == target) return;

    var landedOnTarget = false; // 停在目标上
    rootContext.popUntil((state) {
      final path = state.uri.path;
      if (path == target) {
        landedOnTarget = true;
        return true; // 停：回到既有实例
      }
      if (!_isMenuRoute(path)) {
        return true; // 停：非菜单层（播放器/阅读器/内容页）原样保留
      }
      return false; // 其他菜单区块 → 出栈，继续循环
    });

    // 停在目标上 → 完成；停在非菜单层或出到了栈底 → 跳转目标。
    if (!landedOnTarget) {
      rootContext.pushNamed(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 设置壳内部（SettingsPaneScope 可见）与普通根栈页面的跳转语义不同，
    // 见 _onPressed 与类注释。
    final paneScope = SettingsPaneScope.of(context);
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        tooltip: '更多',
        icon: const Icon(Icons.more_vert),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final entry in entries)
          MenuItemButton(
            leadingIcon: Icon(entry.leadingIcon),
            onPressed: _onPressed(context, entry, paneScope),
            child: Text(entry.label),
          ),
      ],
    );
  }
}
