import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/plugin/plugin_detail_page.dart';
import 'package:wyw/pages/plugin/plugin_manager_page.dart';
import 'package:wyw/pages/route_error_page.dart';

/// 插件（规则）模块：管理页 + 插件详情页。
///
/// **挂载在 `settingsModule` 之下**（`settings_module.dart` 的 `..module(pluginModule)`），
/// 因此对外完整路径是 `/settings/plugin`、`/settings/plugin/detail`——导航必须用
/// 完整路径，`/plugin/...` 会命中路由表的 `Route not found`（modular 7 把子模块路由
/// 按完整路径压平，绝对路径不做相对解析）。
///
/// **两条入口的分工**：
///   - **应用内入口**：设置页的详情面板用嵌套 Navigator + `builder` 直接构造
///     [PluginManagerPage]（见 `settings_page.dart` 的 `_settingsGroups`），
///     这样管理页随主从布局切换，不走命名路由。
///   - **命名路由 `/settings/plugin/`**：保留给深链 / 未来的外部入口，目前应用内
///     没有调用方。删掉它会让 `pluginModule` 没有根路由，因此保留并在此说明，
///     避免后来者以为它是死代码。
///   - **详情页**走命名路由：新建与编辑共用同一个页面（`pluginName` 为 null 即新建），
///     属性集中在那里，不再有独立的「编辑页」「设置页」。
final pluginModule = createModule(
  path: '/plugin',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const PluginManagerPage(),
      )
      ..route(
        '/detail',
        child: (context, state) {
          final args = state.arguments;
          if (args is! PluginDetailRouteArgs) {
            return const RouteErrorPage(message: '插件详情参数无效，请返回后重试。');
          }
          return PluginDetailPage(pluginName: args.pluginName);
        },
      );
  },
);
