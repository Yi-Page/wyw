import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/comic_reader/comic_reader_controller.dart';
import 'package:wyw/pages/comic_reader/comic_reader_page.dart';
import 'package:wyw/pages/route_error_page.dart';

/// 阅读器模块：注册 /reader 路由。
///
/// [ComicReaderController] 为路由级 Store 单例，进入路由时由本模块 provide，
/// 页面用路由参数 configure 注入。
final comicReaderModule = createModule(
  path: '/reader',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s.add<ComicReaderController>(ComicReaderController.new),
      child: (context, state) {
        final args = state.arguments;
        if (args is! ComicReaderPageRouteArgs) {
          return const RouteErrorPage(message: '阅读器参数无效，请返回后重试。');
        }
        return ComicReaderPage(
          args: args,
          controller: context.read<ComicReaderController>(),
        );
      },
    );
  },
);
