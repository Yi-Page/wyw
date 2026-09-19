import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/novel_reader/novel_reader_controller.dart';
import 'package:wyw/pages/novel_reader/novel_reader_page.dart';
import 'package:wyw/pages/route_error_page.dart';

/// 小说阅读器模块：注册 /novel 路由。
///
/// [NovelReaderController] 为路由级 Store 单例，进入路由时由本模块 provide，
/// 页面用路由参数 configure 注入。
final novelReaderModule = createModule(
  path: '/novel',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s.add<NovelReaderController>(NovelReaderController.new),
      child: (context, state) {
        final args = state.arguments;
        if (args is! NovelReaderPageRouteArgs) {
          return const RouteErrorPage(message: '小说阅读器参数无效，请返回后重试。');
        }
        return NovelReaderPage(
          args: args,
          controller: context.read<NovelReaderController>(),
        );
      },
    );
  },
);
