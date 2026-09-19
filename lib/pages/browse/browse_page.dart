import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/widget/loading_indicator.dart';
import 'package:wyw/pages/browse/browse_controller.dart';
import 'package:wyw/pages/browse/widgets/category_browse_view.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';

/// 分类浏览 Tab 页（独立路由，与搜索/我的并列）。
///
/// 顶部为插件 TabBar，只展示实现了分类浏览（getCategory 返回非 null）的插件；
/// 每个插件 tab 展示该插件的分类浏览视图。
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> with TickerProviderStateMixin {
  final BrowseController _controller = inject<BrowseController>();
  final PluginController _pluginController = inject<PluginController>();
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _controller.refreshCategoryPlugins();
  }

  /// 按分类插件数量同步 TabController（数量为 0 时置空）。
  void _syncTabs(int length) {
    final old = _tabController;
    if (length > 0) {
      _tabController = TabController(length: length, vsync: this);
    } else {
      _tabController = null;
    }
    old?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('浏览'),
        needTopOffset: false,
        actions: const [WywAppBarMenuButton(pagePath: '/tab/browse/')],
      ),
      body: SafeArea(
        child: Observer(
          builder: (_) {
            final plugins = _pluginController.plugins;
            // 插件数量变化时重新检查哪些支持分类浏览
            if (_controller.checkedPluginsCount != plugins.length) {
              _controller.checkedPluginsCount = plugins.length;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _controller.refreshCategoryPlugins();
              });
            }
            final categoryPlugins = _controller.categoryPlugins;
            final target = categoryPlugins.length;
            // TabController 长度与分类插件数不一致时同步（重建）
            if ((_tabController?.length ?? 0) != target) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _syncTabs(target);
              });
            }
            if (target == 0) {
              return const GeneralEmptyState(
                icon: Icons.category_outlined,
                title: '没有支持分类浏览的插件',
              );
            }
            final tc = _tabController;
            // 插件数变化后 TabController 要等 post-frame 才同步；长度不一致的
            // 那一帧先渲染加载态，避免用陈旧 controller 构建 TabBar。
            if (tc == null || tc.length != target) {
              return const Center(child: LoadingIndicator());
            }
            return Column(
              children: [
                Container(
                  color: Theme.of(context).appBarTheme.backgroundColor,
                  child: TabBar(
                    // 插件可达数十个，必须滚动；定宽会把标签挤成省略号。
                    isScrollable: true,
                    controller: tc,
                    tabs: categoryPlugins
                        .map((p) => Tab(text: p.name))
                        .toList(),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: tc,
                    children: categoryPlugins
                        .map((p) => CategoryBrowseView(pluginName: p.name))
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
}
