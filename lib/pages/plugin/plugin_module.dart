import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/plugin/plugin_edit_page.dart';
import 'package:wyw/pages/plugin/plugin_manager_page.dart';
import 'package:wyw/pages/plugin/plugin_settings_page.dart';
import 'package:wyw/pages/route_error_page.dart';

/// 插件（规则）模块：管理页 + 新增/编辑页 + 插件设置页。
///
/// **挂载在 `settingsModule` 之下**（`settings_module.dart` 的 `..module(pluginModule)`），
/// 因此对外完整路径是 `/settings/plugin`、`/settings/plugin/edit`、
/// `/settings/plugin/settings`——导航必须用完整路径，`/plugin/...` 会命中路由表的
/// `Route not found`（modular 7 把子模块路由按完整路径压平，绝对路径不做相对解析）。
///
/// 编辑页保存时 pop 携带 `PluginEditResult`，调用方以 `pushNamed` 的
/// 返回值接收（此前为裸 MaterialPageRoute 推入，已收敛进路由表）。
final pluginModule = createModule(
  path: '/plugin',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const PluginManagerPage(),
      )
      ..route(
        '/edit',
        child: (context, state) {
          final args = state.arguments;
          if (args is! PluginEditPageRouteArgs) {
            return const RouteErrorPage(message: '规则编辑参数无效，请返回后重试。');
          }
          return PluginEditPage(
            initialName: args.initialName,
            initialContent: args.initialContent,
            isEdit: args.isEdit,
          );
        },
      )
      ..route(
        '/settings',
        child: (context, state) {
          final args = state.arguments;
          if (args is! PluginSettingsPageRouteArgs) {
            return const RouteErrorPage(message: '插件设置参数无效，请返回后重试。');
          }
          return PluginSettingsPage(pluginName: args.pluginName);
        },
      );
  },
);
