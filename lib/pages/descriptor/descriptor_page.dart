import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/js/js_extends/js_descriptor.dart';
import 'package:wyw/pages/descriptor/descriptor_controller.dart';

/// 通用详情页：调用插件 invokeWidgets 渲染描述符树。
///
/// 触发：JS 端在按钮 onTap 写 UI.Navigate({page, method, args, title, actions})，
/// Dart 侧 UiDescriptorRenderer 识别 navigate 后调用 onNavigate 回调，
/// page 层 push 到 /descriptor 路由。
///
/// 页面结构：
/// - AppBar：左返回箭头 + 标题 + 右侧 IconButton 列表（每个 actions 元素）
/// - Body：Container(SingleChildScrollView(Column(cards)))
///
/// 嵌套跳转：详情页内如有 UI.Navigate，再次调用本页（sourcePluginName 透传）。
class DescriptorPage extends StatefulWidget {
  /// 调用方插件名（用于 navigate 嵌套跳转时定位目标 plugin）
  final String pluginName;

  /// 调用的 plugin 方法名
  final String method;

  /// 方法参数
  final List<dynamic> args;

  /// AppBar 标题
  final String? title;

  /// AppBar 右侧 IconButton 列表（每项是 UiAction 描述符 raw Map）
  final List<Map<String, dynamic>> actions;

  /// 路由级 Store 单例（由 [descriptorModule] 在 child 构建上下文解析后传入）。
  final DescriptorController controller;

  const DescriptorPage({
    super.key,
    required this.pluginName,
    required this.method,
    required this.args,
    this.title,
    this.actions = const [],
    required this.controller,
  });

  @override
  State<DescriptorPage> createState() => _DescriptorPageState();
}

/// `/descriptor/` 路由参数（见 descriptorModule）。
class DescriptorPageRouteArgs {
  const DescriptorPageRouteArgs({
    required this.pluginName,
    required this.method,
    this.args = const [],
    this.title,
    this.actions = const [],
  });

  /// 调用方插件名（用于 navigate 嵌套跳转时定位目标 plugin）
  final String pluginName;

  /// 调用的 plugin 方法名
  final String method;

  /// 方法参数
  final List<dynamic> args;

  /// AppBar 标题
  final String? title;

  /// AppBar 右侧 IconButton 列表（每项是 UiAction 描述符 raw Map）
  final List<Map<String, dynamic>> actions;

  /// 从 JS 桥透传的原始 Map 构造（`JSEngineCommonApi.onNavigateToDescriptor`
  /// 边界仍在 Dart 侧收 Map，进路由前在此收敛为强类型）。
  factory DescriptorPageRouteArgs.fromRawMap(Map<String, dynamic>? data) {
    return DescriptorPageRouteArgs(
      pluginName: (data?['plugin'] as String?) ?? '',
      method: (data?['method'] as String?) ?? '',
      args: (data?['args'] as List?)?.cast<dynamic>() ?? const [],
      title: data?['title'] as String?,
      actions: (data?['actions'] as List?)?.cast<Map<String, dynamic>>() ??
          const [],
    );
  }
}

class _DescriptorPageState extends State<DescriptorPage> {
  DescriptorController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller
      ..configure(
        pluginName: widget.pluginName,
        method: widget.method,
        args: widget.args,
        title: widget.title,
        actions: widget.actions,
      )
      ..onNavigate = _handleNavigate
      ..load();
  }

  Future<void> _handleNavigate(UiNavigate nav, String sourcePluginName) async {
    await context.pushNamed(
      '/descriptor/',
      arguments: DescriptorPageRouteArgs(
        pluginName: sourcePluginName,
        method: nav.method,
        args: nav.args,
        title: nav.title,
        actions: nav.actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final appBarActions = <Widget>[
          ...widget.actions.map((a) {
            final action = UiAction.fromJson(a);
            return IconButton(
              icon: Icon(_iconDataFor(action.icon)),
              tooltip: action.method,
              onPressed: () => _controller.handleAction(action),
            );
          }),
          const WywAppBarMenuButton(pagePath: '/descriptor/'),
        ];

        return Scaffold(
          appBar: SysAppBar(
            title: Text(widget.title ?? ''),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: appBarActions,
          ),
          body: SelectableRegion(
            selectionControls: materialTextSelectionControls,
            child: _buildBody(),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_controller.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_controller.error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_controller.cards == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _controller.cards!,
        ),
      ),
    );
  }

  IconData _iconDataFor(String? name) {
    switch (name) {
      case 'favorite':
        return Icons.favorite;
      case 'share':
        return Icons.share;
      case 'download':
        return Icons.download;
      case 'more':
        return Icons.more_vert;
      case 'refresh':
        return Icons.refresh;
      case 'home':
        return Icons.home;
      case 'add':
        return Icons.add;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'star':
        return Icons.star;
      case 'search':
        return Icons.search;
      default:
        return Icons.more_horiz;
    }
  }
}
