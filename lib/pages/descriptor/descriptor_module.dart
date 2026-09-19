import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/descriptor/descriptor_controller.dart';
import 'package:wyw/pages/descriptor/descriptor_page.dart';
import 'package:wyw/pages/route_error_page.dart';

/// 通用详情页模块
///
/// 路由 /descriptor 接收 [DescriptorPageRouteArgs]
/// -> 渲染 DescriptorPage，调 plugin.invokeWidgets(method, args)。
///
/// [DescriptorController] 为路由级 Store 单例，由本模块 provide。
final descriptorModule = createModule(
  path: '/descriptor',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s.add<DescriptorController>(DescriptorController.new),
      child: (context, state) {
        final args = state.arguments;
        if (args is! DescriptorPageRouteArgs) {
          return const RouteErrorPage(message: '详情页参数无效，请返回后重试。');
        }
        return DescriptorPage(
          controller: context.read<DescriptorController>(),
          pluginName: args.pluginName,
          method: args.method,
          args: args.args,
          title: args.title,
          actions: args.actions,
        );
      },
    );
  },
);
